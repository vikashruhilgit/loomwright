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

The auth routes (`/login`, `/probe`, `/protected`) are the item-04 fixture for `verify-run.sh
auth-check` / the AC5 mid-run-expiry mutation control: a session cookie minted by `/login`, checked by
`/probe` and `/protected`, and — with `--auth-expire-after N` — DELIBERATELY invalidated after the
Nth `/protected` hit so a real 401 (never a code-level fake) is observable mid-walk.

Routes:
  GET  /           the form: <label for="v">Value</label><input id="v" name="v"> + a Submit button
  POST /submit     <p id="echo">{v}</p> — `{v}` is the posted `v` (HTML-escaped), or `wrong` under --broken
  GET  /health     200 `ok`
  POST /login      any body ⇒ mints a session token, `Set-Cookie: session=<token>; Path=/`, 200
  GET  /probe      a valid `session` cookie ⇒ 200; missing / unknown / expired ⇒ 302 to `/login`
  GET  /protected  same auth check as `/probe` (302 when missing/unknown/expired) — but once
                   `--auth-expire-after N` has been given and the Nth successful hit is reached, the
                   session is marked EXPIRED and this AND EVERY LATER request presenting it gets 401
                   (not 302 — the app itself observed the session die, distinct from "no session")
  anything else    404

Usage: verify-fixture-app.py --port N [--host 127.0.0.1] [--broken] [--auth-expire-after N]
"""

import argparse
import html
import secrets
import sys
from http.cookies import SimpleCookie
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

PROTECTED_PAGE = (
    "<!doctype html><html><head><meta charset=\"utf-8\"><title>protected</title></head><body>"
    "<h1>Protected</h1><button id=\"act\">Do the thing</button>"
    "</body></html>"
)


def make_handler(broken, auth_expire_after):
    # Session state lives in THIS closure, shared by every per-request Handler instance the same
    # way `broken` already is — HTTPServer instantiates a new Handler per connection but calls the
    # same class, so the dict below persists for the life of the server.
    state = {"valid": set(), "expired": set(), "protected_hits": 0}

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, fmt, *args):  # quiet: the seam test reads nothing from the log
            return

        def _send(self, status, body, content_type="text/html; charset=utf-8", extra_headers=None):
            data = body.encode("utf-8")
            self.send_response(status)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(data)))
            for k, v in (extra_headers or ()):
                self.send_header(k, v)
            self.end_headers()
            self.wfile.write(data)

        def _redirect_login(self):
            self.send_response(302)
            self.send_header("Location", "/login")
            self.end_headers()

        def _cookie_token(self):
            raw = self.headers.get("Cookie")
            if not raw:
                return None
            jar = SimpleCookie()
            try:
                jar.load(raw)
            except Exception:
                return None
            morsel = jar.get("session")
            return morsel.value if morsel else None

        def _session_state(self, token):
            # "none" covers both no cookie and an unrecognized token — both are anonymous, never
            # distinguished from each other (only "expired" is a distinct, later-arriving state).
            if token is not None and token in state["expired"]:
                return "expired"
            if token is not None and token in state["valid"]:
                return "valid"
            return "none"

        def do_GET(self):
            path = self.path.split("?", 1)[0]
            if path == "/":
                self._send(200, PAGE)
            elif path == "/health":
                self._send(200, "ok", "text/plain; charset=utf-8")
            elif path == "/probe":
                if self._session_state(self._cookie_token()) == "valid":
                    self._send(200, "authenticated", "text/plain; charset=utf-8")
                else:
                    self._redirect_login()
            elif path == "/protected":
                st = self._session_state(self._cookie_token())
                if st == "expired":
                    self._send(401, "<p>session expired</p>")
                    return
                if st != "valid":
                    self._redirect_login()
                    return
                state["protected_hits"] += 1
                if auth_expire_after is not None and state["protected_hits"] > auth_expire_after:
                    token = self._cookie_token()
                    state["valid"].discard(token)
                    state["expired"].add(token)
                    self._send(401, "<p>session expired</p>")
                    return
                self._send(200, PROTECTED_PAGE)
            else:
                self._send(404, "<p>not found</p>")

        def do_POST(self):
            path = self.path.split("?", 1)[0]
            length = int(self.headers.get("Content-Length") or 0)
            raw = self.rfile.read(length).decode("utf-8", "replace") if length > 0 else ""
            if path == "/submit":
                value = parse_qs(raw).get("v", [""])[0]
                shown = "wrong" if broken else html.escape(value)
                self._send(200, ECHO.format(value=shown))
                return
            if path == "/login":
                # Any body ⇒ mint a session token; no credential is checked (a stdlib-only,
                # deterministic fixture, not a real auth backend).
                token = secrets.token_hex(16)
                state["valid"].add(token)
                self._send(200, "<p>logged in</p>", extra_headers=[("Set-Cookie", "session=%s; Path=/" % token)])
                return
            self._send(404, "<p>not found</p>")

    return Handler


def main(argv):
    ap = argparse.ArgumentParser(description="echo-form fixture app for the /verify walkthrough seam")
    ap.add_argument("--port", type=int, required=True)
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--broken", action="store_true",
                    help="mutation control: /submit renders `wrong` instead of the posted value")
    ap.add_argument("--auth-expire-after", type=int, default=None, metavar="N",
                    help="invalidate the session cookie after the Nth request to /protected "
                         "(that request, and every later one presenting it, gets 401)")
    args = ap.parse_args(argv)
    server = HTTPServer((args.host, args.port), make_handler(args.broken, args.auth_expire_after))
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
