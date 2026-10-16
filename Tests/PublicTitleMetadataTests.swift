import Foundation

@main
struct PublicTitleMetadataTests {
    static func main() throws {
        try require(PublicMetadataProvider.filimo.accepts(URL(string: "https://www.filimo.com/m/178360")!),
                    "the supplied Filimo title URL was rejected")
        try require(PublicMetadataProvider.filimo.accepts(URL(string: "https://www.filimo.com/m/30jiu")!),
                    "an alphanumeric Filimo title ID from its public search page was rejected")
        try require(!PublicMetadataProvider.filimo.accepts(URL(string: "http://www.filimo.com/m/178360")!),
                    "an insecure Filimo URL was accepted")
        try require(!PublicMetadataProvider.filimo.accepts(URL(string: "https://filimo.com/player/178360")!),
                    "a playback route was accepted as a public title page")
        try require(PublicMetadataProvider.filimo.acceptsSearchPage(URL(string: "https://www.filimo.com/search")!),
                    "Filimo's public search page was not allowlisted")
        try require(PublicMetadataProvider.hexDL.accepts(URL(string: "https://hexdl.com/example-movie/")!),
                    "a public HexDL title page was rejected")
        try require(PublicMetadataProvider.hexDL.acceptsSearchPage(URL(string: "https://hexdl.com/")!),
                    "HexDL's public search page was not allowlisted")
        try require(!PublicMetadataProvider.hexDL.accepts(URL(string: "https://hexdl.com/movie.mkv")!),
                    "a media file URL was accepted as a HexDL metadata page")
        try require(!PublicMetadataProvider.hexDL.accepts(URL(string: "https://hexdl.com/player/example/")!),
                    "a HexDL player route was accepted as a metadata page")

        let source = PublicTitleMetadata(
            provider: .filimo,
            pageURL: URL(string: "https://www.filimo.com/m/178360")!,
            title: "عنوان فارسی",
            synopsis: "خلاصهٔ فارسی",
            posterURL: URL(string: "https://cdn.example/poster.jpg"),
            visiblePageText: "متن عمومی",
            visibleHeadings: ["فصل اول"],
            episodeSnippets: ["قسمت اول · ۴۲ دقیقه"],
            imageURLs: [URL(string: "https://cdn.example/poster.jpg")!],
            importedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let encoded = try JSONEncoder().encode(source)
        let restored = try JSONDecoder().decode(PublicTitleMetadata.self, from: encoded)
        try require(restored.title == source.title && restored.visiblePageText == source.visiblePageText,
                    "the imported public metadata did not survive local serialization")

        let englishRefresh = PublicTitleMetadata(
            provider: .filimo,
            pageURL: URL(string: "https://www.filimo.com/m/30jiu")!,
            title: "English title",
            synopsis: "An English description that should not replace Persian text.",
            posterURL: nil,
            visiblePageText: "English visible text",
            visibleHeadings: [],
            episodeSnippets: [],
            imageURLs: [],
            importedAt: source.importedAt.addingTimeInterval(60)
        )
        let merged = englishRefresh.merging(source)
        try require(merged.synopsis == source.synopsis && merged.hasPersianSynopsis,
                    "an English refresh replaced an existing Persian synopsis")
        try require(merged.posterURL == source.posterURL,
                    "a refresh without artwork discarded the saved poster")
        try require(PersianMetadataText.preferredSynopsis(from: [
            "An English public-page summary.", "توضیحات فارسی موجود در کاتالوگ.", "English reference summary."
        ]) == "توضیحات فارسی موجود در کاتالوگ.",
                    "an English public/reference summary hid the existing Persian catalog description")

        let matching = PublicMetadataCandidate(
            index: 0,
            text: "شهرزاد • سریال • درام • ۱۳۹۴ - ۱۳۹۶",
            titleHints: ["شهرزاد"],
            pageURL: URL(string: "https://hexdl.com/shahrzad-series/")
        )
        let actor = PublicMetadataCandidate(
            index: 1,
            text: "شهرزاد کمال زاده • بازیگر • 2 عنوان",
            titleHints: ["شهرزاد کمال زاده"],
            pageURL: URL(string: "https://hexdl.com/actor/shahrzad/")
        )
        let match = PublicMetadataTitleMatcher.bestCandidate(
            in: [actor, matching], matching: ["Shahrzad", "شهرزاد"], kind: "Series", year: "2015"
        )
        try require(match?.candidate.index == 0,
                    "the title matcher did not choose the exact Persian title over a cast member")
        try require(PublicMetadataTitleMatcher.bestCandidate(
            in: [actor], matching: ["Shahrzad"], kind: "Series", year: "2015"
        ).map { $0.candidate.index } == nil, "the title matcher accepted an actor as an exact title page")

        print("PASS public metadata: search allowlists, Persian synopsis preservation, title matching, and local encoding")
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw PublicMetadataTestFailure(message: message) }
    }
}

private struct PublicMetadataTestFailure: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}
