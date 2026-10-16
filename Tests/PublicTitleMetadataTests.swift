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
            importedAt: Date(timeIntervalSince1970: 1_800_000_000),
            originalTitle: "Supernatural",
            year: "2005",
            country: "آمریکا",
            contentRating: "18+",
            publicRating: "8.4",
            ratingSource: "IMDb",
            communityRating: "4.2",
            communityVotes: "86",
            genres: ["Drama", "Fantasy"],
            seasonCount: 8,
            castNames: ["Jared Padalecki", "Jensen Ackles"],
            publicBadges: ["زیرنویس", "دوبله"],
            pageDetailsVersion: PublicTitleMetadata.currentPageDetailsVersion,
            pageDetailsAttemptedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let encoded = try JSONEncoder().encode(source)
        let restored = try JSONDecoder().decode(PublicTitleMetadata.self, from: encoded)
        try require(restored.title == source.title && restored.visiblePageText == source.visiblePageText
                    && restored.country == "آمریکا" && restored.genres == ["Drama", "Fantasy"]
                    && restored.seasonCount == 8 && restored.castNames?.count == 2
                    && restored.communityRating == "4.2" && restored.communityVotes == "86"
                    && restored.publicBadges == ["زیرنویس", "دوبله"]
                    && restored.pageDetailsVersion == PublicTitleMetadata.currentPageDetailsVersion
                    && restored.pageDetailsAttemptedAt == source.pageDetailsAttemptedAt,
                    "the imported public metadata did not survive local serialization")
        var legacyPayload = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        ["originalTitle", "year", "country", "contentRating", "publicRating", "ratingSource", "runtime", "director",
         "communityRating", "communityVotes", "genres", "seasonCount", "episodeCount", "castNames", "crewNames", "publicBadges"]
            .forEach { legacyPayload.removeValue(forKey: $0) }
        legacyPayload.removeValue(forKey: "enrichmentVersion")
        legacyPayload.removeValue(forKey: "pageDetailsVersion")
        legacyPayload.removeValue(forKey: "pageDetailsAttemptedAt")
        let legacyData = try JSONSerialization.data(withJSONObject: legacyPayload)
        let legacyRestored = try JSONDecoder().decode(PublicTitleMetadata.self, from: legacyData)
        try require(legacyRestored.title == source.title && legacyRestored.originalTitle == nil && legacyRestored.genres == nil,
                    "a cached public-title record from the previous schema did not decode")
        try require(legacyRestored.needsAutomaticRefresh(),
                    "a pre-structured-metadata cache row was not scheduled for one enrichment refresh")
        try require(legacyRestored.needsPageDetailsRefresh(),
                    "a cached record without page details was not queued for detail-page enrichment")
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
        var priorPageDetails = source
        priorPageDetails.pageDetailsVersion = PublicTitleMetadata.currentPageDetailsVersion - 1
        priorPageDetails.pageDetailsAttemptedAt = Date()
        try require(priorPageDetails.needsPageDetailsRefresh(),
                    "an older page parser version was not queued for refresh")
        try require(PublicTitleMetadataRefreshPolicy.lookupVersion == 3,
                    "the metadata lookup version did not invalidate prior failed provider searches")

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
        try require(merged.pageDetailsVersion == PublicTitleMetadata.currentPageDetailsVersion,
                    "a page-detail refresh marker was lost while merging API and page metadata")
        try require(merged.posterURL == source.posterURL,
                    "a refresh without artwork discarded the saved poster")
        try require(merged.originalTitle == "Supernatural" && merged.genres == ["Drama", "Fantasy"]
                    && merged.communityRating == "4.2" && merged.publicBadges == ["زیرنویس", "دوبله"],
                    "an incomplete refresh discarded saved release facts or localized labels")
        try require(PersianMetadataText.preferredSynopsis(from: [
            "An English public-page summary.", "توضیحات فارسی موجود در کاتالوگ.", "English reference summary."
        ]) == "توضیحات فارسی موجود در کاتالوگ.",
                    "an English public/reference summary hid the existing Persian catalog description")

        var failedPageAttempt = englishRefresh
        failedPageAttempt.pageDetailsAttemptedAt = Date()
        try require(!failedPageAttempt.needsPageDetailsRefresh(),
                    "a recent failed page-detail attempt was retried immediately")
        try require(failedPageAttempt.needsPageDetailsRefresh(
            now: Date().addingTimeInterval(PublicTitleMetadataRefreshPolicy.retryInterval + 1)
        ), "page-detail lookup did not become eligible after its cooldown")

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
            importedAt: source.importedAt.addingTimeInterval(120),
            year: "2021",
            country: "United States",
            contentRating: "TV-MA",
            publicRating: "6.8",
            ratingSource: "HexDL",
            communityRating: "88%",
            communityVotes: "8",
            genres: ["Comedy"],
            episodeCount: 5,
            castNames: ["Matthew McConaughey"],
            publicBadges: ["TV-MA", "1080p", "CC"]
        )
        let catalogItem = MediaItem(
            id: "movie-1", title: "Sample Movie", subtitle: "Movie", synopsis: "Existing English catalog summary.",
            year: "2020", kind: "Movie", symbol: "film", palette: 0,
            artworkURL: URL(string: "https://simba.example/current-poster.jpg"), isRemote: true,
            genres: ["Thriller"], imdbRating: "7.4", imdbVotes: 50_000
        )
        let enrichedCatalogItem = catalogItem.applyingPublicTitleMetadata([hexEnglish, source])
        try require(enrichedCatalogItem.synopsis == source.synopsis,
                    "the catalog item did not prefer a saved Persian public synopsis")
        try require(enrichedCatalogItem.artworkURL == source.posterURL,
                    "the catalog item did not prefer the Filimo poster over HexDL and Simba artwork")
        try require(enrichedCatalogItem.year == "2020" && enrichedCatalogItem.genres == ["Thriller"]
                    && enrichedCatalogItem.imdbRating == "7.4" && enrichedCatalogItem.imdbVotes == 50_000,
                    "public-page facts replaced the catalog's primary IMDb year, genre, or rating")
        let publicFallbackItem = MediaItem(
            id: "series-2", title: "Brothers", subtitle: "Series", synopsis: "",
            year: "", kind: "Series", symbol: "tv", palette: 0, isRemote: true
        ).applyingPublicTitleMetadata([hexEnglish])
        try require(publicFallbackItem.year == "2021" && publicFallbackItem.genres == ["Comedy"],
                    "public year and genre facts were not used to fill missing catalog fields")

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

        try require(PublicMetadataGenreParser.canonicalName("درام") == "Drama"
                    && PublicMetadataGenreParser.canonicalName("علمی‌تخیلی") == "Sci-Fi"
                    && PublicMetadataGenreParser.canonicalName("کمدی") == "Comedy",
                    "Persian public genres did not map to the local canonical genre names")

        print("PASS public metadata: matching, Persian synopsis priority, structured facts, genre mapping, cache compatibility, cooldown, and forced refresh")
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw PublicMetadataTestFailure(message: message) }
    }
}

private struct PublicMetadataTestFailure: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}
