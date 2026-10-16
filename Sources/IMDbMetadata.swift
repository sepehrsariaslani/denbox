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

struct IMDbPersonMetadata: Identifiable, Sendable {
    let nconst: String
    let name: String
    let birthYear: Int?
    let deathYear: Int?
    let professions: [String]
    let knownForTitleIDs: [String]

    var id: String { nconst }
    var imdbURL: URL? { URL(string: "https://www.imdb.com/name/\(nconst)/") }
}

struct IMDbPersonLookupRequest: Equatable, Sendable {
    let nconst: String?
    let name: String
}

struct IMDbPersonCredit: Identifiable, Sendable {
    let title: IMDbTitleMetadata
    let category: String
    let job: String?
    let characters: String?
    let ordering: Int

    var id: String { "\(title.tconst)-\(category)-\(ordering)" }
}

struct IMDbFranchiseEntry: Sendable {
    let title: String
    let year: Int
    let kind: String
    var alternateTitles: [String] = []
}

struct IMDbFranchiseDefinition: Identifiable, Sendable {
    let id: String
    let name: String
    let summary: String
    let entries: [IMDbFranchiseEntry]
}

enum IMDbFranchiseCatalog {
    static let all: [IMDbFranchiseDefinition] = [
        .init(id: "mcu", name: "Marvel Cinematic Universe", summary: "Marvel Studios films and series", entries:
            movies([("Iron Man", 2008), ("The Incredible Hulk", 2008), ("Iron Man 2", 2010), ("Thor", 2011), ("Captain America: The First Avenger", 2011), ("The Avengers", 2012), ("Iron Man 3", 2013), ("Thor: The Dark World", 2013), ("Captain America: The Winter Soldier", 2014), ("Guardians of the Galaxy", 2014), ("Avengers: Age of Ultron", 2015), ("Ant-Man", 2015), ("Captain America: Civil War", 2016), ("Doctor Strange", 2016), ("Guardians of the Galaxy Vol. 2", 2017), ("Spider-Man: Homecoming", 2017), ("Thor: Ragnarok", 2017), ("Black Panther", 2018), ("Avengers: Infinity War", 2018), ("Ant-Man and the Wasp", 2018), ("Captain Marvel", 2019), ("Avengers: Endgame", 2019), ("Spider-Man: Far from Home", 2019), ("Black Widow", 2021), ("Shang-Chi and the Legend of the Ten Rings", 2021), ("Eternals", 2021), ("Spider-Man: No Way Home", 2021), ("Doctor Strange in the Multiverse of Madness", 2022), ("Thor: Love and Thunder", 2022), ("Black Panther: Wakanda Forever", 2022), ("Ant-Man and the Wasp: Quantumania", 2023), ("Guardians of the Galaxy Vol. 3", 2023), ("The Marvels", 2023), ("Deadpool & Wolverine", 2024)]) +
            series([("WandaVision", 2021), ("Loki", 2021), ("Hawkeye", 2021), ("Moon Knight", 2022), ("Ms. Marvel", 2022), ("She-Hulk: Attorney at Law", 2022), ("Secret Invasion", 2023), ("Echo", 2024), ("Agatha All Along", 2024)])),
        .init(id: "star-wars", name: "Star Wars", summary: "The Skywalker saga, spin-offs, and series", entries:
            movies([("Star Wars: Episode IV - A New Hope", 1977), ("The Empire Strikes Back", 1980), ("Return of the Jedi", 1983), ("The Phantom Menace", 1999), ("Attack of the Clones", 2002), ("Revenge of the Sith", 2005), ("The Force Awakens", 2015), ("Rogue One", 2016), ("The Last Jedi", 2017), ("Solo", 2018), ("The Rise of Skywalker", 2019)], alternateTitles: ["Star Wars: Episode IV - A New Hope": ["Star Wars"]]) +
            series([("The Mandalorian", 2019), ("The Book of Boba Fett", 2021), ("Obi-Wan Kenobi", 2022), ("Andor", 2022), ("Ahsoka", 2023)])),
        .init(id: "wizarding-world", name: "Wizarding World", summary: "Harry Potter and Fantastic Beasts", entries:
            movies([("Harry Potter and the Sorcerer's Stone", 2001), ("Harry Potter and the Chamber of Secrets", 2002), ("Harry Potter and the Prisoner of Azkaban", 2004), ("Harry Potter and the Goblet of Fire", 2005), ("Harry Potter and the Order of the Phoenix", 2007), ("Harry Potter and the Half-Blood Prince", 2009), ("Harry Potter and the Deathly Hallows: Part 1", 2010), ("Harry Potter and the Deathly Hallows: Part 2", 2011), ("Fantastic Beasts and Where to Find Them", 2016), ("Fantastic Beasts: The Crimes of Grindelwald", 2018), ("Fantastic Beasts: The Secrets of Dumbledore", 2022)], alternateTitles: ["Harry Potter and the Sorcerer's Stone": ["Harry Potter and the Philosopher's Stone"]])),
        .init(id: "middle-earth", name: "Middle-earth", summary: "The Lord of the Rings and The Hobbit", entries:
            movies([("The Lord of the Rings: The Fellowship of the Ring", 2001), ("The Lord of the Rings: The Two Towers", 2002), ("The Lord of the Rings: The Return of the King", 2003), ("The Hobbit: An Unexpected Journey", 2012), ("The Hobbit: The Desolation of Smaug", 2013), ("The Hobbit: The Battle of the Five Armies", 2014)]) +
            series([("The Lord of the Rings: The Rings of Power", 2022)])),
        .init(id: "james-bond", name: "James Bond", summary: "The official 007 film series", entries:
            movies([("Dr. No", 1962), ("From Russia with Love", 1963), ("Goldfinger", 1964), ("Thunderball", 1965), ("You Only Live Twice", 1967), ("On Her Majesty's Secret Service", 1969), ("Diamonds Are Forever", 1971), ("Live and Let Die", 1973), ("The Man with the Golden Gun", 1974), ("The Spy Who Loved Me", 1977), ("Moonraker", 1979), ("For Your Eyes Only", 1981), ("Octopussy", 1983), ("A View to a Kill", 1985), ("The Living Daylights", 1987), ("Licence to Kill", 1989), ("GoldenEye", 1995), ("Tomorrow Never Dies", 1997), ("The World Is Not Enough", 1999), ("Die Another Day", 2002), ("Casino Royale", 2006), ("Quantum of Solace", 2008), ("Skyfall", 2012), ("Spectre", 2015), ("No Time to Die", 2021)])),
        .init(id: "fast-furious", name: "Fast & Furious", summary: "Street racing and heist action films", entries:
            movies([("The Fast and the Furious", 2001), ("2 Fast 2 Furious", 2003), ("The Fast and the Furious: Tokyo Drift", 2006), ("Fast & Furious", 2009), ("Fast Five", 2011), ("Fast & Furious 6", 2013), ("Furious 7", 2015), ("The Fate of the Furious", 2017), ("Fast & Furious Presents: Hobbs & Shaw", 2019), ("F9: The Fast Saga", 2021), ("Fast X", 2023)])),
        .init(id: "mission-impossible", name: "Mission: Impossible", summary: "The IMF action film series", entries:
            movies([("Mission: Impossible", 1996), ("Mission: Impossible II", 2000), ("Mission: Impossible III", 2006), ("Mission: Impossible - Ghost Protocol", 2011), ("Mission: Impossible - Rogue Nation", 2015), ("Mission: Impossible - Fallout", 2018), ("Mission: Impossible - Dead Reckoning Part One", 2023), ("Mission: Impossible - The Final Reckoning", 2025)])),
        .init(id: "jurassic", name: "Jurassic", summary: "Jurassic Park and Jurassic World", entries:
            movies([("Jurassic Park", 1993), ("The Lost World: Jurassic Park", 1997), ("Jurassic Park III", 2001), ("Jurassic World", 2015), ("Jurassic World: Fallen Kingdom", 2018), ("Jurassic World Dominion", 2022), ("Jurassic World Rebirth", 2025)])),
        .init(id: "spider-man", name: "Spider-Man", summary: "Live-action and animated Spider-Man films", entries:
            movies([("Spider-Man", 2002), ("Spider-Man 2", 2004), ("Spider-Man 3", 2007), ("The Amazing Spider-Man", 2012), ("The Amazing Spider-Man 2", 2014), ("Spider-Man: Homecoming", 2017), ("Spider-Man: Into the Spider-Verse", 2018), ("Spider-Man: Far from Home", 2019), ("Spider-Man: No Way Home", 2021), ("Spider-Man: Across the Spider-Verse", 2023)])),
        .init(id: "x-men", name: "X-Men", summary: "X-Men, Wolverine, and Deadpool films", entries:
            movies([("X-Men", 2000), ("X2", 2003), ("X-Men: The Last Stand", 2006), ("X-Men Origins: Wolverine", 2009), ("X-Men: First Class", 2011), ("The Wolverine", 2013), ("X-Men: Days of Future Past", 2014), ("Deadpool", 2016), ("X-Men: Apocalypse", 2016), ("Logan", 2017), ("Deadpool 2", 2018), ("Dark Phoenix", 2019), ("The New Mutants", 2020), ("Deadpool & Wolverine", 2024)])),
        .init(id: "dc", name: "DC Films", summary: "DC superhero films", entries:
            movies([("Man of Steel", 2013), ("Batman v Superman: Dawn of Justice", 2016), ("Suicide Squad", 2016), ("Wonder Woman", 2017), ("Justice League", 2017), ("Aquaman", 2018), ("Shazam!", 2019), ("Birds of Prey", 2020), ("Wonder Woman 1984", 2020), ("The Suicide Squad", 2021), ("Black Adam", 2022), ("Shazam! Fury of the Gods", 2023), ("The Flash", 2023), ("Blue Beetle", 2023), ("Aquaman and the Lost Kingdom", 2023)])),
        .init(id: "toy-story", name: "Toy Story", summary: "Woody, Buzz, and friends", entries:
            movies([("Toy Story", 1995), ("Toy Story 2", 1999), ("Toy Story 3", 2010), ("Toy Story 4", 2019)])),
        .init(id: "shrek", name: "Shrek", summary: "Shrek and Puss in Boots", entries:
            movies([("Shrek", 2001), ("Shrek 2", 2004), ("Shrek the Third", 2007), ("Shrek Forever After", 2010), ("Puss in Boots", 2011), ("Puss in Boots: The Last Wish", 2022)])),
        .init(id: "pirates", name: "Pirates of the Caribbean", summary: "The Pirates of the Caribbean films", entries:
            movies([("Pirates of the Caribbean: The Curse of the Black Pearl", 2003), ("Pirates of the Caribbean: Dead Man's Chest", 2006), ("Pirates of the Caribbean: At World's End", 2007), ("Pirates of the Caribbean: On Stranger Tides", 2011), ("Pirates of the Caribbean: Dead Men Tell No Tales", 2017)])),
        .init(id: "transformers", name: "Transformers", summary: "Autobots, Decepticons, and their origins", entries:
            movies([("Transformers", 2007), ("Transformers: Revenge of the Fallen", 2009), ("Transformers: Dark of the Moon", 2011), ("Transformers: Age of Extinction", 2014), ("Transformers: The Last Knight", 2017), ("Bumblebee", 2018), ("Transformers: Rise of the Beasts", 2023)])),
        .init(id: "hunger-games", name: "The Hunger Games", summary: "The Hunger Games films", entries:
            movies([("The Hunger Games", 2012), ("The Hunger Games: Catching Fire", 2013), ("The Hunger Games: Mockingjay - Part 1", 2014), ("The Hunger Games: Mockingjay - Part 2", 2015), ("The Hunger Games: The Ballad of Songbirds & Snakes", 2023)])),
        .init(id: "twilight", name: "The Twilight Saga", summary: "The Twilight films", entries:
            movies([("Twilight", 2008), ("The Twilight Saga: New Moon", 2009), ("The Twilight Saga: Eclipse", 2010), ("The Twilight Saga: Breaking Dawn - Part 1", 2011), ("The Twilight Saga: Breaking Dawn - Part 2", 2012)])),
        .init(id: "john-wick", name: "John Wick", summary: "The John Wick action series", entries:
            movies([("John Wick", 2014), ("John Wick: Chapter 2", 2017), ("John Wick: Chapter 3 - Parabellum", 2019), ("John Wick: Chapter 4", 2023)])),
        .init(id: "the-matrix", name: "The Matrix", summary: "The Matrix science-fiction films", entries:
            movies([("The Matrix", 1999), ("The Matrix Reloaded", 2003), ("The Matrix Revolutions", 2003), ("The Matrix Resurrections", 2021)])),
        .init(id: "rocky-creed", name: "Rocky & Creed", summary: "Rocky Balboa and Adonis Creed", entries:
            movies([("Rocky", 1976), ("Rocky II", 1979), ("Rocky III", 1982), ("Rocky IV", 1985), ("Rocky V", 1990), ("Rocky Balboa", 2006), ("Creed", 2015), ("Creed II", 2018), ("Creed III", 2023)]))
    ]

