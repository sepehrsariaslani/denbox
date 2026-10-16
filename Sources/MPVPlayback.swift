import AppKit
import Darwin
import MediaPlayer
import MPV
import OpenGL.GL
import OpenGL.GL3
import SwiftUI

enum DenboxMPVConfiguration {
    static let useInputConfigurationKey = "denbox.player.useMPVInputConfig"
    static let preferredAudioLanguagesKey = "denbox.player.preferredAudioLanguages"
    static let preferredSubtitleLanguagesKey = "denbox.player.preferredSubtitleLanguages"

    static func preferredLanguageList(forKey key: String) -> String? {
        let rawValue = UserDefaults.standard.string(forKey: key) ?? ""
        var seen = Set<String>()
        let languageCodes = rawValue
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { code in
                guard code.range(of: #"^[A-Za-z0-9_-]{2,12}$"#, options: .regularExpression) != nil else {
                    return false
                }
                return seen.insert(code.lowercased()).inserted
            }
        guard !languageCodes.isEmpty else { return nil }
        return languageCodes.joined(separator: ",")
    }

    static let directoryURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return appSupport.appendingPathComponent("Denbox/mpv", isDirectory: true)
    }()

    static var scriptsDirectoryURL: URL {
        directoryURL.appendingPathComponent("scripts", isDirectory: true)
    }

    static var inputConfigurationURL: URL {
        directoryURL.appendingPathComponent("input.conf", isDirectory: false)
    }

    @discardableResult
    static func prepare(directory: URL = directoryURL) -> Bool {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(
                at: directory.appendingPathComponent("scripts", isDirectory: true),
                withIntermediateDirectories: true
            )
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    @MainActor
    static func reveal(_ directory: URL) -> Bool {
        guard prepare(directory: directory) else { return false }
        return NSWorkspace.shared.open(directory)
    }

    @discardableResult
    @MainActor
    static func openInputConfiguration() -> Bool {
        guard prepare(), FileManager.default.fileExists(atPath: inputConfigurationURL.path) || createInputConfiguration() else {
            return false
        }
        return NSWorkspace.shared.open(inputConfigurationURL)
    }

    private static func createInputConfiguration() -> Bool {
        let template = "# mpv key bindings for Denbox. Changes apply after reopening the player.\n# Example: Ctrl+Alt+P cycle pause\n"
        return FileManager.default.createFile(atPath: inputConfigurationURL.path, contents: Data(template.utf8))
    }
}

enum MPVInputKeyMapper {
    private static let usKeyboardCharacters: [UInt16: String] = [
        0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x", 8: "c", 9: "v",
        11: "b", 12: "q", 13: "w", 14: "e", 15: "r", 16: "y", 17: "t", 31: "o", 32: "u",
        34: "i", 35: "p", 37: "l", 38: "j", 40: "k", 45: "n", 46: "m",
        18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9", 29: "0",
        24: "=", 27: "-", 30: "]", 33: "[", 39: "'", 41: ";", 42: "\\", 43: ",", 44: "/",
        47: ".", 50: "`"
    ]

    private static let shiftedUSKeyboardCharacters: [UInt16: String] = [
        18: "!", 19: "@", 20: "#", 21: "$", 23: "%", 22: "^", 26: "&", 28: "*", 25: "(", 29: ")",
        24: "+", 27: "_", 30: "}", 33: "{", 39: "\"", 41: ":", 42: "|", 43: "<", 44: "?", 47: ">", 50: "~"
    ]

    private static let specialKeys: [UInt16: String] = [
        36: "ENTER", 48: "TAB", 49: "SPACE", 51: "BS", 53: "ESC",
        76: "KP_ENTER", 115: "HOME", 116: "PGUP", 117: "DEL", 119: "END",
        121: "PGDWN", 123: "LEFT", 124: "RIGHT", 125: "DOWN", 126: "UP",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
        105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17", 79: "F18",
        80: "F19", 90: "F20"
    ]

    static func usLayoutCharacter(for keyCode: UInt16, shifted: Bool = false) -> String? {
        if shifted, let shiftedCharacter = shiftedUSKeyboardCharacters[keyCode] {
            return shiftedCharacter
        }
        guard let character = usKeyboardCharacters[keyCode] else { return nil }
        return shifted ? character.uppercased() : character
    }

    static func keyName(
        keyCode: UInt16,
        charactersIgnoringModifiers: String,
        characters: String?,
        modifiers: NSEvent.ModifierFlags
    ) -> String? {
        let flags = modifiers.intersection(.deviceIndependentFlagsMask)
        let specialKey = specialKeys[keyCode]
        let eventCharacter = singlePrintableCharacter(characters)
        let baseCharacter = eventCharacter ?? singlePrintableCharacter(charactersIgnoringModifiers)
        let needsPhysicalFallback = baseCharacter.map { !isASCIIPrintable($0) } ?? true
        let physicalCharacter = needsPhysicalFallback ? usLayoutCharacter(for: keyCode) : nil
        guard let key = specialKey ?? (needsPhysicalFallback ? physicalCharacter : baseCharacter) else { return nil }

        var prefix: [String] = []
        if flags.contains(.shift), specialKey != nil || needsPhysicalFallback { prefix.append("Shift") }
        if flags.contains(.control) { prefix.append("Ctrl") }
        if flags.contains(.option) { prefix.append("Alt") }
        if flags.contains(.command) { prefix.append("Meta") }
        return (prefix + [key]).joined(separator: "+")
    }

    private static func singlePrintableCharacter(_ value: String?) -> String? {
        guard let value, value.unicodeScalars.count == 1,
              let scalar = value.unicodeScalars.first,
              !CharacterSet.controlCharacters.contains(scalar),
              scalar.value != 0x7F else { return nil }
        return value
    }

    private static func isASCIIPrintable(_ value: String) -> Bool {
        guard value.unicodeScalars.count == 1, let scalar = value.unicodeScalars.first else { return false }
        return (0x20...0x7E).contains(scalar.value)
    }
}

enum MPVFilterKind: String, CaseIterable, Codable, Identifiable {
    case video
    case audio

    var id: String { rawValue }
    var commandName: String { self == .video ? "vf" : "af" }
    var title: String { self == .video ? "Video" : "Audio" }
}

struct MPVSubtitleEncoding: Identifiable, Equatable {
    let title: String
    let codepage: String
    var id: String { codepage }

    static let options: [MPVSubtitleEncoding] = [
        .init(title: "Automatic", codepage: "auto"),
        .init(title: "Universal (UTF-8)", codepage: "utf-8"),
        .init(title: "Universal (UTF-16)", codepage: "utf-16"),
        .init(title: "Universal (UTF-16BE)", codepage: "utf-16be"),
        .init(title: "Universal (UTF-16LE)", codepage: "utf-16le"),
        .init(title: "Arabic (ISO-8859-6)", codepage: "iso-8859-6"),
        .init(title: "Arabic (WINDOWS-1256)", codepage: "cp1256"),
        .init(title: "Baltic (WINDOWS-1257)", codepage: "cp1257"),
        .init(title: "Central European (WINDOWS-1250)", codepage: "cp1250"),
        .init(title: "Cyrillic (ISO-8859-5)", codepage: "iso-8859-5"),
        .init(title: "Cyrillic (WINDOWS-1251)", codepage: "cp1251"),
        .init(title: "Eastern European (ISO-8859-2)", codepage: "iso-8859-2"),
        .init(title: "Western Languages (WINDOWS-1252)", codepage: "cp1252"),
        .init(title: "Greek (ISO-8859-7)", codepage: "iso-8859-7"),
        .init(title: "Greek (WINDOWS-1253)", codepage: "cp1253"),
        .init(title: "Hebrew (ISO-8859-8)", codepage: "iso-8859-8"),
        .init(title: "Hebrew (WINDOWS-1255)", codepage: "cp1255"),
        .init(title: "Japanese (SHIFT-JIS)", codepage: "shift-jis"),
        .init(title: "Japanese (ISO-2022-JP-2)", codepage: "iso-2022-jp-2"),
        .init(title: "Korean (ISO-2022-KR)", codepage: "iso-2022-kr"),
        .init(title: "Russian (KOI8-R)", codepage: "koi8-r"),
        .init(title: "Simplified Chinese (GBK)", codepage: "gbk"),
        .init(title: "Simplified Chinese (GB18030)", codepage: "gb18030"),
        .init(title: "Simplified Chinese (ISO-2022-CN-EXT)", codepage: "iso-2022-cn-ext"),
        .init(title: "Thai (WINDOWS-874)", codepage: "cp874"),
        .init(title: "Traditional Chinese (EUC-TW)", codepage: "euc-tw"),
        .init(title: "Traditional Chinese (BIG5)", codepage: "big5"),
        .init(title: "Traditional Chinese (BIG5-HKSCS)", codepage: "big5-hkscs"),
        .init(title: "Turkish (WINDOWS-1254)", codepage: "cp1254"),
        .init(title: "Ukrainian (KOI8-U)", codepage: "koi8-u"),
        .init(title: "Vietnamese (WINDOWS-1258)", codepage: "cp1258")
    ]
}

enum PlayerControlsAutoHidePolicy {
    static let idleDelayNanoseconds: UInt64 = 1_500_000_000

    static func pointerMoved(from previousLocation: CGPoint?, to currentLocation: CGPoint) -> Bool {
        guard let previousLocation else { return true }
        let deltaX = currentLocation.x - previousLocation.x
        let deltaY = currentLocation.y - previousLocation.y
        return deltaX * deltaX + deltaY * deltaY >= 0.25
    }

    static func shouldHide(isScrubbing: Bool, hasOpenAdjustments: Bool) -> Bool {
        !isScrubbing && !hasOpenAdjustments
    }
}

enum PlaybackSourceFallbackPolicy {
    static func nextSource(
        from sources: [MediaStreamSource],
        excluding attemptedURLs: Set<String>
    ) -> MediaStreamSource? {
        var seen = Set<String>()
        return sources.first { source in
            let url = source.url.absoluteString
            return !attemptedURLs.contains(url) && seen.insert(url).inserted
        }
    }
}

struct MPVFilterPreset: Identifiable, Codable, Equatable {
    let id: String
    var name: String
    var kind: MPVFilterKind
    var expression: String
}

struct MPVActiveFilter: Identifiable, Equatable {
    let id: String
    var name: String
    var kind: MPVFilterKind
    var expression: String
}

enum MPVFilterPresetStore {
    static let userDefaultsKey = "denbox.player.savedMPVFilterPresets"

    static let builtIn: [MPVFilterPreset] = [
        MPVFilterPreset(id: "video-grayscale", name: "Grayscale", kind: .video, expression: "lavfi=[hue=s=0]"),
        MPVFilterPreset(id: "video-sharpen", name: "Sharpen", kind: .video, expression: "lavfi=[unsharp=5:5:0.8]"),
        MPVFilterPreset(id: "video-mirror", name: "Mirror horizontally", kind: .video, expression: "lavfi=[hflip]"),
        MPVFilterPreset(id: "video-flip", name: "Flip vertically", kind: .video, expression: "lavfi=[vflip]"),
        MPVFilterPreset(id: "video-soft-blur", name: "Soft blur", kind: .video, expression: "lavfi=[boxblur=2:1]"),
        MPVFilterPreset(id: "audio-bass", name: "Bass boost", kind: .audio, expression: "lavfi=[bass=g=5]"),
        MPVFilterPreset(id: "audio-compressor", name: "Dynamic compression", kind: .audio, expression: "lavfi=[acompressor]"),
        MPVFilterPreset(id: "audio-lowpass", name: "Low-pass filter", kind: .audio, expression: "lavfi=[lowpass=f=12000]"),
        MPVFilterPreset(id: "audio-noise", name: "Noise reduction", kind: .audio, expression: "lavfi=[afftdn=nf=-25]")
    ]

    static func loadSaved() -> [MPVFilterPreset] {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let presets = try? JSONDecoder().decode([MPVFilterPreset].self, from: data) else { return [] }
        return presets
    }

    static func save(_ presets: [MPVFilterPreset]) {
        guard let data = try? JSONEncoder().encode(presets) else { return }
        UserDefaults.standard.set(data, forKey: userDefaultsKey)
    }
}

struct MPVPlaybackTrack: Identifiable, Hashable {
    enum Kind: String { case video, audio, subtitle }

    let id: Int
    let kind: Kind
    let displayName: String
    let isSelected: Bool
    let isSecondarySelected: Bool
}

struct MPVPlaybackChapter: Identifiable, Hashable {
    let index: Int
    let title: String
    let timeSeconds: Double
    var id: Int { index }
}

struct MPVPlaybackPlaylistEntry: Identifiable, Hashable {
    let index: Int
    let title: String
    let filename: String
    let isCurrent: Bool
    var id: Int { index }
}

enum MPVPlaylistDocumentError: Error {
    case invalidUTF8
    case nonFileDestination
}

