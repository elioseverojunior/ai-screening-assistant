from __future__ import annotations

from typing import Any

from fastapi import FastAPI
from fastapi.testclient import TestClient

from ai_server.config import Settings
from ai_server.main import app as _real_app
from ai_server.main import create_app, lifespan


def _collect_routes(app_instance: FastAPI) -> set[str]:
    paths: set[str] = set()
    for route in app_instance.routes:
        path: Any = getattr(route, "path", None)
        if path:
            paths.add(path)
        ctx = getattr(route, "include_context", None)
        if ctx is not None:
            for r in ctx.included_router.routes:
                p = getattr(r, "path", None)
                if p:
                    paths.add(p)
    return paths


def _app(**overrides: Any) -> FastAPI:
    return create_app(settings=Settings(metrics_port=0, health_port=0, **overrides))


class TestLifespan:
    async def test_lifespan_runs_setup_otel(self) -> None:
        app_instance = _app()
        async with lifespan(app_instance):
            assert app_instance.state.settings.default_model == "llama3.2-vision"

    async def test_lifespan_settings_persists_after_yield(self) -> None:
        app_instance = _app()
        async with lifespan(app_instance):
            pass
        assert app_instance.state.settings.default_model == "llama3.2-vision"


class TestCreateApp:
    def test_create_app_returns_fastapi_instance(self) -> None:
        app_instance = _app()
        assert isinstance(app_instance, FastAPI)

    def test_app_has_docs_enabled(self) -> None:
        app_instance = _app()
        assert app_instance.docs_url == "/docs"
        assert app_instance.redoc_url == "/redoc"

    def test_app_title_and_version(self) -> None:
        app_instance = _app()
        assert (
            app_instance.title
            == "Screening LLM Assistant — AI Server"
        )
        assert app_instance.version == "0.1.0"

    def test_app_has_router_routes(self) -> None:
        app_instance = _app()
        paths = _collect_routes(app_instance)
        assert "/api/analyze" in paths
        assert "/health/live" in paths
        assert "/health/ready" in paths

    def test_app_with_custom_settings(self) -> None:
        settings = Settings(
            metrics_port=0,
            default_model="custom-model",
            ollama_base_url="http://custom:11434",
        )
        app_instance = create_app(settings=settings)
        assert app_instance.state.settings == settings

    def test_app_settings_set_during_create(self) -> None:
        app_instance = _app()
        assert hasattr(app_instance.state, "settings")
        assert app_instance.state.settings.default_model == "llama3.2-vision"

    def test_app_module_includes_router_route(self) -> None:
        paths = _collect_routes(_real_app)
        assert "/api/analyze" in paths
        assert "/health/live" in paths
        assert "/health/ready" in paths

    def test_swagger_ui_accessible(self) -> None:
        client = TestClient(_app())
        response = client.get("/docs")
        assert response.status_code == 200
        assert "swagger" in response.text.lower()

    def test_openapi_json_accessible(self) -> None:
        client = TestClient(_app())
        response = client.get("/openapi.json")
        assert response.status_code == 200
        spec = response.json()
        assert spec["info"]["title"] == "Screening LLM Assistant — AI Server"
        assert "/api/analyze" in spec["paths"]
        assert "/health/live" in spec["paths"]

    def test_redoc_ui_accessible(self) -> None:
        client = TestClient(_app())
        response = client.get("/redoc")
        assert response.status_code == 200
        assert "redoc" in response.text.lower()

    def test_metrics_endpoint_accessible(self) -> None:
        client = TestClient(_app())
        response = client.get("/metrics")
        assert response.status_code == 200
        assert "text/plain" in response.headers["content-type"]
        assert "charset=utf-8" in response.headers["content-type"]
        body = response.text
        assert "# HELP" in body
        assert "ai_screening_requests_total" in body

    def test_metrics_counts_requests(self) -> None:
        client = TestClient(_app())
        client.get("/health/live")
        response = client.get("/metrics")
        body = response.text
        assert 'ai_screening_requests_total{method="GET",path="/health/live",status="200"}' in body

    def test_create_app_without_settings_arg_uses_defaults(self) -> None:
        import os

        os.environ["AI_SERVER_METRICS_PORT"] = "0"
        os.environ["AI_SERVER_HEALTH_PORT"] = "0"
        try:
            app_instance = create_app()
            assert isinstance(app_instance, FastAPI)
            assert app_instance.state.settings.default_model == "llama3.2-vision"
        finally:
            del os.environ["AI_SERVER_METRICS_PORT"]
            del os.environ["AI_SERVER_HEALTH_PORT"]
