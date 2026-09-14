#!/usr/bin/env python3
"""verify-fixture-app.py — the app-under-test FIXTURE for the `/verify` walkthrough seam.

A stdlib-only (`http.server`) echo form, small enough to be read in one screen and deterministic
enough to be an oracle. `test-verify-walkthrough.sh` starts it on a free port, waits for `/health`,
runs the agent-authored-style `[ACn]` specs against it through `verify-run.sh walk`, and kills it in
its trap. The `--broken` flag is the MUTATION CONTROL: the form still renders and still accepts the
POST, but the echo paragraph shows `wrong` instead of the posted value — so a walkthrough whose
verdicts come from observation flips `[AC2]` from PASS to FAIL, and one that merely claims cannot.
Also usable by hand as the target of a dogfood `/verify` run (`.agent/verify.json` `start` =
`python3 <this file> --port 8765`, `base_url` = `http://127.0.0.1:8765`, `health` = `/health`).

Routes:
  GET  /          the form: <label for="v">Value</label><input id="v" name="v"> + a Submit button
  POST /submit    <p id="echo">{v}</p> — `{v}` is the posted `v` (HTML-escaped), or `wrong` under --broken
  GET  /health    200 `ok`
  anything else   404

Usage: verify-fixture-app.py --port N [--host 127.0.0.1] [--broken]
"""

import argparse
import html
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import parse_qs

PAGE = (
    "<!doctype html><html><head><meta charset=\"utf-8\"><title>echo form</title></head><body>"
    "<h1>Echo form</h1>"
    "<form method=\"post\" action=\"/submit\">"
    "<label for=\"v\">Value</label>"
    "<input id=\"v\" name=\"v\">"
    "<button type=\"submit\">Submit</button>"
    "</form>"
    "</body></html>"
)

ECHO = (
    "<!doctype html><html><head><meta charset=\"utf-8\"><title>echo</title></head><body>"
    "<h1>Echo</h1><p id=\"echo\">{value}</p><a href=\"/\">back</a>"
    "</body></html>"
)


def make_handler(broken):
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, fmt, *args):  # quiet: the seam test reads nothing from the log
            return

        def _send(self, status, body, content_type="text/html; charset=utf-8"):
            data = body.encode("utf-8")
            self.send_response(status)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def do_GET(self):
            path = self.path.split("?", 1)[0]
            if path == "/":
                self._send(200, PAGE)
            elif path == "/health":
                self._send(200, "ok", "text/plain; charset=utf-8")
            else:
                self._send(404, "<p>not found</p>")

        def do_POST(self):
            path = self.path.split("?", 1)[0]
            if path != "/submit":
                self._send(404, "<p>not found</p>")
                return
            length = int(self.headers.get("Content-Length") or 0)
            raw = self.rfile.read(length).decode("utf-8", "replace") if length > 0 else ""
            value = parse_qs(raw).get("v", [""])[0]
            shown = "wrong" if broken else html.escape(value)
            self._send(200, ECHO.format(value=shown))

    return Handler


def main(argv):
    ap = argparse.ArgumentParser(description="echo-form fixture app for the /verify walkthrough seam")
    ap.add_argument("--port", type=int, required=True)
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--broken", action="store_true",
                    help="mutation control: /submit renders `wrong` instead of the posted value")
    args = ap.parse_args(argv)
    server = HTTPServer((args.host, args.port), make_handler(args.broken))
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
