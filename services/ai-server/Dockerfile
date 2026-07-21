# syntax=docker/dockerfile:1
# check=experimental=all

# base Stage 1: Base Installation
FROM python:3.14-slim AS base

USER root

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update \
    && apt-get install -y --no-install-recommends curl tini \
    && rm -rf /var/lib/apt/lists/*

# Create a non-root system user with explicit IDs
RUN groupadd -g 10001 appgroup \
    && useradd -u 10001 -g appgroup -m -s /sbin/nologin appuser

# builder Stage 2: Build & Dependency Installation
FROM base AS builder

# Install uv
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/

# Set working directory and environment variables
WORKDIR /app
ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy

# Copy dependency files first to leverage Docker caching
RUN --mount=type=cache,target=/root/.cache/uv \
    --mount=type=bind,source=uv.lock,target=uv.lock \
    --mount=type=bind,source=pyproject.toml,target=pyproject.toml \
    uv sync --frozen --no-install-project --no-dev

# Copy the rest of the application source code
COPY . .

# Sync the project itself
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen --no-dev

# runtime Stage 3: Minimal Runtime Image
FROM base AS runtime

WORKDIR /app

# Copy virtual environment and source from builder
COPY --from=builder --chown=root:appgroup /app/.venv /app/.venv
COPY --from=builder --chown=root:appgroup /app/src/ /app/src/
COPY --from=builder --chown=root:appgroup /app/configs/ /app/configs/

# Set environment variables to use the virtual environment automatically
ENV PATH="/app/.venv/bin:$PATH" \
    PYTHONUNBUFFERED=1

# Switch to the unprivileged user
USER 10001

EXPOSE 8000 8001 8002

ENTRYPOINT ["/usr/bin/tini", "--"]

CMD ["uvicorn", "ai_server.main:app", "--host", "0.0.0.0", "--port", "8000"]
