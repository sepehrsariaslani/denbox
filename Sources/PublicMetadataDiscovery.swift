import AppKit
import Foundation
import WebKit

@MainActor
enum PublicMetadataDiscoveryService {
    static func discover(for item: MediaItem, provider: PublicMetadataProvider) async -> PublicTitleMetadata? {
        guard let searchURL = provider.searchURL else { return nil }
        let session = PublicMetadataDiscoverySession(provider: provider)
        return await session.discover(item: item, searchURL: searchURL)
    }
}

@MainActor
private final class PublicMetadataDiscoverySession: NSObject, WKNavigationDelegate, WKUIDelegate {
    private let provider: PublicMetadataProvider
    private let webView: WKWebView
    private let hostingWindow: NSWindow
    private var pendingNavigation: (id: UUID, continuation: CheckedContinuation<Void, Error>)?

    init(provider: PublicMetadataProvider) {
        self.provider = provider
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        configuration.allowsAirPlayForMediaPlayback = false
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        hostingWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1024, height: 768),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1024, height: 768), configuration: configuration)
        super.init()
        hostingWindow.contentView = webView
        hostingWindow.alphaValue = 0
        hostingWindow.ignoresMouseEvents = true
        hostingWindow.orderOut(nil)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.isHidden = false
    }

    func discover(item: MediaItem, searchURL: URL) async -> PublicTitleMetadata? {
        do {
            try Task.checkCancellation()
            try await navigate(to: searchURL)
            try await prepareSearchPage()

            var seenQueries = Set<String>()
            let queries = ([item.title] + item.matchingTitles)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .filter { seenQueries.insert(PersianMetadataText.normalizeTitle($0)).inserted }
                .sorted { PersianMetadataText.isPersian($0) && !PersianMetadataText.isPersian($1) }
                .prefix(3)

            for query in queries {
                try Task.checkCancellation()
                guard await setSearchQuery(query) else { continue }
                if provider == .filimo {
                    try await Task.sleep(nanoseconds: 450_000_000)
                    await applyMediaKindFilter(item.kind)
                }

                var match: (candidate: PublicMetadataCandidate, score: Double)?
                for _ in 0..<18 {
                    try Task.checkCancellation()
                    let candidates = await readCandidates()
                    if let best = PublicMetadataTitleMatcher.bestCandidate(
                        in: candidates,
                        matching: [item.title] + item.matchingTitles,
                        kind: item.kind,
                        year: item.year
                    ) {
                        match = best
                        break
                    }
                    try await Task.sleep(nanoseconds: 350_000_000)
                }

                guard let match else { continue }
                let pageURL: URL
                switch provider {
                case .filimo:
                    guard await clickFilimoCandidate(index: match.candidate.index),
                          let destination = await waitForFilimoTitlePage() else { continue }
                    pageURL = destination
                case .hexDL:
                    guard let destination = match.candidate.pageURL,
                          provider.accepts(destination) else { continue }
                    try await navigate(to: destination)
                    pageURL = destination
                }
                guard provider.accepts(pageURL), let metadata = await captureTitlePage(at: pageURL) else { continue }
                return metadata
            }
        } catch {
            return nil
        }
        return nil
    }

    private func navigate(to url: URL) async throws {
        guard provider.acceptsSearchPage(url) || provider.accepts(url) else {
            throw PublicMetadataDiscoveryError.blockedNavigation
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let id = UUID()
            pendingNavigation = (id, continuation)
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 25)
            request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
            if webView.load(request) == nil {
                finishNavigation(id: id, error: PublicMetadataDiscoveryError.navigationFailed)
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 25) { [weak self] in
                self?.finishNavigation(id: id, error: PublicMetadataDiscoveryError.navigationTimedOut)
            }
        }
    }

    private func prepareSearchPage() async throws {
        if provider == .filimo {
            for _ in 0..<48 {
                let ready = (try? await evaluate("!!document.querySelector('[data-test-id=search-input]')") as? Bool) ?? false
                if ready { return }
                try await Task.sleep(nanoseconds: 250_000_000)
            }
            throw PublicMetadataDiscoveryError.searchUnavailable
        }
        let openSearch = #"""
        (() => {
          const modal = document.querySelector('#hexajax-modal');
          if (!modal) return false;
          if (!modal.hidden && modal.getAttribute('aria-hidden') !== 'true' && getComputedStyle(modal).display !== 'none') return true;
          const link = Array.from(document.querySelectorAll('a[href]')).find(a => {
            try { return new URL(a.href).pathname === '/search/'; } catch (_) { return false; }
          });
          if (!link) return false;
          link.click();
          return true;
        })()
        """#
        guard (try await evaluate(openSearch) as? Bool) == true else {
            throw PublicMetadataDiscoveryError.searchUnavailable
        }
        for _ in 0..<20 {
            let ready = (try? await evaluate("(() => { const m=document.querySelector('#hexajax-modal'); const i=document.querySelector('#hexajax-input'); return !!(m && !m.hidden && i && m.getAttribute('aria-hidden') !== 'true' && getComputedStyle(m).display !== 'none'); })()") as? Bool) ?? false
            if ready { return }
            try await Task.sleep(nanoseconds: 150_000_000)
        }
        throw PublicMetadataDiscoveryError.searchUnavailable
    }

    private func setSearchQuery(_ query: String) async -> Bool {
        let selector = provider == .filimo
            ? "input[data-test-id=\"search-input\"]"
            : "#hexajax-input"
        let script = #"""
        (() => {
          const input = document.querySelector(__SELECTOR__);
          if (!input) return false;
          const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value')?.set;
          if (setter) setter.call(input, __QUERY__); else input.value = __QUERY__;
          input.dispatchEvent(new InputEvent('input', { bubbles: true, data: __QUERY__, inputType: 'insertText' }));
          input.dispatchEvent(new Event('change', { bubbles: true }));
          return true;
        })()
        """#
            .replacingOccurrences(of: "__SELECTOR__", with: Self.javaScriptString(selector))
            .replacingOccurrences(of: "__QUERY__", with: Self.javaScriptString(query))
        return (try? await evaluate(script) as? Bool) ?? false
    }

    private func applyMediaKindFilter(_ kind: String) async {
        guard kind == "Movie" || kind == "Series" else { return }
        let label = kind == "Movie" ? "فیلم" : "سریال"
        let script = #"""
        (() => {
          const target = __LABEL__;
          const button = Array.from(document.querySelectorAll('button')).find(b => (b.innerText || '').trim() === target);
          if (!button) return false;
          button.click();
          return true;
        })()
        """#.replacingOccurrences(of: "__LABEL__", with: Self.javaScriptString(label))
        _ = try? await evaluate(script)
    }

    private func readCandidates() async -> [PublicMetadataCandidate] {
        let selector = provider == .filimo ? "[role=\"link\"]" : "a.hexajax__link--post[href]"
        let script = #"""
        (() => {
          const selector = __SELECTOR__;
          const visible = e => {
            const r=e.getBoundingClientRect(), s=getComputedStyle(e);
            return r.width>0 && r.height>0 && s.display!=='none' && s.visibility!=='hidden' && Number(s.opacity)>0;
          };
          return Array.from(document.querySelectorAll(selector)).map((e,index) => {
            if (!visible(e)) return null;
            const hints = Array.from(e.querySelectorAll('span,b,strong,h1,h2,h3'))
              .filter(x => x.children.length===0 && visible(x))
              .map(x => (x.innerText || x.textContent || '').trim())
              .filter(x => x.length>0 && x.length<=180);
            const link = e.matches('a[href]') ? e : e.querySelector('a[href]');
            return {index, text:(e.innerText || '').trim(), titleHints:hints, pageURL:link?.href || null};
          }).filter(x => x && x.text.length>0 && x.text.length<=1200);
        })()
        """#.replacingOccurrences(of: "__SELECTOR__", with: Self.javaScriptString(selector))
        guard let rows = try? await evaluate(script) as? [[String: Any]] else { return [] }
        return rows.compactMap { row in
            guard let index = row["index"] as? Int,
                  let text = row["text"] as? String else { return nil }
            let hints = row["titleHints"] as? [String] ?? []
            let pageURL = (row["pageURL"] as? String).flatMap(URL.init(string:))
            return PublicMetadataCandidate(index: index, text: text, titleHints: hints, pageURL: pageURL)
        }
    }

    private func clickFilimoCandidate(index: Int) async -> Bool {
        let script = #"""
        (() => {
          const node = document.querySelectorAll('[role="link"]')[__INDEX__];
          if (!node) return false;
          node.click();
          return true;
        })()
        """#.replacingOccurrences(of: "__INDEX__", with: String(index))
        return (try? await evaluate(script) as? Bool) ?? false
    }

    private func waitForFilimoTitlePage() async -> URL? {
        for _ in 0..<40 {
            if Task.isCancelled { return nil }
            if let url = webView.url, provider.accepts(url) { return url }
            do { try await Task.sleep(nanoseconds: 250_000_000) } catch { return nil }
        }
        return nil
    }

    private func captureTitlePage(at url: URL) async -> PublicTitleMetadata? {
        let script = #"""
        (() => {
          const visible = e => {
            if (!e || !e.isConnected) return false;
            const r=e.getBoundingClientRect(), s=getComputedStyle(e);
            return r.width>0 && r.height>0 && s.display!=='none' && s.visibility!=='hidden' && Number(s.opacity)>0;
          };
          const clean = value => (value || '').replace(/\s+/g, ' ').trim();
          const meta = selector => document.querySelector(selector)?.content || '';
          const main = document.querySelector('main') || document.querySelector('article') || document.body;
          const headingNode = Array.from(main.querySelectorAll('h1')).find(visible);
          const heading = clean(headingNode?.innerText || '');
          const paragraphs = Array.from(main.querySelectorAll('p,[class*="description"],[class*="story"],[class*="summary"]'))
            .filter(visible).map(e => clean(e.innerText || e.textContent || ''))
            .filter(t => t.length>=55 && t.length<=1800);
          const synopsisCandidates = [meta('meta[property="og:description"]'), meta('meta[name="description"]'), ...paragraphs]
            .map(clean).filter(Boolean);
          const hasPersian = text => /[\u0600-\u06FF\uFB50-\uFDFF\uFE70-\uFEFF]{4}/.test(text);
          const synopsis = synopsisCandidates.find(hasPersian) || synopsisCandidates[0] || '';
          const title = clean(heading || meta('meta[property="og:title"]') || document.title);
          const visibleText = clean(document.body?.innerText || '');
          const imageURLs = Array.from(main.querySelectorAll('img')).filter(visible)
            .map(i => i.currentSrc || i.src || '').filter(Boolean);
          const posterURL = meta('meta[property="og:image"]') || meta('meta[name="twitter:image"]') || imageURLs[0] || '';
          const headings = Array.from(main.querySelectorAll('h1,h2,h3,h4')).filter(visible)
            .map(e => clean(e.innerText)).filter(Boolean);
          const episodeSnippets = Array.from(main.querySelectorAll('li,article,[role="listitem"]')).filter(visible)
            .map(e => clean(e.innerText)).filter(t => /(?:فصل|قسمت|episode|season)\s*\d*/i.test(t) && t.length<500);
          return JSON.stringify({title,heading,synopsis,visibleText,posterURL,imageURLs,headings,episodeSnippets});
        })()
        """#
        for _ in 0..<64 {
            if Task.isCancelled { return nil }
            if let raw = try? await evaluate(script) as? String,
               let data = raw.data(using: .utf8),
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let visibleText = (object["visibleText"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let heading = (object["heading"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if visibleText.count >= 80, !heading.isEmpty {
                    let currentURL = webView.url.flatMap { provider.accepts($0) ? $0 : nil } ?? url
                    let title = (object["title"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    let synopsis = (object["synopsis"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    let imageURLs = Self.urls(object["imageURLs"])
                    let posterURL = (object["posterURL"] as? String).flatMap(URL.init(string:))
                        .flatMap { Self.publicImageURL($0) ? $0 : nil }
                    return PublicTitleMetadata(
                        provider: provider,
                        pageURL: currentURL,
                        title: title.isEmpty ? itemFallbackTitle(at: currentURL) : title,
                        synopsis: String(synopsis.prefix(6_000)),
                        posterURL: posterURL ?? imageURLs.first,
                        visiblePageText: String(visibleText.prefix(40_000)),
                        visibleHeadings: Array(Self.strings(object["headings"]).prefix(100)),
                        episodeSnippets: Array(Self.strings(object["episodeSnippets"]).prefix(150)),
                        imageURLs: Array(imageURLs.prefix(40)),
                        importedAt: Date()
                    )
                }
            }
            do { try await Task.sleep(nanoseconds: 350_000_000) } catch { return nil }
        }
        return nil
    }

    private func evaluate(_ script: String) async throws -> Any? {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Any?, Error>) in
            webView.evaluateJavaScript(script) { value, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: value) }
            }
        }
    }

    private func itemFallbackTitle(at url: URL) -> String {
        url.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
    }

    private static func javaScriptString(_ value: String) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let encoded = String(data: data, encoding: .utf8) else { return "\"\"" }
        return encoded
    }

    private static func strings(_ value: Any?) -> [String] {
        (value as? [String] ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func urls(_ value: Any?) -> [URL] {
        strings(value).compactMap(URL.init(string:)).filter(publicImageURL)
    }

    private static func publicImageURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(), !host.isEmpty,
              !["localhost", "127.0.0.1", "::1"].contains(host) else { return false }
        return !["m3u8", "mpd", "mp4", "mkv", "webm", "srt", "vtt"].contains(url.pathExtension.lowercased())
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finishNavigation(error: nil)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finishNavigation(error: error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finishNavigation(error: error)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard navigationAction.targetFrame?.isMainFrame == true,
              let url = navigationAction.request.url,
              provider.acceptsSearchPage(url) || provider.accepts(url) else {
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        guard navigationResponse.isForMainFrame,
              let url = navigationResponse.response.url,
              provider.acceptsSearchPage(url) || provider.accepts(url) else {
            decisionHandler(.cancel)
            return
        }
        if let response = navigationResponse.response as? HTTPURLResponse,
           !(200..<400).contains(response.statusCode) {
            decisionHandler(.cancel)
            finishNavigation(error: PublicMetadataDiscoveryError.navigationFailed)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        nil
    }

    private func finishNavigation(error: Error?) {
        guard let pending = pendingNavigation else { return }
        pendingNavigation = nil
        if let error { pending.continuation.resume(throwing: error) }
        else { pending.continuation.resume() }
    }

    private func finishNavigation(id: UUID, error: Error) {
        guard pendingNavigation?.id == id else { return }
        finishNavigation(error: error)
    }
}

private enum PublicMetadataDiscoveryError: Error {
    case blockedNavigation
    case navigationFailed
    case navigationTimedOut
    case searchUnavailable
}
