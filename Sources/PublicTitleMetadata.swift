import Foundation

enum PublicMetadataProvider: String, Codable, CaseIterable, Equatable, Identifiable, Sendable {
    case filimo = "Filimo"
    case hexDL = "HexDL"

    var id: String { rawValue }

    func accepts(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased() else { return false }
        switch self {
        case .filimo:
            let parts = url.path.split(separator: "/")
            return (host == "filimo.com" || host == "www.filimo.com")
                && parts.count == 2 && parts[0] == "m" && parts[1].allSatisfy(\.isNumber)
        case .hexDL:
            return (host == "hexdl.com" || host == "www.hexdl.com")
                && url.path != "/"
                && !["mp4", "mkv", "webm", "m3u8", "mpd", "srt", "vtt"].contains(url.pathExtension.lowercased())
        }
    }
}

struct PublicTitleMetadata: Codable, Sendable, Identifiable {
    let provider: PublicMetadataProvider
    let pageURL: URL
    var title: String
    var synopsis: String
    var posterURL: URL?
    let visiblePageText: String
    let visibleHeadings: [String]
    let episodeSnippets: [String]
    let imageURLs: [URL]
    let importedAt: Date

    var id: String { "\(provider.rawValue):\(pageURL.absoluteString)" }

    func editing(title: String, synopsis: String) -> PublicTitleMetadata {
        PublicTitleMetadata(
            provider: provider,
            pageURL: pageURL,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            synopsis: synopsis.trimmingCharacters(in: .whitespacesAndNewlines),
            posterURL: posterURL,
            visiblePageText: visiblePageText,
            visibleHeadings: visibleHeadings,
            episodeSnippets: episodeSnippets,
            imageURLs: imageURLs,
            importedAt: importedAt
        )
    }
}
