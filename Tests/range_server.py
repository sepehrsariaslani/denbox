#!/usr/bin/env python3
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import sys

SIZE = 32 * 1024 * 1024
BODY = bytes((index * 31 + 7) % 256 for index in range(SIZE))


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        range_header = self.headers.get("Range")
        if self.path == "/range" and range_header:
            try:
                unit, bounds = range_header.split("=", 1)
                start_text, end_text = bounds.split("-", 1)
                start = int(start_text)
                end = min(int(end_text), SIZE - 1)
                if unit != "bytes" or start < 0 or start > end:
                    raise ValueError("bad byte range")
            except ValueError:
                self.send_error(400)
                return
            body = BODY[start:end + 1]
            self.send_response(206)
            self.send_header("Content-Type", "video/mp4")
            self.send_header("Accept-Ranges", "bytes")
            self.send_header("Content-Range", f"bytes {start}-{end}/{SIZE}")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return

        if self.path in ("/range", "/whole"):
            self.send_response(200)
            self.send_header("Content-Type", "video/mp4")
            self.send_header("Content-Length", str(SIZE))
            self.end_headers()
            self.wfile.write(BODY)
            return
        self.send_error(404)

    def log_message(self, *_args):
        pass


if __name__ == "__main__":
    ThreadingHTTPServer(("127.0.0.1", int(sys.argv[1])), Handler).serve_forever()
