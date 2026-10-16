import Foundation
import AppKit

@main
struct PlaybackRoutingTests {
    @MainActor
    static func main() throws {
        let configurationDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DenboxPlaybackRoutingTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: configurationDirectory.appendingPathComponent("scripts", isDirectory: true),
            withIntermediateDirectories: true
        )
        try Data("audio-delay=0.23\nvolume=23\n".utf8).write(to: configurationDirectory.appendingPathComponent("mpv.conf"))
        try Data("Ctrl+Alt+p set pause yes\n".utf8).write(to: configurationDirectory.appendingPathComponent("input.conf"))
        try Data("mp.set_property_number('volume', 31)\n".utf8)
            .write(to: configurationDirectory.appendingPathComponent("scripts/routing-test.lua"))

        let inputPreferenceKey = DenboxMPVConfiguration.useInputConfigurationKey
        let previousInputPreference = UserDefaults.standard.object(forKey: inputPreferenceKey)
        UserDefaults.standard.set(false, forKey: inputPreferenceKey)
        defer {
            if let previousInputPreference {
                UserDefaults.standard.set(previousInputPreference, forKey: inputPreferenceKey)
            } else {
                UserDefaults.standard.removeObject(forKey: inputPreferenceKey)
            }
            try? FileManager.default.removeItem(at: configurationDirectory)
        }

        let playback = MPVPlaybackController(configurationDirectoryURL: configurationDirectory)
        guard playback.errorMessage == nil else {
            throw TestFailure(message: "the embedded libmpv engine did not initialize: \(playback.errorMessage!)")
        }
        try require(Double(playback.testingProperty("audio-delay") ?? "") == 0.23, "mpv.conf was not read from Denbox's configuration folder")
        let scriptDeadline = Date(timeIntervalSinceNow: 2)
        while Date() < scriptDeadline, Double(playback.testingProperty("volume") ?? "") != 31 {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        }
        try require(Double(playback.testingProperty("volume") ?? "") == 31, "a user Lua script was not loaded at player startup")
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

        let customInputKeyName = MPVInputKeyMapper.keyName(
            keyCode: 35,
            charactersIgnoringModifiers: "p",
            characters: "p",
            modifiers: [.control, .option]
        )
        try require(customInputKeyName == "Ctrl+Alt+p", "the input.conf key name did not preserve its modifiers")
        let arrowInputKeyName = MPVInputKeyMapper.keyName(
            keyCode: 123,
            charactersIgnoringModifiers: "",
            characters: nil,
            modifiers: [.option]
        )
        try require(arrowInputKeyName == "Alt+LEFT", "special keys were not mapped to mpv key names")
        UserDefaults.standard.set(true, forKey: inputPreferenceKey)
        let customKeyHandled = playback.handleKeyboardShortcut(
            keyCode: 35,
            characters: "p",
            modifiers: [.control, .option],
            charactersWithModifiers: "p"
        )
        try require(customKeyHandled, "the custom mpv input binding was not forwarded")
        let keypressDeadline = Date(timeIntervalSinceNow: 1)
        while Date() < keypressDeadline, playback.testingProperty("pause") != "yes" {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        }
        try require(playback.testingProperty("pause") == "yes", "input.conf keypress did not run its configured mpv command")
        UserDefaults.standard.set(false, forKey: inputPreferenceKey)

        let playerWindow = NSWindow(
            contentRect: NSRect(x: 80, y: 90, width: 1280, height: 800),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        playerWindow.isReleasedWhenClosed = false
        playback.setPlayerWindow(playerWindow)
        let originalFrame = playerWindow.frame
        let originalLevel = playerWindow.level
        let originalCollectionBehavior = playerWindow.collectionBehavior
        let originalTitle = playerWindow.title
        try require(playback.enterMiniPlayer(title: "Mini player test"), "the floating mini player did not start")
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        try require(playback.isInMiniPlayerMode, "mini player state was not published")
        try require(playerWindow.level == .floating, "the mini player did not stay above other windows")
        try require(playerWindow.title == "Mini player test", "the mini player title was not updated")
        try require(playerWindow.frame.width < originalFrame.width, "the player window did not shrink into mini mode")
        playback.exitMiniPlayer()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        try require(!playback.isInMiniPlayerMode, "mini player mode did not exit")
        try require(playerWindow.level == originalLevel, "the original window level was not restored")
        try require(playerWindow.collectionBehavior == originalCollectionBehavior, "the original window space behavior was not restored")
        try require(playerWindow.title == originalTitle, "the original player title was not restored")
        try require(playerWindow.frame == originalFrame, "the original player window size and position were not restored")
        playerWindow.close()
        playback.setPlayerWindow(nil)

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
