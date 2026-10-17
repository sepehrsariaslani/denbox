import Foundation

@main
struct IMDbEnrichmentPerformanceTests {
    @MainActor
    static func main() async throws {
        if CommandLine.arguments.dropFirst().contains("--parser-only") {
            try await verifyDetailParsingResponsiveness()
            return
        }

        let databaseURL = CommandLine.arguments.dropFirst().first.map { URL(fileURLWithPath: $0) }
        let model = LibraryModel(
            loadRemoteCatalog: false,
            refreshStaleDetailsInBackground: false,
            databaseURL: databaseURL
        )
        let database = MediaDatabase(databaseURL: databaseURL)
        let candidates = database.loadCatalog().filter { item in
            item.isRemote && item.kind == "Series" && database.loadDetailsPayload(for: item.id) != nil
        }
        guard let item = candidates.max(by: { countEpisodes(for: $0, database: database) < countEpisodes(for: $1, database: database) }) else {
            throw PerformanceTestFailure(message: "no cached series details are available for the responsiveness probe")
        }

        let started = Date()
        guard let details = await model.loadDetails(for: item) else {
            throw PerformanceTestFailure(message: "cached series details could not be loaded")
        }
        let initialLoadSeconds = Date().timeIntervalSince(started)
        let episodeCount = details.seasons.reduce(0) { $0 + $1.episodes.count }
        log(String(format: "Cached series page data: %.3fs · %d episodes", initialLoadSeconds, episodeCount))
        try require(initialLoadSeconds < 1, "cached series details blocked the main actor for more than one second")

        if IMDbMetadataStore.shared.isAvailable {
            let enrichmentStarted = Date()
            for _ in 0..<600 {
                if model.recentlyRefreshedDetails[item.id]?.imdbID != nil { break }
                try await Task.sleep(nanoseconds: 50_000_000)
            }
            guard model.recentlyRefreshedDetails[item.id]?.imdbID != nil else {
                throw PerformanceTestFailure(message: "background IMDb enrichment did not finish within 30 seconds")
            }
            let enrichmentSeconds = Date().timeIntervalSince(enrichmentStarted)
            log(String(format: "IMDb enrichment: %.3fs in background", enrichmentSeconds))
            try require(enrichmentSeconds < 10, "background IMDb enrichment took more than ten seconds")
        }
        log("PASS detail responsiveness: cached series renders before IMDb enrichment completes")
    }

    @MainActor
    private static func verifyDetailParsingResponsiveness() async throws {
        let item = MediaItem(
            id: "detail-parser-fixture",
            title: "Large Series Fixture",
            subtitle: "2026 · Series",
            synopsis: "",
            year: "2026",
            kind: "Series",
            symbol: "tv",
            palette: 0,
            isRemote: true
        )
        let episodes: [[String: Any]] = (0..<4_500).map { index in
            [
                "episode_number": index + 1,
                "title": "Episode \(index + 1)",
                "url": "https://media.example/episode-\(index + 1).mp4"
            ]
        }
        let payload: [String: Any] = [
            "data": [
                "seasons": [["season_number": 1, "episodes": episodes]]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let heartbeatStarted = Date()
        let parseTask = Task { await LibraryModel.parseDetailsData(data, for: item) }
        await Task.yield()
        let heartbeatSeconds = Date().timeIntervalSince(heartbeatStarted)
        guard let details = await parseTask.value else {
            throw PerformanceTestFailure(message: "the synthetic episode details could not be parsed")
        }
        let episodeCount = details.seasons.reduce(0) { $0 + $1.episodes.count }
        try require(episodeCount == 4_500, "the parser lost episodes from the large detail payload")
        try require(heartbeatSeconds < 0.05,
                    String(format: "the main-actor heartbeat was blocked for %.3fs during detail parsing", heartbeatSeconds))
        log(String(format: "PASS detail parsing: 4,500 episodes; main-actor heartbeat %.4fs", heartbeatSeconds))
    }

    @MainActor
    private static func countEpisodes(for item: MediaItem, database: MediaDatabase) -> Int {
        guard let cached = database.loadDetailsPayload(for: item.id),
              let payload = try? JSONSerialization.jsonObject(with: cached.payload, options: [.fragmentsAllowed]) else { return 0 }
        let details = LibraryModel.parseDetails(payload, for: item)
        return details.seasons.reduce(0) { $0 + $1.episodes.count }
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw PerformanceTestFailure(message: message) }
    }

    private static func log(_ message: String) {
        FileHandle.standardOutput.write(Data((message + "\n").utf8))
    }
}

private struct PerformanceTestFailure: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}
