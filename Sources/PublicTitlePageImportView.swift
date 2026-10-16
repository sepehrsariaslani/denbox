import AppKit
import SwiftUI
import WebKit

private struct PublicPageCapture {
    let pageURL: URL
    let title: String
    let synopsis: String
    let posterURL: URL?
    let visiblePageText: String
    let visibleHeadings: [String]
    let episodeSnippets: [String]
    let imageURLs: [URL]

    func metadata(provider: PublicMetadataProvider, title: String, synopsis: String) -> PublicTitleMetadata {
        PublicTitleMetadata(
            provider: provider,
            pageURL: pageURL,
            title: title,
            synopsis: synopsis,
            posterURL: posterURL,
            visiblePageText: visiblePageText,
            visibleHeadings: visibleHeadings,
            episodeSnippets: episodeSnippets,
            imageURLs: imageURLs,
            importedAt: Date()
        )
    }
}

private struct PublicPageCaptureError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct PublicTitlePageImportView: View {
    @Environment(\.dismiss) private var dismiss
    let provider: PublicMetadataProvider
    let url: URL
    let onImport: (PublicTitleMetadata) -> Void

    @State private var capture: PublicPageCapture?
    @State private var title = ""
    @State private var synopsis = ""
    @State private var captureRequest = 0
    @State private var status = "Loading public page…"
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(DenboxLanguage.localizedMessage("Public details from \(provider.rawValue)"))
                        .font(.denbox(size: 17, weight: .semibold))
                    Text(url.absoluteString)
                        .font(.denbox(size: 10))
                        .foregroundStyle(Color(red: 0.62, green: 0.65, blue: 0.69))
                        .lineLimit(1)
                }
                Spacer()
                Button("Recapture visible text") { captureRequest += 1 }
                    .disabled(capture == nil)
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(16)

            PublicTitlePageWebView(provider: provider, url: url, captureRequest: captureRequest) { result in
                switch result {
                case .success(let newCapture):
                    capture = newCapture
                    title = newCapture.title
                    synopsis = newCapture.synopsis
                    status = "Visible page text is ready. Review it before saving."
                    errorMessage = nil
                case .failure(let message):
                    status = ""
                    errorMessage = message.localizedDescription
                }
            }
            .frame(minHeight: 300, idealHeight: 390, maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 10) {
                if let capture {
                    HStack(alignment: .top, spacing: 14) {
                        if let posterURL = capture.posterURL {
                            AsyncImage(url: posterURL) { image in
                                image.resizable().scaledToFill()
                            } placeholder: {
                                RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08))
                            }
                            .frame(width: 86, height: 120)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Title to match in the catalog")
                                .font(.denbox(size: 10, weight: .medium))
                                .foregroundStyle(Color(red: 0.62, green: 0.65, blue: 0.69))
                            TextField("Persian or English title", text: $title)
                                .textFieldStyle(.roundedBorder)
                            Text("Persian synopsis")
                                .font(.denbox(size: 10, weight: .medium))
                                .foregroundStyle(Color(red: 0.62, green: 0.65, blue: 0.69))
                            TextEditor(text: $synopsis)
                                .font(.denbox(size: 12))
                                .frame(minHeight: 74, maxHeight: 110)
                                .scrollContentBackground(.hidden)
                                .padding(4)
                                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
                        }
                    }

                    if !capture.episodeSnippets.isEmpty {
                        DisclosureGroup(DenboxLanguage.localizedMessage("Visible episode details on this page (\(capture.episodeSnippets.count))")) {
                            ScrollView {
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(Array(capture.episodeSnippets.enumerated()), id: \.offset) { _, snippet in
                                        Text(snippet)
                                            .font(.denbox(size: 11))
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                            }
                            .frame(maxHeight: 115)
                        }
                        .font(.denbox(size: 11, weight: .medium))
                    }

                    if !capture.visiblePageText.isEmpty {
                        DisclosureGroup("Full public text on this page") {
                            ScrollView {
                                Text(capture.visiblePageText)
                                    .font(.denbox(size: 11))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                            }
                            .frame(maxHeight: 130)
                        }
                        .font(.denbox(size: 11, weight: .medium))
                    }
                } else {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(DenboxLanguage.localizedMessage(status)).font(.denbox(size: 11)).foregroundStyle(Color(red: 0.62, green: 0.65, blue: 0.69))
                    }
                }

                if let errorMessage {
                    Text(DenboxLanguage.localizedMessage(errorMessage)).font(.denbox(size: 11)).foregroundStyle(.orange)
                }

                HStack {
                    if let capture, let imageURL = capture.posterURL {
                        Link("Open original image", destination: imageURL)
                            .font(.denbox(size: 10))
                    }
                    Spacer()
                    Button("Save to local catalog") {
                        guard let capture, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                        onImport(capture.metadata(provider: provider, title: title, synopsis: synopsis))
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(capture == nil || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(16)
        }
        .frame(minWidth: 900, minHeight: 760)
        .background(Color(red: 0.055, green: 0.061, blue: 0.071))
    }
}

