import Foundation

@main
struct DetailParsingResponsivenessTests {
    @MainActor
    static func main() async throws {
        let episodeCount = 4_500
        let episodes: [[String: Any]] = (1...episodeCount).map { number in
            [
                "id": "episode-\(number)",
                "title": "Episode \(number)",
                "episode_number": number,
                "play_url": "https://media.example/episode-\(number).mp4"
            ]
        }
        let payload = try JSONSerialization.data(withJSONObject: [
            "seasons": [["season_number": 1, "episodes": episodes]]
        ])
        let item = MediaItem(
            id: "series:large-detail", apiID: "large-detail", title: "Large Detail Fixture",
            subtitle: "Series", synopsis: "", year: "2026", kind: "Series",
            symbol: "tv", palette: 0, isRemote: true
        )

        let started = Date()
        let parsing = Task { @MainActor in
            await LibraryModel.parseDetailsData(payload, for: item)
        }
        let heartbeat = Task { @MainActor in
            await Task.yield()
            return Date()
        }
        let heartbeatDate = await heartbeat.value
        let heartbeatDelay = heartbeatDate.timeIntervalSince(started)
        guard let details = await parsing.value else {
            throw DetailParsingFailure(message: "large cached series details could not be parsed")
        }
        let parsedEpisodeCount = details.seasons.reduce(0) { $0 + $1.episodes.count }
        try require(parsedEpisodeCount == episodeCount, "the background parser dropped series episodes")
        try require(heartbeatDelay < 0.15,
                    String(format: "the main actor heartbeat waited %.3fs for series detail parsing", heartbeatDelay))
        print(String(format: "PASS detail parsing responsiveness: main actor tick %.3fs while parsing %d episodes", heartbeatDelay, parsedEpisodeCount))
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw DetailParsingFailure(message: message) }
    }
}

private struct DetailParsingFailure: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}
