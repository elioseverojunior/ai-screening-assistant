from __future__ import annotations

from unittest.mock import MagicMock

import httpx
from fastapi import FastAPI, Request
from fastapi.testclient import TestClient
from httpx import ASGITransport

from ai_server.local_only import DOCS_PATHS, _is_private_request, add_local_only_middleware


class TestIsPrivateRequest:
    def _request(self, host: str | None = None) -> Request:
        req = MagicMock(spec=Request)
        if host is None:
            req.client = None
        else:
            req.client.host = host
        return req

    def test_loopback_ipv4(self) -> None:
        assert _is_private_request(self._request("127.0.0.1"))

    def test_loopback_ipv6(self) -> None:
        assert _is_private_request(self._request("::1"))

    def test_private_10(self) -> None:
        assert _is_private_request(self._request("10.0.0.1"))

    def test_private_192(self) -> None:
        assert _is_private_request(self._request("192.168.1.1"))

    def test_public_ip(self) -> None:
        assert not _is_private_request(self._request("8.8.8.8"))

    def test_no_client(self) -> None:
        assert _is_private_request(self._request(None))

    def test_testclient_host(self) -> None:
        assert _is_private_request(self._request("testclient"))


class TestDocsPaths:
    def test_docs_paths_defined(self) -> None:
        assert DOCS_PATHS == {"/docs", "/redoc", "/openapi.json"}


class TestLocalOnlyMiddleware:
    async def test_public_ip_blocks_openapi(self) -> None:
        app = FastAPI(docs_url=None, redoc_url=None, openapi_url=None)
        add_local_only_middleware(app)

        @app.get("/openapi.json")
        async def openapi_docs() -> dict:
            return {"spec": "ok"}

        transport = ASGITransport(app=app, client=("8.8.8.8", 54321))
        async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
            resp = await client.get("/openapi.json")
            assert resp.status_code == 403
            assert resp.json() == {"detail": "Forbidden"}

    async def test_private_ip_allows_openapi(self) -> None:
        app = FastAPI(docs_url=None, redoc_url=None, openapi_url=None)
        add_local_only_middleware(app)

        @app.get("/openapi.json")
        async def openapi_docs() -> dict:
            return {"spec": "ok"}

        transport = ASGITransport(app=app, client=("127.0.0.1", 54321))
        async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
            resp = await client.get("/openapi.json")
            assert resp.status_code == 200
            assert resp.json() == {"spec": "ok"}

    async def test_non_docs_path_allowed_from_public(self) -> None:
        app = FastAPI()
        add_local_only_middleware(app)

        @app.get("/test-path")
        async def health() -> dict:
            return {"status": "ok"}

        transport = ASGITransport(app=app, client=("8.8.8.8", 54321))
        async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
            resp = await client.get("/test-path")
            assert resp.status_code == 200
            assert resp.json() == {"status": "ok"}
