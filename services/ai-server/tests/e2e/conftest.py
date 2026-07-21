from __future__ import annotations

import json
import os
import socket
import subprocess
import sys
import time
from pathlib import Path
from threading import Thread
from typing import AsyncIterator, Iterator

import httpx
import pytest

HERE = Path(__file__).resolve().parent
PROJECT_ROOT = HERE.parent.parent


def _free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("", 0))
        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        return int(s.getsockname()[1])


def _wait_for_ok(url: str, timeout: float = 15.0, interval: float = 0.2) -> None:
    deadline = time.monotonic() + timeout
    last_err: Exception | None = None
    while time.monotonic() < deadline:
        try:
            r = httpx.get(url, timeout=2)
            if r.status_code < 500:
                return
        except Exception as e:
            last_err = e
            time.sleep(interval)
    msg = f"Timed out waiting for {url}"
    if last_err is not None:
        msg += f": {last_err}"
        raise RuntimeError(msg) from last_err
    raise RuntimeError(msg)


@pytest.fixture(scope="session")
def ollama_mock_server() -> Iterator[str]:
    from http.server import HTTPServer, BaseHTTPRequestHandler

    port = _free_port()
    url = f"http://127.0.0.1:{port}"

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self) -> None:
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.end_headers()
            self.wfile.write(b"mock ollama up")

        def do_POST(self) -> None:
            length = int(self.headers.get("Content-Length", "0"))
            body = json.loads(self.rfile.read(length))
            resp = {"message": {"role": "assistant", "content": "E2E test analysis result."}}
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps(resp).encode())

        def log_message(self, *_: object) -> None:
            pass

    server = HTTPServer(("127.0.0.1", port), Handler)
    server.socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    thread = Thread(target=server.serve_forever, daemon=True)
    thread.start()

    try:
        _wait_for_ok(url, timeout=5)
        yield url
    finally:
        server.shutdown()


@pytest.fixture(scope="session")
def server_url(ollama_mock_server: str) -> Iterator[str]:
    port = _free_port()
    health_port = _free_port()
    url = f"http://127.0.0.1:{port}"

    env = {
        **os.environ,
        "AI_SERVER_ENVIROMENT": "test",
        "AI_SERVER_PORT": str(port),
        "AI_SERVER_HEALTH_PORT": str(health_port),
        "AI_SERVER_METRICS_PORT": "0",
        "AI_SERVER_OLLAMA_BASE_URL": ollama_mock_server,
        "AI_SERVER_OTEL_COLLECTOR_ENDPOINT": "",
    }
    cmd = [
        sys.executable,
        "-m",
        "uvicorn",
        "ai_server.main:app",
        "--host",
        "127.0.0.1",
        "--port",
        str(port),
        "--log-level",
        "error",
    ]

    proc = subprocess.Popen(
        cmd,
        cwd=str(PROJECT_ROOT),
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )

    try:
        _wait_for_ok(f"{url}/api/health", timeout=15)
        yield url
    finally:
        proc.terminate()
        proc.wait(timeout=10)
        _, err = proc.communicate()
        if proc.returncode not in (0, -15, -9):
            print(f"Server stderr: {err.decode()[:500]}", file=sys.stderr)


@pytest.fixture
async def client(server_url: str) -> AsyncIterator[httpx.AsyncClient]:
    async with httpx.AsyncClient(base_url=server_url) as ac:
        yield ac
