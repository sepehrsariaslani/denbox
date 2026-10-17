import Foundation
import SQLite3

@main
struct IMDbChartRankingTests {
    static func main() throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Denbox-IMDb-Charts-\(UUID().uuidString).sqlite")
        defer {
            try? FileManager.default.removeItem(at: databaseURL)
            try? FileManager.default.removeItem(atPath: databaseURL.path + "-wal")
            try? FileManager.default.removeItem(atPath: databaseURL.path + "-shm")
        }

        try createFixtureDatabase(at: databaseURL)
        let store = IMDbMetadataStore.testingStore(databaseURL: databaseURL)
        guard let charts = store.chartLists() else {
            throw IMDbChartRankingFailure(message: "IMDb chart fixture database could not be read")
        }

        // The two eligible movies tie at a report-wide mean of 7.0, so vote count breaks the tie.
        try require(charts.topMovies.map(\.tconst) == ["tt-movie-b", "tt-movie-a"],
                    "movie chart did not apply the weighted formula, 25,000-vote boundary, and vote-count tie-break")

        // With a series mean of 9.5, the same rating/vote pairs rank in the opposite order.
        try require(charts.topSeries.map(\.tconst) == ["tt-mini-at-threshold", "tt-series-a", "tt-series-b"],
                    "series chart did not use its separate report mean, include miniseries, or enforce vote eligibility")
        try require(charts.topMovies.allSatisfy { $0.kind == "Movie" }
                    && charts.topSeries.allSatisfy { $0.kind == "Series" },
                    "IMDb chart rows were returned with the wrong media kind")

        print("PASS IMDb chart ranking: movie/series means, weighted order, 25,000-vote boundary, miniseries, and tie-break")
    }

    private static func createFixtureDatabase(at url: URL) throws {
        var db: OpaquePointer?
        guard sqlite3_open(url.path, &db) == SQLITE_OK, let db else {
            throw IMDbChartRankingFailure(message: "could not create IMDb chart fixture database")
        }
        defer { sqlite3_close(db) }

        try execute("""
            CREATE TABLE titles(
                tconst TEXT PRIMARY KEY,
                primary_title TEXT NOT NULL,
                start_year INTEGER,
                genres TEXT,
                rating REAL,
                votes INTEGER,
                title_type TEXT NOT NULL
            );
            """, in: db)

        let rows = [
            ChartRow(id: "tt-movie-a", type: "movie", rating: 9.0, votes: 25_000),
            ChartRow(id: "tt-movie-b", type: "movie", rating: 8.5, votes: 50_000),
            ChartRow(id: "tt-movie-below", type: "movie", rating: 3.5, votes: 24_999),
            ChartRow(id: "tt-movie-unrated", type: "movie", rating: nil, votes: 50_000),
            ChartRow(id: "tt-series-a", type: "tvSeries", rating: 9.0, votes: 25_000),
            ChartRow(id: "tt-series-b", type: "tvSeries", rating: 8.5, votes: 50_000),
            ChartRow(id: "tt-series-below-1", type: "tvSeries", rating: 10.0, votes: 24_999),
            ChartRow(id: "tt-series-below-2", type: "tvSeries", rating: 10.0, votes: 24_999),
            ChartRow(id: "tt-series-below-3", type: "tvSeries", rating: 10.0, votes: 24_999),
            ChartRow(id: "tt-mini-at-threshold", type: "tvMiniSeries", rating: 9.5, votes: 25_000),
            ChartRow(id: "tt-special", type: "tvSpecial", rating: 10.0, votes: 100_000),
            ChartRow(id: "tt-short", type: "short", rating: 10.0, votes: 100_000),
            ChartRow(id: "tt-episode", type: "tvEpisode", rating: 10.0, votes: 100_000)
        ]

        var statement: OpaquePointer?
        let sql = "INSERT INTO titles(tconst,primary_title,start_year,genres,rating,votes,title_type) VALUES(?,?,2020,'Drama',?,?,?)"
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw IMDbChartRankingFailure(message: "could not prepare chart fixture insert")
        }
        defer { sqlite3_finalize(statement) }

        for row in rows {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            bind(row.id, to: statement, at: 1)
            bind(row.id, to: statement, at: 2)
            if let rating = row.rating {
                sqlite3_bind_double(statement, 3, rating)
            } else {
                sqlite3_bind_null(statement, 3)
            }
            sqlite3_bind_int64(statement, 4, sqlite3_int64(row.votes))
            bind(row.type, to: statement, at: 5)
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw IMDbChartRankingFailure(message: "could not insert IMDb chart fixture row \(row.id)")
            }
        }
    }

    private static func execute(_ sql: String, in db: OpaquePointer) throws {
        var message: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, sql, nil, nil, &message) == SQLITE_OK else {
            let detail = message.map { String(cString: $0) } ?? "SQLite error"
            sqlite3_free(message)
            throw IMDbChartRankingFailure(message: detail)
        }
    }

    private static func bind(_ value: String, to statement: OpaquePointer, at index: Int32) {
        _ = value.withCString { sqlite3_bind_text(statement, index, $0, -1, sqliteTransient) }
    }

    private static let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw IMDbChartRankingFailure(message: message) }
    }
}

private struct ChartRow {
    let id: String
    let type: String
    let rating: Double?
    let votes: Int
}

private struct IMDbChartRankingFailure: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}
