import Foundation

@main
struct ReferenceMetadataTests {
    static func main() throws {
        let series = MediaItem(
            id: "series-1", apiID: "1", title: "Sample Show", subtitle: "", synopsis: "",
            year: "2020", kind: "Series", symbol: "tv", palette: 0,
            matchingTitles: ["Sample Series"]
        )
        let tvmaze = ReferenceMetadataService.parseTVmaze([
            ["score": 0.98, "show": [
                "id": 42, "name": "Sample Show", "url": "https://www.tvmaze.com/shows/42/sample-show",
                "premiered": "2020-01-02", "summary": "<p>A &amp; B</p>", "genres": ["Drama"],
                "rating": ["average": 8.4], "averageRuntime": 44,
                "image": ["original": "https://static.tvmaze.com/poster.jpg"],
                "network": ["country": ["name": "United States"]],
                "_embedded": [
                    "cast": [["person": ["name": "Actor One"]]],
                    "crew": [["type": "Director", "person": ["name": "Director One"]]]
                ]
            ]]
        ], item: series, imdbID: "tt1234567")
        try require(tvmaze?.synopsis == "A & B", "TVmaze summary HTML was not cleaned")
        try require(tvmaze?.year == "2020" && tvmaze?.runtime == "44 min", "TVmaze year/runtime were not mapped")
        try require(tvmaze?.rating == "8.4" && tvmaze?.genres == ["Drama"], "TVmaze rating/genres were not mapped")
        try require(tvmaze?.country == "United States" && tvmaze?.director == "Director One", "TVmaze crew metadata was not mapped")
        try require(tvmaze?.cast == ["Actor One"] && tvmaze?.posterURL != nil, "TVmaze cast/poster were not mapped")
        try require(tvmaze?.citations.first?.provider == "TVmaze", "TVmaze attribution was not retained")

        let wrongSeries = MediaItem(
            id: "series-2", title: "Unrelated Show", subtitle: "", synopsis: "", year: "2020",
            kind: "Series", symbol: "tv", palette: 0
        )
        try require(ReferenceMetadataService.parseTVmaze([
            ["show": ["id": 42, "name": "Sample Show", "premiered": "2020-01-02"]]
        ], item: wrongSeries, imdbID: nil) == nil, "TVmaze accepted a title with a weak match")

        let wikidata = ReferenceMetadataService.parseWikidata([
            "results": ["bindings": [
                ["item": ["value": "http://www.wikidata.org/entity/Q123"],
                 "itemDescription": ["value": "داستان نمونه"], "date": ["value": "2019-05-04T00:00:00Z"],
                 "runtime": ["value": "130"], "genreLabel": ["value": "Drama"],
                 "countryLabel": ["value": "Iran"], "directorLabel": ["value": "Director Two"],
                 "actorLabel": ["value": "Actor Two"],
                 "image": ["value": "https://commons.wikimedia.org/wiki/Special:FilePath/Poster.jpg"]]
            ]]
        ])
        try require(wikidata?.synopsis == "داستان نمونه" && wikidata?.year == "2019", "Wikidata description/year were not mapped")
        try require(wikidata?.runtime == "130 min" && wikidata?.genres == ["Drama"], "Wikidata runtime/genres were not mapped")
        try require(wikidata?.country == "Iran" && wikidata?.director == "Director Two", "Wikidata country/director were not mapped")
        try require(wikidata?.cast == ["Actor Two"] && wikidata?.posterURL != nil, "Wikidata cast/image were not mapped")
        try require(wikidata?.citations.first?.url.absoluteString == "https://www.wikidata.org/wiki/Q123", "Wikidata attribution link was not normalized")

        let movie = MediaItem(
            id: "movie-1", title: "Sample Movie", subtitle: "", synopsis: "", year: "2020",
            kind: "Movie", symbol: "film", palette: 0
        )
        let wikidataSearch: [String: Any] = ["search": [
            ["id": "Q999", "label": "Sample Movie", "description": "2020 film"],
            ["id": "Q998", "label": "Sample Movie", "description": "2020 novel"]
        ]]
        try require(ReferenceMetadataService.parseWikidataSearch(wikidataSearch, item: movie) == "Q999",
                    "Wikidata title search did not select the matching film")
        try require(ReferenceMetadataService.parseWikidataSearch(["search": [
            ["id": "Q998", "label": "Sample Movie", "description": "2020 novel"]
        ]], item: movie) == nil, "Wikidata title search accepted a non-film with the same name")

        var secondSource = wikidata!
        secondSource.genres = ["Comedy"]
        let merged = tvmaze!.merging(secondSource)
        try require(merged.citations.map(\.provider).sorted() == ["TVmaze", "Wikidata"], "metadata sources were not combined")
        try require(merged.synopsis == "A & B" && merged.country == "United States", "higher-priority metadata was overwritten")
        try require(merged.genres == ["Drama", "Comedy"] && merged.cast == ["Actor One", "Actor Two"],
                    "genre and cast data from multiple references were not combined")

        var attempted = ReferenceTitleMetadata.empty()
        attempted.attemptedProviders = ["TVmaze", "Wikidata"]
        try require(!ReferenceMetadataService.shouldRefresh(attempted, for: series, imdbID: nil),
                    "the service ignored the one-day retry window after an empty lookup")
        var tvmazeOnly = ReferenceTitleMetadata.empty()
        tvmazeOnly.attemptedProviders = ["TVmaze"]
        try require(ReferenceMetadataService.shouldRefresh(tvmazeOnly, for: series, imdbID: nil),
                    "a series with no IMDb ID did not schedule Wikidata lookup")
        var noWikidataMatch = ReferenceTitleMetadata.empty()
        noWikidataMatch.attemptedProviders = ["TVmaze", "Wikidata"]
        try require(ReferenceMetadataService.shouldRefresh(noWikidataMatch, for: series, imdbID: "tt1234567"),
                    "a newly available IMDb ID did not retry Wikidata matching")
        try require(ReferenceMetadataService.shouldRefresh(.empty(), for: movie, imdbID: nil),
                    "Wikidata title search did not run for a movie without a local IMDb ID")

        let detail = MediaDetails(
            description: nil, year: nil, rating: nil, runtime: nil, genres: [], country: nil,
            director: nil, cast: [], sources: [], downloadSources: [], seasons: [],
            imdbID: "tt1234567", imdbRating: nil, imdbVotes: nil, similarSeries: [], castPeople: []
        )
        let enriched = ReferenceMetadataService.enrich(detail, with: merged)
        try require(enriched.description == "A & B" && enriched.cast == ["Actor One", "Actor Two"] && enriched.rating == "8.4",
                    "external metadata did not fill empty detail fields and rating")
        try require(ReferenceMetadataService.shouldRefresh(.empty(), for: series, imdbID: nil), "a cache without provider data was not refreshed")

        let databaseURL = FileManager.default.temporaryDirectory.appendingPathComponent("Denbox-reference-\(UUID().uuidString).sqlite")
        let database = MediaDatabase(databaseURL: databaseURL)
        database.saveReferenceMetadata(merged, mediaID: "series-1")
        let restored = database.loadReferenceMetadata(mediaID: "series-1")
        try require(restored?.cast == merged.cast && restored?.citations.count == 2,
                    "reference metadata did not survive local SQLite caching")
        try? FileManager.default.removeItem(at: databaseURL)
        try? FileManager.default.removeItem(atPath: databaseURL.path + "-wal")
        try? FileManager.default.removeItem(atPath: databaseURL.path + "-shm")

        print("PASS reference metadata: TVmaze/Wikidata parsing, safe title matching, merging, SQLite cache, and attribution")
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw ReferenceMetadataTestFailure(message: message) }
    }
}

private struct ReferenceMetadataTestFailure: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}
