from __future__ import annotations

from unittest.mock import AsyncMock, patch

from httpx import ASGITransport, AsyncClient

from ai_server.config import Settings
from ai_server.main import create_app
from ai_server.providers import AnalysisResult


class TestHealth:
    async def test_health_returns_ok(self, client: AsyncClient) -> None:
        response = await client.get("/api/health")
        assert response.status_code == 200
        assert response.json() == {"status": "ok"}

    async def test_liveness_returns_alive(self, client: AsyncClient) -> None:
        response = await client.get("/health/live")
        assert response.status_code == 200
        assert response.json() == {"status": "alive"}

    async def test_readiness_returns_closed(self, client: AsyncClient) -> None:
        response = await client.get("/health/ready")
        assert response.status_code == 200
        data = response.json()
        assert data["ready"] is True
        assert data["circuit_breaker_state"] == "closed"


class TestAnalyze:
    async def test_analyze_with_valid_png(
        self, client: AsyncClient, sample_png: bytes
    ) -> None:
        with patch(
            "ai_server.providers.ollama.OllamaProvider.analyze",
            new_callable=AsyncMock,
        ) as mock_analyze:
            mock_analyze.return_value = AnalysisResult(
                response="I see a red image.",
                model="llama3.2-vision",
                processing_ms=42,
            )

            response = await client.post(
                "/api/analyze",
                files={"file": ("test.png", sample_png, "image/png")},
                data={"prompt": "Describe this image"},
            )

        assert response.status_code == 200
        data = response.json()
        assert data["model"] == "llama3.2-vision"
        assert data["response"] == "I see a red image."
        assert "id" in data
        assert "timestamp" in data
        assert data["processing_ms"] == 42

    async def test_analyze_with_custom_prompt(
        self, client: AsyncClient, sample_png: bytes
    ) -> None:
        with patch(
            "ai_server.providers.ollama.OllamaProvider.analyze",
            new_callable=AsyncMock,
        ) as mock_analyze:
            mock_analyze.return_value = AnalysisResult(
                response="response",
                model="llama3.2-vision",
                processing_ms=10,
            )

            response = await client.post(
                "/api/analyze",
                files={"file": ("test.png", sample_png, "image/png")},
                data={"prompt": "What colors dominate?"},
            )

        assert response.status_code == 200
        mock_analyze.assert_called_once()

    async def test_analyze_rejects_missing_file(
        self, client: AsyncClient
    ) -> None:
        response = await client.post(
            "/api/analyze",
            data={"prompt": "Describe"},
        )
        assert response.status_code == 422

    async def test_analyze_rejects_missing_prompt(
        self, client: AsyncClient, sample_png: bytes
    ) -> None:
        response = await client.post(
            "/api/analyze",
            files={"file": ("test.png", sample_png, "image/png")},
        )
        assert response.status_code == 422

    async def test_analyze_handles_provider_error(
        self, client: AsyncClient, sample_png: bytes
    ) -> None:
        with patch(
            "ai_server.providers.ollama.OllamaProvider.analyze",
            new_callable=AsyncMock,
        ) as mock_analyze:
            import httpx

            mock_analyze.side_effect = httpx.HTTPStatusError(
                "error",
                request=httpx.Request("POST", "http://localhost:11434"),
                response=httpx.Response(500),
            )

            response = await client.post(
                "/api/analyze",
                files={"file": ("test.png", sample_png, "image/png")},
                data={"prompt": "Describe"},
            )

        assert response.status_code == 500

    async def test_analyze_with_custom_model_uses_settings(
        self, sample_png: bytes
    ) -> None:
        settings = Settings(
            default_model="gemma-3-12b-vision",
            ollama_model="gemma-3-12b-vision",
        )
        app = create_app(settings=settings.model_copy(update={"metrics_port": 0}))
        async with AsyncClient(
            transport=ASGITransport(app=app),
            base_url="http://test",
        ) as custom_client:
            with patch(
                "ai_server.providers.ollama.OllamaProvider.analyze",
                new_callable=AsyncMock,
            ) as mock_analyze:
                mock_analyze.return_value = AnalysisResult(
                    response="ok",
                    model="gemma-3-12b-vision",
                    processing_ms=5,
                )

                response = await custom_client.post(
                    "/api/analyze",
                    files={"file": ("test.png", sample_png, "image/png")},
                    data={"prompt": "Describe"},
                )

        assert response.status_code == 200
        data = response.json()
        assert data["model"] == "gemma-3-12b-vision"

    async def test_analyze_returns_503_when_circuit_breaker_open(
        self, client: AsyncClient, sample_png: bytes
    ) -> None:
        cb = client._transport.app.state.circuit_breaker
        cb.failure_threshold = 1
        import httpx

        with patch(
            "ai_server.providers.ollama.OllamaProvider.analyze",
            new_callable=AsyncMock,
        ) as mock_analyze:
            mock_analyze.side_effect = httpx.HTTPStatusError(
                "error",
                request=httpx.Request("POST", "http://localhost:11434"),
                response=httpx.Response(500),
            )
            response1 = await client.post(
                "/api/analyze",
                files={"file": ("test.png", sample_png, "image/png")},
                data={"prompt": "Describe"},
            )
            assert response1.status_code == 500

        with patch(
            "ai_server.providers.ollama.OllamaProvider.analyze",
            new_callable=AsyncMock,
        ) as mock_analyze:
            mock_analyze.side_effect = httpx.HTTPStatusError(
                "error",
                request=httpx.Request("POST", "http://localhost:11434"),
                response=httpx.Response(500),
            )
            response2 = await client.post(
                "/api/analyze",
                files={"file": ("test.png", sample_png, "image/png")},
                data={"prompt": "Describe"},
            )

        assert response2.status_code == 503

    async def test_readiness_returns_not_ready_when_circuit_open(
        self, client: AsyncClient
    ) -> None:
        from ai_server.circuit_breaker import CircuitState

        cb = client._transport.app.state.circuit_breaker
        cb.state = CircuitState.OPEN
        cb.failure_count = 5
        response = await client.get("/health/ready")
        assert response.status_code == 200
        data = response.json()
        assert data["ready"] is False
        assert data["circuit_breaker_state"] == "open"

    async def test_analyze_without_circuit_breaker_fallback(
        self, sample_png: bytes
    ) -> None:
        app = create_app(settings=Settings(metrics_port=0))
        del app.state.circuit_breaker
        async with AsyncClient(
            transport=ASGITransport(app=app),
            base_url="http://test",
        ) as ac:
            with patch(
                "ai_server.providers.ollama.OllamaProvider.analyze",
                new_callable=AsyncMock,
            ) as mock_analyze:
                mock_analyze.return_value = AnalysisResult(
                    response="ok",
                    model="llama3.2-vision",
                    processing_ms=5,
                )
                response = await ac.post(
                    "/api/analyze",
                    files={"file": ("test.png", sample_png, "image/png")},
                    data={"prompt": "Describe"},
                )

        assert response.status_code == 200
        data = response.json()
        assert data["response"] == "ok"
