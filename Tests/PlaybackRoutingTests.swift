import Foundation
import AppKit
import AVFoundation
import MediaPlayer

@main
struct PlaybackRoutingTests {
    @MainActor
    static func main() throws {
        try require(
            MPVPlaybackTimeParser.seconds(from: "20:35") == 1_235,
            "IINA-style minute and second input was not parsed correctly"
        )
        try require(
            MPVPlaybackTimeParser.seconds(from: "1:02:03") == 3_723,
            "IINA-style hour, minute, and second input was not parsed correctly"
        )
        try require(
            MPVPlaybackTimeParser.seconds(from: "۱:۰۲") == 62,
            "Persian digits were not accepted by the time parser"
        )
        try require(
            MPVPlaybackTimeParser.seconds(from: "12") == nil
                && MPVPlaybackTimeParser.seconds(from: "1:a") == nil
                && MPVPlaybackTimeParser.seconds(from: "1::2") == nil
                && MPVPlaybackTimeParser.seconds(from: "1:2:3:4") == nil,
            "the time parser accepted an invalid format"
        )
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
            PlayerSeekPreviewPolicy.time(atX: 10, width: 210, duration: 100) == 0,
            "the seek-preview slider did not map its left edge to time zero"
        )
        try require(
            PlayerSeekPreviewPolicy.time(atX: 105, width: 210, duration: 100) == 50,
            "the seek-preview slider did not map its midpoint to half the duration"
        )
        try require(
            PlayerSeekPreviewPolicy.time(atX: 200, width: 210, duration: 100) == 100,
            "the seek-preview slider did not clamp its right edge to the duration"
        )
        try require(
            PlayerSeekPreviewPolicy.time(atX: 20, width: 20, duration: 100) == nil
                && PlayerSeekPreviewPolicy.time(atX: 20, width: 100, duration: 0) == nil,
            "the seek-preview slider accepted an invalid width or duration"
        )
        let inspectorTracks = [
            MPVPlaybackTrack(
                id: 1, kind: .video, displayName: "Main · en", isSelected: true,
                isSecondarySelected: false, title: "Main", language: "en", codec: "h264",
                codecDescription: "H.264 / AVC", decoderDescription: "H.264 VideoToolbox",
                formatName: "yuv420p10le", dimensions: "1920 × 1080", frameRate: 23.976,
                isDefault: true
            ),
            MPVPlaybackTrack(
                id: 2, kind: .audio, displayName: "English", isSelected: true,
                isSecondarySelected: false, language: "en", codec: "aac",
                codecDescription: "AAC", channels: "stereo", sampleRate: 48_000,
                bitrate: 192_000, isDefault: true
            ),
            MPVPlaybackTrack(
                id: 3, kind: .subtitle, displayName: "Persian", isSelected: false,
                isSecondarySelected: false, language: "fa", codec: "ass", isExternal: true
            )
        ]
        let inspectorInfo = MPVPlaybackTechnicalInfo.make(
            properties: [
                "file-format": "matroska,webm", "file-size": "2048000", "chapters": "3",
                "editions": "2", "current-edition": "1",
                "video-params/w": "1920", "video-params/h": "1080",
                "video-params/pixelformat": "yuv420p10le", "video-params/colormatrix": "bt.709",
                "video-params/primaries": "bt.709", "estimated-vf-fps": "23.976",
                "video-bitrate": "4500000", "current-vo": "libmpv", "hwdec-current": "videotoolbox",
                "audio-params/format": "s16", "audio-params/hr-channels": "Stereo",
                "audio-params/samplerate": "48000", "audio-bitrate": "192000",
                "current-ao": "coreaudio", "audio-device": "auto", "avsync": "0.004",
                "total-avsync-change": "-0.008", "frame-drop-count": "2",
                "decoder-frame-drop-count": "1", "mistimed-frame-count": "0", "idle-active": "no"
            ],
            tracks: inspectorTracks,
            title: "Example Film",
            sourceURL: URL(string: "https://media.example:443/master.m3u8?token=private-value#secret")!,
            currentTime: 76.5,
            duration: 600,
            isLoading: false,
            isPlaying: true,
            speed: 1,
            volume: 80,
            isMuted: false,
            isBuffering: false,
            bufferPercent: 100
        )
        func inspectorValue(_ rows: [MPVPlaybackInfoRow], _ label: String) -> String? {
            rows.first(where: { $0.label == label })?.value
        }
        try require(inspectorValue(inspectorInfo.general, "Source") == "https://media.example",
                    "the media inspector exposed a private stream URL or lost its source host")
        try require(inspectorValue(inspectorInfo.general, "Editions") == "2"
                    && inspectorValue(inspectorInfo.general, "Current edition") == "1",
                    "the inspector did not show the active edition and available-edition count")
        try require(!inspectorInfo.general.map(\.value).joined().contains("private-value"),
                    "the media inspector retained private query credentials")
        try require(inspectorValue(inspectorInfo.video, "Resolution") == "1920 × 1080",
                    "the inspector did not report the decoded video dimensions")
        try require(inspectorValue(inspectorInfo.video, "Codec") == "H.264 / AVC",
                    "the inspector did not show the selected video codec")
        try require(inspectorValue(inspectorInfo.video, "Video bitrate") == "4.5 Mbit/s",
                    "the inspector did not format stream bitrate in bits per second")
        try require(inspectorValue(inspectorInfo.audio, "Channels") == "Stereo",
                    "the inspector did not show the decoded audio channel layout")
        try require(inspectorValue(inspectorInfo.playback, "Frames dropped") == "2"
                    && inspectorValue(inspectorInfo.playback, "Decoder frames dropped") == "1",
                    "the inspector did not expose the renderer and decoder drop counts")
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

