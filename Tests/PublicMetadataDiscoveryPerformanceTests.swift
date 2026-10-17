import Foundation

@main
struct PublicMetadataDiscoveryPerformanceTests {
    @MainActor
    static func main() async throws {
        let candidateCount = 5_000
        let targetIndex = candidateCount - 1
        let included: [[String: Any]] = (0..<candidateCount).map { index in
            [
                "type": "movies",
                "id": "fixture\(index)",
                "attributes": [
                    "movie_title": "عنوان \(index)",
                    "movie_title_en": "Fixture Movie \(index)",
                    "pro_year": "2020",
                    "serial": ["enable": false]
                ] as [String: Any]
            ]
        }
        let data = try JSONSerialization.data(withJSONObject: ["included": included])
        try require(data.count < 2_000_000, "the fixture exceeded the production response limit")

        let item = MediaItem(
            id: "fixture-target",
            title: "Fixture Movie \(targetIndex)",
            subtitle: "2020 · Movie",
            synopsis: "Synthetic metadata fixture.",
            year: "2020",
            kind: "Movie",
            symbol: "film",
            palette: 0,
            isRemote: true
        )
        let startedAt = Date()
        let parseTask = Task {
            await PublicMetadataAPIClient.parseSearchPayload(data, item: item, provider: .filimo)
        }
        await Task.yield()
        let mainActorHeartbeat = Date().timeIntervalSince(startedAt)
        let result = await parseTask.value
        let elapsed = Date().timeIntervalSince(startedAt)

        try require(result.hasExpectedShape, "the JSON search response was rejected")
        try require(!result.parsedOnMainThread, "public search JSON and title matching ran on the main thread")
        try require(result.metadata?.pageURL.lastPathComponent == "fixture\(targetIndex)",
                    "the exact title/year match was not selected")
        try require(mainActorHeartbeat < 0.15,
                    "the main actor heartbeat waited \(String(format: "%.3f", mainActorHeartbeat)) seconds")
        try require(elapsed < 2.5,
                    "parsing \(candidateCount) candidates took \(String(format: "%.3f", elapsed)) seconds")

        print("PASS public metadata parsing: \(candidateCount) candidates in \(String(format: "%.3f", elapsed))s off-main; heartbeat \(String(format: "%.3f", mainActorHeartbeat))s; payload \(data.count) bytes")
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw PublicMetadataDiscoveryPerformanceFailure(message: message) }
    }
}

private struct PublicMetadataDiscoveryPerformanceFailure: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}
