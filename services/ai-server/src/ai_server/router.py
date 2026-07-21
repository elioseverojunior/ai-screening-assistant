from __future__ import annotations

import time
from typing import Annotated

import httpx
from fastapi import APIRouter, Depends, File, Form, HTTPException, Request, UploadFile, WebSocket, WebSocketDisconnect

from ai_server.circuit_breaker import CircuitBreaker, CircuitBreakerOpenError
from ai_server.config import Settings, get_settings
from ai_server.logging import get_logger
from ai_server.metrics import MetricsRegistry
from ai_server.providers import create_provider

logger = get_logger(__name__)
from ai_server.schemas import (
    AnalyzeResponse,
    HealthLivenessResponse,
    HealthReadinessResponse,
    HealthResponse,
)

class ConnectionManager:
    def __init__(self):
        self.active_connections: list[WebSocket] = []

    async def connect(self, websocket: WebSocket):
        await websocket.accept()
        self.active_connections.append(websocket)

    def disconnect(self, websocket: WebSocket):
        self.active_connections.remove(websocket)

    async def broadcast(self, message: dict):
        dead = []
        for connection in self.active_connections:
            try:
                await connection.send_json(message)
            except Exception:
                dead.append(connection)
        for conn in dead:
            self.active_connections.remove(conn)


manager = ConnectionManager()

router = APIRouter()


def _get_metrics(request: Request) -> MetricsRegistry | None:
    return getattr(request.app.state, "metrics", None)


def _get_circuit_breaker(request: Request):
    return getattr(request.app.state, "circuit_breaker", None)


@router.get(
    "/health/live",
    response_model=HealthLivenessResponse,
    tags=["kubernetes"],
    summary="Kubernetes liveness probe",
)
async def liveness() -> HealthLivenessResponse:
    logger.debug("Liveness probe")
    return HealthLivenessResponse()


@router.get(
    "/health/ready",
    response_model=HealthReadinessResponse,
    tags=["kubernetes"],
    summary="Kubernetes readiness probe",
)
async def readiness(request: Request) -> HealthReadinessResponse:
    cb = _get_circuit_breaker(request)
    cb_ready = cb.is_ready if cb is not None else True
    cb_state = cb.state.value if cb is not None else "unknown"
    logger.debug("Readiness probe", extra={"props": {"ready": cb_ready, "circuit_breaker_state": cb_state}})
    return HealthReadinessResponse(ready=cb_ready, circuit_breaker_state=cb_state)


@router.post(
    "/api/analyze",
    response_model=AnalyzeResponse,
    tags=["analysis"],
    summary="Analyze an image using an AI model",
)
async def analyze(
    file: Annotated[UploadFile, File(..., description="Image file (PNG/JPEG)")],
    prompt: Annotated[str, Form(..., description="Prompt for the AI model")],
    settings: Annotated[Settings, Depends(get_settings)],
    request: Request,
) -> AnalyzeResponse:
    image = await file.read()
    logger.info("Analyze request received", extra={"props": {"prompt": prompt, "image_size": len(image), "provider": settings.provider, "model": settings.resolve_model()}})
    provider = create_provider(settings)
    start = time.monotonic()
    try:
        cb = _get_circuit_breaker(request)
        if cb is not None:
            result = await cb.acall(provider.analyze, image, prompt)
        else:
            result = await provider.analyze(image, prompt)
    except CircuitBreakerOpenError:
        logger.warning("Circuit breaker open, request rejected")
        raise HTTPException(status_code=503, detail="Service temporarily unavailable")
    except httpx.HTTPStatusError as e:
        reg = _get_metrics(request)
        if reg is not None:
            reg.analysis_total.labels(
                model=settings.default_model,
                provider=settings.provider,
                status="error",
            ).inc()
        try:
            error_body = e.response.json()
        except Exception:
            error_body = e.response.text
        logger.error(
            "Provider returned error",
            extra={"props": {"status_code": e.response.status_code, "provider": settings.provider, "response": error_body}},
        )
        detail = error_body.get("error", {}).get("message", str(e)) if isinstance(error_body, dict) else str(e)
        raise HTTPException(status_code=e.response.status_code, detail=detail) from e

    duration = time.monotonic() - start
    reg = _get_metrics(request)
    if reg is not None:
        reg.analysis_total.labels(
            model=result.model,
            provider=settings.provider,
            status="success",
        ).inc()
        reg.analysis_duration.labels(
            model=result.model, provider=settings.provider
        ).observe(duration)
        reg.image_bytes_total.inc(len(image))
        reg.last_analysis_timestamp.labels(model=result.model).set_to_current_time()

    resp = AnalyzeResponse(
        model=result.model,
        response=result.response,
        processing_ms=result.processing_ms,
    )
    await manager.broadcast({
        "id": resp.id,
        "timestamp": resp.timestamp,
        "model": resp.model,
        "response": resp.response,
        "prompt": prompt,
        "imageBase64": None,
    })
    logger.info("Analyze request completed", extra={"props": {"model": result.model, "duration_ms": result.processing_ms, "response_length": len(result.response)}})
    return resp


@router.websocket("/ws/analysis")
async def websocket_endpoint(websocket: WebSocket):
    await manager.connect(websocket)
    await websocket.send_json({"type": "welcome", "message": "Connected to analysis broadcast"})
    try:
        while True:
            await websocket.receive_text()
    except WebSocketDisconnect:
        manager.disconnect(websocket)