        try require(
            MPVPlaylistPlayNextPolicy.move(selectedIndex: 4, currentIndex: 2, count: 5)
                == MPVPlaylistMove(source: 4, destination: 3),
            "a later playlist item should move immediately after the current item"
        )
        try require(
            MPVPlaylistPlayNextPolicy.move(selectedIndex: 1, currentIndex: 2, count: 5)
                == MPVPlaylistMove(source: 1, destination: 3),
            "an earlier playlist item should move immediately after the current item"
        )
        try require(
            MPVPlaylistPlayNextPolicy.move(selectedIndex: 0, currentIndex: 4, count: 5)
                == MPVPlaylistMove(source: 4, destination: 0),
            "when the current item is last, moving it before the selected item should make that item play next"
        )
        try require(
            MPVPlaylistPlayNextPolicy.move(selectedIndex: 3, currentIndex: 2, count: 5) == nil,
            "the item already queued next should not be moved"
        )
        try require(
            MPVPlaylistPlayNextPolicy.move(selectedIndex: 2, currentIndex: 2, count: 5) == nil,
            "the current item should not be queued as next"
        )
        try require(
            MPVPlaylistPlayNextPolicy.move(selectedIndex: 5, currentIndex: 2, count: 5) == nil
                && MPVPlaylistPlayNextPolicy.move(selectedIndex: 1, currentIndex: 5, count: 5) == nil
                && MPVPlaylistPlayNextPolicy.move(selectedIndex: 0, currentIndex: 0, count: 1) == nil,
            "invalid indices and a single-item playlist should not produce a move"
        )

        let chapterMusicMetadata = MPVMusicMetadataPolicy.resolve(
            chapterCount: 8,
            chapterTitle: "  Track Seven  ",
            mediaTitle: "Full album",
            album: "Night Drive",
            chapterPerformer: "Guest Singer",
            artist: "Album Artist"
        )
        try require(chapterMusicMetadata.title == "Track Seven", "the current chapter title did not take priority for music metadata")
        try require(chapterMusicMetadata.album == "Night Drive", "the audio album metadata was not retained")
        try require(chapterMusicMetadata.artist == "Guest Singer", "the current chapter performer did not take priority over the album artist")
        try require(chapterMusicMetadata.albumAndArtist == "Night Drive — Guest Singer", "the music byline did not combine album and artist")

        let fallbackMusicMetadata = MPVMusicMetadataPolicy.resolve(
            chapterCount: 8,
            chapterTitle: "  ",
            mediaTitle: "Full album",
            album: "",
            chapterPerformer: nil,
            artist: "Album Artist"
        )
        try require(fallbackMusicMetadata.title == "Full album", "missing chapter names did not fall back to the media title")
        try require(fallbackMusicMetadata.album == nil && fallbackMusicMetadata.artist == "Album Artist",
                    "empty album metadata was retained or the artist fallback was lost")

