import AppKit
import Darwin
import MPV
import OpenGL.GL
import OpenGL.GL3
import SwiftUI

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
    let isCurrent: Bool
    var id: Int { index }
}

struct MPVPlaybackAudioDevice: Identifiable, Hashable {
    let id: String
    let displayName: String
    let isDefault: Bool
}

private struct MPVHandleBox: @unchecked Sendable {
    let handle: OpaquePointer
}

@MainActor
final class MPVPlaybackController: ObservableObject {
    @Published private(set) var isLoading = false
    @Published private(set) var isPlaying = false
    @Published private(set) var isBuffering = false
    @Published private(set) var cacheBufferingPercent = 0.0
    @Published private(set) var didReachEnd = false
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
    @Published private(set) var subtitleScale = 1.0
    @Published private(set) var subtitlePosition = 100.0
    @Published private(set) var subtitleBorderSize = 3.0
    @Published private(set) var subtitleFontSize = 55.0
    @Published private(set) var subtitleVisibility = true
    @Published private(set) var secondarySubtitleID: Int?
    @Published private(set) var secondarySubtitleVisibility = true
    @Published private(set) var isDeinterlacing = false
    @Published private(set) var hardwareDecodingEnabled = true
    @Published private(set) var videoBrightness = 0.0
    @Published private(set) var videoContrast = 0.0
    @Published private(set) var videoGamma = 0.0
    @Published private(set) var videoHue = 0.0
    @Published private(set) var videoSaturation = 0.0
    @Published private(set) var audioEQBands = Array(repeating: 0.0, count: 10)
    @Published private(set) var volume = 100.0
    @Published private(set) var isMuted = false
    @Published private(set) var speed = 1.0
    let subtitlesCanBeDisabled = true

    private var handle: OpaquePointer?
    private var renderContext: OpaquePointer?
    private weak var glContext: NSOpenGLContext?
    private weak var playerWindow: NSWindow?
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
    var onProgress: ((Double, Double?, Double) -> Void)?
    var onUserActivity: (() -> Void)?
    var onToggleFullscreen: (() -> Void)?
    var onScreenshotRequested: ((Bool) -> Void)?
    var onCloseRequested: (() -> Void)?
    var onTogglePlaybackInfo: (() -> Void)?
    var onToggleControls: (() -> Void)?

    init() {
        guard let handle = mpv_create() else {
            errorMessage = "The embedded playback engine could not be created."
            return
        }
        self.handle = handle

        let options: [(String, String)] = [
            ("vo", "libmpv"),
            ("hwdec", "auto-safe"),
            ("keep-open", "yes"),
            ("audio-display", "no"),
            ("config", "no"),
            ("osc", "no"),
            ("osd-level", "1"),
            ("cache", "yes"),
            ("cache-secs", "45"),
            ("cache-pause", "yes"),
            ("cache-pause-initial", "yes"),
            ("cache-pause-wait", "8"),
            ("demuxer-max-bytes", "512MiB"),
            ("demuxer-max-back-bytes", "128MiB"),
            ("sub-auto", "fuzzy"),
            ("sub-font-provider", "auto"),
            ("screenshot-directory", "~/Pictures/Denbox")
        ]
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
        if let handle { mpv_terminate_destroy(handle) }
    }

    func shutdown() {
        guard !shutdownRequested else { return }
        shutdownRequested = true
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
        playerWindow = window
        window?.collectionBehavior.insert(.fullScreenPrimary)
    }

