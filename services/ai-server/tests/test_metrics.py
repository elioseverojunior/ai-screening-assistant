from __future__ import annotations

import socket

import httpx
import pytest
from httpx import ASGITransport

from ai_server.config import Settings
from ai_server.main import create_app


def _free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("", 0))
        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        return int(s.getsockname()[1])


class TestMetricsServer:
    async def test_metrics_served_on_separate_port(self) -> None:
        port = _free_port()
        app = create_app(
            settings=Settings(
                metrics_port=port,
                otel_collector_endpoint="",
            )
        )
        async with httpx.AsyncClient(
            transport=ASGITransport(app=app),
            base_url="http://test",
        ) as client:
            await client.get("/api/health")
            async with httpx.AsyncClient() as hc:
                resp = await hc.get(f"http://127.0.0.1:{port}/metrics", timeout=5)
                assert resp.status_code == 200
                assert "screening_llm_requests_total" in resp.text
