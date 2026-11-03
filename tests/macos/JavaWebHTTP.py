#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Run a packaged Java WebView test against a disposable loopback HTTP origin."""
import json
import os
from pathlib import Path
import subprocess
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit


def main():
    page = (Path(__file__).parent / "java/storage.html").read_bytes()
    requests = []
    lock = threading.Lock()
    history_held = threading.Event()
    history_release = threading.Event()
    history_check_release = threading.Event()

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *args):
            pass

        def do_GET(self):
            self.respond()

        def do_POST(self):
            self.respond()

        def respond(self):
            path = urlsplit(self.path).path
            length = int(self.headers.get("Content-Length", "0"))
            if length > 4096:
                self.send_error(413)
                return
            body = self.rfile.read(length).decode("utf-8") if length else ""
            if path == "/hold-history":
                history_held.set()
            elif path == "/release-history":
                history_release.set()
            elif path == "/release-history-check":
                history_check_release.set()
            with lock:
                if path != "/report":
                    requests.append({"path": path, "method": self.command,
                                     "cookie": self.headers.get("Cookie", ""), "body": body})
                snapshot = list(requests)
            if path == "/start" and history_held.is_set():
                # The host harness observes the admitted request before it
                # asks Husk to stop, then releases this response while closing.
                if not history_release.wait(timeout=15):
                    self.send_error(504, "History response was not released")
                    return
            if path == "/history-check-wait" and not history_check_release.wait(timeout=15):
                self.send_error(504, "History check was not released")
                return
            status, payload, content_type = 200, page, "text/html; charset=utf-8"
            if path == "/report":
                payload, content_type = json.dumps(snapshot).encode(), "application/json"
            elif path == "/saved":
                payload, content_type = b"saved", "text/plain"
            elif path in ("/hold-history", "/release-history", "/history-check-wait", "/release-history-check"):
                payload, content_type = b"ok", "text/plain"
            elif path == "/redirect":
                status, payload = 302, b""
            elif path not in ("/start", "/second"):
                status, payload = 404, b"unknown fixture resource"
            self.send_response(status)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(payload)))
            self.send_header("Cache-Control", "no-store")
            if path == "/redirect":
                self.send_header("Location", "/second")
            if path == "/start":
                self.send_header("Set-Cookie", "fixture_http=server; Path=/; Max-Age=3600; HttpOnly; SameSite=Lax")
            self.end_headers()
            try:
                self.wfile.write(payload)
            except (BrokenPipeError, ConnectionResetError):
                pass  # A cancelled navigation is an expected test outcome.

    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    worker = threading.Thread(target=server.serve_forever, daemon=True)
    worker.start()
    env = dict(os.environ, HUSK_WEB_HTTP_ORIGIN=f"http://127.0.0.1:{server.server_port}")
    try:
        result = subprocess.run(sys.argv[1:], env=env, timeout=150, check=False)
        print("HTTP fixture requests:", json.dumps(requests), flush=True)
        return result.returncode
    finally:
        history_release.set()
        history_check_release.set()
        server.shutdown()
        server.server_close()
        worker.join()


if __name__ == "__main__":
    raise SystemExit(main())