enum MPVPlaylistDocument {
    static let playlistExtensions: Set<String> = ["m3u", "m3u8", "pls"]
    static let chooserExtensions: Set<String> = playlistExtensions.union(["cue"])

    static func isPlaylistFile(_ url: URL) -> Bool {
        playlistExtensions.contains(url.pathExtension.lowercased())
    }

    static func urls(from selections: [URL]) throws -> [URL] {
        var result = [URL]()
        for url in selections {
            guard url.isFileURL else { continue }
            if isPlaylistFile(url) {
                result.append(contentsOf: try read(from: url))
            } else {
                result.append(url.standardizedFileURL)
            }
        }
        return result
    }

    static func read(from url: URL) throws -> [URL] {
        let fileExtension = url.pathExtension.lowercased()
        guard playlistExtensions.contains(fileExtension) else { return [url.standardizedFileURL] }
        guard let raw = String(data: try Data(contentsOf: url), encoding: .utf8) else {
            throw MPVPlaylistDocumentError.invalidUTF8
        }
        let text = raw.hasPrefix("\u{feff}") ? String(raw.dropFirst()) : raw
        let lines = text.components(separatedBy: .newlines)
        let entries: [String]
        if fileExtension == "pls" {
            let numberedEntries = lines.compactMap { line -> (Int, String)? in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, !trimmed.hasPrefix(";"), !trimmed.hasPrefix("#"),
                      let equals = trimmed.firstIndex(of: "=") else { return nil }
                let key = trimmed[..<equals].trimmingCharacters(in: .whitespaces).lowercased()
                guard key.hasPrefix("file"), let index = Int(key.dropFirst(4)) else { return nil }
                let value = String(trimmed[trimmed.index(after: equals)...])
                    .trimmingCharacters(in: .whitespaces)
                return value.isEmpty ? nil : (index, value)
            }
            entries = numberedEntries.sorted { $0.0 < $1.0 }.map(\.1)
        } else {
            entries = lines.compactMap { line in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty || trimmed.hasPrefix("#") ? nil : trimmed
            }
        }

        return entries.compactMap { resolve($0, relativeTo: url.deletingLastPathComponent()) }
    }

    static func data(for entries: [MPVPlaybackPlaylistEntry]) -> Data {
        let body = entries.map(\.filename).joined(separator: "\n")
        return Data((entries.isEmpty ? body : body + "\n").utf8)
    }

    static func save(_ entries: [MPVPlaybackPlaylistEntry], to url: URL) throws {
        guard url.isFileURL else { throw MPVPlaylistDocumentError.nonFileDestination }
        try data(for: entries).write(to: url, options: .atomic)
    }

    private static func resolve(_ value: String, relativeTo directory: URL) -> URL? {
        guard !value.isEmpty else { return nil }
        if let components = URLComponents(string: value), let scheme = components.scheme?.lowercased() {
            guard ["file", "http", "https"].contains(scheme) else { return nil }
            return components.url
        }
        return URL(fileURLWithPath: value, relativeTo: directory).standardizedFileURL
    }
}

struct MPVPlaybackAudioDevice: Identifiable, Hashable {
    let id: String
    let displayName: String
    let isDefault: Bool
}

private struct MPVHandleBox: @unchecked Sendable {
    let handle: OpaquePointer
}

private struct MPVPlayerWindowState {
    let frame: NSRect
    let title: String
    let level: NSWindow.Level
    let collectionBehavior: NSWindow.CollectionBehavior
    let minSize: NSSize
    let maxSize: NSSize
    let isMovableByWindowBackground: Bool
}

@MainActor
private final class DenboxRemotePlaybackBridge {
    static let shared = DenboxRemotePlaybackBridge()

    private let commandCenter = MPRemoteCommandCenter.shared()
    private let nowPlayingCenter = MPNowPlayingInfoCenter.default()
    private var targetTokens: [Any] = []
    private weak var activePlayback: MPVPlaybackController?
    private var publishedTitle: String?
    private var publishedElapsed: Double?
    private var publishedRate: Double?
    private var publishedState: MPNowPlayingPlaybackState = .unknown
    private var lastPublishedAt = Date.distantPast

    private init() {
        installCommandTargets()
        setCommandsEnabled(false, canSeek: false, hasPlaylist: false)
    }

    func activate(_ playback: MPVPlaybackController) {
        activePlayback = playback
        setCommandsEnabled(true, canSeek: false, hasPlaylist: false)
    }

    func update(
        playback: MPVPlaybackController,
        title: String,
        elapsed: Double,
        duration: Double?,
        rate: Double,
        isPlaying: Bool,
        playlistCount: Int,
        playlistPosition: Int,
        repeatType: MPRepeatType,
        force: Bool = false
    ) {
        guard activePlayback === playback else { return }
        let usableDuration = duration.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        let boundedElapsed = elapsed.isFinite ? max(0, elapsed) : 0
        let playbackRate = isPlaying && rate.isFinite && rate > 0 ? rate : 0
        let state: MPNowPlayingPlaybackState = isPlaying ? .playing : .paused
        let now = Date()

        setCommandsEnabled(true, canSeek: usableDuration != nil, hasPlaylist: playlistCount > 1)
        commandCenter.changeRepeatModeCommand.currentRepeatType = repeatType

        let shouldPublish = force
            || title != publishedTitle
            || state != publishedState
            || abs(playbackRate - (publishedRate ?? -1)) > 0.001
            || abs(boundedElapsed - (publishedElapsed ?? -10)) >= 1
            || now.timeIntervalSince(lastPublishedAt) >= 1
        guard shouldPublish else { return }

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.video.rawValue,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: boundedElapsed,
            MPNowPlayingInfoPropertyPlaybackRate: playbackRate,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0
        ]
        if let usableDuration { info[MPMediaItemPropertyPlaybackDuration] = usableDuration }
        if playlistCount > 0 {
            info[MPNowPlayingInfoPropertyPlaybackQueueCount] = playlistCount
            info[MPNowPlayingInfoPropertyPlaybackQueueIndex] = min(max(0, playlistPosition), playlistCount - 1)
        }

        nowPlayingCenter.playbackState = state
        nowPlayingCenter.nowPlayingInfo = info
        publishedTitle = title
        publishedElapsed = boundedElapsed
        publishedRate = playbackRate
        publishedState = state
        lastPublishedAt = now
    }

    func deactivate(_ playback: MPVPlaybackController) {
        guard activePlayback === playback else { return }
        activePlayback = nil
        setCommandsEnabled(false, canSeek: false, hasPlaylist: false)
        if let publishedTitle,
           nowPlayingCenter.nowPlayingInfo?[MPMediaItemPropertyTitle] as? String == publishedTitle {
            nowPlayingCenter.nowPlayingInfo = nil
        }
        nowPlayingCenter.playbackState = .stopped
        self.publishedTitle = nil
        publishedElapsed = nil
        publishedRate = nil
        publishedState = .stopped
        lastPublishedAt = .distantPast
    }

    private func installCommandTargets() {
        targetTokens.append(commandCenter.playCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.activePlayback?.setPlaybackPaused(false) }
            return .success
        })
        targetTokens.append(commandCenter.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.activePlayback?.setPlaybackPaused(true) }
            return .success
        })
        targetTokens.append(commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.activePlayback?.togglePlayPause() }
            return .success
        })
        targetTokens.append(commandCenter.stopCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.activePlayback?.stop() }
            return .success
        })
        targetTokens.append(commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.activePlayback?.stepPlaylist(by: 1) }
            return .success
        })
        targetTokens.append(commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.activePlayback?.stepPlaylist(by: -1) }
            return .success
        })
        targetTokens.append(commandCenter.changeRepeatModeCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangeRepeatModeCommandEvent else { return .commandFailed }
            let repeatType = event.repeatType
            Task { @MainActor [weak self] in self?.activePlayback?.setRemoteRepeatType(repeatType) }
            return .success
        })
        targetTokens.append(commandCenter.changePlaybackRateCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackRateCommandEvent else { return .commandFailed }
            let rate = Double(event.playbackRate)
            Task { @MainActor [weak self] in self?.activePlayback?.setSpeed(rate) }
            return .success
        })
        targetTokens.append(commandCenter.skipForwardCommand.addTarget { [weak self] event in
            guard let event = event as? MPSkipIntervalCommandEvent else { return .commandFailed }
            let interval = event.interval
            Task { @MainActor [weak self] in self?.activePlayback?.seek(by: interval) }
            return .success
        })
        targetTokens.append(commandCenter.skipBackwardCommand.addTarget { [weak self] event in
            guard let event = event as? MPSkipIntervalCommandEvent else { return .commandFailed }
            let interval = event.interval
            Task { @MainActor [weak self] in self?.activePlayback?.seek(by: -interval) }
            return .success
        })
        targetTokens.append(commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let position = event.positionTime
            Task { @MainActor [weak self] in self?.activePlayback?.seek(to: position) }
            return .success
        })

        commandCenter.changePlaybackRateCommand.supportedPlaybackRates = [0.5, 1.0, 1.5, 2.0]
        commandCenter.skipForwardCommand.preferredIntervals = [15]
        commandCenter.skipBackwardCommand.preferredIntervals = [15]
        commandCenter.changeShuffleModeCommand.isEnabled = false
    }

    private func setCommandsEnabled(_ enabled: Bool, canSeek: Bool, hasPlaylist: Bool) {
        commandCenter.playCommand.isEnabled = enabled
        commandCenter.pauseCommand.isEnabled = enabled
        commandCenter.togglePlayPauseCommand.isEnabled = enabled
        commandCenter.stopCommand.isEnabled = enabled
        commandCenter.nextTrackCommand.isEnabled = enabled && hasPlaylist
        commandCenter.previousTrackCommand.isEnabled = enabled && hasPlaylist
        commandCenter.changeRepeatModeCommand.isEnabled = enabled
        commandCenter.changePlaybackRateCommand.isEnabled = enabled
        commandCenter.skipForwardCommand.isEnabled = enabled && canSeek
        commandCenter.skipBackwardCommand.isEnabled = enabled && canSeek
        commandCenter.changePlaybackPositionCommand.isEnabled = enabled && canSeek
        commandCenter.changeShuffleModeCommand.isEnabled = false
    }
}

@MainActor
final class MPVPlaybackController: ObservableObject {
    @Published private(set) var isLoading = false
    @Published private(set) var isPlaying = false
    @Published private(set) var isBuffering = false
    @Published private(set) var cacheBufferingPercent = 0.0
    @Published private(set) var didReachEnd = false
    @Published private(set) var isInMiniPlayerMode = false
    @Published private(set) var isInSystemPictureInPictureMode = false
    @Published private(set) var isMusicMode = false
    @Published private(set) var isPlaylistLoopEnabled = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var currentTimeSeconds = 0.0
    @Published private(set) var durationSeconds: Double?
    @Published private(set) var videoOptions: [MPVPlaybackTrack] = []
    @Published private(set) var audioOptions: [MPVPlaybackTrack] = []
    @Published private(set) var subtitleOptions: [MPVPlaybackTrack] = []
    @Published private(set) var chapters: [MPVPlaybackChapter] = []
    @Published private(set) var playlist: [MPVPlaybackPlaylistEntry] = []
    @Published private(set) var playlistPosition = 0
    @Published private(set) var audioDevices = [MPVPlaybackAudioDevice(
        id: "auto", displayName: "System default", isDefault: true
    )]
    @Published private(set) var selectedAudioDeviceID = "auto"
    @Published private(set) var currentChapterIndex: Int?
    @Published private(set) var audioDelaySeconds = 0.0
    @Published private(set) var subtitleDelaySeconds = 0.0
    @Published private(set) var subtitleEncoding = "auto"
    @Published private(set) var subtitleScale = 1.0
    @Published private(set) var subtitlePosition = 100.0
    @Published private(set) var subtitleBorderSize = 3.0
    @Published private(set) var subtitleFontSize = 55.0
    @Published private(set) var subtitleVisibility = true
    @Published private(set) var secondarySubtitleID: Int?
    @Published private(set) var secondarySubtitleVisibility = true
    @Published private(set) var isDeinterlacing = false
    @Published private(set) var isVerticallyFlipped = false
    @Published private(set) var isHorizontallyMirrored = false
    @Published private(set) var hardwareDecodingEnabled = true
    @Published private(set) var videoBrightness = 0.0
    @Published private(set) var videoContrast = 0.0
    @Published private(set) var videoGamma = 0.0
    @Published private(set) var videoHue = 0.0
    @Published private(set) var videoSaturation = 0.0
    @Published private(set) var audioEQBands = Array(repeating: 0.0, count: 10)
    @Published private(set) var activeFilters: [MPVActiveFilter] = []
    @Published private(set) var savedFilterPresets = MPVFilterPresetStore.loadSaved()
    @Published private(set) var volume = 100.0
    @Published private(set) var isMuted = false
    @Published private(set) var speed = 1.0
    let subtitlesCanBeDisabled = true

