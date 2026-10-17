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
                    "cast": [
                        ["person": [
                            "id": 1001, "name": "Actor One",
                            "url": "https://www.tvmaze.com/people/1001/actor-one",
                            "externals": ["imdb": "nm0000001"],
                            "image": ["original": "https://static.tvmaze.com/actors/1001.jpg"]
                        ], "character": ["name": "Character One"]],
                        ["person": [
                            "id": 2001, "name": "Actor One",
                            "externals": ["imdb": "NM0000001"]
                        ], "character": ["name": "Duplicate Character"]],
                        ["person": ["id": 1002, "name": "Actor Two"],
                         "character": ["name": "Character Two"]]
                    ],
                    "crew": [["type": "Director", "person": ["name": "Director One"]]]
                ]
            ]]
        ], item: series, imdbID: "tt1234567")
        try require(tvmaze?.synopsis == "A & B", "TVmaze summary HTML was not cleaned")
        try require(tvmaze?.year == "2020" && tvmaze?.runtime == "44 min", "TVmaze year/runtime were not mapped")
        try require(tvmaze?.rating == "8.4" && tvmaze?.genres == ["Drama"], "TVmaze rating/genres were not mapped")
        try require(tvmaze?.country == "United States" && tvmaze?.director == "Director One", "TVmaze crew metadata was not mapped")
        try require(tvmaze?.cast == ["Actor One", "Actor Two"] && tvmaze?.posterURL != nil,
                    "TVmaze cast/poster were not mapped or duplicate names were retained")
        try require(tvmaze?.tvmazeCastProfilesVersion == 1,
                    "TVmaze cast-profile cache version was not set")
        let castProfiles = tvmaze?.castProfiles ?? []
        try require(castProfiles.map(\.id) == ["imdb:nm0000001", "tvmaze:1002"],
                    "TVmaze cast profiles did not deduplicate by IMDb ID and retain stable person IDs")
        try require(castProfiles[0].character == "Character One"
                    && castProfiles[0].imageURL?.absoluteString == "https://static.tvmaze.com/actors/1001.jpg"
                    && castProfiles[0].tvmazeURL?.absoluteString == "https://www.tvmaze.com/people/1001/actor-one"
                    && castProfiles[0].tvmazeID == 1001,
                    "TVmaze actor portrait, character, or person-page link was not mapped")
        try require(castProfiles[1].character == "Character Two" && castProfiles[1].imageURL == nil,
                    "TVmaze cast fallback profile was not mapped")
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

        let tmdbCandidate = ReferenceMetadataService.bestTMDBCandidate(in: [
            ["id": 1, "title": "Sample Movie", "original_title": "Sample Movie", "release_date": "2016-01-01", "popularity": 99.0],
            ["id": 2, "title": "Sample Movie", "original_title": "Sample Movie", "release_date": "2020-01-01", "popularity": 1.0]
        ], item: movie, mediaType: "movie")
        try require(tmdbCandidate?["id"] as? Int == 2, "TMDB title matching did not prefer the matching release year")
        try require(ReferenceMetadataService.bestTMDBCandidate(in: [
            ["id": 3, "title": "Unrelated Film", "original_title": "Unrelated Film", "release_date": "2020-01-01"]
        ], item: movie, mediaType: "movie") == nil, "TMDB accepted an unrelated title")

        let tmdbMovie = ReferenceMetadataService.parseTMDB([
            "id": 100,
            "title": "Sample Movie",
            "original_title": "Original Sample Movie",
            "release_date": "2020-03-04",
            "overview": "Sample synopsis",
            "tagline": "A short sample tagline",
            "status": "Released",
            "original_language": "en",
            "vote_average": 8.2,
            "runtime": 123,
            "poster_path": "/poster.jpg",
            "backdrop_path": "/backdrop.jpg",
            "genres": [["name": "Drama"]],
            "production_companies": [["name": "Sample Studio"]],
            "production_countries": [["name": "United States"]],
            "credits": [
                "cast": [["name": "Lead Actor"]],
                "crew": [
                    ["name": "Film Director", "job": "Director"],
                    ["name": "Film Writer", "job": "Screenplay"]
                ]
            ],
            "videos": ["results": [["site": "YouTube", "type": "Trailer", "key": "sample123", "official": true]]],
            "keywords": ["keywords": [["name": "mystery"]]],
            "release_dates": ["results": [[
                "iso_3166_1": "US",
                "release_dates": [["certification": "R"]]
            ]]]
        ], mediaType: "movie")
        try require(tmdbMovie?.year == "2020" && tmdbMovie?.runtime == "123 min", "TMDB movie year/runtime were not mapped")
        try require(tmdbMovie?.rating == "8.2" && tmdbMovie?.ratingSource == "TMDB", "TMDB rating source was not retained")
        try require(tmdbMovie?.director == "Film Director" && tmdbMovie?.writers == ["Film Writer"], "TMDB movie crew was not mapped")
        try require(tmdbMovie?.contentRating == "US · R" && tmdbMovie?.keywords == ["mystery"], "TMDB movie certification/keywords were not mapped")
        try require(tmdbMovie?.trailerURL?.absoluteString == "https://www.youtube.com/watch?v=sample123"
                    && tmdbMovie?.backdropURL != nil && tmdbMovie?.citations.first?.provider == "TMDB",
                    "TMDB trailer, artwork, or attribution was not mapped")

        let tmdbSeries = ReferenceMetadataService.parseTMDB([
            "id": 200,
            "name": "Sample Show",
            "original_name": "Original Sample Show",
            "first_air_date": "2020-06-07",
            "created_by": [["name": "Series Creator"]],
            "number_of_seasons": 3,
            "number_of_episodes": 24,
            "episode_run_time": [42],
            "networks": [["name": "Sample Network"]],
            "content_ratings": ["results": [["iso_3166_1": "US", "rating": "TV-14"]]]
        ], mediaType: "tv")
        try require(tmdbSeries?.seasonCount == 3 && tmdbSeries?.episodeCount == 24 && tmdbSeries?.runtime == "42 min",
                    "TMDB series counts/runtime were not mapped")
        try require(tmdbSeries?.director == "Series Creator" && tmdbSeries?.networks == ["Sample Network"]
                    && tmdbSeries?.contentRating == "US · TV-14", "TMDB series creator/network/rating were not mapped")

        var alreadyTriedTMDB = ReferenceTitleMetadata.empty()
        alreadyTriedTMDB.attemptedProviders = ["Wikidata", "TMDB"]
        alreadyTriedTMDB.citations = [MetadataCitation(provider: "TMDB", url: URL(string: "https://www.themoviedb.org/movie/100")!)]
        try require(!ReferenceMetadataService.shouldRefresh(alreadyTriedTMDB, for: movie, imdbID: nil, hasTMDBToken: true),
                    "TMDB was retried immediately after a completed lookup")
        try require(ReferenceMetadataService.shouldRefresh(alreadyTriedTMDB, for: movie, imdbID: nil,
                                                           hasTMDBToken: true, forceTMDB: true),
                    "saving a corrected TMDB token did not force a fresh lookup")
        try require(!ReferenceMetadataService.shouldRefresh(alreadyTriedTMDB, for: movie, imdbID: nil,
                                                            hasTMDBToken: false, forceTMDB: true),
                    "TMDB was scheduled without a saved token")

        var secondSource = wikidata!
        secondSource.genres = ["Comedy"]
        let merged = tvmaze!.merging(secondSource)
        try require(merged.citations.map(\.provider).sorted() == ["TVmaze", "Wikidata"], "metadata sources were not combined")
        try require(merged.synopsis == "داستان نمونه" && merged.country == "United States",
                    "a Persian description was replaced by a higher-ranked English summary")
        try require(merged.genres == ["Drama", "Comedy"] && merged.cast == ["Actor One", "Actor Two"],
                    "genre and cast data from multiple references were not combined")
        try require(merged.castProfiles?.first?.character == "Character One"
                    && merged.castProfiles?.first?.imageURL == castProfiles.first?.imageURL,
                    "TVmaze cast portraits or character names were lost during cross-source merging")
        try require(!ReferenceMetadataService.shouldRefresh(merged, for: series, imdbID: nil),
                    "a current TVmaze cast-profile cache was unexpectedly refreshed")
        try require(!ReferenceMetadataService.needsTVmazeRefresh(for: series, cached: merged, stale: false),
                    "TVmaze was still fetched after its cast-profile cache was current")
        var oldTVmazeCache = merged
        oldTVmazeCache.castProfiles = nil
        oldTVmazeCache.tvmazeCastProfilesVersion = nil
        try require(ReferenceMetadataService.shouldRefresh(oldTVmazeCache, for: series, imdbID: nil),
                    "a pre-portrait TVmaze cache was not scheduled for automatic refresh")
        try require(ReferenceMetadataService.needsTVmazeRefresh(for: series, cached: oldTVmazeCache, stale: false),
                    "a pre-portrait TVmaze cache was scheduled but its fetch was skipped")

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
        noWikidataMatch.wikidataLookupIMDbID = "tt1234567"
        try require(!ReferenceMetadataService.shouldRefresh(noWikidataMatch, for: series, imdbID: "tt1234567"),
                    "a completed Wikidata miss was retried on every title-page visit")
        try require(ReferenceMetadataService.shouldRefresh(.empty(), for: movie, imdbID: nil),
                    "Wikidata title search did not run for a movie without a local IMDb ID")

        let detail = MediaDetails(
            description: nil, year: nil, rating: nil, runtime: nil, genres: [], country: nil,
            director: nil, cast: [], sources: [], downloadSources: [], seasons: [],
            imdbID: "tt1234567", imdbRating: nil, imdbVotes: nil, similarSeries: []
        )
        let enriched = ReferenceMetadataService.enrich(detail, with: merged)
        try require(enriched.description == "داستان نمونه" && enriched.cast == ["Actor One", "Actor Two"] && enriched.rating == "8.4",
                    "external metadata did not fill empty detail fields and rating")
        let tmdbEnriched = ReferenceMetadataService.enrich(detail, with: tmdbMovie!)
        try require(tmdbEnriched.ratingSource == "TMDB" && tmdbEnriched.tagline == "A short sample tagline"
                    && tmdbEnriched.contentRating == "US · R" && tmdbEnriched.trailerURL == tmdbMovie?.trailerURL,
                    "TMDB details were not carried into the title detail model")
        try require(ReferenceMetadataService.shouldRefresh(.empty(), for: series, imdbID: nil), "a cache without provider data was not refreshed")

        let databaseURL = FileManager.default.temporaryDirectory.appendingPathComponent("Denbox-reference-\(UUID().uuidString).sqlite")
        let database = MediaDatabase(databaseURL: databaseURL)
        database.saveReferenceMetadata(merged, mediaID: "series-1")
        let restored = database.loadReferenceMetadata(mediaID: "series-1")
        try require(restored?.cast == merged.cast && restored?.citations.count == 2
                    && restored?.castProfiles?.first?.imageURL == castProfiles.first?.imageURL
                    && restored?.tvmazeCastProfilesVersion == 1,
                    "reference metadata did not survive local SQLite caching")
        try? FileManager.default.removeItem(at: databaseURL)
        try? FileManager.default.removeItem(atPath: databaseURL.path + "-wal")
        try? FileManager.default.removeItem(atPath: databaseURL.path + "-shm")

        try verifyPublicTitleSQLitePersistence()

        print("PASS reference metadata: TMDB/TVmaze/Wikidata parsing, cast profiles, safe title matching, merging, SQLite caches, and attribution")
    }

    private static func verifyPublicTitleSQLitePersistence() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Denbox-public-title-\(UUID().uuidString).sqlite")
        let attemptedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let metadata = PublicTitleMetadata(
            provider: .hexDL,
            pageURL: URL(string: "https://hexdl.com/shahrzad-series/")!,
            title: "شهرزاد",
            synopsis: "شرح فارسی نمونه",
            posterURL: URL(string: "https://hexdl.com/wp-content/uploads/example.jpg"),
            visiblePageText: "عنوان و توضیحات فارسی",
            visibleHeadings: ["قسمت ۱"],
            episodeSnippets: ["فصل ۱ قسمت ۱"],
            imageURLs: [URL(string: "https://hexdl.com/wp-content/uploads/example.jpg")!],
            importedAt: attemptedAt
        )
        do {
            let database = MediaDatabase(databaseURL: url)
            try require(database.savePublicTitleMetadata(metadata, for: "series:42"),
                        "public title metadata was not written to SQLite")
            database.recordPublicTitleMetadataAttempt(mediaID: "series:42", provider: .hexDL, at: attemptedAt)
        }
        do {
            let reopened = MediaDatabase(databaseURL: url)
            let restored = reopened.loadPublicTitleMetadata(mediaID: "series:42", provider: .hexDL)
            try require(restored?.synopsis == metadata.synopsis && restored?.episodeSnippets == metadata.episodeSnippets,
                        "public Persian metadata did not survive reopening the local SQLite database")
            try require(reopened.publicTitleMetadataLastAttempt(mediaID: "series:42", provider: .hexDL) == attemptedAt,
                        "the automatic lookup cooldown did not survive reopening SQLite")
        }
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(atPath: url.path + "-wal")
        try? FileManager.default.removeItem(atPath: url.path + "-shm")
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw ReferenceMetadataTestFailure(message: message) }
    }
}

private struct ReferenceMetadataTestFailure: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}
