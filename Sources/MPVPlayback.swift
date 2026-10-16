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
}

struct MPVPlaybackChapter: Identifiable, Hashable {
    let index: Int
    let title: String
    let timeSeconds: Double
    var id: Int { index }
}

private struct MPVHandleBox: @unchecked Sendable {
    let handle: OpaquePointer
}

@MainActor
final class MPVPlaybackController: ObservableObject {
    @Published private(set) var isLoading = false
    @Published private(set) var isPlaying = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var currentTimeSeconds = 0.0
    @Published private(set) var durationSeconds: Double?
    @Published private(set) var videoOptions: [MPVPlaybackTrack] = []
    @Published private(set) var audioOptions: [MPVPlaybackTrack] = []
    @Published private(set) var subtitleOptions: [MPVPlaybackTrack] = []
    @Published private(set) var chapters: [MPVPlaybackChapter] = []
    @Published private(set) var currentChapterIndex: Int?
    @Published private(set) var audioDelaySeconds = 0.0
    @Published private(set) var isDeinterlacing = false
    @Published private(set) var hardwareDecodingEnabled = true
    @Published private(set) var videoBrightness = 0.0
    @Published private(set) var videoContrast = 0.0
    @Published private(set) var videoGamma = 0.0
    @Published private(set) var videoHue = 0.0
    @Published private(set) var videoSaturation = 0.0
    @Published private(set) var audioEQBands = Array(repeating: 0.0, count: 5)
    @Published private(set) var volume = 100.0
    @Published private(set) var speed = 1.0
    let subtitlesCanBeDisabled = true

    private var handle: OpaquePointer?
    private var renderContext: OpaquePointer?
    private weak var glContext: NSOpenGLContext?
    private var pollTimer: Timer?
    private var loadedURL: URL?
    private var loadedHeaders: [String: String] = [:]
    private var pendingResumeSeconds = 0.0
    private var pendingPlayback: (url: URL, headers: [String: String])?
    private var trackRefreshAt = Date.distantPast
    private var lastWatchTick: Date?
    private var pendingWatchedSeconds = 0.0
    private var shutdownRequested = false
    var onProgress: ((Double, Double?, Double) -> Void)?

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
            ("demuxer-max-bytes", "256MiB"),
            ("demuxer-max-back-bytes", "64MiB"),
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
        guard renderContext == nil, let handle else { return }
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

    func render(width: Int32, height: Int32) {
        guard width > 0, height > 0, let renderContext else { return }
        let flags = mpv_render_context_update(renderContext)
        guard flags & UInt64(MPV_RENDER_UPDATE_FRAME.rawValue) != 0 else { return }

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
        errorMessage = nil
        currentTimeSeconds = 0
        durationSeconds = nil
        videoOptions = []
        audioOptions = []
        subtitleOptions = []
        chapters = []
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

    func setSubtitleDelay(_ seconds: Double) { setProperty("sub-delay", value: String(seconds)) }
    func setAudioDelay(_ seconds: Double) {
        guard seconds.isFinite else { return }
        audioDelaySeconds = seconds
        setProperty("audio-delay", value: String(seconds))
    }
    func setSubtitleScale(_ value: Double) { setProperty("sub-scale", value: String(value)) }
    func adjustSubtitleScale(by multiplier: Double) {
        guard multiplier.isFinite, multiplier > 0 else { return }
        let current = getProperty("sub-scale").flatMap(Double.init) ?? 1
        setSubtitleScale(min(3, max(0.3, current * multiplier)))
    }
    func setSubtitleFont(_ name: String) { setProperty("options/sub-font", value: name) }
    func setSubtitleColor(_ value: String) { setProperty("options/sub-color", value: value) }
    func setSubtitleBackgroundColor(_ value: String) { setProperty("options/sub-back-color", value: value) }
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
        let frequencies = [60, 250, 1_000, 4_000, 12_000]
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

    func addSubtitleFile(_ url: URL) {
        _ = command(["sub-add", url.path, "select"])
        refreshTracksSoon()
    }

    func captureScreenshot(to url: URL) {
        _ = command(["screenshot-to-file", url.path, "video"])
    }

    func setMute(_ enabled: Bool) { setProperty("mute", value: enabled ? "yes" : "no") }

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
        trackRefreshAt = .distantPast
        if pendingResumeSeconds > 0 {
            setProperty("time-pos", value: String(pendingResumeSeconds))
            pendingResumeSeconds = 0
        }
        refreshTracks()
    }

    private func refreshState() {
        guard handle != nil else { return }
        currentTimeSeconds = getProperty("time-pos").flatMap(Double.init).map { max(0, $0) } ?? currentTimeSeconds
        durationSeconds = getProperty("duration").flatMap(Double.init).flatMap { $0 > 0 ? $0 : nil }
        volume = getProperty("volume").flatMap(Double.init) ?? volume
        speed = getProperty("speed").flatMap(Double.init) ?? speed
        audioDelaySeconds = getProperty("audio-delay").flatMap(Double.init) ?? audioDelaySeconds
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
        let seeking = getProperty("seeking") == "yes"
        let coreIdle = getProperty("core-idle") == "yes"
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
        if Date().timeIntervalSince(trackRefreshAt) >= 1.5 { refreshTracks() }
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
                                         isSelected: getProperty("\(prefix)/selected") == "yes")
            } else if type == "audio" {
                track = MPVPlaybackTrack(id: id, kind: .audio, displayName: displayName.isEmpty ? "Audio \(id)" : displayName,
                                         isSelected: getProperty("\(prefix)/selected") == "yes")
            } else if type == "sub" {
                track = MPVPlaybackTrack(id: id, kind: .subtitle, displayName: displayName.isEmpty ? "Subtitle \(id)" : displayName,
                                         isSelected: getProperty("\(prefix)/selected") == "yes")
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

    private func refreshTracksSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.refreshTracks() }
    }

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

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { window?.makeFirstResponder(self) }
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
        glClearColor(0, 0, 0, 1)
        glClear(GLbitfield(GL_COLOR_BUFFER_BIT))
        let scale = window?.backingScaleFactor ?? 1
        controller.render(width: Int32(bounds.width * scale), height: Int32(bounds.height * scale))
        openGLContext.flushBuffer()
        controller.reportSwap()
    }

    func detach() {
        redrawTimer?.invalidate()
        redrawTimer = nil
        openGLContext?.makeCurrentContext()
        controller.detachRenderer()
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 49: controller.togglePlayPause()
        case 123: controller.seek(by: -10)
        case 124: controller.seek(by: 10)
        case 126: controller.setVolume(controller.volume + 5)
        case 125: controller.setVolume(controller.volume - 5)
        default: super.keyDown(with: event)
        }
    }
}
