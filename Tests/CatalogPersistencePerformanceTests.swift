import Foundation

@main
struct CatalogPersistencePerformanceTests {
    @MainActor
    static func main() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DenboxCatalogPersistence-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let databaseURL = root.appendingPathComponent("library.sqlite")
        let items = (0..<1_000).map { index in
            MediaItem(
                id: "catalog-\(index)", apiID: "catalog-\(index)", title: "Catalog Title \(index)",
                subtitle: "2026 · Movie", synopsis: "Catalog fixture synopsis \(index)", year: "2026",
                kind: index.isMultiple(of: 2) ? "Movie" : "Series", symbol: "film", palette: index % 8,
                artworkURL: URL(string: "https://example.com/poster-\(index).jpg"), isRemote: true
            )
        }

        var database: MediaDatabase? = MediaDatabase(databaseURL: databaseURL)
        let started = Date()
        database?.saveRemoteItems(items)
        let writeSeconds = Date().timeIntervalSince(started)
        try require(database?.loadCatalog().count == items.count,
                    "the transaction did not persist every catalog title")
        database = nil

        let reopened = MediaDatabase(databaseURL: databaseURL)
        try require(reopened.loadCatalog().count == items.count,
                    "the transaction was not durable after reopening the catalog")
        try require(writeSeconds < 1.0,
                    String(format: "writing 1,000 catalog titles took %.3fs", writeSeconds))
        print(String(format: "PASS catalog persistence: 1,000 titles saved atomically in %.3fs and reloaded", writeSeconds))
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw CatalogPersistenceFailure(message: message) }
    }
}

private struct CatalogPersistenceFailure: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}
