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

        let metadata = Dictionary(uniqueKeysWithValues: items.enumerated().map { index, item in
            (item.id, IMDbTitleMetadata(
                tconst: String(format: "tt%07d", index + 1), title: item.title, year: 2026,
                genres: ["Drama"], rating: 7.5, votes: 10_000, kind: item.kind
            ))
        })
        let metadataStarted = Date()
        database?.saveIMDbMetadata(metadata)
        let metadataWriteSeconds = Date().timeIntervalSince(metadataStarted)
        let enriched = database?.loadCatalog() ?? []
        try require(enriched.count == items.count && enriched.allSatisfy { $0.imdbID != nil && $0.genres == ["Drama"] },
                    "batched IMDb catalog metadata did not persist every match")

        let cachedReference = ReferenceTitleMetadata.empty()
        let cachedPublicTitle = PublicTitleMetadata(
            provider: .filimo,
            pageURL: URL(string: "https://www.filimo.com/m/fixture")!,
            title: "Cached catalog fixture",
            synopsis: "خلاصهٔ فارسی آزمایشی",
            posterURL: nil,
            visiblePageText: "",
            visibleHeadings: [],
            episodeSnippets: [],
            imageURLs: [],
            importedAt: Date()
        )
        for item in items {
            database?.saveReferenceMetadata(cachedReference, mediaID: item.id)
            _ = database?.savePublicTitleMetadata(cachedPublicTitle, for: item.id)
            database?.recordPublicTitleMetadataAttempt(mediaID: item.id, provider: .filimo)
        }
        let cacheReadStarted = Date()
        let metadataCache = database?.loadCatalogMetadataPayloads(for: Set(items.map(\.id))) ?? CatalogMetadataPayloads()
        let metadataCacheReadSeconds = Date().timeIntervalSince(cacheReadStarted)
        try require(metadataCache.references.count == items.count,
                    "batched cache loading skipped reference metadata")
        try require(metadataCache.publicTitles.count == items.count,
                    "batched cache loading skipped public title metadata")
        try require(metadataCache.publicAttempts.count == items.count,
                    "batched cache loading skipped public metadata cooldowns")
        try require(metadataCacheReadSeconds < 0.25,
                    String(format: "loading 1,000 metadata cache rows took %.3fs", metadataCacheReadSeconds))
        database = nil

        let reopened = MediaDatabase(databaseURL: databaseURL)
        try require(reopened.loadCatalog().count == items.count,
                    "the transaction was not durable after reopening the catalog")
        try require(writeSeconds < 1.0,
                    String(format: "writing 1,000 catalog titles took %.3fs", writeSeconds))
        try require(metadataWriteSeconds < 0.5,
                    String(format: "writing 1,000 IMDb metadata rows took %.3fs", metadataWriteSeconds))
        print(String(format: "PASS catalog persistence: 1,000 titles in %.3fs; 1,000 IMDb rows in %.3fs; 1,000 cache sets in %.3fs",
                      writeSeconds, metadataWriteSeconds, metadataCacheReadSeconds))
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw CatalogPersistenceFailure(message: message) }
    }
}

private struct CatalogPersistenceFailure: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}
