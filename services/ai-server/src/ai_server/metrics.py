from __future__ import annotations

from fastapi import FastAPI, Response
from prometheus_client import (
    CONTENT_TYPE_LATEST,
    Counter,
    Gauge,
    Histogram,
    generate_latest,
    registry,
)


def setup_metrics(
    app: FastAPI,
    prefix: str = "screening_llm",
    metrics_port: int = 0,
) -> MetricsRegistry:
    reg = MetricsRegistry(prefix)

    if metrics_port:
        from prometheus_client import start_http_server

        start_http_server(metrics_port, registry=reg.registry)
    else:
        @app.get("/metrics", include_in_schema=False, tags=["observability"])
        async def metrics() -> Response:
            return Response(
                content=generate_latest(reg.registry),
                media_type=CONTENT_TYPE_LATEST,
            )

    return reg


class MetricsRegistry:
    def __init__(self, prefix: str = "screening_llm") -> None:
        self.registry = registry.CollectorRegistry(auto_describe=True)
        self.prefix = prefix

        self.requests_total = Counter(
            name=f"{prefix}_requests_total",
            documentation="Total HTTP requests processed",
            labelnames=["method", "path", "status"],
            registry=self.registry,
        )

        self.request_duration = Histogram(
            name=f"{prefix}_request_duration_seconds",
            documentation="HTTP request duration in seconds",
            labelnames=["method", "path"],
            buckets=(0.01, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0),
            registry=self.registry,
        )

        self.analysis_total = Counter(
            name=f"{prefix}_analysis_total",
            documentation="Total image analyses performed",
            labelnames=["model", "provider", "status"],
            registry=self.registry,
        )

        self.analysis_duration = Histogram(
            name=f"{prefix}_analysis_duration_seconds",
            documentation="AI analysis duration in seconds",
            labelnames=["model", "provider"],
            buckets=(0.1, 0.5, 1.0, 2.0, 5.0, 10.0, 30.0, 60.0),
            registry=self.registry,
        )

        self.active_requests = Gauge(
            name=f"{prefix}_active_requests",
            documentation="Currently active HTTP requests",
            labelnames=[],
            registry=self.registry,
        )

        self.image_bytes_total = Counter(
            name=f"{prefix}_image_bytes_total",
            documentation="Total image bytes received",
            labelnames=[],
            registry=self.registry,
        )

        self.last_analysis_timestamp = Gauge(
            name=f"{prefix}_last_analysis_timestamp_seconds",
            documentation="Unix timestamp of the last analysis",
            labelnames=["model"],
            registry=self.registry,
        )

        self.cb_state = Gauge(
            name=f"{prefix}_circuit_breaker_state",
            documentation="Circuit breaker state (0=closed, 1=open, 2=half_open)",
            labelnames=["name"],
            registry=self.registry,
        )

        self.cb_failures = Gauge(
            name=f"{prefix}_circuit_breaker_failures",
            documentation="Current circuit breaker failure count",
            labelnames=["name"],
            registry=self.registry,
        )
