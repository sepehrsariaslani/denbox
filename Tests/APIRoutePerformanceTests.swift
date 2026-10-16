import Foundation

@main
struct APIRoutePerformanceTests {
    @MainActor
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DenboxRouteRace-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let portFile = root.appendingPathComponent("port")

        let server = Process()
        server.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        server.arguments = ["-u", "-c", #"""
import json, pathlib, sys, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/slow":
            time.sleep(3)
            rows = [{"title": "slow"}]
        elif self.path == "/empty":
            rows = []
        else:
            time.sleep(0.05)
            rows = [{"title": "fast"}]
        payload = json.dumps({"movies": rows}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        try: self.wfile.write(payload)
        except BrokenPipeError: pass
    def log_message(self, *_args): pass

server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
pathlib.Path(sys.argv[1]).write_text(str(server.server_address[1]))
server.serve_forever()
"""#]
        server.arguments?.append(portFile.path)
        server.standardOutput = FileHandle.nullDevice
        server.standardError = FileHandle.nullDevice
        try server.run()
        defer { if server.isRunning { server.terminate() } }

        let deadline = Date().addingTimeInterval(3)
        while !FileManager.default.fileExists(atPath: portFile.path), Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        guard let port = Int(try String(contentsOf: portFile, encoding: .utf8)) else {
            throw RouteTestFailure(message: "local HTTP test server did not start")
        }
        let base = URL(string: "http://127.0.0.1:\(port)")!
        let acceptsRows: (Any) -> Bool = { !((DirectMediaAPI.rows(from: $0) ?? []).isEmpty) }

        let started = Date()
        let fast = try await DirectMediaAPI.getJSON(
            firstAcceptableFrom: [base.appendingPathComponent("slow"), base.appendingPathComponent("fast")],
            timeout: 5,
            accepting: acceptsRows
        )
        let fastSeconds = Date().timeIntervalSince(started)
        try require(DirectMediaAPI.rows(from: fast)?.first?["title"] as? String == "fast",
                    "the route race did not return the first usable response")
        try require(fastSeconds < 1, "a slow fallback delayed a fast usable route by more than one second")

        let skippedEmpty = try await DirectMediaAPI.getJSON(
            firstAcceptableFrom: [base.appendingPathComponent("empty"), base.appendingPathComponent("fast")],
            timeout: 5,
            accepting: acceptsRows
        )
        try require(DirectMediaAPI.rows(from: skippedEmpty)?.first?["title"] as? String == "fast",
                    "the route race did not skip an empty response")
        print(String(format: "PASS API route race: usable response in %.3fs; empty route skipped", fastSeconds))
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw RouteTestFailure(message: message) }
    }
}

private struct RouteTestFailure: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}
