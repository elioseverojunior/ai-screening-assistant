from __future__ import annotations

from os import environ
from typing import TYPE_CHECKING

import logging

from opentelemetry import _logs, trace
from opentelemetry.exporter.otlp.proto.http._log_exporter import OTLPLogExporter
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
from opentelemetry.instrumentation.httpx import HTTPXClientInstrumentor
from opentelemetry.instrumentation.logging import LoggingInstrumentor
from opentelemetry.sdk._logs import LoggerProvider
from opentelemetry.sdk._logs.export import BatchLogRecordProcessor
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor

from ai_server.config import Settings
from ai_server.logging import get_logger

if TYPE_CHECKING:
    from fastapi import FastAPI

logger = get_logger(__name__)


def setup_otel(settings: Settings, app: FastAPI | None = None) -> None:
    service_name = "ai-server"
    endpoint = (
        f"{settings.otel_collector_endpoint}/v1/traces"
        if settings.otel_collector_endpoint
        else None
    )
    log_endpoint = (
        f"{settings.otel_collector_endpoint}/v1/logs"
        if settings.otel_collector_endpoint
        else None
    )

    resource = Resource.create(
        {
            "service.name": service_name,
            "telemetry.sdk.name": "opentelemetry",
            "telemetry.sdk.language": "python",
            "telemetry.sdk.version": "1.0.0",
            "deployment.environment": environ.get(
                "DEPLOYMENT_ENVIRONMENT", "development"
            ),
        }
    )

    if endpoint:
        logger.info("Configuring OpenTelemetry", extra={"props": {"traces_endpoint": endpoint, "logs_endpoint": log_endpoint}})
        tracer_provider = TracerProvider(resource=resource)
        tracer_provider.add_span_processor(
            BatchSpanProcessor(OTLPSpanExporter(endpoint=endpoint))
        )
        trace.set_tracer_provider(tracer_provider)

        logger_provider = LoggerProvider(resource=resource)
        logger_provider.add_log_record_processor(
            BatchLogRecordProcessor(OTLPLogExporter(endpoint=log_endpoint))
        )
        _logs.set_logger_provider(logger_provider)

        LoggingInstrumentor().instrument(
            set_logging_format=True,
            log_level=settings.otel_log_level,
        )

        # Use handler from opentelemetry-instrumentation-logging instead of deprecated SDK handler
        from opentelemetry.instrumentation.logging.handler import LoggingHandler as OTelLoggingHandler
        ai_server_logger = logging.getLogger("ai_server")
        ai_server_logger.addHandler(
            OTelLoggingHandler(level=logging.NOTSET, logger_provider=logger_provider)
        )

        FastAPIInstrumentor().instrument()
        if app is not None:
            FastAPIInstrumentor.instrument_app(app)
        HTTPXClientInstrumentor().instrument()
        logger.info("OpenTelemetry initialized successfully")
    else:
        logger.info("OpenTelemetry not configured (no endpoint)")


