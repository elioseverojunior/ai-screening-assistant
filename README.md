# Screening Assistant

Multi-platform screen intelligence pipeline: macOS capture node and Python FastAPI AI server.

## Quick Start

```bash
# macOS app tests
xcodebuild test -project apps/screening-assistant/screening-assistant.xcodeproj \
  -scheme "screening-assistant" -destination "platform=macOS"

# AI server tests
cd services/ai-server && uv run pytest --cov=ai_server

# Start full observability stack
docker compose -f development/docker-compose.yml up -d
```

## Architecture

| Component | Stack | Status |
|---|---|---|
| **macOS Agent** | SwiftUI + AppKit | ✅ 36 XCTest passing |
| **AI Server** | Python FastAPI (uv) | ✅ 117 tests, 100% coverage |
| **Observability** | OTel + Jaeger + Loki + Prometheus + Grafana + cAdvisor | ✅ |


### Ports

| Port | Service | Host Access |
|------|---------|-------------|
| 8000 | FastAPI application | Public |
| 8001 | Health checks | `127.0.0.1` only |
| 9000 | Prometheus metrics | Internal Docker only |

## Documentation

- [Architecture & Roadmap](docs/README.md) — Mermaid diagrams, module maps, ports, test details
- [Manifest](docs/MANIFEST.md) — System overview, components, pipeline