    func toggleFullscreen() {
        // Prefer the key window because SwiftUI can replace its window while
        // moving a WindowGroup scene. The render view's weak reference can
        // briefly point at the previous window during that transition.
        guard let window = [NSApp.keyWindow, playerWindow, NSApp.mainWindow]
            .compactMap({ $0 })
            .first(where: \.isVisible) else { return }
        window.collectionBehavior.insert(.fullScreenPrimary)
        // AppKit may ignore a fullscreen request issued in the middle of a
        // SwiftUI button update. Schedule it on the next main-loop turn after
        // making the visible player window key.
        DispatchQueue.main.async { [weak window] in
            guard let window, window.isVisible else { return }
            window.makeKeyAndOrderFront(nil)
            window.toggleFullScreen(nil)
        }
    }

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
            setProperty("pause", value: "no")
            isPlaying = true
            return
        }

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
        flushPendingWatchTime()
        isPlaying = false
        lastWatchTick = nil
        _ = command(["stop"])
        loadedURL = nil
        loadedHeaders = [:]
        pendingPlayback = nil
    }

    func retry(_ url: URL, headers: [String: String], startAtSeconds: Double? = nil) {
        loadedURL = nil
        play(url, headers: headers, startAtSeconds: startAtSeconds ?? currentTimeSeconds)
    }

    func flushWatchProgress() { flushPendingWatchTime() }

    func togglePlayPause() {
        setProperty("pause", value: isPlaying ? "yes" : "no")
        isPlaying.toggle()
    }

    func seek(to seconds: Double) {
        guard seconds.isFinite else { return }
        setProperty("time-pos", value: String(max(0, seconds)))
        currentTimeSeconds = max(0, seconds)
    }

    func seek(by seconds: Double) { seek(to: currentTimeSeconds + seconds) }

    func setSpeed(_ value: Double) {
        guard value.isFinite, value > 0 else { return }
        setProperty("speed", value: String(value))
        speed = value
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
    func setHardwareDecoding(_ enabled: Bool) {
        hardwareDecodingEnabled = enabled
        setProperty("hwdec", value: enabled ? "auto-safe" : "no")
    }
    func setDeinterlacing(_ enabled: Bool) {
        isDeinterlacing = enabled
        setProperty("deinterlace", value: enabled ? "yes" : "no")
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
        for url in urls where url.isFileURL {
            _ = command(["loadfile", url.path, "append"])
        }
        refreshPlaylist()
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

    private func selectNextTrack(_ tracks: [MPVPlaybackTrack], property: String, direction: Int) {
        guard !tracks.isEmpty else { return }
        let currentID = getProperty(property).flatMap(Int.init)
        let selectedIndex = tracks.firstIndex { $0.id == currentID } ?? tracks.firstIndex(where: \.isSelected)
        let start = selectedIndex.map { $0 + 1 } ?? 0
        let next = (start + direction % tracks.count + tracks.count) % tracks.count
        setProperty(property, value: String(tracks[next].id))
        refreshTracks()
    }

    func handleKeyboardShortcut(keyCode: UInt16, characters: String, modifiers: NSEvent.ModifierFlags) -> Bool {
        let flags = modifiers.intersection(.deviceIndependentFlagsMask)
        let command = flags.contains(.command)
        let control = flags.contains(.control)
        let option = flags.contains(.option)
        let shift = flags.contains(.shift)
        let key = characters.lowercased()

        if command && control && key == "f" { onToggleFullscreen?(); return true }
        if command && key == "s" { onScreenshotRequested?(shift); return true }
        if command && key == "l" {
            if shift { setFileLoop(getProperty("loop-file") != "inf") }
            else { markABLoop() }
            return true
        }
        if command && key == "/" { toggleMute(); return true }
        if command && key == "[" { setSpeed(max(0.25, speed * 0.5)); return true }
        if command && key == "]" { setSpeed(min(4, speed * 2)); return true }
        if command && key == "\\" { setSpeed(1); return true }
        if command && keyCode == 123 { stepPlaylist(by: -1); return true }
        if command && keyCode == 124 { stepPlaylist(by: 1); return true }
        if control && key == "h" { setHardwareDecoding(!hardwareDecodingEnabled); return true }

        if control || command { return false }
        if shift && keyCode == 20 { cycleAudioTrack(); return true }
        if shift && keyCode == 27 { cycleVideoTrack(); return true }
        switch keyCode {
        case 49: togglePlayPause(); return true
        case 123:
            if option { panVideo(x: -0.1) }
            else if shift { seekSubtitle(by: -1) }
            else { seek(by: -5) }
            return true
        case 124:
            if option { panVideo(x: 0.1) }
            else if shift { seekSubtitle(by: 1) }
            else { seek(by: 5) }
            return true
        case 126:
            if option { panVideo(y: -0.1) }
            else { setVolume(volume + (shift ? 1 : 5)) }
            return true
        case 125:
            if option { panVideo(y: 0.1) }
            else { setVolume(volume - (shift ? 1 : 5)) }
            return true
        case 53:
            if let window = playerWindow, window.styleMask.contains(.fullScreen) { window.toggleFullScreen(nil) }
            else { onCloseRequested?() }
            return true
        case 51:
            onToggleControls?()
            return true
        default: break
        }

        if option && (key == "+" || key == "=") { zoomVideo(by: 0.1); return true }
        if option && key == "-" { zoomVideo(by: -0.1); return true }
        switch key {
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
        subtitleScale = getProperty("sub-scale").flatMap(Double.init) ?? subtitleScale
        subtitlePosition = getProperty("sub-pos").flatMap(Double.init) ?? subtitlePosition
        subtitleBorderSize = getProperty("sub-border-size").flatMap(Double.init) ?? subtitleBorderSize
        subtitleFontSize = getProperty("sub-font-size").flatMap(Double.init) ?? subtitleFontSize
        subtitleVisibility = getProperty("sub-visibility") != "no"
        secondarySubtitleVisibility = getProperty("secondary-sub-visibility") != "no"
        secondarySubtitleID = getProperty("secondary-sid").flatMap(Int.init)
        isDeinterlacing = getProperty("deinterlace") == "yes"
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
                                            isCurrent: index == playlistPosition)
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

    private func getProperty(_ name: String) -> String? {
        guard let handle else { return nil }
        guard let pointer = name.withCString({ mpv_get_property_string(handle, $0) }) else { return nil }
        let value = String(cString: pointer)
        mpv_free(UnsafeMutableRawPointer(pointer))
        return value
    }

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

private let openGLFramework = dlopen("/System/Library/Frameworks/OpenGL.framework/OpenGL", RTLD_LAZY | RTLD_LOCAL)

private let mpvOpenGLGetProcAddress: @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?) -> UnsafeMutableRawPointer? = { _, name in
    guard let openGLFramework, let name else { return nil }
    return dlsym(openGLFramework, name)
}

struct MPVVideoView: NSViewRepresentable {
    @ObservedObject var controller: MPVPlaybackController

    func makeNSView(context: Context) -> MPVRenderView {
        MPVRenderView(frame: .zero, controller: controller)!
    }

    func updateNSView(_ view: MPVRenderView, context: Context) {
        view.controller = controller
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
    private weak var inputWindow: NSWindow?
    private var previousMouseMoveSetting: Bool?
    private var viewTrackingArea: NSTrackingArea?
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
            self?.needsDisplay = true
        }
        RunLoop.main.add(timer, forMode: .common)
        redrawTimer = timer
    }

    required init?(coder: NSCoder) { nil }

    deinit {
        if let keyEventMonitor { NSEvent.removeMonitor(keyEventMonitor) }
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
        if let previous = inputWindow, let previousMouseMoveSetting {
            previous.acceptsMouseMovedEvents = previousMouseMoveSetting
        }
        inputWindow = window
        previousMouseMoveSetting = window?.acceptsMouseMovedEvents
        window?.acceptsMouseMovedEvents = true
        if window != nil { window?.makeFirstResponder(self) }
        if let keyEventMonitor { NSEvent.removeMonitor(keyEventMonitor) }
        keyEventMonitor = nil
        if window != nil {
            keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, event.window === self.window else { return event }
                self.controller.onUserActivity?()
                return self.controller.handleKeyboardShortcut(
                    keyCode: event.keyCode,
                    characters: event.charactersIgnoringModifiers ?? "",
                    modifiers: event.modifierFlags
                ) ? nil : event
            }
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let viewTrackingArea { removeTrackingArea(viewTrackingArea) }
        let tracking = NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(tracking)
        viewTrackingArea = tracking
    }

    override func mouseMoved(with event: NSEvent) {
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
        if let inputWindow, let previousMouseMoveSetting {
            inputWindow.acceptsMouseMovedEvents = previousMouseMoveSetting
        }
        inputWindow = nil
        previousMouseMoveSetting = nil
        controller.setPlayerWindow(nil)
        openGLContext?.makeCurrentContext()
        controller.detachRenderer()
    }

    override func keyDown(with event: NSEvent) {
        controller.onUserActivity?()
        if !controller.handleKeyboardShortcut(keyCode: event.keyCode,
                                              characters: event.charactersIgnoringModifiers ?? "",
                                              modifiers: event.modifierFlags) {
            super.keyDown(with: event)
        }
    }
}
