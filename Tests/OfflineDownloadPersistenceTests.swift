import Foundation

@main
struct OfflineDownloadPersistenceTests {
    @MainActor
    static func main() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DenboxOfflineTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let databaseURL = root.appendingPathComponent("library.sqlite")
        let mediaURL = root.appendingPathComponent("episode.mp4")
        try Data("local episode bytes".utf8).write(to: mediaURL)

        let firstDatabase = MediaDatabase(databaseURL: databaseURL)
        firstDatabase.saveDownloadedMedia(DownloadedMedia(
            id: "download-1",
            title: "Series · Episode 1",
            fileURL: mediaURL,
            byteCount: 19,
            segmentCount: 3,
            createdAt: Date(),
            catalogMediaID: "series-1",
            episodeID: "episode-1"
        ))

        let reopenedManager = DownloadManager(database: MediaDatabase(databaseURL: databaseURL))
        guard let offlineURL = reopenedManager.completedDownload(
            mediaItemID: "series-1",
            episodeID: "episode-1",
            title: "Series · Episode 1"
        ) else {
            throw TestFailure(message: "a completed episode was not available offline after reopening the database")
        }
        try require(offlineURL.standardizedFileURL == mediaURL.standardizedFileURL,
                    "the offline episode points to a different file")

        try FileManager.default.removeItem(at: mediaURL)
        try require(reopenedManager.completedDownload(
            mediaItemID: "series-1",
            episodeID: "episode-1",
            title: "Series · Episode 1"
        ) == nil, "a missing download was still advertised as available offline")

        print("PASS offline episode: linked download survives database reopen and missing files are ignored")
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw TestFailure(message: message) }
    }
}

private struct TestFailure: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}
