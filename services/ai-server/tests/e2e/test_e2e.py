from __future__ import annotations

from io import BytesIO

import httpx
import pytest
from PIL import Image

pytestmark = pytest.mark.e2e


class TestHealth:
    async def test_health_returns_ok(self, client: httpx.AsyncClient) -> None:
        response = await client.get("/api/health")
        assert response.status_code == 200
        assert response.json() == {"status": "ok"}

    async def test_liveness_returns_alive(self, client: httpx.AsyncClient) -> None:
        response = await client.get("/health/live")
        assert response.status_code == 200
        assert response.json() == {"status": "alive"}

    async def test_readiness_returns_ready(self, client: httpx.AsyncClient) -> None:
        response = await client.get("/health/ready")
        assert response.status_code == 200
        data = response.json()
        assert data["ready"] is True


class TestSwagger:
    async def test_swagger_ui_accessible(self, client: httpx.AsyncClient) -> None:
        response = await client.get("/docs")
        assert response.status_code == 200
        assert "swagger" in response.text.lower()

    async def test_redoc_ui_accessible(self, client: httpx.AsyncClient) -> None:
        response = await client.get("/redoc")
        assert response.status_code == 200
        assert "redoc" in response.text.lower()


class TestAnalyze:
    @pytest.fixture
    def sample_png(self) -> bytes:
        buf = BytesIO()
        Image.new("RGB", (100, 100), color="blue").save(buf, format="PNG")
        return buf.getvalue()

    async def test_analyze_with_valid_png(
        self, client: httpx.AsyncClient, sample_png: bytes
    ) -> None:
        response = await client.post(
            "/api/analyze",
            files={"file": ("test.png", sample_png, "image/png")},
            data={"prompt": "Describe this image"},
        )
        assert response.status_code == 200
        data = response.json()
        assert data["model"] == "llama3.2-vision"
        assert data["response"] == "E2E test analysis result."
        assert "id" in data
        assert "timestamp" in data
        assert isinstance(data["processing_ms"], int)

    async def test_analyze_with_custom_model(
        self, client: httpx.AsyncClient, sample_png: bytes
    ) -> None:
        response = await client.post(
            "/api/analyze",
            files={"file": ("test.png", sample_png, "image/png")},
            data={"prompt": "Describe", "model": "custom-model"},
        )
        assert response.status_code == 200

    async def test_analyze_rejects_missing_file(
        self, client: httpx.AsyncClient
    ) -> None:
        response = await client.post(
            "/api/analyze",
            data={"prompt": "Describe"},
        )
        assert response.status_code == 422

    async def test_analyze_rejects_missing_prompt(
        self, client: httpx.AsyncClient, sample_png: bytes
    ) -> None:
        response = await client.post(
            "/api/analyze",
            files={"file": ("test.png", sample_png, "image/png")},
        )
        assert response.status_code == 422
