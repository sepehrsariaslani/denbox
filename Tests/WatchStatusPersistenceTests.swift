import Foundation

@main
struct WatchStatusPersistenceTests {
    @MainActor
    static func main() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DenboxWatchStatus-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let database = MediaDatabase(databaseURL: root.appendingPathComponent("library.sqlite"))
        let episode = progress(
            mediaID: "series:watch-status",
            episodeID: "api-episode-old",
            kind: "Series",
            episodeTitle: "Pilot",
            episodeLabel: "S01E01",
            position: 420,
            duration: 1_800
        )

        database.setWatched(episode, watched: true)
        let refreshedEpisode = database.watchProgress(
            mediaID: episode.mediaID,
            episodeID: "api-episode-regenerated",
            episodeLabel: episode.episodeLabel,
            episodeTitle: episode.episodeTitle
        )
        try require(refreshedEpisode?.isWatched == true,
                    "a manually watched episode was not found after its API ID changed")
        try require(refreshedEpisode?.positionSeconds == 1_800,
                    "marking the episode watched did not move progress to the end")
        try require(database.viewingStats().completedEpisodes == 1,
                    "manually watched episodes were not included in completion statistics")

        guard let markedEpisode = database.watchProgress(mediaID: episode.mediaID, episodeID: episode.episodeID) else {
            throw WatchStatusFailure(message: "the manually watched episode was not persisted")
        }
        database.setWatched(markedEpisode, watched: false)
        let resetEpisode = database.watchProgress(mediaID: episode.mediaID, episodeID: episode.episodeID)
        try require(resetEpisode?.isWatched == false && resetEpisode?.positionSeconds == 0,
                    "unmarking a watched episode did not reset resume progress to the beginning")
        try require(resetEpisode?.watchedSeconds == episode.watchedSeconds,
                    "unmarking an episode discarded its actual recorded viewing time")
        try require(database.viewingStats().completedEpisodes == 0,
                    "unmarking an episode left the completion count unchanged")

        let movie = progress(
            mediaID: "movie:watch-status",
            episodeID: nil,
            kind: "Movie",
            episodeTitle: nil,
            episodeLabel: nil,
            position: 300,
            duration: 5_400
        )
        database.setWatched(movie, watched: true)
        try require(database.viewingStats().completedMovies == 1,
                    "manually watched movies were not included in completion statistics")

        print("PASS watch status: mark/unmark, regenerated episode IDs, resume reset, and completion stats")
    }

    private static func progress(
        mediaID: String,
        episodeID: String?,
        kind: String,
        episodeTitle: String?,
        episodeLabel: String?,
        position: Double,
        duration: Double
    ) -> WatchProgress {
        WatchProgress(
            mediaID: mediaID,
            episodeID: episodeID,
            mediaTitle: mediaID,
            kind: kind,
            episodeTitle: episodeTitle,
            episodeLabel: episodeLabel,
            year: "2026",
            artworkURL: nil,
            imdbID: "tt1234567",
            genres: ["Drama"],
            positionSeconds: position,
            durationSeconds: duration,
            watchedSeconds: position,
            isWatched: false,
            updatedAt: Date()
        )
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw WatchStatusFailure(message: message) }
    }
}

private struct WatchStatusFailure: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}
