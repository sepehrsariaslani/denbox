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
        let catalog = (0..<444).map { index in
            MediaItem(
                id: "startup-\(index)", apiID: "startup-\(index)", title: "Saved Title \(index)",
                subtitle: "2026 · Movie", synopsis: "Fixture catalog item \(index)", year: "2026",
                kind: index.isMultiple(of: 2) ? "Movie" : "Series", symbol: "film", palette: index % 8,
                isRemote: true
            )
        }
        seed.saveRemoteItems(catalog)

        let started = Date()
        let model = LibraryModel(loadRemoteCatalog: false, databaseURL: databaseURL)
        let startupSeconds = Date().timeIntervalSince(started)
        try require(startupSeconds < 1, "loading a small saved catalog took more than one second")
        try require(model.items.count == catalog.count, "the saved catalog was not available immediately at startup")
        try require(model.recommendations.isEmpty, "startup eagerly built recommendations before the page was opened")

        try await Task.sleep(nanoseconds: 150_000_000)
        try require(model.items.count == catalog.count, "background metadata loading changed the visible catalog")
        try require(model.recommendations.isEmpty, "background startup work started the full discovery query")
        print(String(format: "PASS startup responsiveness: %.3fs to show %d saved titles; discovery remains lazy", startupSeconds, catalog.count))
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw StartupFailure(message: message) }
    }
}

private struct StartupFailure: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}
