import Foundation

@main
struct PlaybackRoutingTests {
    @MainActor
    static func main() throws {
        let playback = MPVPlaybackController()
        guard playback.errorMessage == nil else {
            throw TestFailure(message: "the embedded libmpv engine did not initialize: \(playback.errorMessage!)")
        }
        try require(playback.audioDevices.contains(where: { $0.id == "auto" }), "the system-default audio device was not listed")
        try require(playback.setAudioDevice("auto"), "libmpv rejected the system-default audio device")
        try require(playback.selectedAudioDeviceID == "auto", "the selected audio output was not updated")

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
        try require(playback.audioEQBands.count == 10, "the IINA-style ten-band equalizer was not created")
        playback.setAudioEQBand(9, gain: 3)
        try require(playback.audioEQBands[9] == 3, "the highest equalizer band was not updated")
        playback.setAudioEQBand(9, gain: 0)

        playback.setSubtitlePosition(91)
        playback.setSubtitleBorderSize(4)
        playback.setSubtitleFontSize(48)
        try require(playback.subtitlePosition == 91, "subtitle position was not updated")
        try require(playback.subtitleBorderSize == 4, "subtitle outline size was not updated")
        try require(playback.subtitleFontSize == 48, "subtitle font size was not updated")
        playback.toggleSecondarySubtitleVisibility()
        try require(!playback.secondarySubtitleVisibility, "secondary subtitle visibility did not toggle")
        playback.toggleSecondarySubtitleVisibility()

        let previousMuteState = playback.isMuted
        playback.toggleMute()
        try require(playback.isMuted != previousMuteState, "mute state did not toggle")
        playback.toggleMute()

        var screenshotRequested: Bool?
        playback.onScreenshotRequested = { screenshotRequested = $0 }
        let screenshotHandled = playback.handleKeyboardShortcut(
            keyCode: 1,
            characters: "s",
            modifiers: [.command, .shift]
        )
        try require(screenshotHandled && screenshotRequested == true, "Command-Shift-S did not request a video-only screenshot")
        playback.onScreenshotRequested = nil

        var fullscreenRequested = false
        playback.onToggleFullscreen = { fullscreenRequested = true }
        let fullscreenHandled = playback.handleKeyboardShortcut(
            keyCode: 3,
            characters: "f",
            modifiers: [.command, .control]
        )
        try require(fullscreenHandled && fullscreenRequested, "Control-Command-F did not request full screen")
        playback.onToggleFullscreen = nil

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
