import Foundation

@main
struct PublicTitleMetadataTests {
    static func main() throws {
        try require(PublicMetadataProvider.filimo.accepts(URL(string: "https://www.filimo.com/m/178360")!),
                    "the supplied Filimo title URL was rejected")
        try require(!PublicMetadataProvider.filimo.accepts(URL(string: "http://www.filimo.com/m/178360")!),
                    "an insecure Filimo URL was accepted")
        try require(!PublicMetadataProvider.filimo.accepts(URL(string: "https://filimo.com/player/178360")!),
                    "a playback route was accepted as a public title page")
        try require(PublicMetadataProvider.hexDL.accepts(URL(string: "https://hexdl.com/example-movie/")!),
                    "a public HexDL title page was rejected")
        try require(!PublicMetadataProvider.hexDL.accepts(URL(string: "https://hexdl.com/movie.mkv")!),
                    "a media file URL was accepted as a HexDL metadata page")

        let source = PublicTitleMetadata(
            provider: .filimo,
            pageURL: URL(string: "https://www.filimo.com/m/178360")!,
            title: "عنوان فارسی",
            synopsis: "خلاصهٔ فارسی",
            posterURL: URL(string: "https://cdn.example/poster.jpg"),
            visiblePageText: "متن عمومی",
            visibleHeadings: ["فصل اول"],
            episodeSnippets: ["قسمت اول · ۴۲ دقیقه"],
            imageURLs: [URL(string: "https://cdn.example/poster.jpg")!],
            importedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let encoded = try JSONEncoder().encode(source)
        let restored = try JSONDecoder().decode(PublicTitleMetadata.self, from: encoded)
        try require(restored.title == source.title && restored.visiblePageText == source.visiblePageText,
                    "the imported public metadata did not survive local serialization")
        print("PASS public metadata: Filimo/HexDL URL allowlists and local metadata encoding")
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw PublicMetadataTestFailure(message: message) }
    }
}

private struct PublicMetadataTestFailure: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}
