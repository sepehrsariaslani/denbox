import Foundation

@main
struct PlaybackRoutingTests {
    @MainActor
    static func main() throws {
        let playback = MPVPlaybackController()
        guard playback.errorMessage == nil else {
            throw TestFailure(message: "the embedded libmpv engine did not initialize: \(playback.errorMessage!)")
        }

        playback.setAudioDelay(0.25)
        try require(playback.audioDelaySeconds == 0.25, "audio delay was not reflected by the controller")
        playback.setDeinterlacing(true)
        try require(playback.isDeinterlacing, "deinterlacing did not enable")
        playback.setHardwareDecoding(false)
        try require(!playback.hardwareDecodingEnabled, "software decoding did not disable hardware decoding")
        playback.setVideoAdjustment("brightness", value: 18)
        try require(playback.videoBrightness == 18, "video brightness was not updated")
        playback.setAudioEQBand(0, gain: 4)
        try require(playback.audioEQBands[0] == 4, "audio equalizer band was not updated")
        playback.setAudioEQBand(0, gain: 0)

        playback.markABLoop()
        try require(playback.abLoopState == 1, "the A point was not stored")
        playback.markABLoop()
        try require(playback.abLoopState == 2, "the B point was not stored")
        playback.clearABLoop()
        try require(playback.abLoopState == 0, "A-B loop points were not cleared")

        playback.shutdown()
        print("PASS playback routing: embedded libmpv controls initialize and update without starting IINA")
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw TestFailure(message: message) }
    }
}

private struct TestFailure: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}
