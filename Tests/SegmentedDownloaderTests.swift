import CryptoKit
import Foundation

@main
struct SegmentedDownloaderTests {
    static func main() async throws {
        guard CommandLine.arguments.count == 2, let port = Int(CommandLine.arguments[1]) else {
            throw TestFailure(message: "usage: SegmentedDownloaderTests PORT")
        }
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("DenboxDownloaderTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let expected = Data((0..<12_000_000).map { UInt8(($0 * 31 + 7) % 256) })
        let expectedDigest = SHA256.hash(data: expected)
        let base = URL(string: "http://127.0.0.1:\(port)")!

        let segmentedURL = root.appendingPathComponent("segmented.mp4")
        let segmented = try await SegmentedDownloader.download(
            source: DownloadRequestSource(url: base.appendingPathComponent("range"), headers: [:]),
            to: segmentedURL
        )
        try require(segmented.segmentCount > 1, "range-enabled source was not downloaded in parallel segments")
        try require(segmented.byteCount == Int64(expected.count), "segmented byte count is incorrect")
        let segmentedData = try Data(contentsOf: segmentedURL)
        try require(SHA256.hash(data: segmentedData) == expectedDigest,
                    "concatenated ranges do not match the original media bytes")

        let ordinaryURL = root.appendingPathComponent("ordinary.mp4")
        let ordinary = try await SegmentedDownloader.download(
            source: DownloadRequestSource(url: base.appendingPathComponent("whole"), headers: [:]),
            to: ordinaryURL
        )
        try require(ordinary.segmentCount == 1, "a server without range support did not fall back to a single download")
        let ordinaryData = try Data(contentsOf: ordinaryURL)
        try require(SHA256.hash(data: ordinaryData) == expectedDigest,
                    "single-download fallback bytes do not match the original media")

        print("PASS segmented download: parallel ranges, checksum, and no-range fallback")
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw TestFailure(message: message) }
    }
}

private struct TestFailure: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}