    private var handle: OpaquePointer?
    private var renderContext: OpaquePointer?
    private weak var glContext: NSOpenGLContext?
    private weak var playerWindow: NSWindow?
    private weak var renderView: MPVRenderView?
    private var referencePlayerContentSize: NSSize?
    private var regularPlayerWindowState: MPVPlayerWindowState?
    private var systemPIPController: NSObject?
    private var systemPIPContentController: NSViewController?
    private var systemPIPDelegate: DenboxSystemPictureInPictureDelegate?
    private var systemPIPOriginalSuperview: NSView?
    private var systemPIPOriginalWindow: NSWindow?
    private var systemPIPOriginalConstraints: [NSLayoutConstraint] = []
    private var systemPIPOriginalFrame = NSRect.zero
    private var systemPIPOriginalSubviewIndex = 0
    private var systemPIPOriginalAutoresizingMask: NSView.AutoresizingMask = []
    private var systemPIPOriginalTranslatesAutoresizingMask = true
    private var systemPIPWindowWasMiniaturized = false
    private var didMiniaturizePlayerWindowForPIP = false
    private var systemPIPClosePrepared = false
    private var pollTimer: Timer?
    private var loadedURL: URL?
    private var loadedHeaders: [String: String] = [:]
    private var pendingResumeSeconds = 0.0
    private var pendingPlayback: (url: URL, headers: [String: String])?
    private var trackRefreshAt = Date.distantPast
    private var lastWatchTick: Date?
    private var pendingWatchedSeconds = 0.0
    private var shutdownRequested = false
    private var audioDeviceRefreshAt = Date.distantPast
    private var preferredLanguageObserver: NSObjectProtocol?
    private var preferredLanguageUpdateTask: Task<Void, Never>?
    private var appliedPreferredAudioLanguages: String?
    private var appliedPreferredSubtitleLanguages: String?
    private var nowPlayingTitle = "Denbox"
    var onProgress: ((Double, Double?, Double) -> Void)?
    var onUserActivity: (() -> Void)?
    var onToggleFullscreen: (() -> Void)?
    var onTogglePictureInPicture: (() -> Void)?
    var onFindOnlineSubtitles: (() -> Void)?
    var onSetWindowScale: ((Double) -> Void)?
    var onScreenshotRequested: ((Bool) -> Void)?
    var onCloseRequested: (() -> Void)?
    var onTogglePlaybackInfo: (() -> Void)?
    var onToggleControls: (() -> Void)?
    var onPictureInPictureUnavailable: (() -> Void)?

    private static let systemPIPFrameworkLoaded: Bool = {
        guard let framework = Bundle(path: "/System/Library/PrivateFrameworks/PIP.framework") else {
            return false
        }
        return framework.isLoaded || framework.load()
    }()