        let mediaTitleMusicMetadata = MPVMusicMetadataPolicy.resolve(
            chapterCount: 0,
            chapterTitle: "Ignored chapter",
            mediaTitle: "Single Track",
            album: nil,
            chapterPerformer: nil,
            artist: nil
        )
        try require(mediaTitleMusicMetadata.title == "Single Track", "files without chapters did not use the media title")

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
        let separatelySelectedFile = playlistDirectory.appendingPathComponent("Selected first.mp4")
        let expandedOpenSelection = try MPVPlaylistDocument.urls(from: [separatelySelectedFile, m3uURL])
        try require(
            expandedOpenSelection == [separatelySelectedFile.standardizedFileURL] + parsedM3U,
            "opening multiple files and a playlist should preserve selection and playlist order"
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
        try require(
            MPVPlaylistDocument.streamURL(from: "  http://media.example.test/live.m3u8  ")?.absoluteString
                == "http://media.example.test/live.m3u8",
            "a whitespace-padded HTTP stream URL was not accepted"
        )
        try require(
            MPVPlaylistDocument.streamURL(from: "https://media.example.test/movie.mkv")?.scheme == "https",
            "an HTTPS stream URL was not accepted"
        )
        try require(
            MPVDirectOpenURL.parse("  media.example.test/movie.m3u8  ")?.absoluteString
                == "https://media.example.test/movie.m3u8",
            "direct-open URL did not default a missing scheme to HTTPS or trim surrounding whitespace"
        )
        try require(
            MPVDirectOpenURL.parse("http://media.example.test:8080/live.m3u8")?.absoluteString
                == "http://media.example.test:8080/live.m3u8",
            "direct-open URL did not preserve explicit HTTP and a valid port"
        )
        try require(
            MPVDirectOpenURL.parse("localhost:8080/movie.mp4")?.host == "localhost"
                && MPVDirectOpenURL.parse("example.test:8443/movie.mp4")?.port == 8443,
            "direct-open URL did not treat a host and port as a URL without an explicit scheme"
        )
        let credentialOrigin = URL(string: "https://MEDIA.example.test/live.m3u8")!
        let credentialOriginWithDefaultPort = URL(string: "https://media.example.test:443/other.m3u8")!
        try require(
            MPVDirectOpenURL.keychainAccount(for: credentialOrigin)
                == MPVDirectOpenURL.keychainAccount(for: credentialOriginWithDefaultPort),
            "remembered URL credentials were not scoped to a normalized origin"
        )
        let enteredCredentials = MPVOpenURLCredentials(username: "viewer@example.test", password: "secret: value")
        let authenticatedURL = MPVDirectOpenURL.applying(enteredCredentials, to: credentialOrigin)!
        let authenticatedComponents = URLComponents(url: authenticatedURL, resolvingAgainstBaseURL: false)!
        try require(
            authenticatedComponents.user == enteredCredentials.username
                && authenticatedComponents.password == enteredCredentials.password
                && authenticatedComponents.percentEncodedUser?.contains("%40") == true
                && authenticatedComponents.percentEncodedPassword?.contains("%20") == true,
            "URL credentials were not attached with URLComponents percent-encoding"
        )
        let embeddedCredentialsURL = URL(string: "https://viewer:secret%3Avalue@media.example.test/live.m3u8")!
        try require(
            MPVDirectOpenURL.credentials(in: embeddedCredentialsURL)
                == MPVOpenURLCredentials(username: "viewer", password: "secret:value"),
            "credentials embedded in a URL were not parsed for the separate credential fields"
        )
        for invalidURL in ["", "not a URL", "ftp://media.example.test/movie.mkv", "file:///tmp/movie.mkv",
                           "javascript:alert(1)", "https:///missing-host", "https://media.example.test:70000/movie.mkv"] {
            try require(
                MPVDirectOpenURL.parse(invalidURL) == nil,
                "direct-open accepted an unsupported, malformed, or invalid-port URL"
            )
        }
        for invalidURL in ["", "not a URL", "file:///tmp/movie.mkv", "javascript:alert(1)", "https:///missing-host"] {
            try require(
                MPVPlaylistDocument.streamURL(from: invalidURL) == nil,
                "an unsupported or malformed stream URL was accepted"
            )
        }

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

        guard let effectiveInputConfiguration = DenboxMPVConfiguration.effectiveInputConfigurationURL(in: configurationDirectory),
              let effectiveInputText = try? String(contentsOf: effectiveInputConfiguration, encoding: .utf8) else {
            throw TestFailure(message: "the combined IINA, mpv, and user input configuration was not generated")
        }
        try require(effectiveInputText.contains("Ctrl+LEFT") && effectiveInputText.contains("Meta+s screenshot"),
                    "the embedded input.conf omitted the mpv or IINA default bindings")
        try require(effectiveInputText.contains("Ctrl+Alt+p set pause yes"),
                    "the embedded input.conf did not retain the user's custom bindings")
        try require(DenboxMPVConfiguration.isDefaultInputBinding("Ctrl+LEFT"),
                    "the default shortcut filter rejected IINA/mpv subtitle-cue navigation")

        let inputPreferenceKey = DenboxMPVConfiguration.useInputConfigurationKey
        let previousInputPreference = UserDefaults.standard.object(forKey: inputPreferenceKey)
        let audioLanguagePreferenceKey = DenboxMPVConfiguration.preferredAudioLanguagesKey
        let previousAudioLanguagePreference = UserDefaults.standard.object(forKey: audioLanguagePreferenceKey)
        let subtitleLanguagePreferenceKey = DenboxMPVConfiguration.preferredSubtitleLanguagesKey
        let previousSubtitleLanguagePreference = UserDefaults.standard.object(forKey: subtitleLanguagePreferenceKey)
        let audioPassthroughPreferenceKey = DenboxMPVConfiguration.audioPassthroughCodecsKey
        let previousAudioPassthroughPreference = UserDefaults.standard.object(forKey: audioPassthroughPreferenceKey)
        let filterPresetsKey = MPVFilterPresetStore.userDefaultsKey
        let previousFilterPresets = UserDefaults.standard.data(forKey: filterPresetsKey)
        UserDefaults.standard.set(false, forKey: inputPreferenceKey)
        UserDefaults.standard.set("", forKey: audioPassthroughPreferenceKey)
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
            if let previousAudioPassthroughPreference {
                UserDefaults.standard.set(previousAudioPassthroughPreference, forKey: audioPassthroughPreferenceKey)
            } else {
                UserDefaults.standard.removeObject(forKey: audioPassthroughPreferenceKey)
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
        try require(
            playback.testingProperty("audio-display") == "embedded-first",
            "embedded cover art should remain visible while playing audio"
        )
        try require(playback.testingProperty("input-media-keys") == "no", "libmpv media keys were not left to the macOS player controls")
        try require(playback.testingProperty("audio-spdif") == "", "audio passthrough should be disabled by default")
        try require(
            DenboxMPVConfiguration.audioPassthroughCodecs(from: "DTS, ac3,unknown,dts,dts-hd") == ["ac3", "dts", "dts-hd"],
            "audio passthrough settings did not validate, deduplicate, and order codec names"
        )
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
        playback.testingSetAudioMetadata(chapterMusicMetadata, hasAlbumArt: true)
        let audioNowPlayingInfo = nowPlayingCenter.nowPlayingInfo ?? [:]
        try require(
            audioNowPlayingInfo[MPMediaItemPropertyTitle] as? String == "Track Seven",
            "audio Now Playing did not publish the chapter track title"
        )
        try require(
            audioNowPlayingInfo[MPMediaItemPropertyAlbumTitle] as? String == "Night Drive"
                && audioNowPlayingInfo[MPMediaItemPropertyArtist] as? String == "Guest Singer",
            "audio Now Playing did not publish album and chapter performer metadata"
        )
        try require(
            ((audioNowPlayingInfo[MPNowPlayingInfoPropertyMediaType] as? NSNumber)?.intValue ?? -1)
                == MPNowPlayingInfoMediaType.audio.rawValue,
            "audio with an embedded album-art video track was misidentified as video in Now Playing"
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
        UserDefaults.standard.set("DTS, ac3, unsupported, dts-hd, dts", forKey: audioPassthroughPreferenceKey)
        let passthroughUpdateDeadline = Date(timeIntervalSinceNow: 2)
        while Date() < passthroughUpdateDeadline,
              playback.testingProperty("audio-spdif") != "ac3,dts,dts-hd" {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        }
        try require(
            playback.testingProperty("audio-spdif") == "ac3,dts,dts-hd",
            "changing audio passthrough settings did not update the open libmpv session"
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

        var screenshotRequests: [Bool?] = []
        playback.onScreenshotRequested = { screenshotRequests.append($0) }
        let screenshotWithSubtitlesHandled = playback.handleKeyboardShortcut(
            keyCode: 1,
            characters: "s",
            modifiers: [.command]
        )
        try require(
            screenshotWithSubtitlesHandled && screenshotRequests == [nil],
            "Command-S did not defer subtitle inclusion to Denbox's screenshot preference"
        )
        let screenshotVideoOnlyHandled = playback.handleKeyboardShortcut(
            keyCode: 1,
            characters: "s",
            modifiers: [.command, .shift]
        )
        try require(
            screenshotVideoOnlyHandled && screenshotRequests == [nil, false],
            "Command-Shift-S did not request a video-only screenshot"
        )
        let plainScreenshotHandled = playback.handleKeyboardShortcut(
            keyCode: 1,
            characters: "s",
            modifiers: []
        )
        try require(
            plainScreenshotHandled && screenshotRequests == [nil, false, true],
            "S did not use mpv's default screenshot-with-subtitles action"
        )
        let plainVideoOnlyHandled = playback.handleKeyboardShortcut(
            keyCode: 1,
            characters: "S",
            modifiers: [.shift]
        )
        try require(
            plainVideoOnlyHandled && screenshotRequests == [nil, false, true, false],
            "Shift-S did not request an image without subtitles"
        )
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
        var jumpToTimeRequested = false
        playback.onJumpToTime = { jumpToTimeRequested = true }
        UserDefaults.standard.set(true, forKey: inputPreferenceKey)
        let jumpToTimeHandled = playback.handleKeyboardShortcut(
            keyCode: 38,
            characters: "j",
            modifiers: [.command]
        )
        UserDefaults.standard.set(false, forKey: inputPreferenceKey)
        try require(
            jumpToTimeHandled && jumpToTimeRequested,
            "Command-J did not open the time prompt ahead of custom mpv input bindings"
        )
        playback.onJumpToTime = nil
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

        playback.setSubtitleDelay(0)
        let subtitleDelayEarlierHandled = playback.handleKeyboardShortcut(
            keyCode: 6, characters: "ض", modifiers: [], charactersWithModifiers: "ض"
        )
        try require(subtitleDelayEarlierHandled && abs(playback.subtitleDelaySeconds + 0.5) < 0.001,
                    "Z did not move Persian subtitles earlier by half a second")
        let subtitleDelayLaterHandled = playback.handleKeyboardShortcut(
            keyCode: 7, characters: "ص", modifiers: [], charactersWithModifiers: "ص"
        )
        try require(subtitleDelayLaterHandled && abs(playback.subtitleDelaySeconds) < 0.001,
                    "X did not restore subtitle synchronization under Persian input")
        _ = playback.handleKeyboardShortcut(
            keyCode: 7, characters: "ص", modifiers: [.option], charactersWithModifiers: "ص"
        )
        try require(abs(playback.subtitleDelaySeconds - 0.1) < 0.001,
                    "Option-X did not apply the fine 0.1-second subtitle adjustment")
        _ = playback.handleKeyboardShortcut(
            keyCode: 8, characters: "ث", modifiers: [], charactersWithModifiers: "ث"
        )
        try require(abs(playback.subtitleDelaySeconds) < 0.001, "C did not reset subtitle synchronization")

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

        playback.setSpeed(1)
        try require(playback.handleKeyboardShortcut(keyCode: 30, characters: "]", modifiers: []),
                    "the embedded IINA/mpv default speed-up binding was not routed")
        let defaultSpeedDeadline = Date(timeIntervalSinceNow: 1)
        while Date() < defaultSpeedDeadline {
            let actualSpeed = Double(playback.testingProperty("speed") ?? "1") ?? 1
            if abs(actualSpeed - 1.1) < 0.01 { break }
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        }
        try require(abs((Double(playback.testingProperty("speed") ?? "1") ?? 1) - 1.1) < 0.01,
                    "the IINA/mpv default ] shortcut did not change embedded playback speed")
        playback.setSpeed(1)
        let originalASSOverride = playback.testingProperty("sub-ass-override")
        try require(playback.handleKeyboardShortcut(keyCode: 32, characters: "u", modifiers: []),
                    "the default ASS subtitle-style shortcut was not routed through embedded mpv")
        let overrideDeadline = Date(timeIntervalSinceNow: 1)
        while Date() < overrideDeadline, playback.testingProperty("sub-ass-override") == originalASSOverride {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        }
        try require(playback.testingProperty("sub-ass-override") != originalASSOverride,
                    "the default ASS subtitle-style shortcut did not change the mpv property")
        try require(playback.handleKeyboardShortcut(keyCode: 123, characters: "", modifiers: [.control]),
                    "Control-Left did not reach mpv's previous-subtitle cue binding")
        try require(playback.handleKeyboardShortcut(keyCode: 124, characters: "", modifiers: [.control, .shift]),
                    "Control-Shift-Right did not reach mpv's frame-level subtitle sync binding")
        try require(playback.handleKeyboardShortcut(keyCode: 3, characters: "f", modifiers: [.shift]),
                    "Shift-F did not reach IINA's reduce-subtitle-size binding")
        try require(playback.handleKeyboardShortcut(keyCode: 116, characters: "", modifiers: []),
                    "Page Up did not reach the next-chapter binding")

        var playerCloseRequested = false
        playback.onCloseRequested = { playerCloseRequested = true }
        let closeShortcutHandled = playback.handleKeyboardShortcut(keyCode: 12, characters: "q", modifiers: [])
        try require(closeShortcutHandled && playerCloseRequested, "Q did not close the current player window")
        playback.onCloseRequested = nil
        let editionShortcutHandled = playback.handleKeyboardShortcut(
            keyCode: 14,
            characters: "ث",
            modifiers: [.shift]
        )
        try require(editionShortcutHandled, "Shift-E did not route IINA's edition-cycle shortcut with Persian input active")

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

        let loopDirectory = configurationDirectory.appendingPathComponent("ab-loop-player", isDirectory: true)
        try FileManager.default.createDirectory(at: loopDirectory, withIntermediateDirectories: true)
        let loopPlayback = MPVPlaybackController(
            configurationDirectoryURL: loopDirectory,
            videoOutput: "null",
            allowsPlaybackWithoutRenderer: true
        )
        let loopFixtureURL = configurationDirectory.appendingPathComponent("ab-loop-fixture.mov")
        try writeTestMovie(to: loopFixtureURL)
        loopPlayback.play(loopFixtureURL, headers: [:])
        let loopLoadDeadline = Date().addingTimeInterval(8)
        while loopPlayback.isLoading, loopPlayback.errorMessage == nil, Date() < loopLoadDeadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        try require(
            !loopPlayback.isLoading && loopPlayback.errorMessage == nil,
            "the local animated GIF did not load in the test libmpv session (loading: \(loopPlayback.isLoading), error: \(loopPlayback.errorMessage ?? "none"))"
        )
        try require(loopPlayback.seekAbsoluteExact(to: 1.0), "embedded libmpv rejected an absolute exact seek")
        let exactSeekDeadline = Date().addingTimeInterval(2)
        var exactSeekPosition = Double(loopPlayback.testingProperty("time-pos") ?? "") ?? 0
        while abs(exactSeekPosition - 1.0) > 0.2 && Date() < exactSeekDeadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
            exactSeekPosition = Double(loopPlayback.testingProperty("time-pos") ?? "") ?? exactSeekPosition
        }
        try require(
            abs(exactSeekPosition - 1.0) <= 0.2,
            "embedded libmpv did not seek to the requested absolute time (actual: \(exactSeekPosition))"
        )
        let screenshotURL = configurationDirectory.appendingPathComponent("captured-frame.png")
        try require(
            loopPlayback.captureScreenshot(to: screenshotURL, includeSubtitles: false),
            "embedded libmpv rejected a screenshot-to-file command"
        )
        let screenshotDeadline = Date().addingTimeInterval(4)
        var screenshotData = try? Data(contentsOf: screenshotURL)
        while screenshotData == nil && Date() < screenshotDeadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            screenshotData = try? Data(contentsOf: screenshotURL)
        }
        try require(
            screenshotData.map {
                $0.count > 20
                    && $0.prefix(8).elementsEqual([137, 80, 78, 71, 13, 10, 26, 10])
                    && $0.suffix(12).elementsEqual([0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130])
            } == true,
            "embedded libmpv did not write a complete PNG frame"
        )
        loopPlayback.markABLoop()
        try require(loopPlayback.abLoopState == 1, "the A point was not stored")
        try require(
            loopPlayback.onScreenMessage == DenboxLanguage.localizedMessage("A loop point set"),
            "setting the A point did not show the IINA-style status message"
        )
        loopPlayback.markABLoop()
        try require(loopPlayback.abLoopState == 2, "the B point was not stored")
        try require(
            loopPlayback.onScreenMessage == DenboxLanguage.localizedMessage("B loop point set"),
            "setting the B point did not show the IINA-style status message"
        )
        loopPlayback.markABLoop()
        try require(loopPlayback.abLoopState == 0, "the third A-B action did not clear both loop points")
        try require(
            loopPlayback.onScreenMessage == DenboxLanguage.localizedMessage("A-B loop cleared"),
            "clearing A-B repeat did not show the IINA-style status message"
        )
        loopPlayback.shutdown()

        let previewMovieURL = configurationDirectory.appendingPathComponent("seek-preview-fixture.mov")
        try writeTestMovie(to: previewMovieURL)
        let previewModel = MPVSeekPreviewModel()
        previewModel.setSource(previewMovieURL)
        previewModel.requestPreview(at: 0.75, duration: 2)
        let previewDeadline = Date().addingTimeInterval(8)
        while previewModel.image == nil && Date() < previewDeadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        try require(previewModel.image != nil, "AVFoundation did not decode a thumbnail from the local MOV fixture")
        try require(previewModel.timeSeconds == 0.75, "the seek-preview model did not retain the pointed-at time")
        previewModel.clearPreview()
        try require(previewModel.image == nil && previewModel.timeSeconds == nil, "leaving the timeline did not clear its thumbnail preview")
        previewModel.setSource(URL(string: "https://example.invalid/preview.mov")!)
        previewModel.requestPreview(at: 0.75, duration: 2)
        try require(previewModel.image == nil, "a remote stream unexpectedly requested a local-file thumbnail")

        playback.shutdown()
        print("PASS playback routing: embedded libmpv controls initialize and update without starting IINA")
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw TestFailure(message: message) }
    }

