#!/usr/bin/env python3
"""Loopback-only fixture for local YouTube preview accounting.

Run explicitly when needed; this module does not start a server on import.
"""
from __future__ import annotations

import argparse
import json
from http.server import BaseHTTPRequestHandler, HTTPServer


def make_handler(mode: str):
    class Handler(BaseHTTPRequestHandler):
        usage_seconds = 60 if mode == "exhausted" else 0
        payload_count = 0

        def _json(self, status: int, value: dict) -> None:
            body = json.dumps(value, separators=(",", ":")).encode("utf-8")
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self) -> None:
            if self.path.split("?", 1)[0] == "/rules":
                self._json(200, {"blockedDomains": [], "blockedUrlParts": [],
                                 "keywords": [], "blockExceptions": [],
                                 "youtubeQuotaBlocked": self.usage_seconds >= 60})
            elif self.path.split("?", 1)[0] in ("/usage/youtube", "/youtube/usage"):
                unavailable = mode == "unavailable"
                exhausted = mode == "exhausted"
                status = 503 if unavailable else 200
                self._json(status, {
                    "todaySeconds": self.usage_seconds,
                    "dailyCapMinutes": 1,
                    "hourlyCapMinutes": 1,
                    "hourlyUsedSeconds": self.usage_seconds,
                    "hourlyRemainingSeconds": max(0, 60 - self.usage_seconds),
                    "blocked": self.usage_seconds >= 60,
                    "cloudSignedIn": True,
                    "accountBudget": {"available": not unavailable, "fresh": not unavailable,
                                       "enabled": True},
                })
            else:
                self._json(404, {"error": "not_found"})

        def do_POST(self) -> None:
            path = self.path.split("?", 1)[0]
            try:
                length = int(self.headers.get("Content-Length", "0"))
                payload = json.loads(self.rfile.read(length) or b"{}")
            except (ValueError, json.JSONDecodeError):
                self._json(400, {"error": "invalid_payload"})
                return
            if path == "/youtube/budget/grant":
                self._json(400, {"status": 400, "error": "invalid_youtube_lease_request"})
                return
            if path == "/ingest":
                if not isinstance(payload, dict):
                    self._json(400, {"error": "invalid_payload"})
                    return
                seconds = payload.get("seconds", 0)
                watch_seconds = payload.get("watchSeconds")
                if (mode != "allowed" or isinstance(seconds, bool) or not isinstance(seconds, int)
                        or isinstance(watch_seconds, bool) or not isinstance(watch_seconds, int)
                        or not 1 <= watch_seconds <= 120 or watch_seconds > seconds):
                    self._json(400, {"error": "invalid_payload"})
                    return
                type(self).payload_count += 1
                type(self).usage_seconds += watch_seconds
                self._json(200, {"ok": True})
                return
            self._json(404, {"error": "not_found"})

        def log_message(self, _format: str, *_args: object) -> None:
            # Never print request paths, headers, identifiers, or payloads.
            return

    return Handler


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mode", choices=("allowed", "unavailable", "exhausted"), default="allowed")
    args = parser.parse_args()
    server = HTTPServer(("127.0.0.1", 0), make_handler(args.mode))
    print(json.dumps({"url": f"http://127.0.0.1:{server.server_address[1]}",
                      "host": "127.0.0.1", "port": server.server_address[1],
                      "mode": args.mode, "payload_count": 0,
                      "usage_seconds": server.RequestHandlerClass.usage_seconds}), flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        print(json.dumps({"payload_count": server.RequestHandlerClass.payload_count,
                          "usage_seconds": server.RequestHandlerClass.usage_seconds}))
        server.server_close()


if __name__ == "__main__":
    main()
