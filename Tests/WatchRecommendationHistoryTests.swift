import Foundation

@main
struct WatchRecommendationHistoryTests {
    @MainActor
    static func main() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DenboxRecommendationHistory-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let database = MediaDatabase(databaseURL: root.appendingPathComponent("library.sqlite"))
        var progress = (1...2_000).map { index in
            makeProgress(
                mediaID: "movie:recent-\(index)",
                imdbID: String(format: "tt%07d", index + 10),
                updatedAt: Date(timeIntervalSince1970: Double(index)),
                isWatched: false,
                position: 50
            )
        }
        let oldWatchedID = "tt0000001"
        let nearCompleteID = "tt0003001"
        let incompleteID = "tt0003002"
        progress.append(makeProgress(
            mediaID: "movie:old-watched", imdbID: oldWatchedID,
            updatedAt: Date(timeIntervalSince1970: 0), isWatched: true, position: 100
        ))
        progress.append(makeProgress(
            mediaID: "movie:near-complete", imdbID: nearCompleteID,
            updatedAt: Date(timeIntervalSince1970: 2_001), isWatched: false, position: 90
        ))
        progress.append(makeProgress(
            mediaID: "movie:incomplete", imdbID: incompleteID,
            updatedAt: Date(timeIntervalSince1970: 2_002), isWatched: false, position: 50
        ))

        let export = ViewingDataExport(
            schemaVersion: 2,
            exportedAt: Date(),
            progress: progress,
            history: [],
            personalRatings: []
        )
        try require(database.mergeViewingData(export), "could not seed the local watch-progress fixture")

        let cappedHistory = database.loadWatchProgress(limit: 2_000, includeWatched: true)
        try require(!cappedHistory.contains(where: { $0.imdbID == oldWatchedID }),
                    "the fixture did not place an old watched title beyond the former 2,000-row cap")

        let excluded = database.loadWatchedIMDbIDs()
        try require(excluded.contains(oldWatchedID), "an old watched title fell outside the recommendation exclusion set")
        try require(excluded.contains(nearCompleteID), "a title at 90% progress was not excluded")
        try require(!excluded.contains(incompleteID), "an unfinished title was incorrectly excluded")

        let candidates = [oldWatchedID, nearCompleteID, incompleteID].map { id in
            IMDbTitleMetadata(tconst: id, title: id, year: 2020, genres: ["Drama"],
                              rating: 8.0, votes: 10_000, kind: "Movie")
        }
        let recommendations = PersonalizedRecommendationRanker.rank(
            candidates,
            history: [],
            preferredGenres: [],
            excluding: excluded,
            limit: 10
        )
        try require(recommendations.map(\.tconst) == [incompleteID],
                    "For You did not exclude all watched titles while keeping unfinished titles eligible")

        print("PASS recommendation history: no 2,000-row cap, 90% progress excluded, unfinished titles retained")
    }

    private static func makeProgress(
        mediaID: String,
        imdbID: String,
        updatedAt: Date,
        isWatched: Bool,
        position: Double
    ) -> WatchProgress {
        WatchProgress(
            mediaID: mediaID,
            episodeID: nil,
            mediaTitle: mediaID,
            kind: "Movie",
            episodeTitle: nil,
            episodeLabel: nil,
            year: "2020",
            artworkURL: nil,
            imdbID: imdbID,
            genres: ["Drama"],
            positionSeconds: position,
            durationSeconds: 100,
            watchedSeconds: position,
            isWatched: isWatched,
            updatedAt: updatedAt
        )
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw RecommendationHistoryFailure(message: message) }
    }
}

private struct RecommendationHistoryFailure: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}
