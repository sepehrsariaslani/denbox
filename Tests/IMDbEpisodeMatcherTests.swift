import Foundation

@main
struct IMDbEpisodeMatcherTests {
    static func main() throws {
        try exactTitleAndDuplicateNumbering()
        try fuzzyTitleAndNumberedFallback()
        try ambiguousFuzzyMatchIsRejected()
        try imdbTitleNormalization()
        try largeEpisodeListDoesNotRegress()
        print("PASS IMDb episode matcher: exact, fuzzy, fallback, ambiguity, and large lists")
    }

    private static func exactTitleAndDuplicateNumbering() throws {
        let imdb = [
            episode("tt1000001", "Pilot", season: 1, number: 1, votes: 100),
            episode("tt1000002", "Pilot", season: 2, number: 1, votes: 200)
        ]
        let result = IMDbEpisodeMatcher.remap(
            [season(2, [mediaEpisode("Pilot", label: "S02E01")])],
            using: imdb
        )
        try require(result.first?.episodes.first?.episodeLabel == "S02E01", "duplicate exact titles ignored the season hint")
        try require(result.first?.episodes.first?.imdbVotes == 200, "duplicate exact titles selected the wrong IMDb row")
    }

    private static func fuzzyTitleAndNumberedFallback() throws {
        let fuzzy = episode("tt2000001", "The Lost Expedition Returns", season: 3, number: 4, votes: 345)
        let generic = episode("tt2000002", "A Different Adventure", season: 4, number: 9, votes: 456)
        let result = IMDbEpisodeMatcher.remap(
            [season(1, [
                mediaEpisode("The Lost Expediton Returns", label: "S01E01"),
                mediaEpisode("Episode", label: "S04E09")
            ])],
            using: [fuzzy, generic]
        )
        let mapped = result.flatMap(\.episodes)
        try require(mapped.first?.episodeLabel == "S03E04", "a near-exact title was not matched")
        try require(mapped.first?.imdbVotes == 345, "fuzzy title mapping lost its IMDb rating metadata")
        try require(mapped.dropFirst().first?.episodeLabel == "S04E09", "numbered fallback changed the episode number")
        try require(mapped.dropFirst().first?.imdbVotes == 456, "numbered fallback did not attach IMDb metadata")
    }

    private static func ambiguousFuzzyMatchIsRejected() throws {
        let candidates = [
            episode("tt3000001", "The Miraculous Journey Through Outer Spaxe", season: 1, number: 1, votes: 11),
            episode("tt3000002", "The Miraculous Journey Through Outer Spade", season: 2, number: 1, votes: 22)
        ]
        let result = IMDbEpisodeMatcher.remap(
            [season(8, [mediaEpisode("The Miraculous Journey Through Outer Spaze", label: "S08E99")])],
            using: candidates
        )
        try require(result.first?.episodes.first?.episodeLabel == "S08E99", "ambiguous fuzzy title was assigned to an IMDb episode")
        try require(result.first?.episodes.first?.imdbVotes == nil, "ambiguous fuzzy title received an arbitrary rating")
    }

    private static func imdbTitleNormalization() throws {
        try require(IMDbTitleNormalizer.normalize("The Matrix: Reloaded (2003)") == "thematrixreloaded2003",
                    "ASCII normalization changed the title key")
        try require(IMDbTitleNormalizer.normalize("Léon: The Professional") == "leontheprofessional",
                    "Unicode normalization did not fold accents")
        try require(IMDbTitleNormalizer.normalize("  São-Paulo 2049  ") == "saopaulo2049",
                    "Unicode normalization did not keep letters and digits")

        let started = Date()
        for _ in 0..<100_000 {
            _ = IMDbTitleNormalizer.normalize("The Matrix: Reloaded (2003)")
        }
        let elapsed = Date().timeIntervalSince(started)
        print(String(format: "IMDb title normalization benchmark: %.3fs for 100,000 ASCII titles", elapsed))
    }

    private static func largeEpisodeListDoesNotRegress() throws {
        let imdb = (0..<10_000).map { index in
            episode("tt\(4_000_000 + index)", "Episode title \(index)", season: index / 100 + 1,
                    number: index % 100 + 1, votes: index)
        }
        let api = (0..<300).map { index in
            mediaEpisode("Episode title \(index)", label: String(format: "S%02dE%02d", index / 100 + 1, index % 100 + 1))
        }
        let started = Date()
        let result = IMDbEpisodeMatcher.remap([season(1, api)], using: imdb)
        let elapsed = Date().timeIntervalSince(started)
        try require(result.reduce(0) { $0 + $1.episodes.count } == api.count, "large episode list lost entries")
        try require(result.flatMap(\.episodes).allSatisfy { $0.imdbVotes != nil }, "large episode list failed exact title matching")
        print(String(format: "IMDb episode match benchmark: %.3fs for 300 catalog / 10,000 IMDb episodes", elapsed))
    }

    private static func episode(_ id: String, _ title: String, season: Int, number: Int, votes: Int) -> IMDbEpisodeMetadata {
        IMDbEpisodeMetadata(tconst: id, title: title, season: season, episode: number, rating: 8.0, votes: votes)
    }

    private static func season(_ number: Int, _ episodes: [MediaEpisode]) -> MediaSeason {
        MediaSeason(id: "s\(number)", title: "Season \(number)", episodes: episodes)
    }

    private static func mediaEpisode(_ title: String, label: String, aliases: [String] = []) -> MediaEpisode {
        MediaEpisode(id: label, title: title, episodeLabel: label, synopsis: "", duration: nil,
                     artworkURL: nil, sources: [], downloadSources: [], imdbRating: nil, imdbVotes: nil,
                     matchingTitles: aliases)
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw MatcherTestFailure(message: message) }
    }
}

private struct MatcherTestFailure: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}
