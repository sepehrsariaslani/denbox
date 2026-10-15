import Foundation
import SQLite3

struct IMDbTitleMetadata: Identifiable, Sendable {
    let tconst: String
    let title: String
    let year: Int?
    let genres: [String]
    let rating: Double?
    let votes: Int?
    let kind: String

    init(tconst: String, title: String, year: Int?, genres: [String], rating: Double?, votes: Int?, kind: String = "Series") {
        self.tconst = tconst
        self.title = title
        self.year = year
        self.genres = genres
        self.rating = rating
        self.votes = votes
        self.kind = kind
    }

    var id: String { tconst }
    var imdbURL: URL? { URL(string: "https://www.imdb.com/title/\(tconst)/") }
}

struct IMDbChartLists: Sendable {
    let topMovies: [IMDbTitleMetadata]
    let topSeries: [IMDbTitleMetadata]
    let mostVotedMovies: [IMDbTitleMetadata]
    let mostVotedSeries: [IMDbTitleMetadata]
}

struct IMDbEpisodeMetadata {
    let tconst: String
    let title: String
    let season: Int
    let episode: Int
    let rating: Double?
    let votes: Int?
}

struct IMDbEnrichment {
    let series: IMDbTitleMetadata
    let episodes: [IMDbEpisodeMetadata]
    let similarSeries: [IMDbTitleMetadata]
}

enum IMDbMetadataError: LocalizedError {
    case invalidDatabase
    case downloadFailed(String)
    case importFailed(String)
    case datasetUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidDatabase: "Could not open the local IMDb metadata database."
        case .downloadFailed(let message): "IMDb dataset download failed: \(message)"
        case .importFailed(let message): "IMDb dataset import failed: \(message)"
        case .datasetUnavailable: "The IMDb dataset has not been downloaded yet."
        }
    }
}

final class IMDbMetadataStore: @unchecked Sendable {
    static let shared = IMDbMetadataStore()

    private let databaseURL: URL
    private let fileManager = FileManager.default
    private let endpoints: [(String, URL)] = [
        ("titles", URL(string: "https://datasets.imdbws.com/title.basics.tsv.gz")!),
        ("episodes", URL(string: "https://datasets.imdbws.com/title.episode.tsv.gz")!),
        ("ratings", URL(string: "https://datasets.imdbws.com/title.ratings.tsv.gz")!)
    ]