    private static func movies(_ values: [(String, Int)], alternateTitles: [String: [String]] = [:]) -> [IMDbFranchiseEntry] {
        values.map {
            IMDbFranchiseEntry(title: $0.0, year: $0.1, kind: "Movie", alternateTitles: alternateTitles[$0.0] ?? [])
        }
    }

    private static func series(_ values: [(String, Int)]) -> [IMDbFranchiseEntry] {
        values.map { IMDbFranchiseEntry(title: $0.0, year: $0.1, kind: "Series") }
    }
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
    private static let topChartMinimumVotes = 25_000
    private static let topChartFallbackMeanRating = 7.0

    private let databaseURL: URL
    private let fileManager = FileManager.default
    private let searchIndexLock = NSLock()
    private var hasSearchIndexes = false
    private let discoveryIndexLock = NSLock()
    private var hasDiscoveryIndex = false
    private let seriesGenreIndexLock = NSLock()
    private var hasSeriesGenreIndex = false
    private let datasetCacheLock = NSLock()
    private var cachedGenreFacets: [IMDbGenreFacet]?
    private var cachedDiscoveryCandidates: [Int: [IMDbTitleMetadata]] = [:]
    private var cachedIMDbChartMeans: (movies: Double, series: Double)?
    private let endpoints: [(String, URL)] = [
        ("titles", URL(string: "https://datasets.imdbws.com/title.basics.tsv.gz")!),
        ("episodes", URL(string: "https://datasets.imdbws.com/title.episode.tsv.gz")!),
        ("ratings", URL(string: "https://datasets.imdbws.com/title.ratings.tsv.gz")!),
        ("names", URL(string: "https://datasets.imdbws.com/name.basics.tsv.gz")!),
        ("principals", URL(string: "https://datasets.imdbws.com/title.principals.tsv.gz")!),
        ("crew", URL(string: "https://datasets.imdbws.com/title.crew.tsv.gz")!)
    ]

