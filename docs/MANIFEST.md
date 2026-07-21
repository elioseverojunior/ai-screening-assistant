# Application Manifest: Screening LLM Assistant

## System Overview

Cross-device orchestration between macOS (data-capture sensor) and AI inference server (Python FastAPI).

---

## Component 1: macOS Client

**Path:** `apps/screening-assistant`
**Target:** macOS 15.0+ (Swift / SwiftUI / AppKit)
**Process Mode:** Agent / Accessory (`LSUIElement` = true, no Dock icon)

### Entitlements

| Entitlement | Purpose |
|---|---|
| `com.apple.security.device.screen-capture` | Screen capture via ScreenCaptureKit |
| `com.apple.security.network.client` | Outbound TCP to AI server |

### Hotkeys

| Shortcut | Action |
|----------|--------|
| `⌘⌥⇧ + .` | Capture screen |
| `⌘⌥⇧ + '` | Toggle menu bar visibility |

### Test Suite (36 XCTest)

| Suite | Tests |
|---|---|
| `KeyBindingsTests` | 26 (Codable, controller, modifier flags, conflicts, toggle) |
| `ScreenshotsTests` | 8 (capture service, store CRUD, manager, disk persistence) |
| `UploadServiceTests` | 2 (upload-and-analyze, server error) |

---

## Component 2: AI Inference Server

**Path:** `services/ai-server`
**Stack:** Python FastAPI with uv package manager
**Ports:** 8000 (app), 8001 (health), 9000 (metrics)

### Internal Modules (16, 482 statements, 100% coverage)

| Module | Purpose |
|---|---|
| `main.py` | `create_app()`, lifespan, middleware registration |
| `router.py` | API routes: `/api/analyze`, `/health/live`, `/health/ready` |
| `config.py` | `Settings` — TOML + env vars (`AI_SERVER_` prefix) |
| `circuit_breaker.py` | Resilience: 5 failures → open, 30s → half-open |
| `metrics.py` | Prometheus (9 instruments: requests, analysis, CB, image bytes) |
| `otel.py` | OTel traces → Jaeger, logs → Loki, FastAPI + httpx instrumentation |
| `health_server.py` | Isolated HTTP server on port 8001 for Docker healthchecks |
| `local_only.py` | Docs IP restriction (403 from public IPs) |
| `logging.py` | Structured JSON logging to stdout (K8s format) |
| `schemas.py` | Pydantic models |
| `providers/base.py` | `AnalysisProvider` ABC |
| `providers/ollama.py` | Ollama vision API client |
| `providers/zen.py` | OpenCode Zen API client |
| `providers/factory.py` | Provider factory |

### Providers

- **Ollama** — Local vision model via `http://localhost:11434/v1/chat/completions`
- **Zen** — OpenCode DeepSeek V4 Flash Free at `https://opencode.ai/zen/v1`

### Providers (planned)

- HuggingFace Inference API
- Groq Cloud
- Google Gemini
- Cloudflare Workers AI

### Observability Stack (Docker)

| Service | Port | Purpose |
|---|---|---|
| OTel Collector | 4318 | OTLP ingestion |
| Jaeger | 16686 | Distributed tracing |
| Loki | 3100 | Log aggregation (OTLP) |
| Prometheus | 9090 | Metrics scraping |
| Grafana | 3000 | Dashboards (18 panels, 5 rows) |
| cAdvisor | 8080 | Container resource metrics |

### Test Suite (117 tests, 100% coverage)

- 83 unit tests across 16 modules
- 9 end-to-end integration tests
- 17 local-only + health server + OTel tests

---

---

## Pipeline Architecture

1. **Trigger:** macOS hotkey (`⌘⌥⇧+.`)
2. **Capture:** ScreenCaptureKit → NSImage → TIFF/manifest on disk
3. **Analyze (future):** POST image to AI Server `/api/analyze`
4. **Bridge (future):** Server broadcasts response via WebSocket to clients
5. **Render (future):** Connected clients display analysis
