import Foundation

@main
struct IINAPlaybackMonitorTests {
    static func main() throws {
        let socketURL = try IINAPlaybackMonitor.makePrivateSocketURL()
        defer { try? FileManager.default.removeItem(at: socketURL.deletingLastPathComponent()) }

        let server = Process()
        server.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        server.arguments = ["-c", #"""
import json, socket, sys
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.bind(sys.argv[1])
s.listen(1)
c, _ = s.accept()
buffer = b""
idle_reads = 0
while True:
    chunk = c.recv(4096)
    if not chunk:
        break
    buffer += chunk
    while b"\n" in buffer:
        line, buffer = buffer.split(b"\n", 1)
        request = json.loads(line)
        prop = request["command"][1]
        if prop == "time-pos": data = float(idle_reads * 5 + 10)
        elif prop == "duration": data = 100.0
        elif prop == "pause": data = False
        elif prop == "paused-for-cache": data = False
        elif prop == "idle-active":
            idle_reads += 1
            data = idle_reads >= 3
        else: data = None
        reply = {"request_id": request["request_id"], "error": "success", "data": data}
        c.sendall((json.dumps(reply) + "\n").encode())
"""#, socketURL.path]
        do {
            try server.run()
        } catch {
            throw MonitorTestFailure(message: "could not start the local IPC fixture: \(error.localizedDescription)")
        }
        defer { if server.isRunning { server.terminate() } }

        let finished = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var observedDeltas: [Double] = []
        var finalSnapshot: (Double, Double?)?
        let monitor = IINAPlaybackMonitor(
            socketURL: socketURL,
            onProgress: { _, _, delta in
                lock.lock()
                observedDeltas.append(delta)
                lock.unlock()
            },
            onFinished: { position, duration in
                lock.lock()
                finalSnapshot = (position, duration)
                lock.unlock()
                finished.signal()
            }
        )
        monitor.start()
        guard finished.wait(timeout: .now() + 12) == .success else {
            monitor.stop()
            throw MonitorTestFailure(message: "the monitor did not observe mpv's idle/end-of-file state")
        }
        server.waitUntilExit()
        lock.lock()
        let deltas = observedDeltas
        let final = finalSnapshot
        lock.unlock()

        try require(deltas.contains { $0 > 0.5 }, "playing snapshots did not accumulate watched time")
        try require(final?.0 == 20, "the final mpv time position was not saved")
        try require(final?.1 == 100, "the mpv duration was not saved")
        print("PASS IINA IPC monitor: progress, duration, watched time, and end-of-playback")
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw MonitorTestFailure(message: message) }
    }
}

private struct MonitorTestFailure: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}