private struct PublicTitlePageWebView: NSViewRepresentable {
    let provider: PublicMetadataProvider
    let url: URL
    let captureRequest: Int
    let onCapture: (Result<PublicPageCapture, PublicPageCaptureError>) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(provider: provider, sourceURL: url, onCapture: onCapture)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        configuration.allowsAirPlayForMediaPlayback = false
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.onCapture = onCapture
        if context.coordinator.lastCaptureRequest != captureRequest {
            context.coordinator.lastCaptureRequest = captureRequest
            context.coordinator.captureVisiblePage(in: webView, attempt: 0)
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let provider: PublicMetadataProvider
        let sourceURL: URL
        var onCapture: (Result<PublicPageCapture, PublicPageCaptureError>) -> Void
        var lastCaptureRequest = 0
        private var didFinishNavigation = false

        init(provider: PublicMetadataProvider, sourceURL: URL,
             onCapture: @escaping (Result<PublicPageCapture, PublicPageCaptureError>) -> Void) {
            self.provider = provider
            self.sourceURL = sourceURL
            self.onCapture = onCapture
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            didFinishNavigation = true
            captureVisiblePage(in: webView, attempt: 0)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            onCapture(.failure(PublicPageCaptureError(message: "The public page failed to load: \(error.localizedDescription)")))
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            onCapture(.failure(PublicPageCaptureError(message: "Could not connect to the public page: \(error.localizedDescription)")))
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard navigationAction.targetFrame?.isMainFrame != false,
                  let targetURL = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }
            decisionHandler(provider.accepts(targetURL) ? .allow : .cancel)
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            nil
        }

        func captureVisiblePage(in webView: WKWebView, attempt: Int) {
            guard didFinishNavigation || attempt > 0 else { return }
            let script = Self.captureScript
            webView.evaluateJavaScript(script) { [weak self, weak webView] result, error in
                guard let self else { return }
                if let error {
                    self.onCapture(.failure(PublicPageCaptureError(message: "Could not read the visible page text: \(error.localizedDescription)")))
                    return
                }
                guard let json = result as? String,
                      let data = json.data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    self.retryOrFail(webView: webView, attempt: attempt)
                    return
                }
                let visibleText = (object["visibleText"] as? String ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let title = (object["title"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard visibleText.count >= 80 else {
                    self.retryOrFail(webView: webView, attempt: attempt)
                    return
                }
                let headings = Self.strings(object["headings"])
                let episodeSnippets = Self.strings(object["episodeSnippets"])
                let imageURLs = Self.urls(object["images"])
                let posterURL = URL(string: object["posterURL"] as? String ?? "")
                    .flatMap { Self.publicImageURL($0) ? $0 : nil }
                self.onCapture(.success(PublicPageCapture(
                    pageURL: self.sourceURL,
                    title: title.isEmpty ? self.provider.rawValue : title,
                    synopsis: (object["synopsis"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                    posterURL: posterURL ?? imageURLs.first,
                    visiblePageText: String(visibleText.prefix(40_000)),
                    visibleHeadings: Array(headings.prefix(100)),
                    episodeSnippets: Array(episodeSnippets.prefix(150)),
                    imageURLs: Array(imageURLs.prefix(40))
                )))
            }
        }

        private func retryOrFail(webView: WKWebView?, attempt: Int) {
            guard attempt < 15, let webView else {
                onCapture(.failure(PublicPageCaptureError(message: "No public page text could be extracted. Try a title page with an About section.")))
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self, weak webView] in
                guard let self, let webView else { return }
                self.captureVisiblePage(in: webView, attempt: attempt + 1)
            }
        }

        private static func strings(_ value: Any?) -> [String] {
            (value as? [String] ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }

        private static func urls(_ value: Any?) -> [URL] {
            strings(value).compactMap { URL(string: $0) }.filter(publicImageURL)
        }

        private static func publicImageURL(_ url: URL) -> Bool {
            guard let scheme = url.scheme?.lowercased(), ["https", "http"].contains(scheme),
                  let host = url.host?.lowercased() else { return false }
            return !host.isEmpty && !host.contains("localhost")
        }

        private static let captureScript = #"""
        (() => {
          const visible = (e) => {
            if (!e || !e.isConnected) return false;
            const r = e.getBoundingClientRect(), s = getComputedStyle(e);
            return r.width > 0 && r.height > 0 && s.display !== 'none' && s.visibility !== 'hidden' && Number(s.opacity) > 0;
          };
          const clean = (v) => (v || '').replace(/\u200c/g, '‌').replace(/[ \t]+/g, ' ').replace(/\n{3,}/g, '\n\n').trim();
          const meta = (selector) => document.querySelector(selector)?.content || '';
          const headings = [...document.querySelectorAll('h1,h2,h3,h4')].filter(visible).map(e => clean(e.innerText)).filter(Boolean);
          const visibleText = clean(document.body?.innerText || '').slice(0, 40000);
          const title = clean(headings.find(t => t.length > 2) || meta('meta[property="og:title"]') || document.title || '');
          const descriptionNode = [...document.querySelectorAll('[class*="description"],[class*="synopsis"],[data-testid*="description"]')]
            .filter(visible).map(e => clean(e.innerText)).find(t => t.length >= 70 && t.length < 5000) || '';
          const synopsis = clean(meta('meta[property="og:description"]') || meta('meta[name="description"]') || descriptionNode);
          const images = [...document.images].filter(visible).map(img => {
            const r = img.getBoundingClientRect();
            return {src: img.currentSrc || img.src, area: r.width * r.height};
          }).filter(i => /^https?:/.test(i.src) && i.area >= 10000).sort((a,b) => b.area-a.area).map(i => i.src);
          const posterURL = meta('meta[property="og:image"]') || images[0] || '';
          const candidates = [...document.querySelectorAll('article,li,a,button,[role="button"]')]
            .filter(visible).map(e => clean(e.innerText)).filter(t => t.length >= 5 && t.length <= 900)
            .filter(t => /(قسمت|اپیزود|episode|s\s*\d{1,2}\s*e\s*\d{1,2}|\d+\s*(دقیقه|min))/i.test(t));
          const episodeSnippets = [...new Set(candidates)];
          return JSON.stringify({title, synopsis, posterURL, visibleText, headings, episodeSnippets, images});
        })()
        """#
    }
}
