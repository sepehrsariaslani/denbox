import Foundation

@main
struct StartupResponsivenessTests {
    @MainActor
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DenboxStartup-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let databaseURL = root.appendingPathComponent("library.sqlite")
        let seed = MediaDatabase(databaseURL: databaseURL)
        let savedItems = (0..<2_000).map { index in
            MediaItem(
                id: "startup-\(index)",
                apiID: "startup-\(index)",
                title: "Startup Fixture \(index)",
                subtitle: "2026 · Movie",
                synopsis: "A saved catalog fixture.",
                year: "2026",
                kind: index.isMultiple(of: 2) ? "Movie" : "Series",
                symbol: index.isMultiple(of: 2) ? "film" : "tv",
                palette: index % 8,
                isRemote: true
            )
        }
        seed.saveRemoteItems(savedItems)

        let started = Date()
        let model = LibraryModel(
            loadRemoteCatalog: false,
            databaseURL: databaseURL,
            startBackgroundCatalogEnrichment: false
        )
        let startupSeconds = Date().timeIntervalSince(started)
        try require(startupSeconds < 0.5,
                    String(format: "loading 2,000 saved titles took %.3fs", startupSeconds))
        try require(model.items.count == savedItems.count,
                    "the full saved catalog was not available immediately at startup")
        try require(model.recommendations.isEmpty, "startup eagerly built recommendations before the page was opened")

        try await Task.sleep(nanoseconds: 150_000_000)
        try require(model.items.count == savedItems.count, "background metadata loading changed the visible catalog")
        try require(model.recommendations.isEmpty, "background startup work started the full discovery query")
        print(String(format: "PASS startup responsiveness: %.3fs to show 2,000 saved titles; discovery remains lazy", startupSeconds))
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw StartupFailure(message: message) }
    }
}

private struct StartupFailure: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}
