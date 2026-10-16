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
        let firstRetry = source.importedAt.addingTimeInterval(60 * 60)
        try require(!PublicTitleMetadataRefreshPolicy.shouldRefresh(
            cached: source, lastAttempt: source.importedAt, now: firstRetry
        ), "a fresh Persian synopsis and poster were refreshed too soon")
        try require(PublicTitleMetadataRefreshPolicy.shouldRefresh(
            cached: source,
            lastAttempt: source.importedAt,
            now: source.importedAt.addingTimeInterval(31 * 24 * 60 * 60)
        ), "complete public metadata did not become due after its refresh interval")
        try require(!PublicTitleMetadataRefreshPolicy.shouldRefresh(
            cached: nil, lastAttempt: firstRetry, now: firstRetry.addingTimeInterval(60 * 60)
        ), "an unsuccessful search bypassed its retry cooldown")
        try require(PublicTitleMetadataRefreshPolicy.shouldRefresh(
            cached: source, lastAttempt: firstRetry, now: firstRetry, force: true
        ), "a manual refresh did not bypass the cache and cooldown")

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

        let hexEnglish = PublicTitleMetadata(
            provider: .hexDL,
            pageURL: URL(string: "https://hexdl.com/sample-movie/")!,
            title: "Sample Movie",
            synopsis: "An English HexDL summary.",
            posterURL: URL(string: "https://hexdl.com/hex-poster.jpg"),
            visiblePageText: "English details",
            visibleHeadings: [],
            episodeSnippets: [],
            imageURLs: [],
            importedAt: source.importedAt.addingTimeInterval(120)
        )
        let catalogItem = MediaItem(
            id: "movie-1", title: "Sample Movie", subtitle: "Movie", synopsis: "Existing English catalog summary.",
            year: "2020", kind: "Movie", symbol: "film", palette: 0,
            artworkURL: URL(string: "https://simba.example/current-poster.jpg"), isRemote: true
        )
        let enrichedCatalogItem = catalogItem.applyingPublicTitleMetadata([hexEnglish, source])
        try require(enrichedCatalogItem.synopsis == source.synopsis,
                    "the catalog item did not prefer a saved Persian public synopsis")
        try require(enrichedCatalogItem.artworkURL == source.posterURL,
                    "the catalog item did not prefer the Filimo poster over HexDL and Simba artwork")

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

        print("PASS public metadata: matching, Persian synopsis priority, refresh policy, cooldown, and forced refresh")
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw PublicMetadataTestFailure(message: message) }
    }
}

private struct PublicMetadataTestFailure: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}
