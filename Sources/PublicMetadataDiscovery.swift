import AppKit
import Foundation
import WebKit

@MainActor
enum PublicMetadataDiscoveryService {
    static func discover(
        for item: MediaItem,
        provider: PublicMetadataProvider,
        includePageDetails: Bool = false
    ) async -> PublicTitleMetadata? {
        guard let searchURL = provider.searchURL else { return nil }
        switch await PublicMetadataAPIClient.discover(for: item, provider: provider) {
        case .match(let apiMetadata):
            guard includePageDetails else { return apiMetadata }
            return await enrichPageDetails(from: apiMetadata)
        case .searchedNoMatch, .unavailable: break
        }
        let session = PublicMetadataDiscoverySession(provider: provider)
        let discovered = await session.discover(item: item, searchURL: searchURL)
        session.close()
        guard let discovered else { return nil }
        guard includePageDetails else { return discovered }
        return await enrichPageDetails(from: discovered)
    }

    static func enrichPageDetails(from metadata: PublicTitleMetadata) async -> PublicTitleMetadata {
        let session = PublicMetadataDiscoverySession(provider: metadata.provider)
        let pageMetadata = await session.capturePublicTitlePage(at: metadata.pageURL)
        session.close()
        var merged = pageMetadata?.merging(metadata) ?? metadata
        merged.pageDetailsAttemptedAt = Date()
        if pageMetadata != nil {
            merged.pageDetailsVersion = PublicTitleMetadata.currentPageDetailsVersion
        }
        return merged
    }
}

enum PublicMetadataAPIClient {
    enum SearchResult: Sendable {
        case match(PublicTitleMetadata)
        case searchedNoMatch
        case unavailable
    }

    struct ParsedSearchPayload: Sendable {
        let hasExpectedShape: Bool
        let metadata: PublicTitleMetadata?
        let parsedOnMainThread: Bool
    }

