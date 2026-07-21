from __future__ import annotations

import time
from contextlib import asynccontextmanager
from typing import AsyncIterator

from fastapi import FastAPI, Request
from fastapi.openapi.utils import get_openapi
from starlette.middleware.base import _StreamingResponse

from ai_server.circuit_breaker import CircuitBreaker
from ai_server.config import Settings
from ai_server.health_server import set_ready, set_not_ready, start_health_server
from ai_server.local_only import add_local_only_middleware
from ai_server.logging import get_logger, setup_logging
from ai_server.metrics import MetricsRegistry, setup_metrics
from ai_server.otel import setup_otel
from ai_server.router import router

logger = get_logger(__name__)


def custom_openapi():
    if app.openapi_schema:
        return app.openapi_schema
    openapi_schema = get_openapi(
        title="Screening LLM Assistant — AI Server",
        version="0.1.0",
        description="Receives screen captures from macOS agent and returns AI analysis via free endpoints.",
        routes=app.routes,
    )
    openapi_schema["paths"]["/ws/analysis"] = {
        "get": {
            "summary": "Real-time analysis results",
            "description": "WebSocket endpoint that broadcasts analysis results to all connected clients. Messages are JSON objects with type 'analysis', 'welcome', or 'error'.",
            "responses": {
                "101": {
                    "description": "Switching Protocols - WebSocket connection established",
                    "content": {
                        "application/json": {
                            "schema": {
                                "type": "object",
                                "properties": {
                                    "type": {"type": "string", "enum": ["welcome", "analysis", "error"]},
                                    "message": {"type": "string"},
                                    "model": {"type": "string"},
                                    "response": {"type": "string"},
                                    "processing_ms": {"type": "integer"},
                                    "timestamp": {"type": "string", "format": "date-time"},
                                },
                            },
                        }
                    },
                }
            },
        }
    }
    app.openapi_schema = openapi_schema
    return app.openapi_schema


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    settings = app.state.settings
    setup_logging(settings.log_level)
    logger.info("Starting app", extra={"props": {"version": "0.1.0", "provider": settings.provider, "model": settings.resolve_model(), "metrics_port": settings.metrics_port}})
    health_svr = start_health_server(settings.health_port)
    logger.info("Health server started", extra={"props": {"port": settings.health_port}})
    setup_otel(settings, app=app)
    set_ready()
    yield
    set_not_ready()
    health_svr.shutdown()
    logger.info("Shutting down app")


def create_app(settings: Settings | None = None) -> FastAPI:
    app = FastAPI(
        title="Screening LLM Assistant — AI Server",
        description="Receives screen captures from macOS agent and returns AI analysis via free endpoints.",
        version="0.1.0",
        docs_url="/docs",
        redoc_url="/redoc",
        lifespan=lifespan,
    )
    app.include_router(router)
    app.openapi = custom_openapi

    if settings is None:
        settings = Settings()

    if not hasattr(app.state, "settings"):
        app.state.settings = settings

    cb = CircuitBreaker(
        failure_threshold=settings.cb_failure_threshold,
        recovery_timeout=settings.cb_recovery_timeout,
    )
    app.state.circuit_breaker = cb

    reg = setup_metrics(
        app,
        prefix=settings.otel_metrics_prefix,
        metrics_port=settings.metrics_port,
    )
    app.state.metrics = reg

    add_local_only_middleware(app)
    _add_metrics_middleware(app, reg)
    _add_cb_metrics_updater(app, cb, reg)

    return app


def _add_metrics_middleware(app: FastAPI, reg: MetricsRegistry) -> None:
    @app.middleware("http")
    async def metrics_middleware(request: Request, call_next: object) -> _StreamingResponse:
        reg.active_requests.inc()
        start = time.monotonic()
        response = await call_next(request)  # type: ignore[misc]
        duration = time.monotonic() - start
        reg.active_requests.dec()
        route_path = (
            request.scope.get("route", {}).path
            if hasattr(request.scope.get("route"), "path")
            else request.url.path
        )
        reg.requests_total.labels(
            method=request.method, path=route_path, status=response.status_code
        ).inc()
        reg.request_duration.labels(
            method=request.method, path=route_path
        ).observe(duration)
        return response


def _update_cb_metrics(cb: CircuitBreaker, reg: MetricsRegistry) -> None:
    state_map = {"closed": 0, "open": 1, "half_open": 2}
    reg.cb_state.labels(name="ollama").set(state_map[cb.state.value])
    reg.cb_failures.labels(name="ollama").set(cb.failure_count)


def _add_cb_metrics_updater(
    app: FastAPI, cb: CircuitBreaker, reg: MetricsRegistry
) -> None:
    @app.middleware("http")
    async def cb_metrics_middleware(request: Request, call_next: object) -> _StreamingResponse:
        _update_cb_metrics(cb, reg)
        return await call_next(request)  # type: ignore[misc]


app = create_app(settings=Settings(metrics_port=0))