    private static func writeTestMovie(to url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 64,
            AVVideoHeightKey: 64
        ])
        let pixelAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: 64,
            kCVPixelBufferHeightKey as String: 64,
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: pixelAttributes
        )
        guard writer.canAdd(input) else {
            throw TestFailure(message: "AVFoundation could not add the synthetic video track")
        }
        writer.add(input)
        guard writer.startWriting() else {
            throw TestFailure(message: "AVFoundation could not start the synthetic local MOV")
        }
        writer.startSession(atSourceTime: .zero)

        for frame in 0..<8 {
            let deadline = Date().addingTimeInterval(3)
            while !input.isReadyForMoreMediaData && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.005)
            }
            guard input.isReadyForMoreMediaData,
                  let pool = adaptor.pixelBufferPool else {
                input.markAsFinished()
                throw TestFailure(message: "AVFoundation did not provide a pixel-buffer pool")
            }
            var optionalBuffer: CVPixelBuffer?
            guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &optionalBuffer) == kCVReturnSuccess,
                  let pixelBuffer = optionalBuffer else {
                input.markAsFinished()
                throw TestFailure(message: "could not allocate a frame for the synthetic MOV")
            }
            CVPixelBufferLockBaseAddress(pixelBuffer, [])
            guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer),
                  let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(
                    data: baseAddress,
                    width: 64,
                    height: 64,
                    bitsPerComponent: 8,
                    bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
                    space: colorSpace,
                    bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
                  ) else {
                CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
                input.markAsFinished()
                throw TestFailure(message: "could not render a synthetic MOV frame")
            }
            context.setFillColor(CGColor(
                srgbRed: CGFloat(frame) / 8,
                green: 0.35,
                blue: 0.7,
                alpha: 1
            ))
            context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
            CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
            guard adaptor.append(pixelBuffer, withPresentationTime: CMTime(value: Int64(frame), timescale: 4)) else {
                input.markAsFinished()
                throw TestFailure(message: "AVFoundation rejected a synthetic MOV frame")
            }
        }
        input.markAsFinished()
        let finished = DispatchSemaphore(value: 0)
        writer.finishWriting { finished.signal() }
        guard finished.wait(timeout: .now() + 8) == .success,
              writer.status == .completed else {
            throw TestFailure(message: "AVFoundation did not finish the synthetic local MOV")
        }
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
