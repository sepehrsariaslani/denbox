import Foundation

@main
struct DownloadLookupPerformanceTests {
    @MainActor
    static func main() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DenboxDownloadLookup-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let database = MediaDatabase(databaseURL: root.appendingPathComponent("library.sqlite"))
        let mediaID = "series:download-lookup-fixture"
        let downloadsDirectory = root.appendingPathComponent("downloads", isDirectory: true)
        try FileManager.default.createDirectory(at: downloadsDirectory, withIntermediateDirectories: true)

        let downloadCount = 300
        var expectedURLs: [URL] = []
        for index in 0..<downloadCount {
            let fileURL = downloadsDirectory.appendingPathComponent("episode-\(index).mp4")
            try Data().write(to: fileURL)
            expectedURLs.append(fileURL)
            database.saveDownloadedMedia(DownloadedMedia(
                id: "download-\(index)",
                title: "Long Series · Episode \(index)",
                fileURL: fileURL,
                byteCount: 0,
                segmentCount: 1,
                createdAt: Date(timeIntervalSince1970: Double(index)),
                catalogMediaID: mediaID,
                episodeID: "old-episode-\(index)"
            ))
        }

        let manager = DownloadManager(database: database)
        let started = Date()
        for request in 0..<3_000 {
            let index = request % downloadCount
            let found = manager.completedDownload(
                mediaItemID: mediaID,
                episodeID: "old-episode-\(index)",
                title: "Long Series · Episode \(index)"
            )
            try require(found == expectedURLs[index], "indexed lookup returned the wrong offline episode")
        }
        let lookupSeconds = Date().timeIntervalSince(started)
        try require(lookupSeconds < 0.5,
                    String(format: "3,000 indexed offline lookups took %.3fs", lookupSeconds))

        let regeneratedID = manager.completedDownload(
            mediaItemID: mediaID,
            episodeID: "new-episode-42",
            title: "Long Series · Episode 42"
        )
        try require(regeneratedID == expectedURLs[42], "title fallback did not match the regenerated episode ID")
        try FileManager.default.removeItem(at: expectedURLs[0])
        let missingFile = manager.completedDownload(
            mediaItemID: mediaID,
            episodeID: "old-episode-0",
            title: "Long Series · Episode 0"
        )
        try require(missingFile == nil, "an offline lookup returned a file that no longer exists")

        print(String(format: "PASS download lookup performance: 3,000 indexed lookups over %d entries in %.3fs",
                     downloadCount, lookupSeconds))
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw DownloadLookupFailure(message: message) }
    }
}

private struct DownloadLookupFailure: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}