    private init() {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = support.appendingPathComponent("Denbox", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        databaseURL = directory.appendingPathComponent("imdb-metadata.sqlite")
    }

    var isAvailable: Bool { fileManager.fileExists(atPath: databaseURL.path) }

    var lastUpdated: Date? {
        guard let db = openReadOnly() else { return nil }
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT value FROM metadata WHERE key='updated_at'", -1, &statement, nil) == SQLITE_OK,
              let statement else { return nil }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW,
              let raw = text(statement, 0), let seconds = Double(raw) else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    func refresh(progress: @escaping @Sendable (String) -> Void) async throws {
        let workspace = fileManager.temporaryDirectory.appendingPathComponent("Denbox-IMDb-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: workspace) }

        var downloaded: [String: URL] = [:]
        for (label, endpoint) in endpoints {
            progress("Downloading IMDb \(label)…")
            do {
                let (tempURL, response) = try await URLSession.shared.download(from: endpoint)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                    throw IMDbMetadataError.downloadFailed("HTTP response was not successful.")
                }
                let target = workspace.appendingPathComponent("\(label).tsv.gz")
                try fileManager.moveItem(at: tempURL, to: target)
                downloaded[label] = target
            } catch {
                throw IMDbMetadataError.downloadFailed(error.localizedDescription)
            }
        }

        progress("Preparing the local IMDb index…")
        do {
            try await Task.detached(priority: .userInitiated) {
                try self.installOfficialFiles(titles: downloaded["titles"]!, episodes: downloaded["episodes"]!, ratings: downloaded["ratings"]!, progress: progress)
            }.value
        } catch {
            throw IMDbMetadataError.importFailed(error.localizedDescription)
        }
        progress("IMDb data is ready on this Mac.")
    }

    func installOfficialFiles(titles: URL, episodes: URL, ratings: URL,
                              progress: @escaping @Sendable (String) -> Void) throws {
        let workspace = fileManager.temporaryDirectory.appendingPathComponent("Denbox-IMDb-Import-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: workspace) }
        let buildURL = workspace.appendingPathComponent("imdb-metadata.sqlite")
        try importDataset(titles: titles, episodes: episodes, ratings: ratings, to: buildURL, progress: progress)
        try installDatabase(from: buildURL)
    }

    func enrichment(title: String, year: String) -> IMDbEnrichment? {
        guard let db = openReadOnly() else { return nil }
        defer { sqlite3_close(db) }
        guard let series = matchSeries(db: db, title: title, year: Int(year)) else { return nil }
        let episodes = episodeRows(db: db, parent: series.tconst)
        let similar = similarRows(db: db, to: series)
        return IMDbEnrichment(series: series, episodes: episodes, similarSeries: similar)
    }

    func chartLists() -> IMDbChartLists? {
        guard let db = openReadOnly() else { return nil }
        defer { sqlite3_close(db) }
        return IMDbChartLists(
            topMovies: chartRows(
                db: db,
                predicate: "title_type='movie' AND rating IS NOT NULL AND votes >= 25000",
                order: "((votes * rating + 175000.0) / (votes + 25000.0)) DESC, votes DESC",
                limit: 250,
                kind: "Movie"
            ),
            topSeries: chartRows(
                db: db,
                predicate: "title_type IN ('tvSeries','tvMiniSeries') AND rating IS NOT NULL AND votes >= 10000",
                order: "((votes * rating + 175000.0) / (votes + 25000.0)) DESC, votes DESC",
                limit: 250,
                kind: "Series"
            ),
            mostVotedMovies: chartRows(
                db: db,
                predicate: "title_type='movie' AND rating IS NOT NULL AND votes >= 5000",
                order: "votes DESC, rating DESC",
                limit: 100,
                kind: "Movie"
            ),
            mostVotedSeries: chartRows(
                db: db,
                predicate: "title_type IN ('tvSeries','tvMiniSeries') AND rating IS NOT NULL AND votes >= 5000",
                order: "votes DESC, rating DESC",
                limit: 100,
                kind: "Series"
            )
        )
    }

    private func chartRows(db: OpaquePointer, predicate: String, order: String, limit: Int, kind: String) -> [IMDbTitleMetadata] {
        let sql = "SELECT tconst,primary_title,start_year,genres,rating,votes FROM titles WHERE \(predicate) ORDER BY \(order) LIMIT \(limit)"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return [] }
        defer { sqlite3_finalize(statement) }
        var result: [IMDbTitleMetadata] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let id = text(statement, 0), let title = text(statement, 1) else { continue }
            result.append(IMDbTitleMetadata(
                tconst: id,
                title: title,
                year: integer(statement, 2),
                genres: (text(statement, 3) ?? "").split(separator: ",").map(String.init),
                rating: double(statement, 4),
                votes: integer(statement, 5),
                kind: kind
            ))
        }
        return result
    }

    private func openReadOnly() -> OpaquePointer? {
        guard isAvailable else { return nil }
        var db: OpaquePointer?
        guard sqlite3_open_v2(databaseURL.path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            if let db { sqlite3_close(db) }
            return nil
        }
        sqlite3_busy_timeout(db, 3000)
        return db
    }

    private func matchSeries(db: OpaquePointer, title: String, year: Int?) -> IMDbTitleMetadata? {
        let normalized = imdbNormalize(title)
        guard !normalized.isEmpty else { return nil }
        let columns = "tconst,primary_title,start_year,genres,rating,votes,normalized_primary,normalized_original"
        let exactSQL = "SELECT \(columns) FROM titles WHERE title_type IN ('tvSeries','tvMiniSeries') AND (normalized_primary=? OR normalized_original=?)"
        var candidates = querySeries(db: db, sql: exactSQL, title: normalized, year: year)
        if candidates.isEmpty, let year {
            let fuzzySQL = "SELECT \(columns) FROM titles WHERE title_type IN ('tvSeries','tvMiniSeries') AND start_year BETWEEN ? AND ?"
            candidates = querySeries(db: db, sql: fuzzySQL, title: normalized, year: year)
        }
        guard !candidates.isEmpty else { return nil }
        let exact = candidates.filter { $0.1 == normalized || $0.2 == normalized }
        let pool = exact.isEmpty ? candidates.filter { $0.3 >= 0.91 } : exact
        guard !pool.isEmpty else { return nil }
        let ranked = pool.sorted { left, right in
            if left.3 != right.3 { return left.3 > right.3 }
            if let year {
                let leftDistance = left.0.year.map { abs($0 - year) } ?? Int.max
                let rightDistance = right.0.year.map { abs($0 - year) } ?? Int.max
                if leftDistance != rightDistance { return leftDistance < rightDistance }
            }
            return (left.0.votes ?? 0) > (right.0.votes ?? 0)
        }
        if exact.isEmpty, ranked.count > 1, ranked[0].3 - ranked[1].3 < 0.035 { return nil }
        // A title or episode guide can carry a badly shifted start year, especially
        // for older shows. Keep the year as a ranking hint, but don't discard an
        // exact IMDb title match just because that metadata is stale. The distance
        // guard is useful only for fuzzy matches where the title itself is uncertain.
        if exact.isEmpty, let year, let matchedYear = ranked[0].0.year, abs(year - matchedYear) > 2 { return nil }
        return ranked[0].0
    }

    private func episodeRows(db: OpaquePointer, parent: String) -> [IMDbEpisodeMetadata] {
        let sql = """
        SELECT tconst,primary_title,season_number,episode_number,rating,votes
        FROM titles WHERE title_type='tvEpisode' AND parent_tconst=?
          AND season_number IS NOT NULL AND episode_number IS NOT NULL
        ORDER BY season_number,episode_number
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return [] }
        defer { sqlite3_finalize(statement) }
        bind(parent, to: statement, at: 1)
        var result: [IMDbEpisodeMetadata] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let id = text(statement, 0), let title = text(statement, 1),
                  let season = integer(statement, 2), let episode = integer(statement, 3) else { continue }
            result.append(IMDbEpisodeMetadata(tconst: id, title: title, season: season, episode: episode,
                                              rating: double(statement, 4), votes: integer(statement, 5)))
        }
        return result
    }

    private func similarRows(db: OpaquePointer, to series: IMDbTitleMetadata) -> [IMDbTitleMetadata] {
        let genres = Array(series.genres.prefix(4))
        guard !genres.isEmpty else { return [] }
        let clauses = Array(repeating: "(',' || genres || ',') LIKE ?", count: genres.count).joined(separator: " OR ")
        let sql = """
        SELECT tconst,primary_title,start_year,genres,rating,votes
        FROM titles WHERE title_type IN ('tvSeries','tvMiniSeries') AND rating IS NOT NULL
          AND tconst<>? AND (\(clauses))
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return [] }
        defer { sqlite3_finalize(statement) }
        bind(series.tconst, to: statement, at: 1)
        for (index, genre) in genres.enumerated() { bind("%,\(genre),%", to: statement, at: Int32(index + 2)) }
        var candidates: [(IMDbTitleMetadata, Double)] = []
        let sourceGenres = Set(series.genres)
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let id = text(statement, 0), let title = text(statement, 1) else { continue }
            let relatedGenres = (text(statement, 3) ?? "").split(separator: ",").map(String.init)
            let intersection = sourceGenres.intersection(relatedGenres).count
            guard intersection > 0 else { continue }
            let unionCount = max(1, sourceGenres.union(relatedGenres).count)
            let overlap = Double(intersection) / Double(unionCount)
            let rating = double(statement, 4)
            let votes = integer(statement, 5)
            let popularity = min(1, log10(Double(max(1, votes ?? 1)) + 1) / 7.0)
            let rank = overlap * 0.8 + (rating ?? 0) / 10.0 * 0.15 + popularity * 0.05
            candidates.append((IMDbTitleMetadata(tconst: id, title: title, year: integer(statement, 2),
                                                  genres: relatedGenres, rating: rating, votes: votes), rank))
        }
        return candidates.sorted { $0.1 > $1.1 }.prefix(10).map(\.0)
    }

    private func importDataset(titles: URL, episodes: URL, ratings: URL, to destination: URL,
                               progress: @escaping @Sendable (String) -> Void) throws {
        var db: OpaquePointer?
        guard sqlite3_open(destination.path, &db) == SQLITE_OK, let db else { throw IMDbMetadataError.invalidDatabase }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 20_000)
        try execute("PRAGMA journal_mode=OFF; PRAGMA synchronous=OFF; PRAGMA temp_store=MEMORY;", db: db)
        try execute("""
        CREATE TABLE titles(
          tconst TEXT PRIMARY KEY,title_type TEXT NOT NULL,primary_title TEXT NOT NULL,original_title TEXT,
          normalized_primary TEXT NOT NULL,normalized_original TEXT NOT NULL,start_year INTEGER,genres TEXT,
          rating REAL,votes INTEGER,parent_tconst TEXT,season_number INTEGER,episode_number INTEGER
        );
        CREATE TABLE metadata(key TEXT PRIMARY KEY,value TEXT NOT NULL);
        BEGIN TRANSACTION;
        """, db: db)
        defer { try? execute("ROLLBACK;", db: db) }

        var insert: OpaquePointer?
        let insertSQL = "INSERT OR IGNORE INTO titles(tconst,title_type,primary_title,original_title,normalized_primary,normalized_original,start_year,genres) VALUES(?,?,?,?,?,?,?,?)"
        guard sqlite3_prepare_v2(db, insertSQL, -1, &insert, nil) == SQLITE_OK, let insert else {
            throw IMDbMetadataError.invalidDatabase
        }
        defer { sqlite3_finalize(insert) }
        progress("Indexing IMDb series and episode titles…")
        try readGzipTSV(titles) { columns in
            guard columns.count > 8, let type = columns[1],
                  ["movie", "tvSeries", "tvMiniSeries", "tvEpisode"].contains(type),
                  columns[4] != "1",
                  let id = columns[0], let primary = columns[2] else { return }
            let original = columns[3] ?? primary
            let year = columns[5].flatMap(Int32.init)
            sqlite3_reset(insert); sqlite3_clear_bindings(insert)
            bind(id, to: insert, at: 1)
            bind(type, to: insert, at: 2)
            bind(primary, to: insert, at: 3)
            bind(original, to: insert, at: 4)
            bind(imdbNormalize(primary), to: insert, at: 5)
            bind(imdbNormalize(original), to: insert, at: 6)
            if let year { sqlite3_bind_int(insert, 7, year) } else { sqlite3_bind_null(insert, 7) }
            bind(columns[8] ?? "", to: insert, at: 8)
            guard sqlite3_step(insert) == SQLITE_DONE else { throw IMDbMetadataError.invalidDatabase }
        }

        progress("Linking IMDb seasons and episode numbers…")
        var updateEpisode: OpaquePointer?
        guard sqlite3_prepare_v2(db, "UPDATE titles SET parent_tconst=?,season_number=?,episode_number=? WHERE tconst=? AND title_type='tvEpisode'", -1, &updateEpisode, nil) == SQLITE_OK,
              let updateEpisode else { throw IMDbMetadataError.invalidDatabase }
        defer { sqlite3_finalize(updateEpisode) }
        try readGzipTSV(episodes) { columns in
            guard columns.count >= 4, let id = columns[0], let parent = columns[1] else { return }
            let season = columns[2].flatMap(Int32.init)
            let episode = columns[3].flatMap(Int32.init)
            sqlite3_reset(updateEpisode); sqlite3_clear_bindings(updateEpisode)
            bind(parent, to: updateEpisode, at: 1)
            if let season { sqlite3_bind_int(updateEpisode, 2, season) } else { sqlite3_bind_null(updateEpisode, 2) }
            if let episode { sqlite3_bind_int(updateEpisode, 3, episode) } else { sqlite3_bind_null(updateEpisode, 3) }
            bind(id, to: updateEpisode, at: 4)
            guard sqlite3_step(updateEpisode) == SQLITE_DONE else { throw IMDbMetadataError.invalidDatabase }
        }

        progress("Adding IMDb series and episode ratings…")
        var updateRating: OpaquePointer?
        guard sqlite3_prepare_v2(db, "UPDATE titles SET rating=?,votes=? WHERE tconst=?", -1, &updateRating, nil) == SQLITE_OK,
              let updateRating else { throw IMDbMetadataError.invalidDatabase }
        defer { sqlite3_finalize(updateRating) }
        try readGzipTSV(ratings) { columns in
            guard columns.count >= 3, let id = columns[0] else { return }
            sqlite3_reset(updateRating); sqlite3_clear_bindings(updateRating)
            if let rating = columns[1].flatMap(Double.init) { sqlite3_bind_double(updateRating, 1, rating) } else { sqlite3_bind_null(updateRating, 1) }
            if let votes = columns[2].flatMap(Int32.init) { sqlite3_bind_int(updateRating, 2, votes) } else { sqlite3_bind_null(updateRating, 2) }
            bind(id, to: updateRating, at: 3)
            guard sqlite3_step(updateRating) == SQLITE_DONE else { throw IMDbMetadataError.invalidDatabase }
        }

        progress("Finishing the local IMDb index…")
        try execute("""
        CREATE INDEX idx_titles_normalized ON titles(title_type,normalized_primary,normalized_original);
        CREATE INDEX idx_episode_parent ON titles(parent_tconst,season_number,episode_number);
        CREATE INDEX idx_genres ON titles(title_type,genres);
        CREATE INDEX idx_title_chart ON titles(title_type,votes DESC,rating DESC);
        INSERT INTO metadata(key,value) VALUES('updated_at','\(Date().timeIntervalSince1970)');
        COMMIT;
        """, db: db)
    }

    private func installDatabase(from source: URL) throws {
        let backup = databaseURL.appendingPathExtension("backup")
        try? fileManager.removeItem(at: backup)
        let hadPrevious = fileManager.fileExists(atPath: databaseURL.path)
        if hadPrevious { try fileManager.moveItem(at: databaseURL, to: backup) }
        do {
            try fileManager.moveItem(at: source, to: databaseURL)
            try? fileManager.removeItem(at: backup)
        } catch {
            if hadPrevious { try? fileManager.moveItem(at: backup, to: databaseURL) }
            throw error
        }
    }

    private func readGzipTSV(_ url: URL, row: ([String?]) throws -> Void) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/gzip")
        process.arguments = ["-dc", url.path]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let handle = output.fileHandleForReading
        defer { try? handle.close() }
        var pending = Data()
        do {
            while let chunk = try handle.read(upToCount: 256 * 1024), !chunk.isEmpty {
                var lineStart = 0
                for index in 0..<chunk.count where chunk[index] == 10 {
                    pending.append(chunk.subdata(in: lineStart..<index))
                    if !pending.isEmpty, pending.last == 13 { pending.removeLast() }
                    if let line = String(data: pending, encoding: .utf8), !line.isEmpty, !line.hasPrefix("tconst\t") {
                        try row(line.split(separator: "\t", omittingEmptySubsequences: false).map { field in
                            field == "\\N" ? nil : String(field)
                        })
                    }
                    pending.removeAll(keepingCapacity: true)
                    lineStart = index + 1
                }
                if lineStart < chunk.count { pending.append(chunk.subdata(in: lineStart..<chunk.count)) }
            }
            if !pending.isEmpty, let line = String(data: pending, encoding: .utf8) {
                try row(line.split(separator: "\t", omittingEmptySubsequences: false).map { $0 == "\\N" ? nil : String($0) })
            }
        } catch {
            if process.isRunning { process.terminate() }
            process.waitUntilExit()
            throw error
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw IMDbMetadataError.importFailed("Could not decompress \(url.lastPathComponent).") }
    }

    private func execute(_ sql: String, db: OpaquePointer) throws {
        var message: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, sql, nil, nil, &message) == SQLITE_OK else {
            let detail = message.map { String(cString: $0) } ?? "SQLite error"
            sqlite3_free(message)
            throw IMDbMetadataError.importFailed(detail)
        }
    }

    private func querySeries(db: OpaquePointer, sql: String, title: String, year: Int?) -> [(IMDbTitleMetadata, String, String, Double)] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return [] }
        defer { sqlite3_finalize(statement) }
        if sql.contains("BETWEEN") {
            sqlite3_bind_int(statement, 1, Int32(year! - 1))
            sqlite3_bind_int(statement, 2, Int32(year! + 1))
        } else {
            bind(title, to: statement, at: 1)
            bind(title, to: statement, at: 2)
        }
        var result: [(IMDbTitleMetadata, String, String, Double)] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let id = text(statement, 0), let name = text(statement, 1) else { continue }
            let primary = text(statement, 6) ?? ""
            let original = text(statement, 7) ?? ""
            let recordYear = integer(statement, 2)
            let score = max(titleSimilarity(title, primary), titleSimilarity(title, original))
            let yearPenalty: Int
            if let year, let recordYear { yearPenalty = abs(year - recordYear) }
            else { yearPenalty = 0 }
            let record = IMDbTitleMetadata(
                tconst: id, title: name, year: recordYear,
                genres: (text(statement, 3) ?? "").split(separator: ",").map(String.init),
                rating: double(statement, 4), votes: integer(statement, 5)
            )
            result.append((record, primary, original, score - Double(yearPenalty) * 0.025))
        }
        return result
    }

    private func text(_ statement: OpaquePointer, _ index: Int32) -> String? {
        guard let value = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: value)
    }

    private func integer(_ statement: OpaquePointer, _ index: Int32) -> Int? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        return Int(sqlite3_column_int(statement, index))
    }

    private func double(_ statement: OpaquePointer, _ index: Int32) -> Double? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        return sqlite3_column_double(statement, index)
    }

    private func bind(_ value: String, to statement: OpaquePointer, at index: Int32) {
        _ = value.withCString { sqlite3_bind_text(statement, index, $0, -1, imdbSQLiteTransient) }
    }
}

private let imdbSQLiteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

private func imdbNormalize(_ value: String) -> String {
    value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        .unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
        .map(String.init).joined()
}

private func titleSimilarity(_ lhs: String, _ rhs: String) -> Double {
    guard !lhs.isEmpty, !rhs.isEmpty else { return 0 }
    if lhs == rhs { return 1 }
    let left = Array(lhs), right = Array(rhs)
    if abs(left.count - right.count) > 4 { return 0 }
    var previous = Array(0...right.count)
    for (i, l) in left.enumerated() {
        var current = [i + 1] + Array(repeating: 0, count: right.count)
        for (j, r) in right.enumerated() {
            current[j + 1] = min(current[j] + 1, previous[j + 1] + 1, previous[j] + (l == r ? 0 : 1))
        }
        previous = current
    }
    return 1 - Double(previous[right.count]) / Double(max(left.count, right.count))
}
