import Foundation
import SQLite3

@main
struct IMDbGenreIndexPerformanceTests {
    static func main() throws {
        if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--database" {
            try measureInstalledDatabase(at: URL(fileURLWithPath: CommandLine.arguments[2]))
            return
        }

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DenboxGenreIndexTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let databaseURL = root.appendingPathComponent("imdb-metadata.sqlite")
        try verifyCatalogMatchIndexes(in: root)
        try createLegacyDatabase(at: databaseURL, seriesCount: 50_000)
        let store = IMDbMetadataStore.testingStore(databaseURL: databaseURL)

        let migrationStarted = Date()
        let firstPage = store.similarSeries(for: "tt-source")
        let migrationSeconds = Date().timeIntervalSince(migrationStarted)
        try require(firstPage.count == 10, "genre-index migration did not return the ten highest-ranked matches")
        try require(firstPage.allSatisfy { $0.tconst != "tt-source" && $0.genres.contains("Drama") },
                    "genre-index migration returned the source series or unrelated genres")
        try require(indexExists("idx_series_similarity_lookup", in: databaseURL),
                    "the compact covering index for similar-series lookups was not created")

        let cachedSimilarStarted = Date()
        var cachedSimilarCount = 0
        for _ in 0..<100 { cachedSimilarCount += store.similarSeries(for: "tt-source").count }
        let cachedSimilarSeconds = Date().timeIntervalSince(cachedSimilarStarted)
        try require(cachedSimilarCount == 1_000, "the cached similar-series results changed")
        try require(cachedSimilarSeconds < 0.2,
                    String(format: "100 similar-series cache hits took %.3fs", cachedSimilarSeconds))

        let seriesMatch = store.matchTitle(title: "Drama Series 49999", year: "2020", kind: "Series")
        try require(seriesMatch?.tconst == "tt0049999",
                    "indexed primary-title lookup selected \(seriesMatch?.tconst ?? "no series") instead of tt0049999")
        let movieMatch = store.matchTitle(title: "Original Movie", year: "2022", kind: "Movie")
        try require(movieMatch?.tconst == "tt-movie", "indexed original-title lookup missed a movie")

        let discoveryStarted = Date()
        let discovery = store.discoveryCandidates(limit: 30_000)
        let discoverySeconds = Date().timeIntervalSince(discoveryStarted)
        try require(discovery.count == 30_000, "discovery lookup did not return the requested number of rated titles")
        try require(discovery.first?.tconst == "tt0049999", "discovery lookup did not preserve rating/vote order")
        let plan = store.discoveryQueryPlanForTesting().joined(separator: " | ")
        try require(plan.contains("idx_discovery_rating"), "discovery lookup did not use its rating-order index: \(plan)")
        try require(!plan.localizedCaseInsensitiveContains("temp b-tree"), "discovery lookup still sorts into a temporary B-tree: \(plan)")

        let repeatedDiscoveryStarted = Date()
        let repeatedDiscovery = store.discoveryCandidates(limit: 30_000)
        let repeatedDiscoverySeconds = Date().timeIntervalSince(repeatedDiscoveryStarted)
        try require(repeatedDiscovery.count == discovery.count && repeatedDiscovery.first?.tconst == discovery.first?.tconst,
                    "cached discovery candidates changed order")
        try require(repeatedDiscoverySeconds < 0.2, "cached discovery query took more than 200 ms")

        let rankingStarted = Date()
        let ranked = PersonalizedRecommendationRanker.rank(
            discovery,
            history: [],
            preferredGenres: ["Drama"],
            excluding: [],
            limit: 80
        )
        let rankingSeconds = Date().timeIntervalSince(rankingStarted)
        try require(ranked.count == 80, "recommendation ranking returned fewer than 80 eligible titles")
        try require(rankingSeconds < 1, "ranking 30,000 discovery candidates took more than one second")

        try verifyIMDbGenreBrowse(store: store)

