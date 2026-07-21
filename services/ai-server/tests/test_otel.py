from __future__ import annotations

from fastapi import FastAPI
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider

from ai_server.config import Settings
from ai_server.otel import setup_otel


class TestSetupOtel:
    def test_no_op_when_endpoint_empty(self) -> None:
        settings = Settings(otel_collector_endpoint="")
        setup_otel(settings)
        assert trace.get_tracer_provider() is not None

    def test_initializes_when_endpoint_set(self) -> None:
        settings = Settings(
            otel_collector_endpoint="http://localhost:14318",
            otel_log_level="WARNING",
        )
        setup_otel(settings)
        provider = trace.get_tracer_provider()
        assert isinstance(provider, TracerProvider)

    def test_instruments_existing_app(self) -> None:
        app = FastAPI()
        settings = Settings(
            otel_collector_endpoint="http://localhost:14318",
        )
        setup_otel(settings, app=app)
        assert getattr(app, "_is_instrumented_by_opentelemetry", False)