    private struct CandidateRecord {
        let candidate: PublicMetadataCandidate
        let payload: [String: Any]
    }

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.httpMaximumConnectionsPerHost = 3
        return URLSession(configuration: configuration)
    }()

    static func discover(for item: MediaItem, provider: PublicMetadataProvider) async -> SearchResult {
        var successfulRequests = 0
        for query in queryVariants(for: item) {
            guard let url = searchURL(for: provider, query: query),
                  let data = try? await loadJSONData(from: url) else { continue }
            let parsed = await parseSearchPayload(data, item: item, provider: provider)
            guard parsed.hasExpectedShape else { continue }
            successfulRequests += 1
            if let metadata = parsed.metadata { return .match(metadata) }
        }
        return successfulRequests > 0 ? .searchedNoMatch : .unavailable
    }

    static func parseSearchPayload(
        _ data: Data,
        item: MediaItem,
        provider: PublicMetadataProvider
    ) async -> ParsedSearchPayload {
        await Task.detached(priority: .utility) {
            guard let payload = try? JSONSerialization.jsonObject(with: data),
                  hasExpectedSearchShape(payload, provider: provider) else {
                return ParsedSearchPayload(hasExpectedShape: false, metadata: nil, parsedOnMainThread: Self.isMainThread())
            }
            let metadata: PublicTitleMetadata?
            switch provider {
            case .filimo: metadata = filimoMetadata(from: payload, item: item)
            case .hexDL: metadata = hexDLMetadata(from: payload, item: item)
            }
            return ParsedSearchPayload(hasExpectedShape: true, metadata: metadata, parsedOnMainThread: Self.isMainThread())
        }.value
    }

    private static func isMainThread() -> Bool { Thread.isMainThread }

    private static func hasExpectedSearchShape(_ payload: Any, provider: PublicMetadataProvider) -> Bool {
        guard let root = payload as? [String: Any] else { return false }
        switch provider {
        case .filimo: return root["included"] is [[String: Any]]
        case .hexDL: return root["items"] is [[String: Any]]
        }
    }

    private static func queryVariants(for item: MediaItem) -> [String] {
        var seen = Set<String>()
        return ([item.title] + item.matchingTitles)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { seen.insert(PersianMetadataText.normalizeTitle($0)).inserted }
            .sorted { PersianMetadataText.isPersian($0) && !PersianMetadataText.isPersian($1) }
            .prefix(3)
            .map { $0 }
    }

    private static func searchURL(for provider: PublicMetadataProvider, query: String) -> URL? {
        switch provider {
        case .filimo:
            let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
            guard let segment = query.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
            var components = URLComponents()
            components.scheme = "https"
            components.host = "www.filimo.com"
            components.percentEncodedPath = "/api/fa/v1/movie/movie/list/tagid/1000300/text/\(segment)"
            return components.url
        case .hexDL:
            var components = URLComponents(string: "https://hexdl.com/wp-json/hexdl/v1/search")
            components?.queryItems = [
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "page", value: "1"),
                URLQueryItem(name: "limit", value: "20"),
                URLQueryItem(name: "type", value: "all")
            ]
            return components?.url
        }
    }

    private static func loadJSONData(from url: URL) async throws -> Data {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard data.count <= 2_000_000,
              let response = response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode) else {
            throw PublicMetadataAPIError.invalidResponse
        }
        return data
    }

    private static func filimoMetadata(from payload: Any, item: MediaItem) -> PublicTitleMetadata? {
        guard let root = payload as? [String: Any],
              let included = root["included"] as? [[String: Any]] else { return nil }
        let records = included.enumerated().compactMap { index, record -> CandidateRecord? in
            guard record["type"] as? String == "movies",
                  let attributes = record["attributes"] as? [String: Any],
                  let title = string(attributes["movie_title"]), !title.isEmpty,
                  let id = string(record["id"]), id.range(of: #"^[A-Za-z0-9]+$"#, options: .regularExpression) != nil else { return nil }
            let serial = attributes["serial"] as? [String: Any]
            let isSeries = serial?["enable"] as? Bool ?? false
            let year = string(attributes["pro_year"]) ?? ""
            let englishTitle = string(attributes["movie_title_en"]) ?? ""
            let kindLabel = isSeries ? "سریال" : "فیلم"
            let hints = [title, englishTitle, string(serial?["parent_title"]) ?? ""].filter { !$0.isEmpty }
            let candidate = PublicMetadataCandidate(
                index: index,
                text: "\(title) \(englishTitle) \(year) \(kindLabel)",
                titleHints: hints,
                pageURL: URL(string: "https://www.filimo.com/m/\(id)")
            )
            return CandidateRecord(candidate: candidate, payload: attributes)
        }
        guard let best = PublicMetadataTitleMatcher.bestCandidate(
            in: records.map(\.candidate),
            matching: [item.title] + item.matchingTitles,
            kind: item.kind,
            year: item.year
        ),
        let selected = records.first(where: { $0.candidate.index == best.candidate.index }),
        let pageURL = best.candidate.pageURL else { return nil }

        let synopsis = cleanText(string(selected.payload["descr"]) ?? "")
        let posterURL = filimoImageURL(selected.payload["cover"])
        let title = string(selected.payload["movie_title"]) ?? string(selected.payload["movie_title_en"]) ?? ""
        let originalTitle = string(selected.payload["movie_title_en"])
        let imdbRating = ratingString(selected.payload["imdb_rate"])
        let communityRating = ratingString(selected.payload["rate_avrage"])
        let categories = metadataStrings(selected.payload["categories"], keys: ["title_en", "title", "name"])
            .map(PublicMetadataGenreParser.canonicalName)
        let countries = metadataStrings(selected.payload["countries"], keys: ["country", "country_en", "name"])
        return PublicTitleMetadata(
            provider: .filimo,
            pageURL: pageURL,
            title: title,
            synopsis: synopsis,
            posterURL: posterURL,
            visiblePageText: String(([title, originalTitle, string(selected.payload["pro_year"]),
                                     countries.joined(separator: ", "), categories.joined(separator: ", "), synopsis]
                .compactMap { $0 }.joined(separator: "\n")).prefix(40_000)),
            visibleHeadings: [title],
            episodeSnippets: [],
            imageURLs: posterURL.map { [$0] } ?? [],
            importedAt: Date(),
            originalTitle: originalTitle,
            year: string(selected.payload["pro_year"]),
            country: countries.isEmpty ? nil : countries.joined(separator: ", "),
            contentRating: filimoAgeRating(string(selected.payload["age_range"])),
            publicRating: imdbRating,
            ratingSource: imdbRating == nil ? nil : "IMDb",
            communityRating: communityRating,
            runtime: displayRuntime(selected.payload["duration"]),
            director: string(selected.payload["director"]),
            genres: categories.isEmpty ? nil : categories
        )
    }

    private static func hexDLMetadata(from payload: Any, item: MediaItem) -> PublicTitleMetadata? {
        guard let root = payload as? [String: Any],
              let items = root["items"] as? [[String: Any]] else { return nil }
        let records = items.enumerated().compactMap { index, payload -> CandidateRecord? in
            guard let title = string(payload["title"]), !title.isEmpty,
                  let link = string(payload["link"]).flatMap(URL.init(string:)),
                  PublicMetadataProvider.hexDL.accepts(link) else { return nil }
            let titleFA = string(payload["title_fa"]) ?? ""
            let titleEN = string(payload["title_en"]) ?? ""
            let year = string(payload["year"]) ?? ""
            let type = string(payload["type_label"]) ?? ""
            let hints = [titleFA, titleEN, title].filter { !$0.isEmpty }
            let candidate = PublicMetadataCandidate(
                index: index,
                text: "\(title) \(titleFA) \(titleEN) \(year) \(type)",
                titleHints: hints,
                pageURL: link
            )
            return CandidateRecord(candidate: candidate, payload: payload)
        }
        guard let best = PublicMetadataTitleMatcher.bestCandidate(
            in: records.map(\.candidate),
            matching: [item.title] + item.matchingTitles,
            kind: item.kind,
            year: item.year
        ),
        let selected = records.first(where: { $0.candidate.index == best.candidate.index }),
        let pageURL = best.candidate.pageURL else { return nil }

        let synopsis = cleanText(string(selected.payload["plot"]) ?? string(selected.payload["excerpt"]) ?? "")
        let posterURL = string(selected.payload["thumb"]).flatMap(URL.init(string:)).flatMap { url -> URL? in
            guard url.scheme?.lowercased() == "https",
                  let host = url.host?.lowercased(), host == "hexdl.com" || host.hasSuffix(".hexdl.com") else { return nil }
            return url
        }
        let title = string(selected.payload["title_fa"]) ?? string(selected.payload["title_en"])
            ?? string(selected.payload["title"]) ?? ""
        let originalTitle = string(selected.payload["title_en"])
        let genres = metadataStrings(selected.payload["genres"], keys: ["name", "title", "title_en"])
            .map(PublicMetadataGenreParser.canonicalName)
        let badges = metadataStrings(selected.payload["badges"], keys: ["label", "title", "name", "text"])
        let rating = ratingString(selected.payload["rate"])
        return PublicTitleMetadata(
            provider: .hexDL,
            pageURL: pageURL,
            title: title,
            synopsis: synopsis,
            posterURL: posterURL,
            visiblePageText: String("\(title)\n\(synopsis)".prefix(40_000)),
            visibleHeadings: [title],
            episodeSnippets: [],
            imageURLs: posterURL.map { [$0] } ?? [],
            importedAt: Date(),
            originalTitle: originalTitle,
            year: string(selected.payload["year"]),
            publicRating: rating,
            ratingSource: rating == nil ? nil : "HexDL",
            genres: genres.isEmpty ? nil : genres,
            publicBadges: badges.isEmpty ? nil : badges
        )
    }

    private static func metadataStrings(_ value: Any?, keys: [String]) -> [String] {
        let values: [String]
        if let array = value as? [Any] {
            values = array.compactMap { element in
                if let text = element as? String { return text }
                guard let object = element as? [String: Any] else { return nil }
                return keys.compactMap { string(object[$0]) }.first
            }
        } else if let text = value as? String {
            values = text.components(separatedBy: CharacterSet(charactersIn: ",،•·"))
        } else {
            values = []
        }
        var seen = Set<String>()
        return values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }

    private static func ratingString(_ value: Any?) -> String? {
        guard let raw = string(value)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let number = Double(raw.replacingOccurrences(of: ",", with: ".")),
              number > 0, number <= 10 else { return nil }
        return String(format: "%.1f", number)
    }

    private static func filimoAgeRating(_ value: String?) -> String? {
        guard let value,
              let match = value.range(of: #"^\s*(\d{1,2})"#, options: .regularExpression),
              let firstNumber = value[match].split(whereSeparator: { !$0.isNumber }).first,
              let age = Int(firstNumber), age > 0 else { return nil }
        return "\(age)+"
    }

    private static func displayRuntime(_ value: Any?) -> String? {
        guard let raw = string(value)?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty,
              raw.range(of: #"^\d{1,3}:\d{2}(?::\d{2})?$"#, options: .regularExpression) != nil else { return nil }
        return raw
    }

    private static func filimoImageURL(_ value: Any?) -> URL? {
        guard let path = string(value), !path.isEmpty else { return nil }
        let rawURL = path.hasPrefix("https://")
            ? path
            : "https://static.cdn.asset.filimo.com/\(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))"
        guard let url = URL(string: rawURL),
              url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(), host == "filimo.com" || host.hasSuffix(".filimo.com") else { return nil }
        return url
    }

    private static func string(_ value: Any?) -> String? {
        guard let value, !(value is NSNull) else { return nil }
        if let value = value as? String { return value }
        if let value = value as? NSNumber { return value.stringValue }
        return nil
    }

    private static func cleanText(_ value: String) -> String {
        let withoutTags = value.replacingOccurrences(of: #"<[^>]*>"#, with: " ", options: .regularExpression)
        let entities: [(String, String)] = [
            ("&amp;", "&"), ("&quot;", "\""), ("&#39;", "'"), ("&#039;", "'"),
            ("&#8217;", "’"), ("&#8211;", "–"), ("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">")
        ]
        let decoded = entities.reduce(withoutTags) { $0.replacingOccurrences(of: $1.0, with: $1.1) }
        return decoded.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private enum PublicMetadataAPIError: Error {
    case invalidResponse
}

@MainActor
private final class PublicMetadataDiscoverySession: NSObject, WKNavigationDelegate, WKUIDelegate {
    private let provider: PublicMetadataProvider
    private let webView: WKWebView
    private let hostingWindow: NSWindow
    private var pendingNavigation: (id: UUID, continuation: CheckedContinuation<Void, Error>)?
    private var isClosed = false

    init(provider: PublicMetadataProvider) {
        self.provider = provider
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        configuration.allowsAirPlayForMediaPlayback = false
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1024, height: 768),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        // NSWindow defaults to releasing itself on close; ARC already owns it.
        window.isReleasedWhenClosed = false
        hostingWindow = window
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

    func close() {
        guard !isClosed else { return }
        isClosed = true
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        hostingWindow.contentView = nil
        hostingWindow.close()
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

    func capturePublicTitlePage(at url: URL) async -> PublicTitleMetadata? {
        guard provider.accepts(url) else { return nil }
        do {
            try Task.checkCancellation()
            try await navigate(to: url)
            guard provider == .filimo else { return await captureTitlePage(at: url) }

            var combined: PublicTitleMetadata?
            for tabID in ["info", "episodes"] {
                guard await activateFilimoTab(tabID) else { continue }
                try await Task.sleep(nanoseconds: 450_000_000)
                if let page = await captureTitlePage(at: url) {
                    combined = combined.map { page.merging($0) } ?? page
                }

                guard tabID == "episodes" else { continue }
                let seasonCount = min(await filimoSeasonButtonCount(), 24)
                for index in 0..<seasonCount {
                    try Task.checkCancellation()
                    guard await selectFilimoSeason(at: index) else { continue }
                    try await Task.sleep(nanoseconds: 350_000_000)
                    if let seasonPage = await captureTitlePage(at: url) {
                        combined = combined.map { seasonPage.merging($0) } ?? seasonPage
                    }
                }
            }
            if let combined { return combined }
            return await captureTitlePage(at: url)
        } catch {
            return nil
        }
    }

    private func activateFilimoTab(_ id: String) async -> Bool {
        guard ["info", "episodes"].contains(id) else { return false }
        let script = #"""
        (() => {
          const tab = document.querySelector('[data-test-id="__TAB_ID__"]');
          if (!tab) return false;
          if (tab.getAttribute('aria-selected') !== 'true') tab.click();
          return true;
        })()
        """#.replacingOccurrences(of: "__TAB_ID__", with: id)
        return (try? await evaluate(script) as? Bool) ?? false
    }

    private func filimoSeasonButtonCount() async -> Int {
        let script = #"""
        (() => {
          const clean = e => (e?.innerText || '').replace(/\s+/g, ' ').trim();
          const visible = e => {
            const r=e.getBoundingClientRect(), s=getComputedStyle(e);
            return r.width>0 && r.height>0 && s.display!=='none' && s.visibility!=='hidden' && Number(s.opacity)>0;
          };
          return Array.from(document.querySelectorAll('button'))
            .filter(e => visible(e) && /^فصل(?:\s|$)/.test(clean(e))).length;
        })()
        """#
        return (try? await evaluate(script) as? Int) ?? 0
    }

    private func selectFilimoSeason(at index: Int) async -> Bool {
        guard (0..<24).contains(index) else { return false }
        let script = #"""
        (() => {
          const clean = e => (e?.innerText || '').replace(/\s+/g, ' ').trim();
          const visible = e => {
            const r=e.getBoundingClientRect(), s=getComputedStyle(e);
            return r.width>0 && r.height>0 && s.display!=='none' && s.visibility!=='hidden' && Number(s.opacity)>0;
          };
          const buttons = Array.from(document.querySelectorAll('button'))
            .filter(e => visible(e) && /^فصل(?:\s|$)/.test(clean(e)));
          const button = buttons[__INDEX__];
          if (!button) return false;
          button.click();
          return true;
        })()
        """#.replacingOccurrences(of: "__INDEX__", with: String(index))
        return (try? await evaluate(script) as? Bool) ?? false
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
          const visibleLines = (document.body?.innerText || '').split(/\n+/).map(clean).filter(Boolean);
          const visibleText = visibleLines.join('\n');
          const mainLines = (main.innerText || '').split(/\n+/).map(clean).filter(Boolean);
          const headerText = mainLines.slice(0, 18).join(' · ').slice(0, 1600);
          const asciiDigits = value => (value || '').replace(/[۰-۹٠-٩]/g, digit => String('۰۱۲۳۴۵۶۷۸۹٠١٢٣٤٥٦٧٨٩'.indexOf(digit) % 10));
          const normalizedHeader = asciiDigits(headerText);
          const year = normalizedHeader.match(/(?:13\d{2}|14\d{2}|19\d{2}|20\d{2})/)?.[0] || '';
          const yearLine = mainLines.find(line => asciiDigits(line).includes(year) && year.length === 4) || '';
          const country = clean(yearLine.replace(new RegExp('(?:13|14|19|20)\\d{2}'), '')
            .replace(/محصول|produced in/ig, '').replace(/[()•·|]/g, ' '));
          const contentRating = normalizedHeader.match(/\b(?:TV-Y7?|TV-G|TV-PG|TV-14|TV-MA|G|PG-13|PG|R|NC-17|18\+)\b/i)?.[0] || '';
          const communityMatch = normalizedHeader.match(/%\s*(\d{1,3})\s*\((\d+)\)\s*(?:رای|votes?)/i);
          const communityRating = communityMatch ? `${communityMatch[1]}%` : '';
          const communityVotes = communityMatch ? communityMatch[2] : '';
          const normalizedPageLines = visibleLines.map(asciiDigits);
          const seasonCountMatch = normalizedPageLines.map(line => line.match(/(\d+)\s*فصل/)).find(Boolean);
          const episodeCountMatch = normalizedPageLines.map(line =>
            line.match(/فصل\s*\d+\s+(\d+)\s*قسمت/) || line.match(/(\d+)\s*قسمت/)
          ).find(Boolean);
          const genreMap = new Map([
            ['action','Action'],['اکشن','Action'],['adventure','Adventure'],['ماجراجویی','Adventure'],
            ['animation','Animation'],['انیمیشن','Animation'],['biography','Biography'],['زندگی‌نامه','Biography'],
            ['comedy','Comedy'],['کمدی','Comedy'],['crime','Crime'],['جنایی','Crime'],
            ['documentary','Documentary'],['مستند','Documentary'],['drama','Drama'],['درام','Drama'],
            ['family','Family'],['خانوادگی','Family'],['fantasy','Fantasy'],['فانتزی','Fantasy'],
            ['history','History'],['تاریخی','History'],['horror','Horror'],['ترسناک','Horror'],
            ['music','Music'],['موسیقی','Music'],['musical','Musical'],['موزیکال','Musical'],
            ['mystery','Mystery'],['معمایی','Mystery'],['reality-tv','Reality-TV'],['واقع‌نما','Reality-TV'],
            ['romance','Romance'],['عاشقانه','Romance'],['sci-fi','Sci-Fi'],['science fiction','Sci-Fi'],
            ['علمی-تخیلی','Sci-Fi'],['علمی تخیلی','Sci-Fi'],['thriller','Thriller'],['هیجان‌انگیز','Thriller'],
            ['war','War'],['جنگی','War'],['western','Western'],['وسترن','Western'],
            ['talk-show','Talk-Show'],['گفت‌وگو','Talk-Show'],['sport','Sport'],['ورزشی','Sport']
          ]);
          const genres = Array.from(main.querySelectorAll('a[href],li,span'))
            .filter(visible).map(e => clean(e.innerText || e.getAttribute('aria-label') || '').toLocaleLowerCase())
            .map(label => genreMap.get(label)).filter(Boolean);
          const originalTitle = mainLines.slice(0, 12).find(line => line !== heading && /[A-Za-z]{3}/.test(line)
            && line.length <= 100 && !/^(?:ONLINE|1080p|720p|480p|CC)$/i.test(line))
            ?.replace(/\s+(?:TV-[A-Z0-9]+|PG-13|PG|R|NC-17|\d+(?:\.\d+)?|ONLINE|1080p|720p|480p|CC).*$/i, '') || '';
          const imdbRating = normalizedHeader.match(/(?:امتیاز\s*آی\s*ام\s*دی\s*بی|IMDb)\s*[:：]?\s*(\d{1,2}\.\d)/i)?.[1] || '';
          const isHexDL = /(^|\.)hexdl\.com$/i.test(location.hostname);
          const hexRating = isHexDL ? normalizedHeader.match(/(?:^|\s)(\d{1,2}\.\d)(?=\s|$)/)?.[1] || '' : '';
          const publicRating = imdbRating || hexRating;
          const ratingSource = imdbRating ? 'IMDb' : (hexRating ? 'HexDL' : '');
          const runtime = headerText.match(/\b\d{1,3}\s*(?:min(?:utes)?|دقیقه)/i)?.[0] || '';
          const badgePattern = /^(?:TV-Y7?|TV-G|TV-PG|TV-14|TV-MA|G|PG-13|PG|R|NC-17|18\+|ONLINE|1080p|720p|480p|4K|HDR|CC|دوبله فارسی|زیرنویس فارسی|زیرنویس چسبیده|زیرنویس|دوبله)$/i;
          const publicBadges = Array.from(main.querySelectorAll('li,span,div')).filter(visible)
            .map(e => clean(e.innerText || '')).filter(t => t.length <= 30 && badgePattern.test(t));
          const directorLine = visibleLines.find(line => /(?:کارگردان|director)\s*[:：]/i.test(line)) || '';
          const director = directorLine.match(/(?:کارگردان|director)\s*[:：]\s*([^,،؛;|]+?)(?=\s*(?:بازیگران?|تهیه[‌ ]کننده|نویسنده|producer|writer|cast)\s*[:：]|$)/i)?.[1]?.trim() || '';
          const creditLabel = '(?:کارگردان|تهیه[‌ ]کننده|نویسنده|بازیگران?|director|producer|writer|cast|actors?)';
          const labeledCastNames = visibleLines.flatMap(line => {
            const match = line.match(/(?:بازیگران?|cast|actors?)\s*[:：]\s*([^.;|]+)/i);
            if (!match) return [];
            const names = match[1].split(new RegExp('\\s*(?=' + creditLabel + '\\s*[:：])', 'i'))[0];
            return names.split(/[,،|]/).map(clean).filter(name => name.length > 1 && name.length < 100);
          });
          const labeledCrewNames = visibleLines.flatMap(line => {
            const expression = new RegExp('(کارگردان|تهیه[‌ ]کننده|نویسنده|director|producer|writer)\\s*[:：]\\s*([^,،؛;|]+?)(?=\\s*(?:' + creditLabel + ')\\s*[:：]|$)', 'ig');
            const names = [];
            for (const match of line.matchAll(expression)) names.push(...match[2].split(/[,،]/).map(clean));
            return names.filter(name => name.length > 1 && name.length < 100);
          });
          const filimoPeople = Array.from(main.querySelectorAll('a[href^="/crew/"]'))
            .filter(a => visible(a) && a.getAttribute('aria-hidden') !== 'true' && a.getAttribute('tabindex') !== '-1')
            .map(a => {
              const labels = Array.from(a.querySelectorAll('span')).map(span => clean(span.innerText)).filter(Boolean);
              return {name: labels[0] || clean(a.innerText), role: labels[labels.length - 1] || ''};
            }).filter(person => person.name.length > 1 && person.name.length < 100);
          const uniqueNames = names => Array.from(new Map(names.map(name => [name.toLocaleLowerCase(), name])).values());
          const castNames = uniqueNames([
            ...filimoPeople.filter(person => /بازیگر|actor|cast/i.test(person.role)).map(person => person.name),
            ...labeledCastNames
          ]);
          const crewNames = uniqueNames([
            ...filimoPeople.filter(person => /کارگردان|نویسنده|تهیه|director|writer|producer/i.test(person.role)).map(person => person.name),
            ...labeledCrewNames
          ]);
          const imageURLs = Array.from(main.querySelectorAll('img')).filter(visible)
            .map(i => i.currentSrc || i.src || '').filter(Boolean);
          const posterURL = meta('meta[property="og:image"]') || meta('meta[name="twitter:image"]') || imageURLs[0] || '';
          const headings = Array.from(main.querySelectorAll('h1,h2,h3,h4')).filter(visible)
            .map(e => clean(e.innerText)).filter(Boolean);
          const episodeMatches = visibleLines.flatMap((line, index) => {
            const match = asciiDigits(line).match(/(?:قسمت|episode)\s*(?:#\s*)?(\d+)/i);
            return match ? [{line, index, number:Number(match[1])}] : [];
          });
          const episodeSnippets = episodeMatches.map(({line,index}) => {
            const season = visibleLines.slice(index + 1, index + 5)
              .find(candidate => /(?:فصل|season)\s*\d+/i.test(asciiDigits(candidate)));
            return clean([line, season].filter(Boolean).join(' · '));
          }).filter(Boolean);
          const visibleSeasonCount = new Set(visibleLines.flatMap(line => {
            const match = asciiDigits(line).match(/(?:فصل|season)\s*(\d+)/i);
            return match ? [Number(match[1])] : [];
          })).size;
          return JSON.stringify({title,originalTitle,year,country,contentRating,publicRating,ratingSource,
            communityRating,communityVotes,publicBadges,runtime,director,
            genres,seasonCount:seasonCountMatch ? Number(seasonCountMatch[1]) : (visibleSeasonCount || null),
            episodeCount:episodeCountMatch ? Number(episodeCountMatch[1]) : null,
            castNames,crewNames,synopsis,visibleText,posterURL,imageURLs,headings,episodeSnippets});
        })()
        """#
        for _ in 0..<64 {
            if Task.isCancelled { return nil }
            if let raw = try? await evaluate(script) as? String,
               let data = raw.data(using: .utf8),
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let visibleText = (object["visibleText"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let headings = Self.strings(object["headings"])
                let heading = headings.first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
                    ?? (object["title"] as? String ?? "")
                if visibleText.count >= 80, !heading.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let currentURL = webView.url.flatMap { provider.accepts($0) ? $0 : nil } ?? url
                    let title = (object["title"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    let synopsis = (object["synopsis"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    let imageURLs = Self.urls(object["imageURLs"])
                    let posterURL = (object["posterURL"] as? String).flatMap(URL.init(string:))
                        .flatMap { Self.publicImageURL($0) ? $0 : nil }
                    let stringValue: (String) -> String? = { key in
                        guard let value = object[key] as? String else { return nil }
                        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                        return trimmed.isEmpty ? nil : trimmed
                    }
                    let integerValue: (String) -> Int? = { key in
                        guard let number = object[key] as? NSNumber, number.intValue > 0 else { return nil }
                        return number.intValue
                    }
                    let genres = Self.uniqueStrings(object["genres"], limit: 12)
                    let castNames = Self.uniqueStrings(object["castNames"], limit: 40)
                    let crewNames = Self.uniqueStrings(object["crewNames"], limit: 30)
                    let publicBadges = Self.uniqueStrings(object["publicBadges"], limit: 20)
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
                        importedAt: Date(),
                        originalTitle: stringValue("originalTitle"),
                        year: stringValue("year"),
                        country: stringValue("country"),
                        contentRating: stringValue("contentRating"),
                        publicRating: stringValue("publicRating"),
                        ratingSource: stringValue("ratingSource"),
                        communityRating: stringValue("communityRating"),
                        communityVotes: stringValue("communityVotes"),
                        runtime: stringValue("runtime"),
                        director: stringValue("director"),
                        genres: genres.isEmpty ? nil : genres,
                        seasonCount: integerValue("seasonCount"),
                        episodeCount: integerValue("episodeCount"),
                        castNames: castNames.isEmpty ? nil : castNames,
                        crewNames: crewNames.isEmpty ? nil : crewNames,
                        publicBadges: publicBadges.isEmpty ? nil : publicBadges,
                        pageDetailsVersion: PublicTitleMetadata.currentPageDetailsVersion
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

    private static func uniqueStrings(_ value: Any?, limit: Int) -> [String] {
        var seen = Set<String>()
        return Array(strings(value).filter { seen.insert($0).inserted }.prefix(limit))
    }

    private static func urls(_ value: Any?) -> [URL] {
        strings(value).compactMap(URL.init(string:)).filter(publicImageURL)
    }

    private static func publicImageURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(), !host.isEmpty,
              !["localhost", "127.0.0.1", "::1"].contains(host) else { return false }
        let sensitiveQueryNames: Set<String> = [
            "token", "access_token", "secret", "signature", "sig", "auth", "authorization", "key", "expires", "policy"
        ]
        if URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.contains(where: {
            sensitiveQueryNames.contains($0.name.lowercased())
        }) == true { return false }
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