    init(configurationDirectoryURL: URL? = nil) {
        guard let handle = mpv_create() else {
            errorMessage = "The embedded playback engine could not be created."
            return
        }
        self.handle = handle

        let configurationDirectory = configurationDirectoryURL ?? DenboxMPVConfiguration.directoryURL
        let shouldLoadUserConfiguration = DenboxMPVConfiguration.prepare(directory: configurationDirectory)

        var options: [(String, String)] = [
            ("vo", "libmpv"),
            ("hwdec", "auto-safe"),
            ("keep-open", "yes"),
            ("audio-display", "no"),
            ("config", shouldLoadUserConfiguration ? "yes" : "no"),
            ("osc", "no"),
            ("osd-level", "1"),
            ("cache", "yes"),
            ("cache-secs", "30"),
            ("cache-pause", "yes"),
            ("cache-pause-initial", "yes"),
            ("cache-pause-wait", "8"),
            ("demuxer-max-bytes", "192MiB"),
            ("demuxer-max-back-bytes", "48MiB"),
            ("sub-auto", "fuzzy"),
            ("sub-font-provider", "auto"),
            ("screenshot-directory", "~/Pictures/Denbox")
        ]
        if let audioLanguages = DenboxMPVConfiguration.preferredLanguageList(
            forKey: DenboxMPVConfiguration.preferredAudioLanguagesKey
        ) {
            options.append(("alang", audioLanguages))
        }
        if let subtitleLanguages = DenboxMPVConfiguration.preferredLanguageList(
            forKey: DenboxMPVConfiguration.preferredSubtitleLanguagesKey
        ) {
            options.append(("slang", subtitleLanguages))
        }
        if shouldLoadUserConfiguration {
            options.insert(("config-dir", configurationDirectory.path), at: 0)
            options.insert(("load-scripts", "yes"), at: 1)
        }
        for (name, value) in options {
            _ = name.withCString { key in value.withCString { mpv_set_option_string(handle, key, $0) } }
        }

        let result = mpv_initialize(handle)
        if result < 0 {
            errorMessage = "The embedded playback engine could not start: \(Self.errorText(result))"
            mpv_terminate_destroy(handle)
            self.handle = nil
            return
        }

        appliedPreferredAudioLanguages = UserDefaults.standard.string(
            forKey: DenboxMPVConfiguration.preferredAudioLanguagesKey
        )
        appliedPreferredSubtitleLanguages = UserDefaults.standard.string(
            forKey: DenboxMPVConfiguration.preferredSubtitleLanguagesKey
        )
        preferredLanguageObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: UserDefaults.standard,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.schedulePreferredLanguageUpdate()
            }
        }

        refreshAudioDevices(force: true)
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshState() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
        startEventLoop(MPVHandleBox(handle: handle))
    }

    deinit {
        pollTimer?.invalidate()
        if let renderContext {
            mpv_render_context_set_update_callback(renderContext, nil, nil)
            mpv_render_context_free(renderContext)
        }
        preferredLanguageUpdateTask?.cancel()
        if let preferredLanguageObserver {
            NotificationCenter.default.removeObserver(preferredLanguageObserver)
        }
        if let handle { mpv_terminate_destroy(handle) }
    }

    func shutdown() {
        guard !shutdownRequested else { return }
        shutdownRequested = true
        if loadedURL != nil { DenboxRemotePlaybackBridge.shared.deactivate(self) }
        preferredLanguageUpdateTask?.cancel()
        preferredLanguageUpdateTask = nil
        if let preferredLanguageObserver {
            NotificationCenter.default.removeObserver(preferredLanguageObserver)
            self.preferredLanguageObserver = nil
        }
        _ = exitSystemPictureInPicture()
        pollTimer?.invalidate()
        pollTimer = nil
        detachRenderer()
        _ = command(["quit"])
    }

    func attachRenderer(using context: NSOpenGLContext) {
        if renderContext != nil {
            guard glContext !== context else { return }
            // AppKit can move an NSOpenGLView into a new window while entering
            // full screen. libmpv's render context belongs to the old GL
            // context, so rebuild it before drawing into the new window.
            detachRenderer()
        }
        guard let handle else { return }
        context.makeCurrentContext()
        glContext = context

        guard let apiName = (MPV_RENDER_API_TYPE_OPENGL as NSString).utf8String else {
            errorMessage = "OpenGL is unavailable for this window."
            return
        }
        let apiType = UnsafeMutableRawPointer(mutating: apiName)
        var openGL = mpv_opengl_init_params(
            get_proc_address: mpvOpenGLGetProcAddress,
            get_proc_address_ctx: nil,
            extra_exts: nil
        )
        withUnsafeMutablePointer(to: &openGL) { openGLPointer in
            var parameters = [
                mpv_render_param(type: MPV_RENDER_PARAM_API_TYPE, data: apiType),
                mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_INIT_PARAMS, data: UnsafeMutableRawPointer(openGLPointer)),
                mpv_render_param()
            ]
            let result = parameters.withUnsafeMutableBufferPointer {
                mpv_render_context_create(&renderContext, handle, $0.baseAddress)
            }
            if result < 0 {
                errorMessage = "The embedded video renderer could not initialize: \(Self.errorText(result))"
                renderContext = nil
            } else if let pendingPlayback {
                self.pendingPlayback = nil
                beginPlayback(pendingPlayback.url, headers: pendingPlayback.headers)
            }
        }
    }

    func detachRenderer() {
        guard let renderContext else { return }
        glContext?.makeCurrentContext()
        mpv_render_context_set_update_callback(renderContext, nil, nil)
        mpv_render_context_free(renderContext)
        self.renderContext = nil
        glContext = nil
    }

    func setPlayerWindow(_ window: NSWindow?) {
        if isInSystemPictureInPictureMode, window !== systemPIPOriginalWindow { return }
        if referencePlayerContentSize == nil, let window {
            let viewSize = window.contentView?.bounds.size ?? .zero
            let frameContentSize = window.contentRect(forFrameRect: window.frame).size
            let measuredSize = viewSize.width >= 640 && viewSize.height >= 400 ? viewSize : frameContentSize
            referencePlayerContentSize = measuredSize.width >= 640 && measuredSize.height >= 400
                ? measuredSize
                : NSSize(width: 1280, height: 800)
        }
        playerWindow = window
        window?.collectionBehavior.insert(.fullScreenPrimary)
    }

    func isPointerInsidePlayerWindow() -> Bool {
        guard let playerWindow else { return false }
        return playerWindow.frame.contains(NSEvent.mouseLocation)
    }

    func registerRenderView(_ view: MPVRenderView?) {
        renderView = view
    }

    @discardableResult
    func enterSystemPictureInPicture(title: String) -> Bool {
        guard !shutdownRequested,
              !isInSystemPictureInPictureMode,
              !isInMiniPlayerMode,
              Self.systemPIPFrameworkLoaded,
              let pipClass = NSClassFromString("PIPViewController") as? NSObject.Type,
              let view = renderView,
              let parent = view.superview,
              let window = playerWindow ?? view.window else {
            return false
        }

        let pipController = pipClass.init()
        let presentSelector = NSSelectorFromString("presentViewControllerAsPictureInPicture:")
        let dismissSelector = NSSelectorFromString("dismissViewController:")
        guard pipController.responds(to: presentSelector),
              pipController.responds(to: dismissSelector) else {
            return false
        }

        systemPIPOriginalSuperview = parent
        systemPIPOriginalWindow = window
        systemPIPOriginalFrame = view.frame
        systemPIPOriginalSubviewIndex = parent.subviews.firstIndex(where: { $0 === view }) ?? parent.subviews.count
        systemPIPOriginalAutoresizingMask = view.autoresizingMask
        systemPIPOriginalTranslatesAutoresizingMask = view.translatesAutoresizingMaskIntoConstraints
        systemPIPOriginalConstraints = parent.constraints.filter { constraint in
            (constraint.firstItem as? NSView) === view || (constraint.secondItem as? NSView) === view
        }
        systemPIPWindowWasMiniaturized = window.isMiniaturized
        didMiniaturizePlayerWindowForPIP = false
        systemPIPClosePrepared = false

        let contentController = NSViewController()
        contentController.view = view
        let delegate = DenboxSystemPictureInPictureDelegate(owner: self)
        pipController.setValue(title, forKey: "title")
        pipController.setValue(NSNumber(value: isPlaying), forKey: "playing")
        pipController.setValue(delegate, forKey: "delegate")
        systemPIPController = pipController
        systemPIPContentController = contentController
        systemPIPDelegate = delegate
        isInSystemPictureInPictureMode = true
        _ = pipController.perform(presentSelector, with: contentController)

        // IINA leaves the system PiP window visible and tucks away the full
        // player window after the existing video view has moved into PiP.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self, weak view, weak window] in
            guard let self, let view, let window, self.isInSystemPictureInPictureMode else { return }
            guard view.window !== window else {
                _ = self.systemPIPController?.perform(dismissSelector, with: contentController)
                self.finishSystemPictureInPicture()
                self.onPictureInPictureUnavailable?()
                return
            }
            if !self.systemPIPWindowWasMiniaturized,
               !window.styleMask.contains(.fullScreen),
               !window.isMiniaturized {
                self.didMiniaturizePlayerWindowForPIP = true
                window.miniaturize(nil)
            }
        }
        return true
    }

    @discardableResult
    func exitSystemPictureInPicture() -> Bool {
        guard isInSystemPictureInPictureMode,
              let pipController = systemPIPController,
              let contentController = systemPIPContentController else { return false }
        prepareSystemPictureInPictureClose(using: pipController)
        _ = pipController.perform(NSSelectorFromString("dismissViewController:"), with: contentController)
        return true
    }

    func prepareSystemPictureInPictureClose(using pipController: AnyObject) {
        guard !systemPIPClosePrepared,
              let pipController = pipController as? NSObject,
              let window = systemPIPOriginalWindow else { return }
        systemPIPClosePrepared = true
        let replacementRect = systemPIPOriginalSuperview?.convert(systemPIPOriginalFrame, to: nil) ?? .zero
        pipController.setValue(NSValue(rect: replacementRect), forKey: "replacementRect")
        _ = pipController.perform(NSSelectorFromString("setReplacementWindow:"), with: window)
        NSApp.activate(ignoringOtherApps: true)
        if didMiniaturizePlayerWindowForPIP || window.isMiniaturized {
            window.deminiaturize(nil)
            window.makeKeyAndOrderFront(nil)
        }
    }

    func finishSystemPictureInPicture() {
        guard isInSystemPictureInPictureMode else { return }
        isInSystemPictureInPictureMode = false
        if let view = renderView, let parent = systemPIPOriginalSuperview {
            view.removeFromSuperview()
            let sibling = parent.subviews.indices.contains(systemPIPOriginalSubviewIndex)
                ? parent.subviews[systemPIPOriginalSubviewIndex] : nil
            if let sibling {
                parent.addSubview(view, positioned: .below, relativeTo: sibling)
            } else {
                parent.addSubview(view)
            }
            view.frame = systemPIPOriginalFrame
            view.autoresizingMask = systemPIPOriginalAutoresizingMask
            view.translatesAutoresizingMaskIntoConstraints = systemPIPOriginalTranslatesAutoresizingMask
            for constraint in systemPIPOriginalConstraints where !constraint.isActive {
                constraint.isActive = true
            }
            view.openGLContext?.update()
            view.needsDisplay = true
        }
        if didMiniaturizePlayerWindowForPIP, let window = systemPIPOriginalWindow, window.isMiniaturized {
            window.deminiaturize(nil)
            window.makeKeyAndOrderFront(nil)
        }
        systemPIPController = nil
        systemPIPContentController = nil
        systemPIPDelegate = nil
        systemPIPOriginalSuperview = nil
        systemPIPOriginalWindow = nil
        systemPIPOriginalConstraints = []
        didMiniaturizePlayerWindowForPIP = false
        systemPIPClosePrepared = false
    }

    fileprivate func setPlaybackPausedByPictureInPicture(_ paused: Bool) {
        setProperty("pause", value: paused ? "yes" : "no")
        isPlaying = !paused
        updateSystemPictureInPicturePlayingState()
    }

    private func updateSystemPictureInPicturePlayingState() {
        systemPIPController?.setValue(NSNumber(value: isPlaying), forKey: "playing")
    }

    @discardableResult
    func enterMiniPlayer(title: String) -> Bool {
        guard !isInMiniPlayerMode, !isInSystemPictureInPictureMode, let window = playerWindow else { return false }
        regularPlayerWindowState = MPVPlayerWindowState(
            frame: window.frame,
            title: window.title,
            level: window.level,
            collectionBehavior: window.collectionBehavior,
            minSize: window.minSize,
            maxSize: window.maxSize,
            isMovableByWindowBackground: window.isMovableByWindowBackground
        )
        isInMiniPlayerMode = true

        // Keep the existing libmpv view and playback session in the same
        // window. Only the AppKit presentation changes, so entering the mini
        // player does not reload the stream or hand it to another app.
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window, self.isInMiniPlayerMode else { return }
            window.minSize = NSSize(width: 420, height: 280)
            window.maxSize = NSSize(width: 900, height: 620)
            window.level = .floating
            window.collectionBehavior.insert(.canJoinAllSpaces)
            window.isMovableByWindowBackground = true
            window.title = title
            window.setContentSize(NSSize(width: 560, height: 350))

            if let visibleFrame = (window.screen ?? NSScreen.main)?.visibleFrame {
                let frame = window.frame
                let origin = NSPoint(
                    x: max(visibleFrame.minX + 16, visibleFrame.maxX - frame.width - 16),
                    y: max(visibleFrame.minY + 16, visibleFrame.maxY - frame.height - 16)
                )
                window.setFrameOrigin(origin)
            }
            window.makeKeyAndOrderFront(nil)
        }
        return true
    }

    func updateMiniPlayerTitle(_ title: String) {
        if isInSystemPictureInPictureMode {
            systemPIPController?.setValue(title, forKey: "title")
            return
        }
        guard isInMiniPlayerMode else { return }
        playerWindow?.title = title
    }

    func exitMiniPlayer() {
        guard isInMiniPlayerMode else { return }
        isInMiniPlayerMode = false
        guard let state = regularPlayerWindowState else { return }
        regularPlayerWindowState = nil
        guard let window = playerWindow else { return }

        // SwiftUI updates the content's minimum size after the published mode
        // change. Restore the original AppKit constraints and frame afterward.
        DispatchQueue.main.async { [weak window] in
            guard let window else { return }
            window.minSize = state.minSize
            window.maxSize = state.maxSize
            window.level = state.level
            window.collectionBehavior = state.collectionBehavior
            window.isMovableByWindowBackground = state.isMovableByWindowBackground
            window.title = state.title
            window.setFrame(state.frame, display: true, animate: true)
            window.makeKeyAndOrderFront(nil)
        }
    }

    private func visiblePlayerWindow() -> NSWindow? {
        // Prefer the key window because SwiftUI can replace its window while
        // moving a WindowGroup scene. The render view's weak reference can
        // briefly point at the previous window during that transition.
        [NSApp.keyWindow, playerWindow, NSApp.mainWindow]
            .compactMap({ $0 })
            .first(where: \.isVisible)
    }

    private func requestFullscreen(_ shouldBeFullscreen: Bool) {
        guard let window = visiblePlayerWindow(),
              window.styleMask.contains(.fullScreen) != shouldBeFullscreen else { return }
        window.collectionBehavior.insert(.fullScreenPrimary)
        // AppKit may ignore a fullscreen request issued in the middle of a
        // SwiftUI button update. Schedule it on the next main-loop turn after
        // making the visible player window key.
        DispatchQueue.main.async { [weak window] in
            guard let window, window.isVisible,
                  window.styleMask.contains(.fullScreen) != shouldBeFullscreen else { return }
            window.makeKeyAndOrderFront(nil)
            window.toggleFullScreen(nil)
        }
    }

    func toggleFullscreen() {
        guard let window = visiblePlayerWindow() else { return }
        requestFullscreen(!window.styleMask.contains(.fullScreen))
    }

    func enterFullscreen() { requestFullscreen(true) }
    func exitFullscreen() { requestFullscreen(false) }

    func toggleAlwaysOnTop() {
        guard !isInMiniPlayerMode, !isInSystemPictureInPictureMode,
              let window = playerWindow else { return }
        window.level = window.level == .floating ? .normal : .floating
    }

    func setWindowScale(_ scale: Double) {
        guard scale.isFinite, (0.5...2).contains(scale),
              !isInMiniPlayerMode, !isInSystemPictureInPictureMode,
              let window = playerWindow,
              !window.styleMask.contains(.fullScreen),
              let reference = referencePlayerContentSize else { return }
        let targetContentSize = NSSize(width: reference.width * scale, height: reference.height * scale)
        let minimumContentSize = NSSize(width: 1024 * scale, height: 640 * scale)
        let minimumFrame = window.frameRect(forContentRect: NSRect(origin: .zero, size: minimumContentSize)).size
        window.minSize = minimumFrame
        window.setContentSize(targetContentSize)
    }

    func fitWindowToScreen() {
        guard let window = playerWindow,
              let reference = referencePlayerContentSize,
              let screen = window.screen ?? NSScreen.main else { return }
        let chromeHeight = window.frameRect(forContentRect: NSRect(origin: .zero, size: reference)).height - reference.height
        let visible = screen.visibleFrame
        let availableHeight = max(240, visible.height - chromeHeight - 24)
        let scale = min(visible.width / reference.width, availableHeight / reference.height)
        guard scale.isFinite, scale > 0 else { return }
        onSetWindowScale?(max(0.5, min(2, scale)))
    }

    func toggleMusicMode() { isMusicMode.toggle() }

    func render(width: Int32, height: Int32, force: Bool = false) -> Bool {
        guard width > 0, height > 0, let renderContext else { return false }
        let flags = mpv_render_context_update(renderContext)
        // NSOpenGLView uses a double-buffered drawable whose back buffer can
        // be discarded after a swap or window/screen transition. Re-rendering
        // the current mpv frame on an AppKit redraw keeps that surface from
        // flashing black when the stream itself has not produced a new frame.
        guard force || flags & UInt64(MPV_RENDER_UPDATE_FRAME.rawValue) != 0 else { return false }

        var framebuffer = mpv_opengl_fbo(fbo: 0, w: width, h: height, internal_format: 0)
        var flip: Int32 = 1
        withUnsafeMutablePointer(to: &framebuffer) { framebufferPointer in
            withUnsafeMutablePointer(to: &flip) { flipPointer in
                var parameters = [
                    mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_FBO, data: UnsafeMutableRawPointer(framebufferPointer)),
                    mpv_render_param(type: MPV_RENDER_PARAM_FLIP_Y, data: UnsafeMutableRawPointer(flipPointer)),
                    mpv_render_param()
                ]
                _ = parameters.withUnsafeMutableBufferPointer {
                    mpv_render_context_render(renderContext, $0.baseAddress)
                }
            }
        }
        return true
    }

    func reportSwap() {
        if let renderContext { mpv_render_context_report_swap(renderContext) }
    }

    func play(_ url: URL, headers: [String: String], startAtSeconds: Double = 0) {
        guard handle != nil else {
            errorMessage = "The embedded playback engine is not ready."
            return
        }
        if loadedURL == url, loadedHeaders == headers {
            if startAtSeconds.isFinite, startAtSeconds > 0,
               abs(currentTimeSeconds - startAtSeconds) > 1 {
                seek(to: startAtSeconds)
            }
            setProperty("pause", value: "no")
            isPlaying = true
            DenboxRemotePlaybackBridge.shared.activate(self)
            updateSystemMediaControls(force: true)
            return
        }

        resetVideoOrientation()
        loadedURL = url
        loadedHeaders = headers
        pendingResumeSeconds = max(0, startAtSeconds)
        isLoading = true
        isPlaying = false
        didReachEnd = false
        errorMessage = nil
        currentTimeSeconds = 0
        durationSeconds = nil
        videoOptions = []
        audioOptions = []
        subtitleOptions = []
        chapters = []
        playlist = []
        playlistPosition = 0
        currentChapterIndex = nil
        lastWatchTick = nil
        pendingWatchedSeconds = 0
        DenboxRemotePlaybackBridge.shared.activate(self)
        updateSystemMediaControls(force: true)

        guard renderContext != nil else {
            pendingPlayback = (url, headers)
            return
        }

        beginPlayback(url, headers: headers)
    }

    private func beginPlayback(_ url: URL, headers: [String: String]) {
        guard handle != nil else { return }

        let headerValue = headers.sorted {
            $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending
        }.map { "\($0.key): \($0.value)" }.joined(separator: ",")
        setProperty("http-header-fields", value: headerValue)
        let result = command(["loadfile", url.isFileURL ? url.path : url.absoluteString, "replace"])
        if result < 0 {
            isLoading = false
            errorMessage = "The video source could not be opened: \(Self.errorText(result))"
        }
    }

    func stop() {
        let hadLoadedMedia = loadedURL != nil
        _ = exitSystemPictureInPicture()
        flushPendingWatchTime()
        isLoading = false
        isPlaying = false
        isBuffering = false
        cacheBufferingPercent = 0
        lastWatchTick = nil
        _ = command(["stop"])
        loadedURL = nil
        loadedHeaders = [:]
        pendingPlayback = nil
        if hadLoadedMedia { DenboxRemotePlaybackBridge.shared.deactivate(self) }
    }

    func updateNowPlayingTitle(_ title: String) {
        let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
        nowPlayingTitle = cleaned.isEmpty ? "Denbox" : cleaned
        updateSystemMediaControls(force: true)
    }

    func retry(_ url: URL, headers: [String: String], startAtSeconds: Double? = nil) {
        loadedURL = nil
        play(url, headers: headers, startAtSeconds: startAtSeconds ?? currentTimeSeconds)
    }

    func flushWatchProgress() { flushPendingWatchTime() }

    func setPendingResumePosition(_ seconds: Double) {
        pendingResumeSeconds = seconds.isFinite ? max(0, seconds) : 0
    }

    func setPlaybackPaused(_ paused: Bool) {
        setProperty("pause", value: paused ? "yes" : "no")
        isPlaying = !paused && !isLoading && errorMessage == nil
        updateSystemPictureInPicturePlayingState()
        updateSystemMediaControls(force: true)
    }

    func togglePlayPause() { setPlaybackPaused(!isPlaying) }

    func seek(to seconds: Double) {
        guard seconds.isFinite else { return }
        setProperty("time-pos", value: String(max(0, seconds)))
        currentTimeSeconds = max(0, seconds)
        updateSystemMediaControls(force: true)
    }

    func seek(by seconds: Double) { seek(to: currentTimeSeconds + seconds) }

    func setSpeed(_ value: Double) {
        guard value.isFinite, value > 0 else { return }
        setProperty("speed", value: String(value))
        speed = value
        updateSystemMediaControls(force: true)
    }

    func setVolume(_ value: Double) {
        let bounded = min(130, max(0, value))
        setProperty("volume", value: String(bounded))
        volume = bounded
    }

    @discardableResult
    func setAudioDevice(_ identifier: String) -> Bool {
        guard !identifier.isEmpty, let handle else { return false }
        let result = "audio-device".withCString { key in
            identifier.withCString { mpv_set_property_string(handle, key, $0) }
        }
        guard result >= 0 else { return false }
        selectedAudioDeviceID = identifier
        return true
    }

    func selectAudio(_ track: MPVPlaybackTrack?) {
        setProperty("aid", value: track.map { String($0.id) } ?? "no")
        refreshTracks()
    }

    func selectVideo(_ track: MPVPlaybackTrack?) {
        setProperty("vid", value: track.map { String($0.id) } ?? "no")
        refreshTracks()
    }

    func selectSubtitle(_ track: MPVPlaybackTrack?) {
        setProperty("sid", value: track.map { String($0.id) } ?? "no")
        refreshTracks()
    }

    func setSubtitleDelay(_ seconds: Double) {
        guard seconds.isFinite else { return }
        subtitleDelaySeconds = seconds
        setProperty("sub-delay", value: String(seconds))
    }

    @discardableResult
    func setSubtitleEncoding(_ codepage: String) -> Bool {
        guard let option = MPVSubtitleEncoding.options.first(where: {
            $0.codepage.caseInsensitiveCompare(codepage) == .orderedSame
        }), let handle else { return false }
        guard subtitleEncoding.caseInsensitiveCompare(option.codepage) != .orderedSame else { return true }
        let result = "sub-codepage".withCString { key in
            option.codepage.withCString { mpv_set_property_string(handle, key, $0) }
        }
        guard result >= 0 else { return false }
        subtitleEncoding = option.codepage
        reloadExternalSubtitleTracks()
        return true
    }

    func setAudioDelay(_ seconds: Double) {
        guard seconds.isFinite else { return }
        audioDelaySeconds = seconds
        setProperty("audio-delay", value: String(seconds))
    }
    func setSubtitleScale(_ value: Double) {
        guard value.isFinite else { return }
        subtitleScale = min(3, max(0.3, value))
        setProperty("sub-scale", value: String(subtitleScale))
    }
    func setSubtitlePosition(_ value: Double) {
        guard value.isFinite else { return }
        subtitlePosition = min(100, max(0, value))
        setProperty("sub-pos", value: String(subtitlePosition))
    }
    func setSubtitleBorderSize(_ value: Double) {
        guard value.isFinite else { return }
        subtitleBorderSize = min(10, max(0, value))
        setProperty("sub-border-size", value: String(subtitleBorderSize))
    }
    func setSubtitleFontSize(_ value: Double) {
        guard value.isFinite else { return }
        subtitleFontSize = min(120, max(12, value))
        setProperty("sub-font-size", value: String(subtitleFontSize))
    }
    func adjustSubtitleScale(by multiplier: Double) {
        guard multiplier.isFinite, multiplier > 0 else { return }
        let current = getProperty("sub-scale").flatMap(Double.init) ?? 1
        setSubtitleScale(min(3, max(0.3, current * multiplier)))
    }
    func setSubtitleFont(_ name: String) { setProperty("options/sub-font", value: name) }
    func setSubtitleColor(_ value: String) { setProperty("options/sub-color", value: value) }
    func setSubtitleBackgroundColor(_ value: String) { setProperty("options/sub-back-color", value: value) }
    func setSubtitleBorderColor(_ value: String) { setProperty("options/sub-border-color", value: value) }
    func setSubtitleASSOverride(_ value: String) {
        guard ["no", "yes", "force", "scale", "strip"].contains(value) else { return }
        setProperty("sub-ass-override", value: value)
    }
    func toggleSubtitleVisibility() {
        subtitleVisibility.toggle()
        setProperty("sub-visibility", value: subtitleVisibility ? "yes" : "no")
    }
    func toggleSecondarySubtitleVisibility() {
        secondarySubtitleVisibility.toggle()
        setProperty("secondary-sub-visibility", value: secondarySubtitleVisibility ? "yes" : "no")
    }
    func selectSecondarySubtitle(_ track: MPVPlaybackTrack?) {
        secondarySubtitleID = track?.id
        setProperty("secondary-sid", value: track.map { String($0.id) } ?? "no")
    }
    func setAspectRatio(_ value: String) { setProperty("video-aspect-override", value: value) }
    func setRotation(_ degrees: Int) { setProperty("video-rotate", value: String(degrees)) }
    func setFileLoop(_ enabled: Bool) { setProperty("loop-file", value: enabled ? "inf" : "no") }
    func setPlaylistLoop(_ enabled: Bool) {
        isPlaylistLoopEnabled = enabled
        setProperty("loop-playlist", value: enabled ? "inf" : "no")
        updateSystemMediaControls(force: true)
    }
    func togglePlaylistLoop() { setPlaylistLoop(!isPlaylistLoopEnabled) }
    var remoteRepeatType: MPRepeatType {
        if getProperty("loop-file") == "inf" { return .one }
        if getProperty("loop-playlist") == "inf" { return .all }
        return .off
    }

    func setRemoteRepeatType(_ repeatType: MPRepeatType) {
        switch repeatType {
        case .one:
            setProperty("loop-playlist", value: "no")
            setPlaylistLoop(false)
            setFileLoop(true)
        case .all:
            setFileLoop(false)
            setPlaylistLoop(true)
        default:
            setFileLoop(false)
            setPlaylistLoop(false)
        }
        updateSystemMediaControls(force: true)
    }

    private func updateSystemMediaControls(force: Bool = false) {
        guard loadedURL != nil, !shutdownRequested else { return }
        DenboxRemotePlaybackBridge.shared.update(
            playback: self,
            title: nowPlayingTitle,
            elapsed: currentTimeSeconds,
            duration: durationSeconds,
            rate: speed,
            isPlaying: isPlaying,
            playlistCount: playlist.count,
            playlistPosition: playlistPosition,
            repeatType: remoteRepeatType,
            force: force
        )
    }
    func setHardwareDecoding(_ enabled: Bool) {
        hardwareDecodingEnabled = enabled
        setProperty("hwdec", value: enabled ? "auto-safe" : "no")
    }
    func setDeinterlacing(_ enabled: Bool) {
        isDeinterlacing = enabled
        setProperty("deinterlace", value: enabled ? "yes" : "no")
    }

    @discardableResult
    func setVerticalFlip(_ enabled: Bool) -> Bool {
        guard isVerticallyFlipped != enabled else { return true }
        guard setNamedVideoFilter(id: "denbox_iina_flip", expression: "vflip", enabled: enabled) else { return false }
        isVerticallyFlipped = enabled
        return true
    }

    @discardableResult
    func setHorizontalMirror(_ enabled: Bool) -> Bool {
        guard isHorizontallyMirrored != enabled else { return true }
        guard setNamedVideoFilter(id: "denbox_iina_mirror", expression: "hflip", enabled: enabled) else { return false }
        isHorizontallyMirrored = enabled
        return true
    }

    private func setNamedVideoFilter(id: String, expression: String, enabled: Bool) -> Bool {
        let arguments = enabled
            ? ["vf", "add", "@\(id):\(expression)"]
            : ["vf", "remove", "@\(id)"]
        return command(arguments) >= 0
    }

    private func resetVideoOrientation() {
        if isVerticallyFlipped { _ = command(["vf", "remove", "@denbox_iina_flip"]) }
        if isHorizontallyMirrored { _ = command(["vf", "remove", "@denbox_iina_mirror"]) }
        isVerticallyFlipped = false
        isHorizontallyMirrored = false
    }

    func setVideoAdjustment(_ property: String, value: Double) {
        let allowed = ["brightness", "contrast", "gamma", "hue", "saturation"]
        guard allowed.contains(property), value.isFinite else { return }
        let bounded = min(100, max(-100, value))
        switch property {
        case "brightness": videoBrightness = bounded
        case "contrast": videoContrast = bounded
        case "gamma": videoGamma = bounded
        case "hue": videoHue = bounded
        case "saturation": videoSaturation = bounded
        default: break
        }
        setProperty(property, value: String(bounded))
    }

    func setAudioEQBand(_ index: Int, gain: Double) {
        guard audioEQBands.indices.contains(index), gain.isFinite else { return }
        audioEQBands[index] = min(12, max(-12, gain))
        let frequencies = Self.equalizerFrequencies
        _ = command(["af", "remove", "@denbox_eq"])
        guard audioEQBands.contains(where: { abs($0) > 0.01 }) else { return }
        let filters = zip(frequencies, audioEQBands).map { frequency, gain in
            "equalizer=f=\(frequency):t=q:w=1:g=\(String(format: "%.2f", gain))"
        }.joined(separator: ",")
        _ = command(["af", "add", "@denbox_eq:lavfi=[\(filters)]"])
    }

    @discardableResult
    func addFilter(kind: MPVFilterKind, name: String, expression: String) -> Bool {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanExpression = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanExpression.isEmpty, cleanExpression.count <= 2048,
              !cleanExpression.contains("\n"), !cleanExpression.contains("\r") else { return false }
        let filterID = "denbox_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        guard command([kind.commandName, "add", "@\(filterID):\(cleanExpression)"]) >= 0 else { return false }
        activeFilters.append(MPVActiveFilter(
            id: filterID,
            name: cleanName.isEmpty ? cleanExpression : cleanName,
            kind: kind,
            expression: cleanExpression
        ))
        return true
    }

    @discardableResult
    func addFilter(_ preset: MPVFilterPreset) -> Bool {
        addFilter(kind: preset.kind, name: preset.name, expression: preset.expression)
    }

    @discardableResult
    func removeFilter(_ filter: MPVActiveFilter) -> Bool {
        guard command([filter.kind.commandName, "remove", "@\(filter.id)"]) >= 0 else { return false }
        activeFilters.removeAll { $0.id == filter.id }
        return true
    }

    @discardableResult
    func saveFilterPreset(name: String, kind: MPVFilterKind, expression: String) -> Bool {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanExpression = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty, cleanName.count <= 80,
              !cleanExpression.isEmpty, cleanExpression.count <= 2048,
              !cleanExpression.contains("\n"), !cleanExpression.contains("\r") else { return false }
        let preset = MPVFilterPreset(id: UUID().uuidString, name: cleanName, kind: kind, expression: cleanExpression)
        savedFilterPresets.append(preset)
        MPVFilterPresetStore.save(savedFilterPresets)
        return true
    }

    func deleteFilterPreset(_ preset: MPVFilterPreset) {
        savedFilterPresets.removeAll { $0.id == preset.id }
        MPVFilterPresetStore.save(savedFilterPresets)
    }

    func setCropAspect(_ value: String) {
        guard value != "no", let ratio = Self.aspectRatio(from: value),
              let sourceWidth = getProperty("video-params/w").flatMap(Double.init),
              let sourceHeight = getProperty("video-params/h").flatMap(Double.init),
              sourceWidth > 0, sourceHeight > 0 else {
            _ = command(["vf", "remove", "@denbox_crop"])
            return
        }
        let sourceRatio = sourceWidth / sourceHeight
        let cropWidth = sourceRatio > ratio ? sourceHeight * ratio : sourceWidth
        let cropHeight = sourceRatio > ratio ? sourceHeight : sourceWidth / ratio
        let width = max(2, Int(cropWidth.rounded(.down)) & ~1)
        let height = max(2, Int(cropHeight.rounded(.down)) & ~1)
        let x = max(0, (Int(sourceWidth.rounded(.down)) - width) / 2 & ~1)
        let y = max(0, (Int(sourceHeight.rounded(.down)) - height) / 2 & ~1)
        _ = command(["vf", "remove", "@denbox_crop"])
        _ = command(["vf", "add", "@denbox_crop:crop=\(width):\(height):\(x):\(y)"])
    }

    func selectChapter(_ index: Int) {
        guard chapters.contains(where: { $0.index == index }) else { return }
        setProperty("chapter", value: String(index))
        currentChapterIndex = index
    }

    func appendLocalFilesToPlaylist(_ urls: [URL]) {
        appendURLsToPlaylist(urls)
    }

    func appendURLsToPlaylist(_ urls: [URL]) {
        for url in urls {
            let scheme = url.scheme?.lowercased()
            guard url.isFileURL || scheme == "http" || scheme == "https" else { continue }
            _ = command(["loadfile", url.isFileURL ? url.path : url.absoluteString, "append"])
        }
        refreshPlaylist()
    }

    func savePlaylist(to url: URL) throws {
        try MPVPlaylistDocument.save(playlist, to: url)
    }

    func playPlaylistEntry(_ index: Int) {
        guard playlist.indices.contains(index) else { return }
        setProperty("playlist-pos", value: String(index))
    }

    func removePlaylistEntry(_ index: Int) {
        guard playlist.indices.contains(index), playlist.count > 1 else { return }
        _ = command(["playlist-remove", String(index)])
        refreshPlaylist()
    }

    func removeCurrentPlaylistEntryAndAdvance() -> MPVPlaybackPlaylistEntry? {
        guard playlist.indices.contains(playlistPosition) else {
            stop()
            refreshPlaylist()
            return nil
        }

        let currentIndex = playlistPosition
        _ = command(["playlist-remove", String(currentIndex)])
        if playlist.count == 1 {
            stop()
            refreshPlaylist()
            return nil
        }

        refreshPlaylist()
        return playlist.first(where: \.isCurrent)
    }

    func movePlaylistEntry(from index: Int, by offset: Int) {
        let destination = index + offset
        guard playlist.indices.contains(index), playlist.indices.contains(destination) else { return }
        _ = command(["playlist-move", String(index), String(destination)])
        refreshPlaylist()
    }

    func shufflePlaylist() {
        guard playlist.count > 1 else { return }
        _ = command(["playlist-shuffle"])
        refreshPlaylist()
    }

    func stepPlaylist(by direction: Int) {
        guard direction != 0, playlist.count > 1 else { return }
        _ = command([direction > 0 ? "playlist-next" : "playlist-prev", "force"])
    }

    func moveChapter(by offset: Int) {
        guard !chapters.isEmpty else { return }
        let current = currentChapterIndex ?? 0
        selectChapter(min(chapters.count - 1, max(0, current + offset)))
    }

    func markABLoop() {
        switch getProperty("ab-loop-a") {
        case nil, "no":
            setProperty("ab-loop-a", value: String(currentTimeSeconds))
            setProperty("ab-loop-b", value: "no")
        default:
            if getProperty("ab-loop-b") == "no" {
                setProperty("ab-loop-b", value: String(currentTimeSeconds))
            } else {
                setProperty("ab-loop-a", value: "no")
                setProperty("ab-loop-b", value: "no")
            }
        }
    }

    func clearABLoop() {
        setProperty("ab-loop-a", value: "no")
        setProperty("ab-loop-b", value: "no")
    }

    var abLoopState: Int {
        guard getProperty("ab-loop-a") != nil, getProperty("ab-loop-a") != "no" else { return 0 }
        return getProperty("ab-loop-b") == "no" ? 1 : 2
    }

    func addAudioFile(_ url: URL) {
        _ = command(["audio-add", url.path, "select"])
        refreshTracksSoon()
    }

    func addSubtitleFile(_ url: URL, asSecondary: Bool = false) {
        let previousPrimaryID = getProperty("sid") ?? "auto"
        _ = command(["sub-add", url.path, "select"])
        if asSecondary {
            refreshTracksSoon { [weak self] in
                guard let self, let selectedID = self.getProperty("sid"), Int(selectedID) != nil else { return }
                self.setProperty("secondary-sid", value: selectedID)
                self.setProperty("sid", value: previousPrimaryID)
                self.refreshTracks()
            }
        } else {
            refreshTracksSoon()
        }
    }

    func captureScreenshot(to url: URL, includeSubtitles: Bool = true) {
        if includeSubtitles {
            _ = command(["screenshot-to-file", url.path])
        } else {
            _ = command(["screenshot-to-file", url.path, "video"])
        }
    }

    func setMute(_ enabled: Bool) { setProperty("mute", value: enabled ? "yes" : "no") }
    func toggleMute() {
        isMuted.toggle()
        setMute(isMuted)
    }
    func frameStep(backward: Bool = false) { _ = command([backward ? "frame-back-step" : "frame-step"]) }
    func seekSubtitle(by offset: Int) { _ = command(["sub-seek", String(offset)]) }
    func panVideo(x: Double = 0, y: Double = 0) {
        if x.isFinite { _ = command(["add", "video-pan-x", String(x)]) }
        if y.isFinite { _ = command(["add", "video-pan-y", String(y)]) }
    }
    func zoomVideo(by value: Double) {
        guard value.isFinite else { return }
        _ = command(["add", "video-zoom", String(value)])
    }
    func setPanscan(_ value: Double) {
        guard value.isFinite else { return }
        setProperty("panscan", value: String(min(1, max(0, value))))
    }
    func cycleAspectRatio() {
        let values = ["no", "16:9", "4:3", "2.35:1"]
        let current = getProperty("video-aspect-override") ?? "no"
        let next = ((values.firstIndex(of: current) ?? 0) + 1) % values.count
        setAspectRatio(values[next])
    }
    func cycleSubtitleTrack(direction: Int = 1) {
        let tracks = subtitleOptions
        let selected = tracks.firstIndex(where: \.isSelected)
        let count = tracks.count + 1
        guard count > 0 else { return }
        let start = selected.map { $0 + 1 } ?? 0
        let index = (start + direction % count + count) % count
        if index == tracks.count { selectSubtitle(nil) }
        else { selectSubtitle(tracks[index]) }
    }
    func cycleAudioTrack(direction: Int = 1) { selectNextTrack(audioOptions, property: "aid", direction: direction) }
    func cycleVideoTrack(direction: Int = 1) { selectNextTrack(videoOptions, property: "vid", direction: direction) }
    func cycleEdition() { _ = command(["cycle", "edition"]) }

    private func selectNextTrack(_ tracks: [MPVPlaybackTrack], property: String, direction: Int) {
        guard !tracks.isEmpty else { return }
        let currentID = getProperty(property).flatMap(Int.init)
        let selectedIndex = tracks.firstIndex { $0.id == currentID } ?? tracks.firstIndex(where: \.isSelected)
        let start = selectedIndex.map { $0 + 1 } ?? 0
        let next = (start + direction % tracks.count + tracks.count) % tracks.count
        setProperty(property, value: String(tracks[next].id))
        refreshTracks()
    }

    func handleKeyboardShortcut(
        keyCode: UInt16,
        characters: String,
        modifiers: NSEvent.ModifierFlags,
        charactersWithModifiers: String? = nil
    ) -> Bool {
        let flags = modifiers.intersection(.deviceIndependentFlagsMask)
        let command = flags.contains(.command)
        let control = flags.contains(.control)
        let option = flags.contains(.option)
        let shift = flags.contains(.shift)
        // The event character follows the active input source. Resolve known keys by
        // their hardware code so the standard shortcuts work with Persian layouts too.
        let key = MPVInputKeyMapper.usLayoutCharacter(for: keyCode)?.lowercased() ?? characters.lowercased()

        if UserDefaults.standard.bool(forKey: DenboxMPVConfiguration.useInputConfigurationKey),
           !(command && control && key == "f") {
            guard let mpvKey = MPVInputKeyMapper.keyName(
                keyCode: keyCode,
                charactersIgnoringModifiers: characters,
                characters: charactersWithModifiers,
                modifiers: flags
            ) else { return false }
            return self.command(["keypress", mpvKey]) >= 0
        }

        if command && control && !option && !shift {
            switch key {
            case "f": onToggleFullscreen?(); return true
            case "v": cycleVideoTrack(); return true
            case "a": cycleAudioTrack(); return true
            case "s": cycleSubtitleTrack(); return true
            case "p": onTogglePictureInPicture?(); return true
            case "t": toggleAlwaysOnTop(); return true
            default: return false
            }
        }
        if command && !control && !option && !shift && key == "d" {
            onFindOnlineSubtitles?()
            return true
        }
        if command && !control && !option && !shift {
            switch key {
            case "0": onSetWindowScale?(0.5); return true
            case "1": onSetWindowScale?(1); return true
            case "2": onSetWindowScale?(2); return true
            case "3": fitWindowToScreen(); return true
            default: break
            }
        }
        if command && option && !control && !shift && key == "m" {
            toggleMusicMode()
            return true
        }
        if command && shift && !option && keyCode == 47 { moveChapter(by: 1); return true }
        if command && shift && !option && keyCode == 43 { moveChapter(by: -1); return true }
        if command && !shift && !option && keyCode == 47 { stop(); return true }
        if command && key == "s" { onScreenshotRequested?(shift); return true }
        if command && key == "l" {
            if shift { setFileLoop(getProperty("loop-file") != "inf") }
            else { markABLoop() }
            return true
        }
        if command && key == "/" { toggleMute(); return true }
        if command && key == "[" {
            setSpeed(max(0.25, speed * (option ? 0.9091 : 0.5)))
            return true
        }
        if command && key == "]" {
            setSpeed(min(4, speed * (option ? 1.1 : 2)))
            return true
        }
        if command && key == "\\" { setSpeed(1); return true }
        if command && keyCode == 123 { stepPlaylist(by: -1); return true }
        if command && keyCode == 124 { stepPlaylist(by: 1); return true }
        if control && key == "h" { setHardwareDecoding(!hardwareDecodingEnabled); return true }

        if !command && !control && shift {
            if keyCode == 116 { seek(by: 600); return true }
            if keyCode == 121 { seek(by: -600); return true }
            if !option && keyCode == 14 { cycleEdition(); return true }
            if keyCode == 25 { setAudioDelay(audioDelaySeconds + (option ? 0.1 : 0.5)); return true }
            if keyCode == 29 { setAudioDelay(audioDelaySeconds - (option ? 0.1 : 0.5)); return true }
            if keyCode == 27 { setAudioDelay(0); return true }
        }
        if !command && !control && option && keyCode == 123 { frameStep(backward: true); return true }
        if !command && !control && option && keyCode == 124 { frameStep(); return true }
        if !command && !control && option && keyCode == 126 { setVolume(volume + 1); return true }
        if !command && !control && option && keyCode == 125 { setVolume(volume - 1); return true }
        if !command && control && option {
            switch keyCode {
            case 123: panVideo(x: -0.1); return true
            case 124: panVideo(x: 0.1); return true
            case 126: panVideo(y: -0.1); return true
            case 125: panVideo(y: 0.1); return true
            default: break
            }
        }
        if control || command { return false }
        if shift && keyCode == 20 { cycleAudioTrack(); return true }
        if shift && keyCode == 27 { cycleVideoTrack(); return true }
        switch keyCode {
        case 49: togglePlayPause(); return true
        case 123:
            if shift { seekSubtitle(by: -1) }
            else { seek(by: -5) }
            return true
        case 124:
            if shift { seekSubtitle(by: 1) }
            else { seek(by: 5) }
            return true
        case 126:
            setVolume(volume + (shift ? 1 : 5))
            return true
        case 125:
            setVolume(volume - (shift ? 1 : 5))
            return true
        case 53:
            exitFullscreen()
            return true
        case 36:
            enterFullscreen()
            return true
        case 51:
            onToggleControls?()
            return true
        default: break
        }

        if option && (key == "+" || key == "=") { zoomVideo(by: 0.1); return true }
        if option && key == "-" { zoomVideo(by: -0.1); return true }
        switch key {
        case "q": onCloseRequested?()
        case "p": togglePlayPause()
        case "m": toggleMute()
        case "f": onToggleFullscreen?()
        case "s": onScreenshotRequested?(shift)
        case "j": cycleSubtitleTrack(direction: shift ? -1 : 1)
        case "v": if option { toggleSecondarySubtitleVisibility() } else { toggleSubtitleVisibility() }
        case "d": setDeinterlacing(!isDeinterlacing)
        case "l": markABLoop()
        case "r": setSubtitlePosition(subtitlePosition - 1)
        case "t": setSubtitlePosition(subtitlePosition + 1)
        case "z": setSubtitleDelay(subtitleDelaySeconds - (option ? 0.1 : 0.5))
        case "x": setSubtitleDelay(subtitleDelaySeconds + (option ? 0.1 : 0.5))
        case "c": setSubtitleDelay(0)
        case "a": if shift { cycleAspectRatio() } else { return false }
        case "i": onTogglePlaybackInfo?()
        case "o": onTogglePlaybackInfo?()
        case ".": frameStep()
        case ",": frameStep(backward: true)
        case "w": setPanscan(getProperty("panscan").flatMap(Double.init).map { $0 + (shift ? 0.1 : -0.1) } ?? 0.1)
        case "1": setVideoAdjustment("contrast", value: videoContrast - 1)
        case "2": setVideoAdjustment("contrast", value: videoContrast + 1)
        case "3": setVideoAdjustment("brightness", value: videoBrightness - 1)
        case "4": setVideoAdjustment("brightness", value: videoBrightness + 1)
        case "5": setVideoAdjustment("gamma", value: videoGamma - 1)
        case "6": setVideoAdjustment("gamma", value: videoGamma + 1)
        case "7": setVideoAdjustment("saturation", value: videoSaturation - 1)
        case "8": setVideoAdjustment("saturation", value: videoSaturation + 1)
        default: return false
        }
        return true
    }

    private func startEventLoop(_ handleBox: MPVHandleBox) {
        DispatchQueue.global(qos: .userInitiated).async { [self, handleBox] in
            while true {
                guard let event = mpv_wait_event(handleBox.handle, 0.25) else { continue }
                let eventID = event.pointee.event_id
                if eventID == MPV_EVENT_SHUTDOWN { break }
                if eventID == MPV_EVENT_FILE_LOADED {
                    Task { @MainActor [weak self] in self?.fileDidLoad() }
                } else if eventID == MPV_EVENT_END_FILE,
                          let data = event.pointee.data?.assumingMemoryBound(to: mpv_event_end_file.self).pointee,
                          data.reason == MPV_END_FILE_REASON_EOF.rawValue {
                    Task { @MainActor [weak self] in
                        self?.isLoading = false
                        self?.isPlaying = false
                        self?.lastWatchTick = nil
                        self?.flushPendingWatchTime()
                        self?.didReachEnd = true
                        self?.updateSystemMediaControls(force: true)
                    }
                } else if eventID == MPV_EVENT_END_FILE,
                          let data = event.pointee.data?.assumingMemoryBound(to: mpv_event_end_file.self).pointee,
                          data.reason == MPV_END_FILE_REASON_ERROR.rawValue {
                    let errorCode = Int32(data.error)
                    Task { @MainActor [weak self] in
                        let message = Self.errorText(errorCode)
                        self?.isLoading = false
                        self?.isPlaying = false
                        self?.errorMessage = "Playback failed: \(message)"
                        if let self { DenboxRemotePlaybackBridge.shared.deactivate(self) }
                    }
                }
            }
        }
    }

    private func fileDidLoad() {
        isLoading = false
        isPlaying = true
        didReachEnd = false
        trackRefreshAt = .distantPast
        if pendingResumeSeconds > 0 {
            setProperty("time-pos", value: String(pendingResumeSeconds))
            pendingResumeSeconds = 0
        }
        refreshTracks()
        refreshPlaylist()
        refreshAudioDevices(force: true)
        updateSystemMediaControls(force: true)
    }

    private func refreshState() {
        guard handle != nil else { return }
        refreshAudioDevices()
        currentTimeSeconds = getProperty("time-pos").flatMap(Double.init).map { max(0, $0) } ?? currentTimeSeconds
        durationSeconds = getProperty("duration").flatMap(Double.init).flatMap { $0 > 0 ? $0 : nil }
        volume = getProperty("volume").flatMap(Double.init) ?? volume
        isMuted = getProperty("mute") == "yes"
        speed = getProperty("speed").flatMap(Double.init) ?? speed
        audioDelaySeconds = getProperty("audio-delay").flatMap(Double.init) ?? audioDelaySeconds
        subtitleDelaySeconds = getProperty("sub-delay").flatMap(Double.init) ?? subtitleDelaySeconds
        if let currentEncoding = getProperty("sub-codepage"),
           let option = MPVSubtitleEncoding.options.first(where: {
               $0.codepage.caseInsensitiveCompare(currentEncoding) == .orderedSame
           }) {
            subtitleEncoding = option.codepage
        }
        subtitleScale = getProperty("sub-scale").flatMap(Double.init) ?? subtitleScale
        subtitlePosition = getProperty("sub-pos").flatMap(Double.init) ?? subtitlePosition
        subtitleBorderSize = getProperty("sub-border-size").flatMap(Double.init) ?? subtitleBorderSize
        subtitleFontSize = getProperty("sub-font-size").flatMap(Double.init) ?? subtitleFontSize
        subtitleVisibility = getProperty("sub-visibility") != "no"
        secondarySubtitleVisibility = getProperty("secondary-sub-visibility") != "no"
        secondarySubtitleID = getProperty("secondary-sid").flatMap(Int.init)
        isDeinterlacing = getProperty("deinterlace") == "yes"
        let playlistLoop = getProperty("loop-playlist") ?? "no"
        isPlaylistLoopEnabled = playlistLoop != "no" && playlistLoop != "0"
        hardwareDecodingEnabled = getProperty("hwdec") != "no"
        videoBrightness = getProperty("brightness").flatMap(Double.init) ?? videoBrightness
        videoContrast = getProperty("contrast").flatMap(Double.init) ?? videoContrast
        videoGamma = getProperty("gamma").flatMap(Double.init) ?? videoGamma
        videoHue = getProperty("hue").flatMap(Double.init) ?? videoHue
        videoSaturation = getProperty("saturation").flatMap(Double.init) ?? videoSaturation
        currentChapterIndex = getProperty("chapter").flatMap(Int.init)
        let paused = getProperty("pause") == "yes"
        let idle = getProperty("idle-active") == "yes"
        let waitingForCache = getProperty("paused-for-cache") == "yes"
        cacheBufferingPercent = min(100, max(0, getProperty("cache-buffering-state").flatMap(Double.init) ?? 0))
        let seeking = getProperty("seeking") == "yes"
        let coreIdle = getProperty("core-idle") == "yes"
        isBuffering = !isLoading && waitingForCache
        // Count viewing time only while mpv's playback core is actually advancing media.
        isPlaying = !isLoading && errorMessage == nil
            && !paused && !idle && !waitingForCache && !seeking && !coreIdle
        updateSystemPictureInPicturePlayingState()
        updateSystemMediaControls()

        guard isPlaying else {
            flushPendingWatchTime()
            lastWatchTick = nil
            return
        }
        let now = Date()
        if let lastWatchTick { pendingWatchedSeconds += min(0.5, max(0, now.timeIntervalSince(lastWatchTick))) }
        lastWatchTick = now
        if pendingWatchedSeconds >= 10 { flushPendingWatchTime() }
        if Date().timeIntervalSince(trackRefreshAt) >= 1.5 {
            refreshTracks()
            refreshPlaylist()
        }
    }

    private func refreshTracks() {
        guard handle != nil else { return }
        trackRefreshAt = Date()
        let count = min(64, max(0, Int(getProperty("track-list/count") ?? "0") ?? 0))
        var video: [MPVPlaybackTrack] = []
        var audio: [MPVPlaybackTrack] = []
        var subtitles: [MPVPlaybackTrack] = []
        for index in 0..<count {
            let prefix = "track-list/\(index)"
            guard let id = getProperty("\(prefix)/id").flatMap(Int.init),
                  let type = getProperty("\(prefix)/type") else { continue }
            let title = getProperty("\(prefix)/title").flatMap { $0.isEmpty ? nil : $0 }
            let language = getProperty("\(prefix)/lang").flatMap { $0.isEmpty ? nil : $0 }
            let displayName = [title, language].compactMap { $0 }.joined(separator: " · ")
            let track: MPVPlaybackTrack?
            if type == "video" {
                track = MPVPlaybackTrack(id: id, kind: .video, displayName: displayName.isEmpty ? "Video \(id)" : displayName,
                                         isSelected: getProperty("\(prefix)/selected") == "yes", isSecondarySelected: false)
            } else if type == "audio" {
                track = MPVPlaybackTrack(id: id, kind: .audio, displayName: displayName.isEmpty ? "Audio \(id)" : displayName,
                                         isSelected: getProperty("\(prefix)/selected") == "yes", isSecondarySelected: false)
            } else if type == "sub" {
                track = MPVPlaybackTrack(id: id, kind: .subtitle, displayName: displayName.isEmpty ? "Subtitle \(id)" : displayName,
                                         isSelected: getProperty("\(prefix)/selected") == "yes",
                                         isSecondarySelected: getProperty("secondary-sid").flatMap(Int.init) == id)
            } else {
                track = nil
            }
            guard let track else { continue }
            switch track.kind {
            case .video: video.append(track)
            case .audio: audio.append(track)
            case .subtitle: subtitles.append(track)
            }
        }
        videoOptions = video
        audioOptions = audio
        subtitleOptions = subtitles
        let chapterCount = min(256, max(0, Int(getProperty("chapter-list/count") ?? "0") ?? 0))
        chapters = (0..<chapterCount).map { index in
            let title = getProperty("chapter-list/\(index)/title").flatMap { $0.isEmpty ? nil : $0 }
            let time = getProperty("chapter-list/\(index)/time").flatMap(Double.init) ?? 0
            return MPVPlaybackChapter(index: index, title: title ?? "Chapter \(index + 1)", timeSeconds: time)
        }
    }

    private func reloadExternalSubtitleTracks() {
        guard handle != nil else { return }
        let selectedID = getProperty("sid").flatMap(Int.init)
        let secondaryID = getProperty("secondary-sid").flatMap(Int.init)
        let selectedFilename = selectedID.flatMap(externalSubtitleFilename(forTrackID:))
        let secondaryFilename = secondaryID.flatMap(externalSubtitleFilename(forTrackID:))
        let count = min(64, max(0, Int(getProperty("track-list/count") ?? "0") ?? 0))
        let externalSubtitleIDs = (0..<count).compactMap { index -> Int? in
            let prefix = "track-list/\(index)"
            guard getProperty("\(prefix)/type") == "sub",
                  getProperty("\(prefix)/external") == "yes" else { return nil }
            return getProperty("\(prefix)/id").flatMap(Int.init)
        }

        for id in externalSubtitleIDs {
            _ = command(["sub-reload", String(id)])
        }
        refreshTracks()

        if let selectedFilename,
           let reloadedID = externalSubtitleTrackID(forFilename: selectedFilename) {
            setProperty("sid", value: String(reloadedID))
        } else if let selectedID, subtitleOptions.contains(where: { $0.id == selectedID }) {
            setProperty("sid", value: String(selectedID))
        }
        if let secondaryFilename,
           let reloadedID = externalSubtitleTrackID(forFilename: secondaryFilename) {
            setProperty("secondary-sid", value: String(reloadedID))
        } else if let secondaryID, subtitleOptions.contains(where: { $0.id == secondaryID }) {
            setProperty("secondary-sid", value: String(secondaryID))
        }
        refreshTracks()
    }

    private func externalSubtitleFilename(forTrackID id: Int) -> String? {
        let count = min(64, max(0, Int(getProperty("track-list/count") ?? "0") ?? 0))
        for index in 0..<count {
            let prefix = "track-list/\(index)"
            guard getProperty("\(prefix)/id").flatMap(Int.init) == id,
                  getProperty("\(prefix)/type") == "sub",
                  getProperty("\(prefix)/external") == "yes" else { continue }
            return getProperty("\(prefix)/external-filename")
        }
        return nil
    }

    private func externalSubtitleTrackID(forFilename filename: String) -> Int? {
        let count = min(64, max(0, Int(getProperty("track-list/count") ?? "0") ?? 0))
        for index in 0..<count {
            let prefix = "track-list/\(index)"
            guard getProperty("\(prefix)/type") == "sub",
                  getProperty("\(prefix)/external") == "yes",
                  getProperty("\(prefix)/external-filename") == filename else { continue }
            return getProperty("\(prefix)/id").flatMap(Int.init)
        }
        return nil
    }

    private func refreshPlaylist() {
        guard handle != nil else { return }
        let count = min(512, max(0, Int(getProperty("playlist/count") ?? "0") ?? 0))
        playlistPosition = max(0, Int(getProperty("playlist-pos") ?? "0") ?? 0)
        playlist = (0..<count).map { index in
            let prefix = "playlist/\(index)"
            let filename = getProperty("\(prefix)/filename") ?? ""
            let title = getProperty("\(prefix)/title").flatMap { $0.isEmpty ? nil : $0 }
                ?? URL(string: filename)?.deletingPathExtension().lastPathComponent
                ?? URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent
            return MPVPlaybackPlaylistEntry(index: index, title: title.isEmpty ? filename : title,
                                            filename: filename, isCurrent: index == playlistPosition)
        }
    }

    private func refreshAudioDevices(force: Bool = false) {
        guard let handle else { return }
        guard force || Date().timeIntervalSince(audioDeviceRefreshAt) >= 5 else { return }
        audioDeviceRefreshAt = Date()

        var node = mpv_node()
        let result = "audio-device-list".withCString {
            mpv_get_property(handle, $0, MPV_FORMAT_NODE, &node)
        }
        guard result >= 0 else { return }
        defer { mpv_free_node_contents(&node) }
        guard node.format == MPV_FORMAT_NODE_ARRAY, let list = node.u.list else { return }

        var devices = [MPVPlaybackAudioDevice(id: "auto", displayName: "System default", isDefault: true)]
        let itemCount = min(64, max(0, Int(list.pointee.num)))
        if itemCount > 0, let values = list.pointee.values {
            for index in 0..<itemCount {
                let item = values[index]
                guard item.format == MPV_FORMAT_NODE_MAP, let fields = item.u.list,
                      let keys = fields.pointee.keys, let fieldValues = fields.pointee.values else { continue }

                var identifier: String?
                var description: String?
                var isDefault = false
                for fieldIndex in 0..<min(16, max(0, Int(fields.pointee.num))) {
                    guard let keyPointer = keys[fieldIndex] else { continue }
                    let key = String(cString: keyPointer)
                    let value = fieldValues[fieldIndex]
                    if key == "name", value.format == MPV_FORMAT_STRING, let pointer = value.u.string {
                        identifier = String(cString: pointer)
                    } else if key == "description", value.format == MPV_FORMAT_STRING, let pointer = value.u.string {
                        description = String(cString: pointer)
                    } else if key == "is-default", value.format == MPV_FORMAT_FLAG {
                        isDefault = value.u.flag != 0
                    }
                }

                guard let identifier, !identifier.isEmpty, identifier != "auto",
                      !devices.contains(where: { $0.id == identifier }) else { continue }
                devices.append(MPVPlaybackAudioDevice(
                    id: identifier,
                    displayName: description.flatMap { $0.isEmpty ? nil : $0 } ?? identifier,
                    isDefault: isDefault
                ))
            }
        }
        audioDevices = devices.sorted { left, right in
            if left.id == "auto" { return true }
            if right.id == "auto" { return false }
            return left.displayName.localizedCaseInsensitiveCompare(right.displayName) == .orderedAscending
        }
        let current = getProperty("audio-device").flatMap { $0.isEmpty ? nil : $0 } ?? "auto"
        selectedAudioDeviceID = audioDevices.contains(where: { $0.id == current }) ? current : "auto"
    }

    private func refreshTracksSoon(after: (() -> Void)? = nil) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self else { return }
            self.refreshTracks()
            after?()
        }
    }

    private static let equalizerFrequencies = [31, 62, 125, 250, 500, 1_000, 2_000, 4_000, 8_000, 16_000]

    private static func aspectRatio(from value: String) -> Double? {
        let parts = value.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, let width = Double(parts[0]), let height = Double(parts[1]),
              width > 0, height > 0 else { return nil }
        return width / height
    }

    private func setProperty(_ name: String, value: String) {
        guard let handle else { return }
        _ = name.withCString { key in value.withCString { mpv_set_property_string(handle, key, $0) } }
    }

    private func schedulePreferredLanguageUpdate() {
        preferredLanguageUpdateTask?.cancel()
        preferredLanguageUpdateTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled, let self else { return }
            self.applyPreferredLanguageChanges()
            self.preferredLanguageUpdateTask = nil
        }
    }

    private func applyPreferredLanguageChanges() {
        let audioPreference = UserDefaults.standard.string(
            forKey: DenboxMPVConfiguration.preferredAudioLanguagesKey
        )
        if audioPreference != appliedPreferredAudioLanguages {
            appliedPreferredAudioLanguages = audioPreference
            let value = DenboxMPVConfiguration.preferredLanguageList(
                forKey: DenboxMPVConfiguration.preferredAudioLanguagesKey
            ) ?? ""
            setProperty("alang", value: value)
        }

        let subtitlePreference = UserDefaults.standard.string(
            forKey: DenboxMPVConfiguration.preferredSubtitleLanguagesKey
        )
        if subtitlePreference != appliedPreferredSubtitleLanguages {
            appliedPreferredSubtitleLanguages = subtitlePreference
            let value = DenboxMPVConfiguration.preferredLanguageList(
                forKey: DenboxMPVConfiguration.preferredSubtitleLanguagesKey
            ) ?? ""
            setProperty("slang", value: value)
        }
    }

    private func getProperty(_ name: String) -> String? {
        guard let handle else { return nil }
        guard let pointer = name.withCString({ mpv_get_property_string(handle, $0) }) else { return nil }
        let value = String(cString: pointer)
        mpv_free(UnsafeMutableRawPointer(pointer))
        return value
    }

