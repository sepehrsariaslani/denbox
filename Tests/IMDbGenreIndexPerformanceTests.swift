import Foundation
import SQLite3

@main
struct IMDbGenreIndexPerformanceTests {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DenboxGenreIndexTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let databaseURL = root.appendingPathComponent("imdb-metadata.sqlite")
        try createLegacyDatabase(at: databaseURL, seriesCount: 50_000)
        let store = IMDbMetadataStore.testingStore(databaseURL: databaseURL)

        let migrationStarted = Date()
        let firstPage = store.similarSeries(for: "tt-source")
        let migrationSeconds = Date().timeIntervalSince(migrationStarted)
        try require(firstPage.count == 10, "genre-index migration did not return the ten highest-ranked matches")
        try require(firstPage.allSatisfy { $0.tconst != "tt-source" && $0.genres.contains("Drama") },
                    "genre-index migration returned the source series or unrelated genres")

        let seriesMatch = store.matchTitle(title: "Drama Series 49999", year: "2020", kind: "Series")
        try require(seriesMatch?.tconst == "tt0049999",
                    "indexed primary-title lookup selected \(seriesMatch?.tconst ?? "no series") instead of tt0049999")
        let movieMatch = store.matchTitle(title: "Original Movie", year: "2022", kind: "Movie")
        try require(movieMatch?.tconst == "tt-movie", "indexed original-title lookup missed a movie")

        let queryStarted = Date()
        var resultCount = 0
        for _ in 0..<20 {
            resultCount += store.similarSeries(for: "tt-source").count
            if store.matchTitle(title: "Drama Series 49999", year: "2020", kind: "Series") != nil { resultCount += 1 }
            if store.matchTitle(title: "Original Movie", year: "2022", kind: "Movie") != nil { resultCount += 1 }
        }
        let indexedQuerySeconds = Date().timeIntervalSince(queryStarted)
        try require(resultCount == 240, "indexed recommendation and title queries returned an inconsistent result count")
        try require(indexedQuerySeconds < 2, "twenty indexed recommendation queries took over two seconds")

        print(String(format: "Legacy genre-index migration: %.3fs for 50,000 series", migrationSeconds))
        print(String(format: "Indexed recommendations and exact title lookups: %.3fs for 60 queries", indexedQuerySeconds))
        print("PASS IMDb indexes: legacy migration, similar-title lookup, and exact series/movie title lookup")
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