    private init(databaseURLOverride: URL? = nil) {
        if let databaseURLOverride {
            databaseURL = databaseURLOverride
            return
        }
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = support.appendingPathComponent("Denbox", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        databaseURL = directory.appendingPathComponent("imdb-metadata.sqlite")
    }

#if DENBOX_TESTING
    static func testingStore(databaseURL: URL) -> IMDbMetadataStore {
        IMDbMetadataStore(databaseURLOverride: databaseURL)
    }
#endif

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
                try self.installOfficialFiles(
                    titles: downloaded["titles"]!, episodes: downloaded["episodes"]!, ratings: downloaded["ratings"]!,
                    names: downloaded["names"], principals: downloaded["principals"], crew: downloaded["crew"], progress: progress
                )
            }.value
        } catch {
            throw IMDbMetadataError.importFailed(error.localizedDescription)
        }
        progress("IMDb data is ready on this Mac.")
    }

    func installOfficialFiles(titles: URL, episodes: URL, ratings: URL,
                              names: URL? = nil, principals: URL? = nil, crew: URL? = nil,
                              progress: @escaping @Sendable (String) -> Void) throws {
        let workspace = fileManager.temporaryDirectory.appendingPathComponent("Denbox-IMDb-Import-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: workspace) }
        let buildURL = workspace.appendingPathComponent("imdb-metadata.sqlite")
        try importDataset(titles: titles, episodes: episodes, ratings: ratings,
                          names: names, principals: principals, crew: crew, to: buildURL, progress: progress)
        try installDatabase(from: buildURL)
    }

    func enrichment(title: String, year: String, includeSimilar: Bool = true) -> IMDbEnrichment? {
        let indexesReady = ensureSearchIndexes()
        guard let db = openReadOnly() else { return nil }
        defer { sqlite3_close(db) }
        guard let series = matchSeries(db: db, title: title, year: Int(year), indexesReady: indexesReady) else { return nil }
        let episodes = episodeRows(db: db, parent: series.tconst)
        let similar = includeSimilar ? similarRows(db: db, to: series) : []
        return IMDbEnrichment(series: series, episodes: episodes, similarSeries: similar)
    }

    func hasPeopleData() -> Bool {
        guard let db = openReadOnly() else { return false }
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT value FROM metadata WHERE key='people_ready'", -1, &statement, nil) == SQLITE_OK,
              let statement else { return false }
        defer { sqlite3_finalize(statement) }
        return sqlite3_step(statement) == SQLITE_ROW && text(statement, 0) == "1"
    }

    func franchiseTitles(for franchiseID: String) -> [IMDbTitleMetadata] {
        guard let franchise = IMDbFranchiseCatalog.all.first(where: { $0.id == franchiseID }) else { return [] }
        let indexesReady = ensureSearchIndexes()
        guard let db = openReadOnly() else { return [] }
        defer { sqlite3_close(db) }

        var resolved: [IMDbTitleMetadata] = []
        var seen = Set<String>()
        for entry in franchise.entries {
            let predicate = entry.kind == "Movie" ? "title_type='movie'" : "title_type IN ('tvSeries','tvMiniSeries')"
            let columns = "tconst,primary_title,start_year,genres,rating,votes,normalized_primary,normalized_original,title_type"
            let sql = exactTitleLookupSQL(columns: columns, predicate: predicate, kind: entry.kind, indexesReady: indexesReady)
            var candidates: [(title: IMDbTitleMetadata, primary: String, original: String, score: Double)] = []
            let aliases = ([entry.title] + entry.alternateTitles).uniqued()

            for alias in aliases {
                let normalized = imdbNormalize(alias)
                guard !normalized.isEmpty else { continue }
                candidates.append(contentsOf: queryTitleRows(db: db, sql: sql, normalized: normalized, year: entry.year))
            }

            let exact = candidates.filter { candidate in
                let normalizedPrimary = imdbNormalize(candidate.primary)
                let normalizedOriginal = imdbNormalize(candidate.original)
                return aliases.contains { alias in
                    let normalizedAlias = imdbNormalize(alias)
                    return normalizedAlias == normalizedPrimary || normalizedAlias == normalizedOriginal
                }
            }
            let best = exact.sorted { lhs, rhs in
                let leftDistance = lhs.title.year.map { abs($0 - entry.year) } ?? Int.max
                let rightDistance = rhs.title.year.map { abs($0 - entry.year) } ?? Int.max
                if leftDistance != rightDistance { return leftDistance < rightDistance }
                return (lhs.title.votes ?? 0) > (rhs.title.votes ?? 0)
            }.first?.title

            if let best, seen.insert(best.tconst).inserted {
                resolved.append(best)
            }
        }
        return resolved
    }

    func searchPeople(_ query: String, limit: Int = 80) -> [IMDbPersonMetadata] {
        let terms = query.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map { imdbNormalize(String($0)) }.filter { $0.count >= 2 }
        guard !terms.isEmpty, hasPeopleData(), let db = openReadOnly() else { return [] }
        defer { sqlite3_close(db) }
        let match = terms.map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"*" }.joined(separator: " AND ")
        let sql = """
        SELECT p.nconst,p.primary_name,p.birth_year,p.death_year,p.primary_profession,p.known_for_titles
        FROM people_search s JOIN people p ON p.nconst=s.nconst
        WHERE people_search MATCH ?
        ORDER BY bm25(people_search),p.primary_name COLLATE NOCASE
        LIMIT ?
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return [] }
        defer { sqlite3_finalize(statement) }
        bind(match, to: statement, at: 1)
        sqlite3_bind_int(statement, 2, Int32(max(1, min(limit, 200))))
        var people: [IMDbPersonMetadata] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let id = text(statement, 0), let name = text(statement, 1) else { continue }
            people.append(IMDbPersonMetadata(
                nconst: id,
                name: name,
                birthYear: integer(statement, 2),
                deathYear: integer(statement, 3),
                professions: (text(statement, 4) ?? "").split(separator: ",").map(String.init),
                knownForTitleIDs: (text(statement, 5) ?? "").split(separator: ",").map(String.init)
            ))
        }
        return people
    }

    func person(for nconst: String) -> IMDbPersonMetadata? {
        guard nconst.range(of: #"^nm\d{7,10}$"#, options: .regularExpression) != nil,
              hasPeopleData(), let db = openReadOnly() else { return nil }
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        let sql = "SELECT nconst,primary_name,birth_year,death_year,primary_profession,known_for_titles FROM people WHERE nconst=? LIMIT 1"
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return nil }
        defer { sqlite3_finalize(statement) }
        bind(nconst, to: statement, at: 1)
        guard sqlite3_step(statement) == SQLITE_ROW,
              let id = text(statement, 0), let name = text(statement, 1) else { return nil }
        return IMDbPersonMetadata(
            nconst: id,
            name: name,
            birthYear: integer(statement, 2),
            deathYear: integer(statement, 3),
            professions: (text(statement, 4) ?? "").split(separator: ",").map(String.init),
            knownForTitleIDs: (text(statement, 5) ?? "").split(separator: ",").map(String.init)
        )
    }

    func principalPeople(for tconst: String, limit: Int = 20) -> [IMDbPersonMetadata] {
        guard tconst.range(of: #"^tt\d{7,10}$"#, options: .regularExpression) != nil,
              hasPeopleData(), let db = openReadOnly() else { return [] }
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        let sql = """
        SELECT p.nconst,p.primary_name,p.birth_year,p.death_year,p.primary_profession,p.known_for_titles
        FROM title_principals c JOIN people p ON p.nconst=c.nconst
        WHERE c.tconst=? AND c.category IN ('actor','actress')
        ORDER BY c.ordering LIMIT ?
        """
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return [] }
        defer { sqlite3_finalize(statement) }
        bind(tconst, to: statement, at: 1)
        sqlite3_bind_int(statement, 2, Int32(max(1, min(limit, 50))))
        var people: [IMDbPersonMetadata] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let id = text(statement, 0), let name = text(statement, 1), !name.isEmpty else { continue }
            people.append(IMDbPersonMetadata(
                nconst: id,
                name: name,
                birthYear: integer(statement, 2),
                deathYear: integer(statement, 3),
                professions: (text(statement, 4) ?? "").split(separator: ",").map(String.init),
                knownForTitleIDs: (text(statement, 5) ?? "").split(separator: ",").map(String.init)
            ))
        }
        return people
    }

    func personCredits(for nconst: String, offset: Int = 0, limit: Int = 100) -> [IMDbPersonCredit] {
        guard hasPeopleData(), let db = openReadOnly() else { return [] }
        defer { sqlite3_close(db) }
        let sql = """
        SELECT t.tconst,t.primary_title,t.start_year,t.genres,t.rating,t.votes,t.title_type,
               c.category,c.job,c.characters,c.ordering
        FROM (
            SELECT tconst,nconst,category,job,characters,ordering FROM title_principals WHERE nconst=?
            UNION ALL
            SELECT c.tconst,c.nconst,c.category,NULL,NULL,10000 FROM title_crew c
            WHERE c.nconst=? AND NOT EXISTS (
                SELECT 1 FROM title_principals p
                WHERE p.tconst=c.tconst AND p.nconst=c.nconst AND p.category=c.category
            )
        ) c JOIN titles t ON t.tconst=c.tconst
        WHERE t.title_type IN ('movie','tvSeries','tvMiniSeries','tvEpisode')
        ORDER BY t.start_year IS NULL,t.start_year DESC,c.ordering,t.primary_title COLLATE NOCASE
        LIMIT ? OFFSET ?
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return [] }
        defer { sqlite3_finalize(statement) }
        bind(nconst, to: statement, at: 1)
        bind(nconst, to: statement, at: 2)
        sqlite3_bind_int(statement, 3, Int32(max(1, min(limit, 250))))
        sqlite3_bind_int(statement, 4, Int32(max(0, offset)))
        var credits: [IMDbPersonCredit] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let id = text(statement, 0), let title = text(statement, 1),
                  let kind = text(statement, 6), let category = text(statement, 7) else { continue }
            let kindLabel = kind == "movie" ? "Movie" : (kind == "tvEpisode" ? "Episode" : "Series")
            let metadata = IMDbTitleMetadata(
                tconst: id, title: title, year: integer(statement, 2),
                genres: (text(statement, 3) ?? "").split(separator: ",").map(String.init),
                rating: double(statement, 4), votes: integer(statement, 5), kind: kindLabel
            )
            credits.append(IMDbPersonCredit(
                title: metadata, category: category, job: text(statement, 8),
                characters: text(statement, 9), ordering: integer(statement, 10) ?? 10_000
            ))
        }
        return credits
    }

    func similarSeries(for seriesID: String) -> [IMDbTitleMetadata] {
        _ = ensureSearchIndexes()
        guard ensureSeriesGenreIndex() else { return [] }
        guard let db = openReadOnly() else { return [] }
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        let sql = "SELECT tconst,primary_title,start_year,genres,rating,votes FROM titles WHERE tconst=? AND title_type IN ('tvSeries','tvMiniSeries')"
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return [] }
        defer { sqlite3_finalize(statement) }
        bind(seriesID, to: statement, at: 1)
        guard sqlite3_step(statement) == SQLITE_ROW,
              let id = text(statement, 0), let title = text(statement, 1) else { return [] }
        let series = IMDbTitleMetadata(
            tconst: id,
            title: title,
            year: integer(statement, 2),
            genres: (text(statement, 3) ?? "").split(separator: ",").map(String.init),
            rating: double(statement, 4),
            votes: integer(statement, 5)
        )
        return similarRows(db: db, to: series)
    }

    func genreFacets() -> [IMDbGenreFacet] {
        datasetCacheLock.lock()
        if let cachedGenreFacets {
            datasetCacheLock.unlock()
            return cachedGenreFacets
        }
        datasetCacheLock.unlock()

        guard let db = openReadOnly() else { return [] }
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        let sql = "SELECT genres FROM titles WHERE title_type IN ('movie','tvSeries','tvMiniSeries') AND genres IS NOT NULL AND genres<>''"
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return [] }
        defer { sqlite3_finalize(statement) }
        var counts: [String: Int] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            let genres = Set((text(statement, 0) ?? "").split(separator: ",").map(String.init))
            for genre in genres where !genre.isEmpty { counts[genre, default: 0] += 1 }
        }
        let facets = counts.map { IMDbGenreFacet(name: $0.key, titleCount: $0.value) }
            .sorted { lhs, rhs in
                if lhs.titleCount != rhs.titleCount { return lhs.titleCount > rhs.titleCount }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
        datasetCacheLock.lock()
        if cachedGenreFacets == nil { cachedGenreFacets = facets }
        let result = cachedGenreFacets ?? facets
        datasetCacheLock.unlock()
        return result
    }

    func discoveryCandidates(limit: Int = 30_000) -> [IMDbTitleMetadata] {
        let bounded = max(1, min(limit, 50_000))
        datasetCacheLock.lock()
        if let cached = cachedDiscoveryCandidates[bounded] {
            datasetCacheLock.unlock()
            return cached
        }
        datasetCacheLock.unlock()

        let indexReady = ensureDiscoveryIndex()
        guard let db = openReadOnly() else { return [] }
        defer { sqlite3_close(db) }
        let discoveryIndex = indexReady ? " INDEXED BY idx_discovery_rating" : ""
        let sql = """
        SELECT tconst,primary_title,start_year,genres,rating,votes,title_type
        FROM titles\(discoveryIndex)
        WHERE title_type IN ('movie','tvSeries','tvMiniSeries')
          AND rating IS NOT NULL AND votes >= 50
        ORDER BY rating DESC,votes DESC
        LIMIT \(bounded)
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return [] }
        defer { sqlite3_finalize(statement) }
        var result: [IMDbTitleMetadata] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let id = text(statement, 0), let title = text(statement, 1), let type = text(statement, 6) else { continue }
            result.append(IMDbTitleMetadata(
                tconst: id,
                title: title,
                year: integer(statement, 2),
                genres: (text(statement, 3) ?? "").split(separator: ",").map(String.init),
                rating: double(statement, 4),
                votes: integer(statement, 5),
                kind: type == "movie" ? "Movie" : "Series"
            ))
        }
        datasetCacheLock.lock()
        if cachedDiscoveryCandidates[bounded] == nil { cachedDiscoveryCandidates[bounded] = result }
        let cachedResult = cachedDiscoveryCandidates[bounded] ?? result
        datasetCacheLock.unlock()
        return cachedResult
    }

#if DENBOX_TESTING
    func discoveryQueryPlanForTesting() -> [String] {
        guard let db = openReadOnly() else { return [] }
        defer { sqlite3_close(db) }
        let sql = """
        EXPLAIN QUERY PLAN
        SELECT tconst,primary_title,start_year,genres,rating,votes,title_type
        FROM titles INDEXED BY idx_discovery_rating
        WHERE title_type IN ('movie','tvSeries','tvMiniSeries')
          AND rating IS NOT NULL AND votes >= 50
        ORDER BY rating DESC,votes DESC LIMIT 30000
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return [] }
        defer { sqlite3_finalize(statement) }
        var rows: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let detail = text(statement, 3) { rows.append(detail) }
        }
        return rows
    }
