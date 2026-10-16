import Foundation

@main
struct DenboxSourceParserTests {
    @MainActor
    static func main() throws {
        let movie = MediaItem(
            id: "movie:test", apiID: "test", title: "Parser Movie", subtitle: "Movie",
            synopsis: "", year: "2026", kind: "Movie", symbol: "film", palette: 0, isRemote: true
        )
        let moviePayload: [String: Any] = [
            "id": "test",
            "title": "Parser Movie",
            "downloadas": "1",
            "sources": [
                ["quality": "1080p", "type": "http", "url": "http://media.example/movie-1080.mp4"],
                ["quality": "720p", "type": "http", "url": "http://media.example/movie-720.mkv"]
            ],
            "download_url": "http://media.example/movie-download.mp4"
        ]
        let movieDetails = LibraryModel.parseDetails(moviePayload, for: movie)
        try require(movieDetails.sources.count == 2, "movie playback sources were not parsed")
        try require(movieDetails.downloadSources.count == 3, "movie download URLs were not collected")
        try require(!movieDetails.downloadSources.contains(where: { $0.url.lastPathComponent == "1" }),
                    "the downloadas flag was incorrectly treated as a media URL")

        let series = MediaItem(
            id: "series:test", apiID: "test", title: "Parser Series", subtitle: "Series",
            synopsis: "", year: "2026", kind: "Series", symbol: "tv", palette: 0, isRemote: true
        )
        let seriesPayload: [[String: Any]] = [[
            "id": "test",
            "title": "Parser Series",
            "episodes": [[
                "id": "ep1",
                "title": "Episode 1",
                "duration": "42 min",
                "downloadas": "1",
                "sources": [["quality": "1080p", "url": "http://media.example/episode.mkv"]],
                "download_url": "http://media.example/episode-extra.mp4"
            ], [
                "id": "ep2",
                "title": "Episode 2",
                "download_url": "http://media.example/episode-2.mp4"
            ]]
        ]]
        let seriesDetails = LibraryModel.parseDetails(seriesPayload, for: series)
        try require(seriesDetails.seasons.count == 1, "series seasons were not parsed")
        try require(seriesDetails.seasons[0].episodes.count == 2, "series episodes were not parsed")
        let episode = seriesDetails.seasons[0].episodes[0]
        try require(episode.sources.count == 1, "episode playback link was not parsed")
        try require(episode.downloadSources.count == 2, "episode download links were not parsed")
        try require(!episode.downloadSources.contains(where: { $0.url.lastPathComponent == "1" }),
                    "the episode downloadas flag was incorrectly treated as a media URL")
        try require(seriesDetails.seasons[0].episodes[1].sources.isEmpty
                    && seriesDetails.seasons[0].episodes[1].downloadSources.count == 1,
                    "an episode with only a download link was omitted from the season")

        print("PASS source parser: movie + series episode URLs and downloadas flag")
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw TestFailure(message: message) }
    }
}

private struct TestFailure: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}
