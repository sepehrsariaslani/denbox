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

        let assrtSearch = Data(#"{"status":0,"sub":{"subs":[{"native_name":"نمونه فیلم / Sample Movie","videoname":"sample.movie.2025","subtype":"Subrip(srt)","upload_time":"2026-10-16 12:00:00","vote_score":12,"release_site":"Sample Team","id":602333,"lang":{"desc":"فارسی"}}]}}"#.utf8)
        let assrtResults = try AssrtSubtitleClient.decodeSearchResponse(assrtSearch)
        try require(assrtResults.count == 1 && assrtResults[0].id == 602333, "ASSRT search result did not decode")
        try require(assrtResults[0].language?.description == "فارسی", "ASSRT language label did not decode")
        try require(AssrtSubtitleClient.normalizeQuery("The.Matrix_1999") == "The Matrix 1999", "ASSRT search query did not preserve readable title words")

        let assrtDetail = Data(#"{"status":0,"sub":{"subs":[{"filelist":[{"url":"http://file0.assrt.net/onthefly/602333/sample.srt?api=1","f":"sample.srt","s":"52KB"},{"url":"http://file0.assrt.net/download/602333/sample.rar","f":"sample.rar","s":"60KB"}] }]}}"#.utf8)
        let subtitleFile = try AssrtSubtitleClient.decodeDetailResponse(assrtDetail)
        try require(subtitleFile.fileName == "sample.srt", "ASSRT did not select the direct SRT file from the archive listing")
        try require(try AssrtSubtitleClient.validatedSubtitleURL(subtitleFile.url).scheme == "http", "ASSRT's documented HTTP subtitle link was rejected")
        do {
            _ = try AssrtSubtitleClient.validatedSubtitleURL("https://untrusted.example/subtitle.srt")
            throw TestFailure(message: "an untrusted ASSRT download host was accepted")
        } catch AssrtSubtitleError.unsafeDownloadLink {
            // The provider may use HTTP for its short-lived media URL, but only on its documented domains.
        }
        do {
            _ = try AssrtSubtitleClient.decodeSearchResponse(Data(#"{"status":20001}"#.utf8))
            throw TestFailure(message: "an invalid ASSRT token status was ignored")
        } catch AssrtSubtitleError.invalidToken {
            // Expected API status mapping.
        }

        print("PASS subtitles: OpenSubtitles hash/decoding and ASSRT parsing, temporary-link validation, and API errors")
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