        let queryStarted = Date()
        var resultCount = 0
        for _ in 0..<20 {
            resultCount += store.similarSeries(for: "tt-source").count
            if store.matchTitle(title: "Drama Series 49999", year: "2020", kind: "Series") != nil { resultCount += 1 }
            if store.matchTitle(title: "Original Movie", year: "2022", kind: "Movie") != nil { resultCount += 1 }
        }
        let indexedQuerySeconds = Date().timeIntervalSince(queryStarted)
        try require(resultCount == 240, "indexed recommendation and title queries returned an inconsistent result count")
        try require(indexedQuerySeconds < 2,
                    String(format: "twenty indexed recommendation queries took %.3fs, over two seconds", indexedQuerySeconds))

        print(String(format: "Legacy genre-index migration: %.3fs for 50,000 series", migrationSeconds))
        print(String(format: "Similar-series cache: 100 requests in %.3fs", cachedSimilarSeconds))
        print(String(format: "Indexed discovery query: %.3fs first run · %.3fs cached; 30,000-title ranking: %.3fs", discoverySeconds, repeatedDiscoverySeconds, rankingSeconds))
        print(String(format: "Indexed recommendations and exact title lookups: %.3fs for 60 queries", indexedQuerySeconds))
        print("PASS IMDb indexes: genre browsing/pagination, legacy migration, discovery ordering/cache, similar-title lookup, and exact series/movie title lookup")
    }

    private static func verifyIMDbGenreBrowse(store: IMDbMetadataStore) throws {
        let firstPage = store.genreTitles(named: "Drama", offset: 0, limit: 10)
        let nextPage = store.genreTitles(named: "Drama", offset: 10, limit: 10)
        let movieTitles = store.genreTitles(named: "Drama", kind: "Movie", limit: 10)
        let seriesTitles = store.genreTitles(named: "Drama", kind: "Series", limit: 10)
        let wrongToken = store.genreTitles(named: "Dramatic", limit: 10)
        try require(firstPage.count == 10 && nextPage.count == 10,
                    "IMDb genre browsing did not return full pages from the local dataset")
        try require(Set(firstPage.map(\.tconst)).isDisjoint(with: Set(nextPage.map(\.tconst))),
                    "IMDb genre pagination repeated titles")
        try require(movieTitles.count == 1 && movieTitles.first?.kind == "Movie",
                    "IMDb movie genre filter did not restrict results to movies")
        try require(seriesTitles.count == 10 && seriesTitles.allSatisfy { $0.kind == "Series" },
                    "IMDb series genre filter did not restrict results to series")
        try require(wrongToken.isEmpty,
                    "IMDb genre matching treated a partial genre word as a match")
        let queryPlan = store.genreBrowseQueryPlanForTesting().joined(separator: " | ")
        try require(queryPlan.contains("idx_discovery_rating"),
                    "IMDb genre browsing did not use the indexed rating order: \(queryPlan)")
        try require(!queryPlan.localizedCaseInsensitiveContains("temp b-tree"),
                    "IMDb genre browsing sorted into a temporary B-tree: \(queryPlan)")
        for kind in ["Movie", "Series"] {
            let kindPlan = store.genreBrowseQueryPlanForTesting(kind: kind).joined(separator: " | ")
            try require(kindPlan.contains("idx_discovery_rating"),
                        "IMDb \(kind.lowercased()) genre browsing did not use the indexed rating order: \(kindPlan)")
        }
    }

    private static func verifyCatalogMatchIndexes(in root: URL) throws {
        let databaseURL = root.appendingPathComponent("catalog-match.sqlite")
        try createLegacyDatabase(at: databaseURL, seriesCount: 50_000)
        let store = IMDbMetadataStore.testingStore(databaseURL: databaseURL)
        let item = MediaItem(
            id: "catalog-series",
            title: "Drama Series 49999",
            subtitle: "2020 · Series",
            synopsis: "",
            year: "2020",
            kind: "Series",
            symbol: "tv",
            palette: 0,
            isRemote: true
        )
        let started = Date()
        let matches = store.catalogMetadata(for: [item])
        let elapsed = Date().timeIntervalSince(started)
        try require(matches[item.id]?.tconst == "tt0049999",
                    "catalog matching failed after creating its compact title indexes")
        try require(elapsed < 2,
                    String(format: "catalog match index creation and lookup took %.3fs", elapsed))
        for index in ["idx_titles_normalized", "idx_series_normalized_original", "idx_movie_normalized_original"] {
            try require(indexExists(index, in: databaseURL), "catalog matching did not create \(index)")
        }
        for index in ["idx_series_start_year", "idx_movie_start_year", "idx_discovery_rating"] {
            try require(!indexExists(index, in: databaseURL),
                        "catalog enrichment built the unrelated \(index) index")
        }

        try require(store.matchTitle(title: item.title, year: item.year, kind: item.kind)?.tconst == "tt0049999",
                    "the full title search did not create its year indexes on demand")
        try require(indexExists("idx_series_start_year", in: databaseURL)
                    && indexExists("idx_movie_start_year", in: databaseURL),
                    "full title search did not build the year indexes it needs")
        print(String(format: "Catalog match indexes: %.3fs for 50,000 IMDb rows; fuzzy year indexes stay lazy", elapsed))
    }

    private static func measureInstalledDatabase(at url: URL) throws {
        let store = IMDbMetadataStore.testingStore(databaseURL: url)
        let firstStarted = Date()
        let candidates = store.discoveryCandidates()
        let firstSeconds = Date().timeIntervalSince(firstStarted)
        try require(candidates.count == 30_000,
                    "the installed IMDb database returned only \(candidates.count) discovery candidates")
        let plan = store.discoveryQueryPlanForTesting().joined(separator: " | ")
        try require(plan.contains("idx_discovery_rating"), "the installed database did not use its discovery index: \(plan)")
        try require(!plan.localizedCaseInsensitiveContains("temp b-tree"), "the installed discovery query still uses a temporary sort: \(plan)")

        let genreStarted = Date()
        let dramaTitles = store.genreTitles(named: "Drama", limit: 60)
        let genreSeconds = Date().timeIntervalSince(genreStarted)
        try require(dramaTitles.count == 60 && dramaTitles.allSatisfy { $0.genres.contains("Drama") },
                    "the installed IMDb database returned an incomplete or mismatched first Drama page")
        let genrePlan = store.genreBrowseQueryPlanForTesting().joined(separator: " | ")
        try require(genrePlan.contains("idx_discovery_rating"), "the installed genre query did not use its rating index: \(genrePlan)")
        try require(!genrePlan.localizedCaseInsensitiveContains("temp b-tree"), "the installed genre query uses a temporary sort: \(genrePlan)")
        let movieGenreTitles = store.genreTitles(named: "Drama", kind: "Movie", limit: 10)
        let seriesGenreTitles = store.genreTitles(named: "Drama", kind: "Series", limit: 10)
        try require(movieGenreTitles.allSatisfy { $0.kind == "Movie" }
                    && seriesGenreTitles.allSatisfy { $0.kind == "Series" },
                    "the installed IMDb genre query returned a title in the wrong type filter")

        let repeatedStarted = Date()
        let repeatedCount = store.discoveryCandidates().count
        let repeatedSeconds = Date().timeIntervalSince(repeatedStarted)
        try require(repeatedCount == candidates.count, "the cached installed discovery query changed its result count")
        try require(repeatedSeconds < 0.2, "the cached installed discovery query took more than 200 ms")

        let facetsStarted = Date()
        let facets = store.genreFacets()
        let facetsSeconds = Date().timeIntervalSince(facetsStarted)
        let cachedFacetsStarted = Date()
        _ = store.genreFacets()
        let cachedFacetsSeconds = Date().timeIntervalSince(cachedFacetsStarted)
        try require(!facets.isEmpty, "the installed IMDb database returned no genre facets")
        try require(cachedFacetsSeconds < 0.2, "cached installed genre facets took more than 200 ms")

        print(String(format: "Installed IMDb index build + discovery query: %.3fs · %d candidates", firstSeconds, candidates.count))
        print(String(format: "Installed 60-title genre page: %.3fs · %d movies · %d series", genreSeconds, movieGenreTitles.count, seriesGenreTitles.count))
        print(String(format: "Installed discovery cache hit: %.4fs · genre scan %.3fs · cache hit %.4fs", repeatedSeconds, facetsSeconds, cachedFacetsSeconds))
        print("PASS installed IMDb discovery index and in-memory caches")
    }

    private static func createLegacyDatabase(at url: URL, seriesCount: Int) throws {
        var db: OpaquePointer?
        guard sqlite3_open(url.path, &db) == SQLITE_OK, let db else {
            throw GenreIndexTestFailure(message: "could not create the temporary IMDb database")
        }
        defer { sqlite3_close(db) }
        try execute("""
            CREATE TABLE metadata(key TEXT PRIMARY KEY,value TEXT NOT NULL);
            CREATE TABLE titles(
              tconst TEXT PRIMARY KEY,title_type TEXT NOT NULL,primary_title TEXT NOT NULL,original_title TEXT,
              normalized_primary TEXT NOT NULL,normalized_original TEXT NOT NULL,start_year INTEGER,genres TEXT,
              rating REAL,votes INTEGER,parent_tconst TEXT,season_number INTEGER,episode_number INTEGER
            );
            INSERT INTO metadata(key,value) VALUES('updated_at','0');
            BEGIN TRANSACTION;
            """, in: db)

        var insert: OpaquePointer?
        let sql = "INSERT INTO titles(tconst,title_type,primary_title,original_title,normalized_primary,normalized_original,start_year,genres,rating,votes) VALUES(?,?,?,?,?,?,?,?,?,?)"
        guard sqlite3_prepare_v2(db, sql, -1, &insert, nil) == SQLITE_OK, let insert else {
            throw GenreIndexTestFailure(message: "could not prepare the temporary IMDb titles table")
        }
        defer { sqlite3_finalize(insert) }

        for index in 0..<seriesCount {
            let isSource = index == 0
            let id = isSource ? "tt-source" : String(format: "tt%07d", index)
            let title = isSource ? "Source Series" : "Drama Series \(index)"
            let genres = isSource || index.isMultiple(of: 100) ? "Drama,Comedy"
                : (index.isMultiple(of: 2) ? "Drama,Thriller" : "Action,Adventure")
            sqlite3_reset(insert)
            sqlite3_clear_bindings(insert)
            bind(id, to: insert, at: 1)
            bind("tvSeries", to: insert, at: 2)
            bind(title, to: insert, at: 3)
            bind(title, to: insert, at: 4)
            bind(normalize(title), to: insert, at: 5)
            bind(normalize(title), to: insert, at: 6)
            sqlite3_bind_int(insert, 7, 2020)
            bind(genres, to: insert, at: 8)
            sqlite3_bind_double(insert, 9, isSource ? 8.2 : 7.0 + Double(index % 20) / 10.0)
            sqlite3_bind_int(insert, 10, Int32(index + 100))
            guard sqlite3_step(insert) == SQLITE_DONE else {
                throw GenreIndexTestFailure(message: "could not insert a temporary IMDb series")
            }
        }
        try execute("""
            INSERT INTO titles(
              tconst,title_type,primary_title,original_title,normalized_primary,normalized_original,
              start_year,genres,rating,votes
            ) VALUES('tt-movie','movie','Primary Movie','Original Movie','primarymovie','originalmovie',2022,'Drama',7.5,5000);
            """, in: db)
        try execute("COMMIT;", in: db)
    }

    private static func execute(_ sql: String, in db: OpaquePointer) throws {
        var message: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, sql, nil, nil, &message) == SQLITE_OK else {
            let detail = message.map { String(cString: $0) } ?? "SQLite error"
            sqlite3_free(message)
            throw GenreIndexTestFailure(message: detail)
        }
    }

    private static func indexExists(_ name: String, in url: URL) -> Bool {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else {
            if let db { sqlite3_close(db) }
            return false
        }
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT 1 FROM sqlite_master WHERE type='index' AND name=?", -1, &statement, nil) == SQLITE_OK,
              let statement else { return false }
        defer { sqlite3_finalize(statement) }
        _ = name.withCString { sqlite3_bind_text(statement, 1, $0, -1, sqliteTransient) }
        return sqlite3_step(statement) == SQLITE_ROW
    }

    private static func bind(_ value: String, to statement: OpaquePointer, at index: Int32) {
        _ = value.withCString { sqlite3_bind_text(statement, index, $0, -1, sqliteTransient) }
    }

    private static func normalize(_ value: String) -> String {
        value.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private static let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw GenreIndexTestFailure(message: message) }
    }
}

private struct GenreIndexTestFailure: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}
