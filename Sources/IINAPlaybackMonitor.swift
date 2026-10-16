import Foundation
import Network

/// Reads mpv's local JSON IPC socket so Denbox can persist actual IINA playback.
/// The socket stays inside a per-user 0700 directory because mpv IPC has no auth.
final class IINAPlaybackMonitor {
    typealias ProgressHandler = (_ position: Double, _ duration: Double?, _ watchedDelta: Double) -> Void
    typealias FinishHandler = (_ position: Double, _ duration: Double?) -> Void

    private static let properties = ["time-pos", "duration", "pause", "idle-active", "paused-for-cache"]

    let socketURL: URL
    private let onProgress: ProgressHandler
    private let onFinished: FinishHandler
    private let queue = DispatchQueue(label: "com.denbox.iina-playback-monitor")
    private var connection: NWConnection?
    private var pollTimer: DispatchSourceTimer?
    private var receiveBuffer = Data()
    private var pendingRequests: [Int: String] = [:]
    private var snapshot: [String: Any] = [:]
    private var nextRequestID = 1
    private var isQuerying = false
    private var queryStartedAt: TimeInterval?
    private var connectionReadyAt: TimeInterval?
    private var isStopped = false
    private var finished = false
    private var connectionAttempts = 0
    private var hasSeenMedia = false
    private var lastSampleTime: TimeInterval?
    private var lastSampleWasPlaying = false
    private var latestPosition = 0.0
    private var latestDuration: Double?

    static func makePrivateSocketURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("denbox-ipc-\(UUID().uuidString.prefix(16))", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        return directory.appendingPathComponent("s")
    }

    init(socketURL: URL, onProgress: @escaping ProgressHandler, onFinished: @escaping FinishHandler) {
        self.socketURL = socketURL
        self.onProgress = onProgress
        self.onFinished = onFinished
    }

    func start() {
        queue.async { [weak self] in self?.connect() }
    }

    /// Stops observing but keeps the latest snapshot available to the caller.
    func stop() {
        queue.async { [weak self] in
            guard let self, !self.isStopped else { return }
            self.finish()
        }
    }

    private func connect() {
        guard !isStopped else { return }
        connectionAttempts += 1
        let connection = NWConnection(to: .unix(path: socketURL.path), using: .tcp)
        self.connection = connection
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self, let connection else { return }
            self.queue.async {
                guard self.connection === connection, !self.isStopped else { return }
                switch state {
                case .ready:
                    if self.connectionReadyAt == nil {
                        self.connectionReadyAt = ProcessInfo.processInfo.systemUptime
                    }
                    self.receiveNext()
                    self.startPolling()
                case .waiting:
                    self.connection = nil
                    connection.cancel()
                    self.retryConnectionOrFinish()
                case .failed, .cancelled:
                    self.connection = nil
                    connection.cancel()
                    if self.hasSeenMedia { self.finish() }
                    else { self.retryConnectionOrFinish() }
                default:
                    break
                }
            }
        }
        connection.start(queue: queue)
    }

    private func retryConnectionOrFinish() {
        guard !isStopped else { return }
        guard connectionAttempts < 40 else {
            finish()
            return
        }
        queue.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.connect() }
    }

    private func startPolling() {
        pollTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: 1.0, leeway: .milliseconds(150))
        timer.setEventHandler { [weak self] in self?.requestSnapshot() }
        pollTimer = timer
        timer.resume()
    }

    private func requestSnapshot() {
        guard !isStopped, let connection else { return }
        if isQuerying {
            if let queryStartedAt,
               ProcessInfo.processInfo.systemUptime - queryStartedAt > 5 {
                pendingRequests.removeAll()
                isQuerying = false
            } else {
                return
            }
        }
        if !hasSeenMedia, let connectionReadyAt,
           ProcessInfo.processInfo.systemUptime - connectionReadyAt > 45 {
            finish()
            return
        }
        isQuerying = true
        queryStartedAt = ProcessInfo.processInfo.systemUptime
        snapshot = [:]
        for property in Self.properties {
            let requestID = nextRequestID
            nextRequestID += 1
            pendingRequests[requestID] = property
            let message: [String: Any] = [
                "command": ["get_property", property],
                "request_id": requestID
            ]
            guard var data = try? JSONSerialization.data(withJSONObject: message) else { continue }
            data.append(0x0A)
            connection.send(content: data, completion: .contentProcessed { [weak self] error in
                guard let error else { return }
                self?.queue.async { self?.connectionFailed(error) }
            })
        }
        if pendingRequests.isEmpty { isQuerying = false }
    }

    private func receiveNext() {
        guard !isStopped, let connection else { return }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            self.queue.async {
                guard !self.isStopped else { return }
                if let data, !data.isEmpty {
                    self.receiveBuffer.append(data)
                    self.consumeMessages()
                }
                if isComplete || error != nil {
                    self.connection = nil
                    connection.cancel()
                    self.finish()
                } else {
                    self.receiveNext()
                }
            }
        }
    }

    private func consumeMessages() {
        let newline = Data([0x0A])
        while let lineEnd = receiveBuffer.range(of: newline) {
            let line = receiveBuffer.subdata(in: receiveBuffer.startIndex..<lineEnd.lowerBound)
            receiveBuffer.removeSubrange(receiveBuffer.startIndex..<lineEnd.upperBound)
            guard let object = try? JSONSerialization.jsonObject(with: line),
                  let response = object as? [String: Any],
                  let requestID = response["request_id"] as? Int,
                  let property = pendingRequests.removeValue(forKey: requestID) else { continue }
            snapshot[property] = response["data"]
            if pendingRequests.isEmpty, isQuerying {
                isQuerying = false
                queryStartedAt = nil
                processSnapshot()
            }
        }
    }

    private func processSnapshot() {
        guard let position = Self.number(snapshot["time-pos"]), position.isFinite else { return }
        latestPosition = max(0, position)
        if let duration = Self.number(snapshot["duration"]), duration.isFinite, duration > 0 {
            latestDuration = duration
        }
        let isIdle = Self.boolean(snapshot["idle-active"]) ?? false
        let isPaused = Self.boolean(snapshot["pause"]) ?? true
        let isBuffering = Self.boolean(snapshot["paused-for-cache"]) ?? false
        if !isIdle, latestDuration != nil { hasSeenMedia = true }

        if isIdle, hasSeenMedia {
            finish()
            return
        }

        let isPlaying = !isIdle && !isPaused && !isBuffering
        let now = ProcessInfo.processInfo.systemUptime
        var watchedDelta = 0.0
        if isPlaying, lastSampleWasPlaying, let lastSampleTime {
            let elapsed = now - lastSampleTime
            if elapsed > 0, elapsed <= 2.5 { watchedDelta = min(2.0, elapsed) }
        }
        lastSampleWasPlaying = isPlaying
        lastSampleTime = now
        onProgress(latestPosition, latestDuration, watchedDelta)
    }

    private func connectionFailed(_: NWError) {
        guard !isStopped else { return }
        connection?.cancel()
        connection = nil
        if hasSeenMedia {
            finish()
        } else {
            retryConnectionOrFinish()
        }
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        isStopped = true
        pollTimer?.cancel()
        pollTimer = nil
        connection?.cancel()
        connection = nil
        try? FileManager.default.removeItem(at: socketURL.deletingLastPathComponent())
        onFinished(latestPosition, latestDuration)
    }

    private static func number(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? NSNumber { return value.doubleValue }
        return nil
    }

    private static func boolean(_ value: Any?) -> Bool? {
        if let value = value as? Bool { return value }
        if let value = value as? NSNumber { return value.boolValue }
        return nil
    }
}
