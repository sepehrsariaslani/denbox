import Foundation

@main
private struct OpenSubtitlesTests {
    static func main() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("denbox-opensubtitles-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let videoURL = tempDirectory.appendingPathComponent("sample.mkv")
        try Data(repeating: 0, count: 128 * 1_024).write(to: videoURL)
        try require(
            try OpenSubtitlesClient.movieHash(for: videoURL) == "0000000000020000",
            "the OpenSubtitles movie hash did not include the file size and edge bytes"
        )

        let shortURL = tempDirectory.appendingPathComponent("short.mkv")
        try Data(repeating: 0, count: 32 * 1_024).write(to: shortURL)
        try require(try OpenSubtitlesClient.movieHash(for: shortURL) == nil, "short files should use name-only subtitle search")
        try require(
            OpenSubtitlesClient.normalizeQuery("The.Matrix_1999.1080p") == "the matrix 1999 1080p",
            "release names were not normalized for API search"
        )

        let sample = Data(#"{"data":[{"id":"1234","attributes":{"language":"fa","release":"Sample release","download_count":23,"moviehash_match":true,"files":[{"file_id":5678,"file_name":"sample.srt"}]}}]}"#.utf8)
        let response = try JSONDecoder().decode(SearchEnvelope.self, from: sample)
        try require(response.data.count == 1, "subtitle results did not decode")
        try require(response.data[0].attributes.files.first?.fileID == 5678, "download file ID did not decode")
        try require(response.data[0].attributes.movieHashMatch == true, "exact file matches were not preserved")

        print("PASS OpenSubtitles: file hash, query normalization, and result decoding")
    }

    private static func require(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        guard try condition() else { throw TestFailure(message: message) }
    }
}

private struct SearchEnvelope: Decodable {
    let data: [OnlineSubtitleResult]
}

private struct TestFailure: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}
