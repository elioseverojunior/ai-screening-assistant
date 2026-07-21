from __future__ import annotations

import ipaddress

from fastapi import FastAPI, Request, Response

DOCS_PATHS = {"/docs", "/redoc", "/openapi.json"}


def _is_private_request(request: Request) -> bool:
    host = request.client.host if request.client else ""
    try:
        addr = ipaddress.ip_address(host)
        return addr.is_loopback or addr.is_private
    except ValueError:
        return host in ("", "testclient")


def add_local_only_middleware(app: FastAPI) -> None:
    @app.middleware("http")
    async def local_only_middleware(request: Request, call_next: object) -> Response:
        if request.url.path in DOCS_PATHS and not _is_private_request(request):
            return Response(status_code=403, content='{"detail":"Forbidden"}', media_type="application/json")
        return await call_next(request)  # type: ignore[misc]