#endif

    func matchTitle(title: String, year: String?, kind: String) -> IMDbTitleMetadata? {
        let normalized = imdbNormalize(title)
        let indexesReady = ensureSearchIndexes()
        guard !normalized.isEmpty, let db = openReadOnly() else { return nil }
        defer { sqlite3_close(db) }
        let predicate = kind == "Movie" ? "title_type='movie'" : "title_type IN ('tvSeries','tvMiniSeries')"
        let columns = "tconst,primary_title,start_year,genres,rating,votes,normalized_primary,normalized_original,title_type"
        let exactSQL = exactTitleLookupSQL(columns: columns, predicate: predicate, kind: kind, indexesReady: indexesReady)
        var exact = queryTitleRows(db: db, sql: exactSQL, normalized: normalized, year: year.flatMap(Int.init))
        if exact.isEmpty, let yearValue = Int(year ?? "") {
            let yearIndex = indexesReady
                ? (kind == "Movie" ? " INDEXED BY idx_movie_start_year" : " INDEXED BY idx_series_start_year")
                : ""
            let fuzzySQL = "SELECT \(columns) FROM titles\(yearIndex) WHERE \(predicate) AND start_year BETWEEN ? AND ? AND rating IS NOT NULL ORDER BY votes DESC LIMIT 4000"
            exact = queryTitleRows(db: db, sql: fuzzySQL, normalized: normalized, year: yearValue)
        }
        guard !exact.isEmpty else { return nil }
        let ranked = exact.sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            if let yearValue = Int(year ?? "") {
                let leftDistance = lhs.title.year.map { abs($0 - yearValue) } ?? Int.max
                let rightDistance = rhs.title.year.map { abs($0 - yearValue) } ?? Int.max
                if leftDistance != rightDistance { return leftDistance < rightDistance }
            }
            return (lhs.title.votes ?? 0) > (rhs.title.votes ?? 0)
        }
        let exactMatches = ranked.filter { $0.primary == normalized || $0.original == normalized }
        if !exactMatches.isEmpty { return exactMatches.first?.title }
        guard ranked[0].score >= 0.92 else { return nil }
        if ranked.count > 1, ranked[0].score - ranked[1].score < 0.035 { return nil }
        if let yearValue = Int(year ?? ""), let matchedYear = ranked[0].title.year, abs(yearValue - matchedYear) > 2 { return nil }
        return ranked[0].title
    }

    func catalogMetadata(for items: [MediaItem]) -> [String: IMDbTitleMetadata] {
        let indexesReady = ensureSearchIndexes()
        guard let db = openReadOnly() else { return [:] }
        defer { sqlite3_close(db) }
        var result: [String: IMDbTitleMetadata] = [:]
        for item in items where item.imdbID == nil || item.genres.isEmpty {
            let normalized = imdbNormalize(item.title)
            guard !normalized.isEmpty else { continue }
            let predicate = item.kind == "Movie" ? "title_type='movie'" : "title_type IN ('tvSeries','tvMiniSeries')"
            let columns = "tconst,primary_title,start_year,genres,rating,votes,normalized_primary,normalized_original,title_type"
            let sql = exactTitleLookupSQL(columns: columns, predicate: predicate, kind: item.kind, indexesReady: indexesReady)
            let candidates = queryTitleRows(db: db, sql: sql, normalized: normalized, year: Int(item.year))
                .filter { $0.primary == normalized || $0.original == normalized }
            let sorted = candidates.sorted { lhs, rhs in
                let year = Int(item.year)
                let leftDistance = year.flatMap { value in lhs.title.year.map { abs($0 - value) } } ?? Int.max
                let rightDistance = year.flatMap { value in rhs.title.year.map { abs($0 - value) } } ?? Int.max
                if leftDistance != rightDistance { return leftDistance < rightDistance }
                return (lhs.title.votes ?? 0) > (rhs.title.votes ?? 0)
            }
            if let match = sorted.first?.title { result[item.id] = match }
        }
        return result
    }

    private func exactTitleLookupSQL(columns: String, predicate: String, kind: String, indexesReady: Bool) -> String {
        let primaryIndex = indexesReady ? " INDEXED BY idx_titles_normalized" : ""
        let originalIndex: String
        if indexesReady {
            originalIndex = kind == "Movie"
                ? " INDEXED BY idx_movie_normalized_original"
                : " INDEXED BY idx_series_normalized_original"
        } else {
            originalIndex = ""
        }
        return """
        SELECT \(columns) FROM titles\(primaryIndex)
        WHERE \(predicate) AND normalized_primary=?
        UNION ALL
        SELECT \(columns) FROM titles\(originalIndex)
        WHERE \(predicate) AND normalized_original=?
        """
    }

    func principalCast(for tconst: String, limit: Int = 20) -> [String] {
        principalPeople(for: tconst, limit: limit).map(\.name)
    }

    func chartLists() -> IMDbChartLists? {
        guard let db = openReadOnly() else { return nil }
        defer { sqlite3_close(db) }
        let means = chartMeanRatings(db: db)
        return IMDbChartLists(
            topMovies: chartRows(
                db: db,
                predicate: "title_type='movie' AND rating IS NOT NULL AND votes >= \(Self.topChartMinimumVotes)",
                order: chartOrder(meanRating: means.movies),
                limit: 250,
                kind: "Movie"
            ),
            topSeries: chartRows(
                db: db,
                predicate: "title_type IN ('tvSeries','tvMiniSeries') AND rating IS NOT NULL AND votes >= \(Self.topChartMinimumVotes)",
                order: chartOrder(meanRating: means.series),
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

    func title(tconst: String) -> IMDbTitleMetadata? {
        guard let db = openReadOnly() else { return nil }
        defer { sqlite3_close(db) }
        let sql = "SELECT tconst,primary_title,start_year,genres,rating,votes,title_type FROM titles WHERE tconst=? LIMIT 1"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return nil }
        defer { sqlite3_finalize(statement) }
        bind(tconst, to: statement, at: 1)
        guard sqlite3_step(statement) == SQLITE_ROW,
              let id = text(statement, 0), let name = text(statement, 1), let type = text(statement, 6) else { return nil }
        let kind = type == "movie" ? "Movie" : (type == "tvEpisode" ? "Episode" : "Series")
        return IMDbTitleMetadata(tconst: id, title: name, year: integer(statement, 2),
                                 genres: (text(statement, 3) ?? "").split(separator: ",").map(String.init),
                                 rating: double(statement, 4), votes: integer(statement, 5), kind: kind)
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

    private func chartMeanRatings(db: OpaquePointer) -> (movies: Double, series: Double) {
        datasetCacheLock.lock()
        if let cachedIMDbChartMeans {
            datasetCacheLock.unlock()
            return cachedIMDbChartMeans
        }
        datasetCacheLock.unlock()

        let computed = (
            movies: chartMeanRating(db: db, titleTypePredicate: "title_type='movie'") ?? Self.topChartFallbackMeanRating,
            series: chartMeanRating(db: db, titleTypePredicate: "title_type IN ('tvSeries','tvMiniSeries')") ?? Self.topChartFallbackMeanRating
        )

        datasetCacheLock.lock()
        if let cachedIMDbChartMeans {
            datasetCacheLock.unlock()
            return cachedIMDbChartMeans
        }
        cachedIMDbChartMeans = computed
        datasetCacheLock.unlock()
        return computed
    }

    private func chartMeanRating(db: OpaquePointer, titleTypePredicate: String) -> Double? {
        let sql = "SELECT AVG(rating) FROM titles WHERE \(titleTypePredicate) AND rating IS NOT NULL"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return nil }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW,
              let value = double(statement, 0), value.isFinite, (1.0...10.0).contains(value) else { return nil }
        return value
    }

    private func chartOrder(meanRating: Double) -> String {
        let priorWeight = Double(Self.topChartMinimumVotes) * meanRating
        return "((votes * rating + \(priorWeight)) / (votes + \(Self.topChartMinimumVotes))) DESC, votes DESC"
    }

    private func queryTitleRows(db: OpaquePointer, sql: String, normalized: String, year: Int?) -> [(title: IMDbTitleMetadata, primary: String, original: String, score: Double)] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return [] }
        defer { sqlite3_finalize(statement) }
        if sql.contains("BETWEEN") {
            guard let year else { return [] }
            sqlite3_bind_int(statement, 1, Int32(year - 1))
            sqlite3_bind_int(statement, 2, Int32(year + 1))
        } else {
            bind(normalized, to: statement, at: 1)
            bind(normalized, to: statement, at: 2)
        }
        var result: [(IMDbTitleMetadata, String, String, Double)] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let id = text(statement, 0), let name = text(statement, 1), let type = text(statement, 8) else { continue }
            let primary = text(statement, 6) ?? ""
            let original = text(statement, 7) ?? ""
            let recordYear = integer(statement, 2)
            let score = max(titleSimilarity(normalized, primary), titleSimilarity(normalized, original))
            let yearPenalty = year.flatMap { target in recordYear.map { abs(target - $0) } } ?? 0
            let metadata = IMDbTitleMetadata(
                tconst: id,
                title: name,
                year: recordYear,
                genres: (text(statement, 3) ?? "").split(separator: ",").map(String.init),
                rating: double(statement, 4),
                votes: integer(statement, 5),
                kind: type == "movie" ? "Movie" : "Series"
            )
            result.append((metadata, primary, original, score - Double(yearPenalty) * 0.025))
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

    private func ensureSearchIndexes() -> Bool {
        searchIndexLock.lock()
        defer { searchIndexLock.unlock() }
        if hasSearchIndexes { return true }
        guard isAvailable else { return false }

        var db: OpaquePointer?
        guard sqlite3_open_v2(databaseURL.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              let db else {
            if let db { sqlite3_close(db) }
            return false
        }
        sqlite3_busy_timeout(db, 20_000)
        let result = sqlite3_exec(db, """
            CREATE INDEX IF NOT EXISTS idx_titles_normalized
                ON titles(title_type,normalized_primary,normalized_original);
            CREATE INDEX IF NOT EXISTS idx_series_normalized_original
                ON titles(normalized_original)
                WHERE title_type IN ('tvSeries','tvMiniSeries');
            CREATE INDEX IF NOT EXISTS idx_series_start_year
                ON titles(start_year)
                WHERE title_type IN ('tvSeries','tvMiniSeries');
            CREATE INDEX IF NOT EXISTS idx_movie_normalized_original
                ON titles(normalized_original)
                WHERE title_type='movie';
            CREATE INDEX IF NOT EXISTS idx_movie_start_year
                ON titles(start_year,votes DESC)
                WHERE title_type='movie' AND rating IS NOT NULL;
            """, nil, nil, nil)
        sqlite3_close(db)
        hasSearchIndexes = result == SQLITE_OK
        return hasSearchIndexes
    }

    private func ensureDiscoveryIndex() -> Bool {
        discoveryIndexLock.lock()
        defer { discoveryIndexLock.unlock() }
        if hasDiscoveryIndex { return true }
        guard isAvailable else { return false }

        var db: OpaquePointer?
        guard sqlite3_open_v2(databaseURL.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              let db else {
            if let db { sqlite3_close(db) }
            return false
        }
        sqlite3_busy_timeout(db, 20_000)
        let result = sqlite3_exec(db, """
            CREATE INDEX IF NOT EXISTS idx_discovery_rating
                ON titles(rating DESC,votes DESC)
                WHERE title_type IN ('movie','tvSeries','tvMiniSeries')
                  AND rating IS NOT NULL AND votes >= 50;
            """, nil, nil, nil)
        sqlite3_close(db)
        hasDiscoveryIndex = result == SQLITE_OK
        return hasDiscoveryIndex
    }

    private func invalidateDatasetCaches() {
        datasetCacheLock.lock()
        cachedGenreFacets = nil
        cachedDiscoveryCandidates.removeAll(keepingCapacity: false)
        cachedIMDbChartMeans = nil
        datasetCacheLock.unlock()
    }

    private func ensureSeriesGenreIndex() -> Bool {
        seriesGenreIndexLock.lock()
        defer { seriesGenreIndexLock.unlock() }
        if hasSeriesGenreIndex { return true }
        guard isAvailable else { return false }

        var db: OpaquePointer?
        guard sqlite3_open_v2(databaseURL.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              let db else {
            if let db { sqlite3_close(db) }
            return false
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 20_000)

        guard sqlite3_exec(db, "CREATE TABLE IF NOT EXISTS series_genres(genre TEXT NOT NULL,tconst TEXT NOT NULL,PRIMARY KEY(genre,tconst)) WITHOUT ROWID;", nil, nil, nil) == SQLITE_OK else {
            return false
        }
        if metadataValue("series_genres_ready", db: db) == "1" {
            hasSeriesGenreIndex = true
            return true
        }

        guard sqlite3_exec(db, "BEGIN IMMEDIATE; DELETE FROM series_genres;", nil, nil, nil) == SQLITE_OK else { return false }
        var committed = false
        defer { if !committed { _ = sqlite3_exec(db, "ROLLBACK;", nil, nil, nil) } }

        var select: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT tconst,genres FROM titles WHERE title_type IN ('tvSeries','tvMiniSeries') AND genres IS NOT NULL AND genres<>''", -1, &select, nil) == SQLITE_OK,
              let select else { return false }
        defer { sqlite3_finalize(select) }
        var insert: OpaquePointer?
        guard sqlite3_prepare_v2(db, "INSERT OR IGNORE INTO series_genres(genre,tconst) VALUES(?,?)", -1, &insert, nil) == SQLITE_OK,
              let insert else { return false }
        defer { sqlite3_finalize(insert) }

        while true {
            let step = sqlite3_step(select)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else { return false }
            guard let id = text(select, 0), let rawGenres = text(select, 1) else { continue }
            for rawGenre in rawGenres.split(separator: ",") {
                let genre = String(rawGenre).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !genre.isEmpty else { continue }
                sqlite3_reset(insert)
                sqlite3_clear_bindings(insert)
                bind(genre, to: insert, at: 1)
                bind(id, to: insert, at: 2)
                guard sqlite3_step(insert) == SQLITE_DONE else { return false }
            }
        }
        guard sqlite3_exec(db, "INSERT OR REPLACE INTO metadata(key,value) VALUES('series_genres_ready','1'); COMMIT;", nil, nil, nil) == SQLITE_OK else {
            return false
        }
        committed = true
        hasSeriesGenreIndex = true
        return true
    }

    private func metadataValue(_ key: String, db: OpaquePointer) -> String? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT value FROM metadata WHERE key=?", -1, &statement, nil) == SQLITE_OK,
              let statement else { return nil }
        defer { sqlite3_finalize(statement) }
        bind(key, to: statement, at: 1)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return text(statement, 0)
    }

    private func matchSeries(db: OpaquePointer, title: String, year: Int?, indexesReady: Bool) -> IMDbTitleMetadata? {
        let normalized = imdbNormalize(title)
        guard !normalized.isEmpty else { return nil }
        let columns = "tconst,primary_title,start_year,genres,rating,votes,normalized_primary,normalized_original"
        let primaryIndex = indexesReady ? " INDEXED BY idx_titles_normalized" : ""
        let originalIndex = indexesReady ? " INDEXED BY idx_series_normalized_original" : ""
        let yearIndex = indexesReady ? " INDEXED BY idx_series_start_year" : ""
        let primarySQL = "SELECT \(columns) FROM titles\(primaryIndex) WHERE title_type IN ('tvSeries','tvMiniSeries') AND normalized_primary=?"
        let originalSQL = "SELECT \(columns) FROM titles\(originalIndex) WHERE title_type IN ('tvSeries','tvMiniSeries') AND normalized_original=?"
        var candidates = querySeries(db: db, sql: primarySQL, title: normalized, year: year)
        let originals = querySeries(db: db, sql: originalSQL, title: normalized, year: year)
        var seenExact = Set(candidates.map { $0.0.tconst })
        candidates.append(contentsOf: originals.filter { seenExact.insert($0.0.tconst).inserted })
        if candidates.isEmpty, let year {
            let fuzzySQL = "SELECT \(columns) FROM titles\(yearIndex) WHERE title_type IN ('tvSeries','tvMiniSeries') AND start_year BETWEEN ? AND ?"
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
        let placeholders = Array(repeating: "?", count: genres.count).joined(separator: ",")
        let sql = """
        SELECT t.tconst,t.primary_title,t.start_year,t.genres,t.rating,t.votes
        FROM series_genres g JOIN titles t ON t.tconst=g.tconst
        WHERE t.title_type IN ('tvSeries','tvMiniSeries') AND t.rating IS NOT NULL
          AND t.tconst<>? AND g.genre IN (\(placeholders))
        GROUP BY t.tconst
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return [] }
        defer { sqlite3_finalize(statement) }
        bind(series.tconst, to: statement, at: 1)
        for (index, genre) in genres.enumerated() { bind(genre, to: statement, at: Int32(index + 2)) }
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

    private func importDataset(titles: URL, episodes: URL, ratings: URL, names: URL?, principals: URL?, crew: URL?, to destination: URL,
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
        CREATE TABLE series_genres(
          genre TEXT NOT NULL,tconst TEXT NOT NULL,PRIMARY KEY(genre,tconst)
        ) WITHOUT ROWID;
        CREATE TABLE people(
          nconst TEXT PRIMARY KEY,primary_name TEXT NOT NULL,birth_year INTEGER,death_year INTEGER,
          primary_profession TEXT NOT NULL,known_for_titles TEXT NOT NULL
        );
        CREATE TABLE title_principals(
          tconst TEXT NOT NULL,nconst TEXT NOT NULL,category TEXT NOT NULL,job TEXT,characters TEXT,ordering INTEGER NOT NULL,
          PRIMARY KEY(tconst,nconst,category,ordering)
        );
        CREATE TABLE title_crew(
          tconst TEXT NOT NULL,nconst TEXT NOT NULL,category TEXT NOT NULL,
          PRIMARY KEY(tconst,nconst,category)
        );
        BEGIN TRANSACTION;
        """, db: db)
        defer { try? execute("ROLLBACK;", db: db) }

        var insert: OpaquePointer?
        let insertSQL = "INSERT OR IGNORE INTO titles(tconst,title_type,primary_title,original_title,normalized_primary,normalized_original,start_year,genres) VALUES(?,?,?,?,?,?,?,?)"
        guard sqlite3_prepare_v2(db, insertSQL, -1, &insert, nil) == SQLITE_OK, let insert else {
            throw IMDbMetadataError.invalidDatabase
        }
        defer { sqlite3_finalize(insert) }
        var insertSeriesGenre: OpaquePointer?
        guard sqlite3_prepare_v2(db, "INSERT OR IGNORE INTO series_genres(genre,tconst) VALUES(?,?)", -1, &insertSeriesGenre, nil) == SQLITE_OK,
              let insertSeriesGenre else { throw IMDbMetadataError.invalidDatabase }
        defer { sqlite3_finalize(insertSeriesGenre) }
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
            if type == "tvSeries" || type == "tvMiniSeries" {
                for rawGenre in (columns[8] ?? "").split(separator: ",") {
                    let genre = String(rawGenre).trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !genre.isEmpty else { continue }
                    sqlite3_reset(insertSeriesGenre)
                    sqlite3_clear_bindings(insertSeriesGenre)
                    bind(genre, to: insertSeriesGenre, at: 1)
                    bind(id, to: insertSeriesGenre, at: 2)
                    guard sqlite3_step(insertSeriesGenre) == SQLITE_DONE else { throw IMDbMetadataError.invalidDatabase }
                }
            }
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

        if let names {
            progress("Indexing IMDb people…")
            var insertPerson: OpaquePointer?
            let sql = "INSERT OR REPLACE INTO people(nconst,primary_name,birth_year,death_year,primary_profession,known_for_titles) VALUES(?,?,?,?,?,?)"
            guard sqlite3_prepare_v2(db, sql, -1, &insertPerson, nil) == SQLITE_OK, let insertPerson else {
                throw IMDbMetadataError.invalidDatabase
            }
            defer { sqlite3_finalize(insertPerson) }
            try readGzipTSV(names) { columns in
                guard columns.count >= 6, let id = columns[0], let name = columns[1] else { return }
                sqlite3_reset(insertPerson); sqlite3_clear_bindings(insertPerson)
                bind(id, to: insertPerson, at: 1)
                bind(name, to: insertPerson, at: 2)
                if let birth = columns[2].flatMap(Int32.init) { sqlite3_bind_int(insertPerson, 3, birth) }
                else { sqlite3_bind_null(insertPerson, 3) }
                if let death = columns[3].flatMap(Int32.init) { sqlite3_bind_int(insertPerson, 4, death) }
                else { sqlite3_bind_null(insertPerson, 4) }
                bind(columns[4] ?? "", to: insertPerson, at: 5)
                bind(columns[5] ?? "", to: insertPerson, at: 6)
                guard sqlite3_step(insertPerson) == SQLITE_DONE else { throw IMDbMetadataError.invalidDatabase }
            }

            progress("Building IMDb people search index…")
            try execute("""
                CREATE VIRTUAL TABLE people_search USING fts5(nconst UNINDEXED,primary_name,tokenize='unicode61 remove_diacritics 2',prefix='2 3');
                INSERT INTO people_search(nconst,primary_name) SELECT nconst,primary_name FROM people;
                """, db: db)
        }

        if let principals {
            progress("Linking IMDb cast and principal credits…")
            var insertCredit: OpaquePointer?
            let sql = "INSERT OR IGNORE INTO title_principals(tconst,nconst,category,job,characters,ordering) VALUES(?,?,?,?,?,?)"
            guard sqlite3_prepare_v2(db, sql, -1, &insertCredit, nil) == SQLITE_OK, let insertCredit else {
                throw IMDbMetadataError.invalidDatabase
            }
            defer { sqlite3_finalize(insertCredit) }
            try readGzipTSV(principals) { columns in
                guard columns.count >= 6, let titleID = columns[0], let order = columns[1].flatMap(Int32.init),
                      let personID = columns[2], let category = columns[3] else { return }
                sqlite3_reset(insertCredit); sqlite3_clear_bindings(insertCredit)
                bind(titleID, to: insertCredit, at: 1)
                bind(personID, to: insertCredit, at: 2)
                bind(category, to: insertCredit, at: 3)
                bind(columns[4] ?? "", to: insertCredit, at: 4)
                bind(columns[5] ?? "", to: insertCredit, at: 5)
                sqlite3_bind_int(insertCredit, 6, order)
                guard sqlite3_step(insertCredit) == SQLITE_DONE else { throw IMDbMetadataError.invalidDatabase }
            }
        }

        if let crew {
            progress("Linking IMDb directors and writers…")
            var insertCrew: OpaquePointer?
            guard sqlite3_prepare_v2(db, "INSERT OR IGNORE INTO title_crew(tconst,nconst,category) VALUES(?,?,?)", -1, &insertCrew, nil) == SQLITE_OK,
                  let insertCrew else { throw IMDbMetadataError.invalidDatabase }
            defer { sqlite3_finalize(insertCrew) }
            try readGzipTSV(crew) { columns in
                guard columns.count >= 3, let titleID = columns[0] else { return }
                for (column, category) in [(1, "director"), (2, "writer")] {
                    for personID in (columns[column] ?? "").split(separator: ",") {
                        sqlite3_reset(insertCrew); sqlite3_clear_bindings(insertCrew)
                        bind(titleID, to: insertCrew, at: 1)
                        bind(String(personID), to: insertCrew, at: 2)
                        bind(category, to: insertCrew, at: 3)
                        guard sqlite3_step(insertCrew) == SQLITE_DONE else { throw IMDbMetadataError.invalidDatabase }
                    }
                }
            }
        }

        progress("Finishing the local IMDb index…")
        try execute("""
        CREATE INDEX idx_titles_normalized ON titles(title_type,normalized_primary,normalized_original);
        CREATE INDEX idx_series_normalized_original ON titles(normalized_original) WHERE title_type IN ('tvSeries','tvMiniSeries');
        CREATE INDEX idx_series_start_year ON titles(start_year) WHERE title_type IN ('tvSeries','tvMiniSeries');
        CREATE INDEX idx_movie_normalized_original ON titles(normalized_original) WHERE title_type='movie';
        CREATE INDEX idx_movie_start_year ON titles(start_year,votes DESC) WHERE title_type='movie' AND rating IS NOT NULL;
        CREATE INDEX idx_discovery_rating ON titles(rating DESC,votes DESC) WHERE title_type IN ('movie','tvSeries','tvMiniSeries') AND rating IS NOT NULL AND votes >= 50;
        CREATE INDEX idx_episode_parent ON titles(parent_tconst,season_number,episode_number);
        CREATE INDEX idx_genres ON titles(title_type,genres);
        CREATE INDEX idx_title_chart ON titles(title_type,votes DESC,rating DESC);
        CREATE INDEX idx_principals_person ON title_principals(nconst,tconst);
        CREATE INDEX idx_crew_person ON title_crew(nconst,tconst);
        INSERT INTO metadata(key,value) VALUES('updated_at','\(Date().timeIntervalSince1970)');
        INSERT INTO metadata(key,value) VALUES('series_genres_ready','1');
        \(names != nil && principals != nil ? "INSERT INTO metadata(key,value) VALUES('people_ready','1');" : "")
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
            searchIndexLock.lock()
            hasSearchIndexes = false
            searchIndexLock.unlock()
            discoveryIndexLock.lock()
            hasDiscoveryIndex = false
            discoveryIndexLock.unlock()
            seriesGenreIndexLock.lock()
            hasSeriesGenreIndex = false
            seriesGenreIndexLock.unlock()
            invalidateDatasetCaches()
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
                    if let line = String(data: pending, encoding: .utf8), !line.isEmpty,
                       !line.hasPrefix("tconst\t"), !line.hasPrefix("nconst\t") {
                        try row(line.split(separator: "\t", omittingEmptySubsequences: false).map { field in
                            field == "\\N" ? nil : String(field)
                        })
                    }
                    pending.removeAll(keepingCapacity: true)
                    lineStart = index + 1
                }
                if lineStart < chunk.count { pending.append(chunk.subdata(in: lineStart..<chunk.count)) }
            }
            if !pending.isEmpty, let line = String(data: pending, encoding: .utf8),
               !line.hasPrefix("tconst\t"), !line.hasPrefix("nconst\t") {
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

enum IMDbTitleNormalizer {
    private static let locale = Locale(identifier: "en_US_POSIX")
    private static let alphanumeric = CharacterSet.alphanumerics

    static func normalize(_ value: String) -> String {
        if value.unicodeScalars.allSatisfy(\.isASCII) {
            var bytes: [UInt8] = []
            bytes.reserveCapacity(value.utf8.count)
            for byte in value.utf8 {
                switch byte {
                case 48...57, 97...122: bytes.append(byte)
                case 65...90: bytes.append(byte + 32)
                default: break
                }
            }
            return String(decoding: bytes, as: UTF8.self)
        }

        let folded = value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: locale)
        var normalized = String.UnicodeScalarView()
        normalized.reserveCapacity(folded.unicodeScalars.count)
        for scalar in folded.unicodeScalars where alphanumeric.contains(scalar) {
            normalized.append(scalar)
        }
        return String(normalized)
    }
}

private func imdbNormalize(_ value: String) -> String {
    IMDbTitleNormalizer.normalize(value)
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
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
