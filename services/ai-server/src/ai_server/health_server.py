from __future__ import annotations

import json
from http.server import HTTPServer, BaseHTTPRequestHandler
from threading import Event, Thread
from typing import ClassVar

_ready = Event()


def set_ready() -> None:
    _ready.set()


def set_not_ready() -> None:
    _ready.clear()


class HealthHandler(BaseHTTPRequestHandler):
    server_version: ClassVar[str] = "HealthServer/1.0"

    def do_GET(self) -> None:
        if self.path == "/health/live":
            self._respond(200, {"status": "alive"})
        elif self.path == "/health/ready":
            if _ready.is_set():
                self._respond(200, {"status": "ready"})
            else:
                self._respond(503, {"status": "not ready"})
        else:
            self._respond(404, {"error": "not found"})

    def _respond(self, status: int, body: dict) -> None:
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps(body).encode())

    def log_message(self, format: str, *args: object) -> None:
        pass


def create_health_server(port: int) -> HTTPServer:
    return HTTPServer(("0.0.0.0", port), HealthHandler)


def start_health_server(port: int) -> HTTPServer:
    server = create_health_server(port)
    thread = Thread(target=server.serve_forever, daemon=True)
    thread.start()
    return server
