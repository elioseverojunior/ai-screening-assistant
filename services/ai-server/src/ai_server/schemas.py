from __future__ import annotations

from datetime import datetime, timezone
from uuid import uuid4

from pydantic import BaseModel, Field


class AnalyzeRequest(BaseModel):
    prompt: str = "Describe what you see in this image"
    model: str | None = None


class AnalyzeResponse(BaseModel):
    id: str = Field(default_factory=lambda: uuid4().hex)
    model: str
    response: str
    processing_ms: int
    timestamp: str = Field(
        default_factory=lambda: datetime.now(timezone.utc).isoformat()
    )


class HealthResponse(BaseModel):
    status: str = "ok"


class HealthLivenessResponse(BaseModel):
    status: str = "alive"


class HealthReadinessResponse(BaseModel):
    ready: bool = True
    circuit_breaker_state: str = "closed"
