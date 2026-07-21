from __future__ import annotations

import socket

import httpx
import pytest

from ai_server.health_server import (
    create_health_server,
    set_not_ready,
    set_ready,
    start_health_server,
)


def _free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("", 0))
        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        return int(s.getsockname()[1])


class TestSetReady:
    def test_set_ready_and_not_ready(self) -> None:
        set_not_ready()
        port = _free_port()
        server = start_health_server(port)
        try:
            with httpx.Client() as client:
                resp = client.get(f"http://127.0.0.1:{port}/health/ready", timeout=5)
                assert resp.status_code == 503
                assert resp.json() == {"status": "not ready"}
                set_ready()
                resp = client.get(f"http://127.0.0.1:{port}/health/ready", timeout=5)
                assert resp.status_code == 200
                assert resp.json() == {"status": "ready"}
        finally:
            server.shutdown()


class TestHealthHandler:
    def setup_method(self) -> None:
        set_ready()

    def test_liveness_returns_200(self) -> None:
        port = _free_port()
        server = start_health_server(port)
        try:
            with httpx.Client() as client:
                resp = client.get(f"http://127.0.0.1:{port}/health/live", timeout=5)
                assert resp.status_code == 200
                assert resp.json() == {"status": "alive"}
        finally:
            server.shutdown()

    def test_ready_returns_200_when_ready(self) -> None:
        set_ready()
        port = _free_port()
        server = start_health_server(port)
        try:
            with httpx.Client() as client:
                resp = client.get(f"http://127.0.0.1:{port}/health/ready", timeout=5)
                assert resp.status_code == 200
                assert resp.json() == {"status": "ready"}
        finally:
            server.shutdown()

    def test_unknown_path_returns_404(self) -> None:
        set_ready()
        port = _free_port()
        server = start_health_server(port)
        try:
            with httpx.Client() as client:
                resp = client.get(f"http://127.0.0.1:{port}/unknown", timeout=5)
                assert resp.status_code == 404
                assert resp.json() == {"error": "not found"}
        finally:
            server.shutdown()


class TestCreateHealthServer:
    def test_create_and_start(self) -> None:
        port = _free_port()
        server = create_health_server(port)
        try:
            assert server.server_address == ("0.0.0.0", port)
        finally:
            server.server_close()
