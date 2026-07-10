from __future__ import annotations

from uuid import UUID

from pydantic import ValidationError

from ai_server.schemas import (
    AnalyzeRequest,
    AnalyzeResponse,
    HealthLivenessResponse,
    HealthReadinessResponse,
    HealthResponse,
)


class TestAnalyzeRequest:
    def test_default_prompt(self) -> None:
        req = AnalyzeRequest()
        assert req.prompt == "Describe what you see in this image"
        assert req.model is None

    def test_custom_prompt(self) -> None:
        req = AnalyzeRequest(prompt="What colors are in this image?")
        assert req.prompt == "What colors are in this image?"

    def test_custom_model(self) -> None:
        req = AnalyzeRequest(model="llama3.2-vision")
        assert req.model == "llama3.2-vision"


class TestAnalyzeResponse:
    def test_fields(self) -> None:
        resp = AnalyzeResponse(
            model="test-model",
            response="analysis text",
            processing_ms=1234,
        )
        assert isinstance(UUID(hex=resp.id), UUID)
        assert resp.model == "test-model"
        assert resp.response == "analysis text"
        assert resp.processing_ms == 1234
        assert "T" in resp.timestamp

    def test_auto_generates_id(self) -> None:
        resp1 = AnalyzeResponse(model="m", response="r", processing_ms=1)
        resp2 = AnalyzeResponse(model="m", response="r", processing_ms=1)
        assert resp1.id != resp2.id


class TestHealthResponse:
    def test_default_status(self) -> None:
        hr = HealthResponse()
        assert hr.status == "ok"

    def test_serialization(self) -> None:
        hr = HealthResponse()
        data = hr.model_dump()
        assert data == {"status": "ok"}


class TestHealthLivenessResponse:
    def test_default(self) -> None:
        resp = HealthLivenessResponse()
        assert resp.status == "alive"

    def test_serialization(self) -> None:
        resp = HealthLivenessResponse()
        assert resp.model_dump() == {"status": "alive"}


class TestHealthReadinessResponse:
    def test_default_ready(self) -> None:
        resp = HealthReadinessResponse()
        assert resp.ready is True
        assert resp.circuit_breaker_state == "closed"

    def test_not_ready(self) -> None:
        resp = HealthReadinessResponse(ready=False, circuit_breaker_state="open")
        assert resp.ready is False
        assert resp.circuit_breaker_state == "open"

    def test_serialization(self) -> None:
        resp = HealthReadinessResponse(ready=True, circuit_breaker_state="closed")
        assert resp.model_dump() == {"ready": True, "circuit_breaker_state": "closed"}