#if DENBOX_TESTING
    func testingProperty(_ name: String) -> String? { getProperty(name) }
#endif

    private func command(_ arguments: [String]) -> Int32 {
        guard let handle else { return -1 }
        let owned = arguments.map { strdup($0) }
        defer { owned.forEach { if let pointer = $0 { free(pointer) } } }
        var pointers: [UnsafePointer<CChar>?] = owned.map { pointer in
            guard let pointer else { return nil }
            return UnsafePointer<CChar>(pointer)
        }
        pointers.append(nil)
        return pointers.withUnsafeMutableBufferPointer { mpv_command(handle, $0.baseAddress) }
    }

    private func flushPendingWatchTime() {
        let delta = pendingWatchedSeconds
        pendingWatchedSeconds = 0
        onProgress?(currentTimeSeconds, durationSeconds, delta)
    }

    private static func errorText(_ code: Int32) -> String {
        guard let pointer = mpv_error_string(code) else { return "Error code \(code)" }
        return String(cString: pointer)
    }
}

@MainActor
private final class DenboxSystemPictureInPictureDelegate: NSObject {
    weak var owner: MPVPlaybackController?

    init(owner: MPVPlaybackController) {
        self.owner = owner
        super.init()
    }

    @objc(pipWillClose:)
    func pipWillClose(_ controller: AnyObject) {
        owner?.prepareSystemPictureInPictureClose(using: controller)
    }

