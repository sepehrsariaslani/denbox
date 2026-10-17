import Foundation

@main
struct PersonalRatingPersistenceTests {
    @MainActor
    static func main() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DenboxPersonalRatings-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let database = MediaDatabase(databaseURL: root.appendingPathComponent("library.sqlite"))
        let movie = MediaItem(
            id: "movie:rating-test", apiID: "rating-test", title: "Rating Test", subtitle: "",
            synopsis: "", year: "2026", kind: "Movie", symbol: "film", palette: 0,
            artworkURL: URL(string: "https://example.com/poster.jpg"), isRemote: true,
            matchingTitles: ["Rating Test Original"], imdbID: "tt1234567", genres: ["Drama"]
        )

        try require(database.loadPersonalRatings().isEmpty, "the fresh library unexpectedly contains personal ratings")
        try require(database.setPersonalRating(4, for: movie), "could not save a personal rating")
        var restored = database.loadPersonalRatings()[movie.id]
        try require(restored?.rating == 4, "the personal rating did not survive a SQLite reload")
        try require(restored?.item.title == movie.title && restored?.item.imdbID == movie.imdbID,
                    "the saved title snapshot lost its catalog metadata")

        try require(database.setPersonalRating(2, for: movie), "could not update a personal rating")
        restored = database.loadPersonalRatings()[movie.id]
        try require(restored?.rating == 2, "updating a personal rating created a duplicate or kept the old value")
        try require(!database.setPersonalRating(0, for: movie), "an out-of-range personal rating was accepted")
        try require(database.setPersonalRating(nil, for: movie), "could not clear a personal rating")
        try require(database.loadPersonalRatings().isEmpty, "clearing a rating left it in My Ratings")

        print("PASS personal ratings: create, update, persist, validate range, and clear")
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw PersonalRatingFailure(message: message) }
    }
}

private struct PersonalRatingFailure: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}
