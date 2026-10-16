import Foundation

@main
struct PlaybackRoutingTests {
    static func main() throws {
        try require(PlaybackRouting.usesIINA(for: URL(string: "https://media.example/episode.mkv")!),
                    "MKV streams should use IINA's playback engine")
        try require(PlaybackRouting.usesIINA(for: URL(fileURLWithPath: "/tmp/episode.webm")),
                    "WebM files should use IINA's playback engine")
        try require(!PlaybackRouting.usesIINA(for: URL(string: "https://media.example/movie.mp4")!),
                    "MP4 streams should remain in the embedded player")
        try require(!PlaybackRouting.usesIINA(for: URL(string: "https://media.example/live.m3u8")!),
                    "HLS streams should remain in the embedded player")
        print("PASS playback routing: AVFoundation-compatible media stays embedded; unsupported containers open in IINA")
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw TestFailure(message: message) }
    }
}

private struct TestFailure: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}