    @objc(pipShouldClose:)
    func pipShouldClose(_ controller: AnyObject) -> Bool {
        owner?.prepareSystemPictureInPictureClose(using: controller)
        return true
    }

    @objc(pipDidClose:)
    func pipDidClose(_ controller: AnyObject) {
        owner?.finishSystemPictureInPicture()
    }

    @objc(pipActionPlay:)
    func pipActionPlay(_ controller: AnyObject) {
        owner?.setPlaybackPausedByPictureInPicture(false)
    }

    @objc(pipActionPause:)
    func pipActionPause(_ controller: AnyObject) {
        owner?.setPlaybackPausedByPictureInPicture(true)
    }

    @objc(pipActionStop:)
    func pipActionStop(_ controller: AnyObject) {
        owner?.setPlaybackPausedByPictureInPicture(true)
    }
}

private let openGLFramework = dlopen("/System/Library/Frameworks/OpenGL.framework/OpenGL", RTLD_LAZY | RTLD_LOCAL)

private let mpvOpenGLGetProcAddress: @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?) -> UnsafeMutableRawPointer? = { _, name in
    guard let openGLFramework, let name else { return nil }
    return dlsym(openGLFramework, name)
}

struct MPVVideoView: NSViewRepresentable {
    @ObservedObject var controller: MPVPlaybackController

