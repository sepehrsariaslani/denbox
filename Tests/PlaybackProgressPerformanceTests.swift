import Foundation

@main
struct PlaybackProgressPerformanceTests {
    @MainActor
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DenboxPlaybackProgress-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let databaseURL = root.appendingPathComponent("library.sqlite")
        let seed = MediaDatabase(databaseURL: databaseURL)
        let historyCount = 10_000
        let now = Date()
        let history = (0..<historyCount).map { index in
            WatchHistoryEntry(
                id: "session-\(index)",
                mediaID: "movie-\(index)",
                episodeID: nil,
                mediaTitle: "Fixture Movie \(index)",
                kind: "Movie",
                episodeTitle: nil,
                episodeLabel: nil,
                year: "2026",
                artworkURL: nil,
                imdbID: nil,
                genres: ["Drama", "Mystery"],
                startedAt: now.addingTimeInterval(-Double(index * 120)),
                positionSeconds: 90,
                durationSeconds: 7_200,
                watchedSeconds: 90,
                playerKind: "Test"
            )
        }
        let export = ViewingDataExport(
            schemaVersion: 2,
            exportedAt: now,
            progress: [],
            history: history,
            personalRatings: []
        )
        guard seed.mergeViewingData(export) else {
            throw PlaybackProgressPerformanceFailure(message: "could not seed watch history")
        }

        let model = LibraryModel(
            loadRemoteCatalog: false,
            refreshStaleDetailsInBackground: false,
            databaseURL: databaseURL,
            startBackgroundCatalogEnrichment: false
        )
        try require(model.viewingStats.sessionCount == 0,
                    "startup synchronously loaded full viewing statistics")
        _ = model.startPlaybackSession(playerKind: "Test", localURL: root.appendingPathComponent("current.mp4"))

        let startedAt = Date()
        for index in 0..<100 {
            model.recordPlaybackProgress(
                position: Double(300 + index * 10),
                duration: 7_200,
                watchedDelta: 10
            )
        }
        let elapsed = Date().timeIntervalSince(startedAt)
        try require(elapsed < 0.75,
                    "100 progress updates with 10,000 history rows took \(String(format: "%.3f", elapsed)) seconds")
        try require(model.continueWatchingItems.contains { $0.mediaID == "local:\(root.appendingPathComponent("current.mp4").standardizedFileURL.path)" },
                    "live progress was not reflected in Continue Watching")
        try require(model.viewingStats.sessionCount == 0,
                    "playback heartbeat forced a full statistics reload")

        let stats = await seed.viewingStatsAsync()
        try require(stats.sessionCount == historyCount + 1,
                    "background viewing statistics missed seeded or active sessions (got \(stats.sessionCount))")
        try require(stats.totalWatchedSeconds == Double(historyCount * 90 + 1_000),
                    "background viewing statistics returned an incorrect watch-time total")

        print("PASS playback progress: 10,000 history rows, 100 heartbeats in \(String(format: "%.3f", elapsed))s; background stats count \(stats.sessionCount)")
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw PlaybackProgressPerformanceFailure(message: message) }
    }
}

private struct PlaybackProgressPerformanceFailure: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}
