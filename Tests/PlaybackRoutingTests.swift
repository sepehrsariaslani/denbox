import Foundation
import AppKit
import MediaPlayer

@main
struct PlaybackRoutingTests {
    @MainActor
    static func main() throws {
        try require(
            PlayerControlsAutoHidePolicy.shouldHide(isScrubbing: false, hasOpenAdjustments: false),
            "idle controls should hide even while playback is paused or buffering"
        )
        try require(
            !PlayerControlsAutoHidePolicy.shouldHide(isScrubbing: true, hasOpenAdjustments: false),
            "active seeking should keep controls visible"
        )
        try require(
            !PlayerControlsAutoHidePolicy.shouldHide(isScrubbing: false, hasOpenAdjustments: true),
            "open player adjustments should keep controls visible"
        )
        try require(
            PlayerControlsAutoHidePolicy.idleDelayNanoseconds == 1_500_000_000,
            "the controls should fade promptly after pointer activity stops"
        )
        let pointerPosition = CGPoint(x: 20, y: 30)
        try require(
            PlayerControlsAutoHidePolicy.pointerMoved(from: nil, to: pointerPosition),
            "the first pointer sample should reveal the controls"
        )
        try require(
            !PlayerControlsAutoHidePolicy.pointerMoved(from: pointerPosition, to: pointerPosition),
            "a stationary pointer should not keep resetting the hide timer"
        )
        try require(
            PlayerControlsAutoHidePolicy.pointerMoved(
                from: pointerPosition,
                to: CGPoint(x: pointerPosition.x + 0.5, y: pointerPosition.y)
            ),
            "small pointer movement should reveal the controls without leaving the player"
        )

        let primarySource = MediaStreamSource(
            id: "primary", title: "Primary", url: URL(string: "https://media.example.test/primary.mkv")!, headers: [:]
        )
        let alternateSource = MediaStreamSource(
            id: "alternate", title: "Alternate", url: URL(string: "https://media.example.test/alternate.mkv")!, headers: [:]
        )
        let duplicateAlternate = MediaStreamSource(
            id: "duplicate", title: "Duplicate", url: alternateSource.url, headers: [:]
        )
        try require(
            PlaybackSourceFallbackPolicy.nextSource(
                from: [primarySource, alternateSource, duplicateAlternate],
                excluding: [primarySource.url.absoluteString]
            )?.id == alternateSource.id,
            "a failed primary source should advance to the next distinct source"
        )
        try require(
            PlaybackSourceFallbackPolicy.nextSource(
                from: [primarySource, alternateSource, duplicateAlternate],
                excluding: [primarySource.url.absoluteString, alternateSource.url.absoluteString]
            ) == nil,
            "the player should not retry an already failed source URL"
        )

        let playlistDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DenboxPlaylistTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: playlistDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: playlistDirectory) }
        let playlistEntries = [
            MPVPlaybackPlaylistEntry(
                index: 0, title: "First", filename: "/Movies/First Film.mkv", isCurrent: true
            ),
            MPVPlaybackPlaylistEntry(
                index: 1, title: "Second", filename: "https://media.example.test/second.m3u8", isCurrent: false
            )
        ]
        let exportedPlaylist = playlistDirectory.appendingPathComponent("saved.m3u8")
        try MPVPlaylistDocument.save(playlistEntries, to: exportedPlaylist)
        let exportedPlaylistData = try Data(contentsOf: exportedPlaylist)
        try require(
            exportedPlaylistData == Data("/Movies/First Film.mkv\nhttps://media.example.test/second.m3u8\n".utf8),
            "saved playlists should match IINA's UTF-8, newline-separated filename format"
        )

        let m3uURL = playlistDirectory.appendingPathComponent("relative.m3u8")
        try Data("\u{feff}#EXTM3U\n#EXTINF:12,Sample\nClips/First Film.mkv\nhttps://media.example.test/second.m3u8\n".utf8)
            .write(to: m3uURL)
        let parsedM3U = try MPVPlaylistDocument.read(from: m3uURL)
        try require(parsedM3U.count == 2, "M3U comments and metadata should not become playlist entries")
        try require(
            parsedM3U[0].path == playlistDirectory.appendingPathComponent("Clips/First Film.mkv").standardizedFileURL.path,
            "relative M3U paths should resolve beside the playlist file"
        )
        try require(
            parsedM3U[1].absoluteString == "https://media.example.test/second.m3u8",
            "M3U stream URLs should remain playable playlist entries"
        )

        let plsURL = playlistDirectory.appendingPathComponent("ordered.pls")
        try Data("[playlist]\nFile2=Clips/Second.mkv\nTitle2=Second\nFile1=Clips/First.mkv\nNumberOfEntries=2\n".utf8)
            .write(to: plsURL)
        let parsedPLS = try MPVPlaylistDocument.read(from: plsURL)
        try require(parsedPLS.count == 2, "PLS FileN entries should be imported")
        try require(
            parsedPLS[0].lastPathComponent == "First.mkv" && parsedPLS[1].lastPathComponent == "Second.mkv",
            "PLS FileN entries should be restored in numeric order"
        )

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
        let audioLanguagePreferenceKey = DenboxMPVConfiguration.preferredAudioLanguagesKey
        let previousAudioLanguagePreference = UserDefaults.standard.object(forKey: audioLanguagePreferenceKey)
        let subtitleLanguagePreferenceKey = DenboxMPVConfiguration.preferredSubtitleLanguagesKey
        let previousSubtitleLanguagePreference = UserDefaults.standard.object(forKey: subtitleLanguagePreferenceKey)
        let filterPresetsKey = MPVFilterPresetStore.userDefaultsKey
        let previousFilterPresets = UserDefaults.standard.data(forKey: filterPresetsKey)
        UserDefaults.standard.set(false, forKey: inputPreferenceKey)
        defer {
            if let previousInputPreference {
                UserDefaults.standard.set(previousInputPreference, forKey: inputPreferenceKey)
            } else {
                UserDefaults.standard.removeObject(forKey: inputPreferenceKey)
            }
            if let previousAudioLanguagePreference {
                UserDefaults.standard.set(previousAudioLanguagePreference, forKey: audioLanguagePreferenceKey)
            } else {
                UserDefaults.standard.removeObject(forKey: audioLanguagePreferenceKey)
            }
            if let previousSubtitleLanguagePreference {
                UserDefaults.standard.set(previousSubtitleLanguagePreference, forKey: subtitleLanguagePreferenceKey)
            } else {
                UserDefaults.standard.removeObject(forKey: subtitleLanguagePreferenceKey)
            }
            if let previousFilterPresets {
                UserDefaults.standard.set(previousFilterPresets, forKey: filterPresetsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: filterPresetsKey)
            }
            try? FileManager.default.removeItem(at: configurationDirectory)
        }

        let playback = MPVPlaybackController(configurationDirectoryURL: configurationDirectory)
        guard playback.errorMessage == nil else {
            throw TestFailure(message: "the embedded libmpv engine did not initialize: \(playback.errorMessage!)")
        }
        let nowPlayingCenter = MPNowPlayingInfoCenter.default()
        let remoteCommandCenter = MPRemoteCommandCenter.shared()
        playback.updateNowPlayingTitle("Denbox remote-control test")
        playback.play(URL(fileURLWithPath: "/tmp/denbox-remote-control-test.mkv"), headers: [:])
        let nowPlayingInfo = nowPlayingCenter.nowPlayingInfo ?? [:]
        try require(
            nowPlayingInfo[MPMediaItemPropertyTitle] as? String == "Denbox remote-control test",
            "the active player title was not published to macOS Now Playing"
        )
        try require(
            ((nowPlayingInfo[MPNowPlayingInfoPropertyMediaType] as? NSNumber)?.intValue ?? -1)
                == MPNowPlayingInfoMediaType.video.rawValue,
            "the player was not identified as video in macOS Now Playing"
        )
        try require(nowPlayingCenter.playbackState == .paused, "the initial remote playback state was not published")
        try require(remoteCommandCenter.playCommand.isEnabled && remoteCommandCenter.pauseCommand.isEnabled,
                    "macOS play and pause commands were not enabled for the current title")
        try require(remoteCommandCenter.skipForwardCommand.preferredIntervals.map(\.doubleValue) == [15],
                    "the system skip-forward command did not use IINA's 15-second interval")
        try require(remoteCommandCenter.skipBackwardCommand.preferredIntervals.map(\.doubleValue) == [15],
                    "the system skip-back command did not use IINA's 15-second interval")
        try require(remoteCommandCenter.changePlaybackRateCommand.supportedPlaybackRates.map(\.doubleValue) == [0.5, 1, 1.5, 2],
                    "the system playback-rate choices did not match IINA's supported rates")
        playback.setRemoteRepeatType(.one)
        try require(playback.testingProperty("loop-file") == "inf", "remote repeat-one did not loop the current file")
        try require(playback.testingProperty("loop-playlist") == "no", "remote repeat-one left playlist repeat enabled")
        playback.setRemoteRepeatType(.all)
        try require(playback.testingProperty("loop-file") == "no", "remote repeat-all left file repeat enabled")
        try require(playback.testingProperty("loop-playlist") == "inf", "remote repeat-all did not loop the playlist")
        playback.setRemoteRepeatType(.off)
        try require(playback.testingProperty("loop-file") == "no" && playback.testingProperty("loop-playlist") == "no",
                    "remote repeat-off did not clear both repeat properties")
        playback.stop()
        try require(nowPlayingCenter.nowPlayingInfo == nil, "stopping the player left stale Now Playing metadata")
        try require(nowPlayingCenter.playbackState == .stopped, "stopping the player did not update the system playback state")
        try require(!remoteCommandCenter.playCommand.isEnabled && !remoteCommandCenter.pauseCommand.isEnabled,
                    "system playback commands stayed enabled after stopping the player")
        UserDefaults.standard.set("fa, per, fa, en", forKey: audioLanguagePreferenceKey)
        UserDefaults.standard.set("fas, en, eng", forKey: subtitleLanguagePreferenceKey)
        let languageUpdateDeadline = Date(timeIntervalSinceNow: 2)
        while Date() < languageUpdateDeadline,
              playback.testingProperty("alang") != "fa,per,en" || playback.testingProperty("slang") != "fas,en,eng" {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        }
        try require(
            playback.testingProperty("alang") == "fa,per,en",
            "changing the preferred audio languages did not update the open libmpv session"
        )
        try require(
            playback.testingProperty("slang") == "fas,en,eng",
            "changing the preferred subtitle languages did not update the open libmpv session"
        )
        try require(Double(playback.testingProperty("audio-delay") ?? "") == 0.23, "mpv.conf was not read from Denbox's configuration folder")
        let scriptDeadline = Date(timeIntervalSinceNow: 2)
        while Date() < scriptDeadline, Double(playback.testingProperty("volume") ?? "") != 31 {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        }
        try require(Double(playback.testingProperty("volume") ?? "") == 31, "a user Lua script was not loaded at player startup")
        try require(playback.audioDevices.contains(where: { $0.id == "auto" }), "the system-default audio device was not listed")
        try require(playback.setAudioDevice("auto"), "libmpv rejected the system-default audio device")
        try require(playback.selectedAudioDeviceID == "auto", "the selected audio output was not updated")
        playback.setPlaylistLoop(true)
        try require(playback.isPlaylistLoopEnabled, "playlist repeat did not update the player state")
        try require(playback.testingProperty("loop-playlist") == "inf", "playlist repeat was not applied to libmpv")
        playback.setPlaylistLoop(false)
        try require(!playback.isPlaylistLoopEnabled, "playlist repeat stayed enabled after it was turned off")
        try require(playback.testingProperty("loop-playlist") == "no", "playlist repeat was not removed from libmpv")

        let firstPlaylistMedia = playlistDirectory.appendingPathComponent("first-silent.wav")
        let secondPlaylistMedia = playlistDirectory.appendingPathComponent("second-silent.wav")
        try makeSilentWAV(seconds: 30).write(to: firstPlaylistMedia)
        try makeSilentWAV(seconds: 30).write(to: secondPlaylistMedia)
        playback.appendURLsToPlaylist([firstPlaylistMedia, secondPlaylistMedia])
        let playlistDeadline = Date(timeIntervalSinceNow: 2)
        while Date() < playlistDeadline && playback.playlist.count < 2 {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        }
        try require(playback.playlist.count == 2, "local media files were not added to the mpv playlist")
        let nextPlaylistEntry = playback.removeCurrentPlaylistEntryAndAdvance()
        try require(
            nextPlaylistEntry?.filename == secondPlaylistMedia.path,
            "removing the current playlist item did not advance to the next item"
        )
        try require(playback.playlist.count == 1, "removing the current item did not update the playlist")
        playback.stop()

        playback.setAudioDelay(0.25)
        try require(playback.audioDelaySeconds == 0.25, "audio delay was not reflected by the controller")
        try require(playback.setVerticalFlip(true), "the named vertical-flip filter was rejected by libmpv")
        try require(playback.isVerticallyFlipped, "vertical flip did not update its visible state")
        try require(playback.setVerticalFlip(false), "the vertical-flip filter could not be removed")
        try require(!playback.isVerticallyFlipped, "vertical flip stayed enabled after removal")
        try require(playback.setHorizontalMirror(true), "the named horizontal-mirror filter was rejected by libmpv")
        try require(playback.isHorizontallyMirrored, "horizontal mirror did not update its visible state")
        try require(playback.setHorizontalMirror(false), "the horizontal-mirror filter could not be removed")
        try require(!playback.isHorizontallyMirrored, "horizontal mirror stayed enabled after removal")
        try require(playback.setSubtitleEncoding("cp1256"), "the Arabic subtitle codepage was rejected by libmpv")
        try require(
            playback.testingProperty("sub-codepage")?.caseInsensitiveCompare("cp1256") == .orderedSame,
            "the chosen subtitle codepage was not applied to libmpv"
        )
        try require(!playback.setSubtitleEncoding("not-a-real-codepage"), "an unknown subtitle codepage was accepted")
        try require(playback.setSubtitleEncoding("auto"), "automatic subtitle codepage detection could not be restored")
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

        let testFilterName = "Playback routing test filter"
        try require(
            playback.saveFilterPreset(name: testFilterName, kind: .video, expression: "lavfi=[hue=s=0]"),
            "a custom filter preset was not saved"
        )
        let restoredPresets = MPVFilterPresetStore.loadSaved()
        guard let savedTestPreset = restoredPresets.first(where: { $0.name == testFilterName }) else {
            throw TestFailure(message: "the custom filter preset did not persist in local preferences")
        }
        playback.deleteFilterPreset(savedTestPreset)
        try require(
            !MPVFilterPresetStore.loadSaved().contains(where: { $0.name == testFilterName }),
            "a saved filter preset was not deleted"
        )
        try require(
            !playback.saveFilterPreset(name: testFilterName, kind: .video, expression: "vf add\nquit"),
            "a multi-line filter command was incorrectly accepted"
        )

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

        for (keyCode, key) in [(9, "v"), (0, "a"), (1, "s")] {
            try require(
                playback.handleKeyboardShortcut(
                    keyCode: UInt16(keyCode),
                    characters: key,
                    modifiers: [.command, .control]
                ),
                "Control-Command-\(key.uppercased()) did not route to its IINA track action"
            )
        }
        var pictureInPictureRequested = false
        playback.onTogglePictureInPicture = { pictureInPictureRequested = true }
        let pictureInPictureHandled = playback.handleKeyboardShortcut(
            keyCode: 35,
            characters: "p",
            modifiers: [.command, .control]
        )
        try require(pictureInPictureHandled && pictureInPictureRequested, "Control-Command-P did not request Picture in Picture")
        playback.onTogglePictureInPicture = nil

        var onlineSubtitleSearchRequested = false
        playback.onFindOnlineSubtitles = { onlineSubtitleSearchRequested = true }
        let onlineSubtitlesHandled = playback.handleKeyboardShortcut(
            keyCode: 2,
            characters: "d",
            modifiers: [.command]
        )
        try require(onlineSubtitlesHandled && onlineSubtitleSearchRequested, "Command-D did not open online subtitle search")
        playback.onFindOnlineSubtitles = nil
        var requestedWindowScale: Double?
        playback.onSetWindowScale = { requestedWindowScale = $0 }
        for (keyCode, key, scale) in [(29, "0", 0.5), (18, "1", 1.0), (19, "2", 2.0)] {
            let handled = playback.handleKeyboardShortcut(
                keyCode: UInt16(keyCode),
                characters: key,
                modifiers: [.command]
            )
            try require(handled && requestedWindowScale == scale, "Command-\(key) did not request IINA's window scale")
        }
        playback.onSetWindowScale = nil
        try require(
            playback.handleKeyboardShortcut(keyCode: 47, characters: ".", modifiers: [.command, .shift]),
            "Shift-Command-> did not reach chapter navigation"
        )
        try require(
            playback.handleKeyboardShortcut(keyCode: 47, characters: ".", modifiers: [.command]),
            "Command-. did not stop playback"
        )

        let slowerSpeedHandled = playback.handleKeyboardShortcut(
            keyCode: 33,
            characters: "[",
            modifiers: [.command, .option]
        )
        try require(slowerSpeedHandled && abs(playback.speed - 0.9091) < 0.001, "Option-Command-[ did not reduce speed by ten percent")
        _ = playback.handleKeyboardShortcut(keyCode: 42, characters: "\\", modifiers: [.command])
        let fasterSpeedHandled = playback.handleKeyboardShortcut(
            keyCode: 30,
            characters: "]",
            modifiers: [.command, .option]
        )
        try require(fasterSpeedHandled && abs(playback.speed - 1.1) < 0.001, "Option-Command-] did not increase speed by ten percent")

        playback.setAudioDelay(0)
        let audioDelayHandled = playback.handleKeyboardShortcut(keyCode: 25, characters: "9", modifiers: [.shift])
        try require(audioDelayHandled && abs(playback.audioDelaySeconds - 0.5) < 0.001, "Shift-( did not delay audio by half a second")
        _ = playback.handleKeyboardShortcut(keyCode: 25, characters: "9", modifiers: [.shift, .option])
        try require(abs(playback.audioDelaySeconds - 0.6) < 0.001, "Option-Shift-( did not finely delay audio")
        _ = playback.handleKeyboardShortcut(keyCode: 27, characters: "-", modifiers: [.shift])
        try require(playback.audioDelaySeconds == 0, "Shift-_ did not reset audio timing")

        let originalMusicMode = playback.isMusicMode
        let musicModeHandled = playback.handleKeyboardShortcut(
            keyCode: 46,
            characters: "m",
            modifiers: [.command, .option]
        )
        try require(musicModeHandled && playback.isMusicMode != originalMusicMode, "Option-Command-M did not toggle music mode")
        playback.toggleMusicMode()

        try require(playback.handleKeyboardShortcut(keyCode: 124, characters: "", modifiers: [.option]), "Alt-Right did not reach frame stepping")
        try require(playback.handleKeyboardShortcut(keyCode: 116, characters: "", modifiers: [.shift]), "Shift-PageUp did not reach the long seek action")

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
        let originalContentSize = playerWindow.contentView?.bounds.size ?? playerWindow.contentRect(forFrameRect: playerWindow.frame).size
        playback.setWindowScale(0.5)
        let halfScaleContentSize = playerWindow.contentView?.bounds.size ?? playerWindow.contentRect(forFrameRect: playerWindow.frame).size
        try require(halfScaleContentSize.width < originalContentSize.width, "half window scale did not shrink the player")
        playback.setWindowScale(1)
        let restoredContentSize = playerWindow.contentView?.bounds.size ?? playerWindow.contentRect(forFrameRect: playerWindow.frame).size
        try require(abs(restoredContentSize.width - originalContentSize.width) < 1, "window scale 1 did not restore the reference size")
        var fitToScreenScale: Double?
        playback.onSetWindowScale = { fitToScreenScale = $0 }
        let fitToScreenHandled = playback.handleKeyboardShortcut(keyCode: 20, characters: "3", modifiers: [.command])
        try require(fitToScreenHandled, "Command-3 did not reach fit-to-screen")
        if NSScreen.main != nil {
            try require((0.5...2).contains(fitToScreenScale ?? 0), "fit-to-screen did not request a valid window scale")
        }
        playback.onSetWindowScale = nil
        let alwaysOnTopHandled = playback.handleKeyboardShortcut(
            keyCode: 17,
            characters: "t",
            modifiers: [.command, .control]
        )
        try require(alwaysOnTopHandled && playerWindow.level == .floating, "Control-Command-T did not put the player above other windows")
        _ = playback.handleKeyboardShortcut(keyCode: 17, characters: "t", modifiers: [.command, .control])
        try require(playerWindow.level == originalLevel, "Control-Command-T did not restore the normal window level")
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

    private static func makeSilentWAV(seconds: UInt32) -> Data {
        let sampleRate: UInt32 = 8_000
        let sampleCount = sampleRate * seconds
        var data = Data("RIFF".utf8)
        appendLittleEndian(36 + sampleCount, to: &data)
        data.append(contentsOf: "WAVEfmt ".utf8)
        appendLittleEndian(UInt32(16), to: &data)
        appendLittleEndian(UInt16(1), to: &data)
        appendLittleEndian(UInt16(1), to: &data)
        appendLittleEndian(sampleRate, to: &data)
        appendLittleEndian(sampleRate, to: &data)
        appendLittleEndian(UInt16(1), to: &data)
        appendLittleEndian(UInt16(8), to: &data)
        data.append(contentsOf: "data".utf8)
        appendLittleEndian(sampleCount, to: &data)
        data.append(Data(repeating: 128, count: Int(sampleCount)))
        return data
    }

    private static func appendLittleEndian(_ value: UInt32, to data: inout Data) {
        var encoded = value.littleEndian
        withUnsafeBytes(of: &encoded) { data.append(contentsOf: $0) }
    }

    private static func appendLittleEndian(_ value: UInt16, to data: inout Data) {
        var encoded = value.littleEndian
        withUnsafeBytes(of: &encoded) { data.append(contentsOf: $0) }
    }
}

private struct TestFailure: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}