    func makeNSView(context: Context) -> MPVRenderView {
        let view = MPVRenderView(frame: .zero, controller: controller)!
        controller.registerRenderView(view)
        return view
    }

    func updateNSView(_ view: MPVRenderView, context: Context) {
        view.controller = controller
        controller.registerRenderView(view)
        view.needsDisplay = true
    }

    static func dismantleNSView(_ view: MPVRenderView, coordinator: ()) {
        view.detach()
    }
}

final class MPVRenderView: NSOpenGLView {
    var controller: MPVPlaybackController
    private var redrawTimer: Timer?
    private var keyEventMonitor: Any?
    private var pointerActivityEventMonitor: Any?
    private weak var inputWindow: NSWindow?
    private var previousMouseMoveSetting: Bool?
    private var viewTrackingArea: NSTrackingArea?
    private var lastPointerSample: CGPoint?
    private var hasRenderedFrame = false

    init?(frame frameRect: NSRect, controller: MPVPlaybackController) {
        self.controller = controller
        let attributes: [NSOpenGLPixelFormatAttribute] = [
            NSOpenGLPixelFormatAttribute(NSOpenGLPFAAccelerated),
            NSOpenGLPixelFormatAttribute(NSOpenGLPFADoubleBuffer),
            NSOpenGLPixelFormatAttribute(NSOpenGLPFAOpenGLProfile),
            NSOpenGLPixelFormatAttribute(NSOpenGLProfileVersion3_2Core),
            0
        ]
        guard let pixelFormat = NSOpenGLPixelFormat(attributes: attributes) else { return nil }
        super.init(frame: frameRect, pixelFormat: pixelFormat)
        wantsBestResolutionOpenGLSurface = true
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.samplePointerActivity()
            self?.needsDisplay = true
        }
        RunLoop.main.add(timer, forMode: .common)
        redrawTimer = timer
    }

    required init?(coder: NSCoder) { nil }

    deinit {
        if let keyEventMonitor { NSEvent.removeMonitor(keyEventMonitor) }
        if let pointerActivityEventMonitor { NSEvent.removeMonitor(pointerActivityEventMonitor) }
        if let inputWindow, let previousMouseMoveSetting {
            inputWindow.acceptsMouseMovedEvents = previousMouseMoveSetting
        }
    }

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil, let openGLContext {
            openGLContext.update()
            controller.attachRenderer(using: openGLContext)
            needsDisplay = true
        }
        controller.setPlayerWindow(window)
        lastPointerSample = nil
        if let previous = inputWindow, let previousMouseMoveSetting {
            previous.acceptsMouseMovedEvents = previousMouseMoveSetting
        }
        inputWindow = window
        previousMouseMoveSetting = window?.acceptsMouseMovedEvents
        window?.acceptsMouseMovedEvents = true
        if window != nil { window?.makeFirstResponder(self) }
        if let keyEventMonitor { NSEvent.removeMonitor(keyEventMonitor) }
        keyEventMonitor = nil
        if let pointerActivityEventMonitor { NSEvent.removeMonitor(pointerActivityEventMonitor) }
        pointerActivityEventMonitor = nil
        if window != nil {
            keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, event.window === self.window else { return event }
                self.controller.onUserActivity?()
                return self.controller.handleKeyboardShortcut(
                    keyCode: event.keyCode,
                    characters: event.charactersIgnoringModifiers ?? "",
                    modifiers: event.modifierFlags,
                    charactersWithModifiers: event.characters
                ) ? nil : event
            }
            pointerActivityEventMonitor = NSEvent.addLocalMonitorForEvents(
                matching: [
                    .mouseMoved,
                    .leftMouseDown, .rightMouseDown, .otherMouseDown,
                    .leftMouseUp, .rightMouseUp, .otherMouseUp,
                    .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
                    .scrollWheel
                ]
            ) { [weak self] event in
                guard let self, event.window === self.window else { return event }
                self.controller.onUserActivity?()
                return event
            }
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let viewTrackingArea { removeTrackingArea(viewTrackingArea) }
        let tracking = NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(tracking)
        viewTrackingArea = tracking
    }

    override func mouseMoved(with event: NSEvent) {
        controller.onUserActivity?()
    }

    override func mouseEntered(with event: NSEvent) {
        controller.onUserActivity?()
    }

    private func samplePointerActivity() {
        guard let window, window.isKeyWindow else {
            lastPointerSample = nil
            return
        }

        let location = NSEvent.mouseLocation
        let moved = PlayerControlsAutoHidePolicy.pointerMoved(from: lastPointerSample, to: location)
        lastPointerSample = location
        guard window.frame.contains(location), moved else { return }
        controller.onUserActivity?()
    }

    override func prepareOpenGL() {
        super.prepareOpenGL()
        guard let openGLContext else { return }
        openGLContext.makeCurrentContext()
        controller.attachRenderer(using: openGLContext)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let openGLContext else { return }
        openGLContext.makeCurrentContext()
        let scale = window?.backingScaleFactor ?? 1
        if controller.render(width: Int32(bounds.width * scale), height: Int32(bounds.height * scale), force: hasRenderedFrame) {
            hasRenderedFrame = true
            openGLContext.flushBuffer()
            controller.reportSwap()
        } else if !hasRenderedFrame {
            glClearColor(0, 0, 0, 1)
            glClear(GLbitfield(GL_COLOR_BUFFER_BIT))
            openGLContext.flushBuffer()
        }
    }

    override func reshape() {
        super.reshape()
        openGLContext?.update()
        openGLContext?.makeCurrentContext()
        needsDisplay = true
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        openGLContext?.update()
        openGLContext?.makeCurrentContext()
        needsDisplay = true
    }

    func detach() {
        redrawTimer?.invalidate()
        redrawTimer = nil
        if let keyEventMonitor { NSEvent.removeMonitor(keyEventMonitor) }
        keyEventMonitor = nil
        if let pointerActivityEventMonitor { NSEvent.removeMonitor(pointerActivityEventMonitor) }
        pointerActivityEventMonitor = nil
        if let inputWindow, let previousMouseMoveSetting {
            inputWindow.acceptsMouseMovedEvents = previousMouseMoveSetting
        }
        inputWindow = nil
        previousMouseMoveSetting = nil
        controller.setPlayerWindow(nil)
        controller.registerRenderView(nil)
        openGLContext?.makeCurrentContext()
        controller.detachRenderer()
    }

    override func keyDown(with event: NSEvent) {
        controller.onUserActivity?()
        if !controller.handleKeyboardShortcut(keyCode: event.keyCode,
                                              characters: event.charactersIgnoringModifiers ?? "",
                                              modifiers: event.modifierFlags,
                                              charactersWithModifiers: event.characters) {
            super.keyDown(with: event)
        }
    }
}
