import Foundation

@main
struct PlaybackRoutingTests {
    @MainActor
    static func main() throws {
        let playback = MPVPlaybackController()
        guard playback.errorMessage == nil else {
            throw TestFailure(message: "the embedded libmpv engine did not initialize: \(playback.errorMessage!)")
        }
        playback.shutdown()
        print("PASS playback routing: Denbox initializes its embedded libmpv engine without starting IINA")
    }
}

private struct TestFailure: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}
