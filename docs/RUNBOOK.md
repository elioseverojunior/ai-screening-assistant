# Screening LLM Assistant — Runbook

This runbook contains all essential commands for building, testing, and running the Screening LLM Assistant components.

---

## Table of Contents

1. [macOS App](#macos-app)
2. [iOS App](#ios-app)
3. [AI Server (Python/FastAPI)](#ai-server-pythonfastapi)
4. [Observability Stack (Docker)](#observability-stack-docker)
5. [Quick Reference (mise tasks)](#quick-reference-mise-tasks)

---

## macOS App

**Project:** `clients/ai-screening-assistant/macos-ai-screening-assistant.xcodeproj`
**Scheme:** `macos-ai-screening-assistant`  
**Workspace:** `clients/ai-screening-assistant/ai-screening-assistant.xcworkspace`

### Build

```bash
# From workspace (recommended — resolves Swift Package Manager dependencies)
xcodebuild build \
  -workspace clients/ai-screening-assistant/ai-screening-assistant.xcworkspace \
  -scheme "macos-ai-screening-assistant" \
  -destination "platform=macOS" \
  -configuration Debug

# From project directly
xcodebuild build \
  -project clients/ai-screening-assistant/macos-ai-screening-assistant.xcodeproj \
  -scheme "macos-ai-screening-assistant" \
  -destination "platform=macOS" \
  -configuration Debug
```

### Test

```bash
# From workspace (recommended)
xcodebuild test \
  -workspace clients/ai-screening-assistant/ai-screening-assistant.xcworkspace \
  -scheme "macos-ai-screening-assistant" \
  -destination "platform=macOS" \
  -parallel-testing-enabled NO

# From project directly
xcodebuild test \
  -project clients/ai-screening-assistant/macos-ai-screening-assistant.xcodeproj \
  -scheme "macos-ai-screening-assistant" \
  -destination "platform=macOS" \
  -parallel-testing-enabled NO
```

### Test Without Building

```bash
xcodebuild test-without-building \
  -workspace clients/ai-screening-assistant/ai-screening-assistant.xcworkspace \
  -scheme "macos-ai-screening-assistant" \
  -destination "platform=macOS" \
  -parallel-testing-enabled NO
```

### Clean

```bash
# Clean build artifacts
xcodebuild clean \
  -workspace clients/ai-screening-assistant/ai-screening-assistant.xcworkspace \
  -scheme "macos-ai-screening-assistant"

# Clean derived data
rm -rf ~/Library/Developer/Xcode/DerivedData/macos-ai-screening-assistant-*
```

### Lint & Format

```bash
# SwiftLint
swiftlint lint --strict clients/ai-screening-assistant/macos-ai-screening-assistant/

# SwiftFormat
swiftformat clients/ai-screening-assistant/macos-ai-screening-assistant/
```

### List Schemes & Destinations

```bash
# List all schemes in macOS project
xcodebuild -list -project clients/ai-screening-assistant/macos-ai-screening-assistant.xcodeproj

# List available destinations
xcodebuild -scheme "macos-ai-screening-assistant" -showdestinations
```

---

## iOS App

**Project:** `clients/ai-screening-assistant/ios-ai-screening-assistant.xcodeproj`  
**Scheme:** `ios-ai-screening-assistant`  
**Workspace:** `clients/ai-screening-assistant/ai-screening-assistant.xcworkspace`

### Build

```bash
# From workspace (recommended)
xcodebuild build \
  -workspace clients/ai-screening-assistant/ai-screening-assistant.xcworkspace \
  -scheme "ios-ai-screening-assistant" \
  -destination "platform=iOS Simulator,name=iPhone 16" \
  -configuration Debug

# From project directly
xcodebuild build \
  -project clients/ai-screening-assistant/ios-ai-screening-assistant.xcodeproj \
  -scheme "ios-ai-screening-assistant" \
  -destination "platform=iOS Simulator,name=iPhone 16" \
  -configuration Debug
```

### Test

```bash
# From workspace (recommended)
xcodebuild test \
  -workspace clients/ai-screening-assistant/ai-screening-assistant.xcworkspace \
  -scheme "ios-ai-screening-assistant" \
  -destination "platform=iOS Simulator,name=iPhone 16" \
  -parallel-testing-enabled NO

# From project directly
xcodebuild test \
  -project clients/ai-screening-assistant/ios-ai-screening-assistant.xcodeproj \
  -scheme "ios-ai-screening-assistant" \
  -destination "platform=iOS Simulator,name=iPhone 16" \
  -parallel-testing-enabled NO
```

### List Simulators

```bash
# List all available iOS simulators
xcrun simctl list devices

# List only booted simulators
xcrun simctl list devices booted
```

---

## AI Server (Python/FastAPI)

**Project:** `services/ai-server/`  
**Package Manager:** `uv`

### Setup & Sync Dependencies

```bash
cd services/ai-server
uv sync
```

### Test

```bash
# Unit tests only (excludes e2e)
uv run pytest tests/ -m "not e2e" --cov=ai_server --cov-report=term-missing -x

# End-to-end tests only (requires mock server)
uv run pytest tests/e2e/ -v -x --no-cov

# All tests
uv run pytest -v --cov=ai_server --cov-report=term-missing -x
```

### Run Server Locally

```bash
# Development mode with auto-reload
uv run uvicorn ai_server.main:app --reload --host 0.0.0.0 --port 8000

# Production mode
uv run uvicorn ai_server.main:app --host 0.0.0.0 --port 8000
```

### Configuration

Environment variables (prefix: `AI_SERVER_`):

| Variable | Default | Description |
|----------|---------|-------------|
| `AI_SERVER_PROVIDER` | `ollama` | AI provider (`ollama` or `zen`) |
| `AI_SERVER_DEFAULT_MODEL` | `llama3.2-vision` | Default model name |
| `AI_SERVER_OLLAMA_BASE_URL` | `http://localhost:11434` | Ollama endpoint |
| `AI_SERVER_ZEN_API_KEY` | `""` | OpenCode Zen API key |
| `AI_SERVER_OTEL_COLLECTOR_ENDPOINT` | `""` | OTel collector HTTP endpoint |
| `AI_SERVER_METRICS_PORT` | `0` | Separate metrics port (0 = inline) |
| `AI_SERVER_HEALTH_PORT` | `8001` | Health check port (0 = disabled) |
| `AI_SERVER_LOG_LEVEL` | `INFO` | Log level |
| `AI_SERVER_CB_FAILURE_THRESHOLD` | `5` | Circuit breaker failures before open |
| `AI_SERVER_CB_RECOVERY_TIMEOUT` | `30` | Circuit breaker recovery timeout (seconds) |

---

## Observability Stack (Docker)

**Compose File:** `development/docker-compose.yml`

### Commands

```bash
# Start full stack
docker compose -f development/docker-compose.yml up -d

# Start with rebuild
docker compose -f development/docker-compose.yml up --build -d

# Stop stack
docker compose -f development/docker-compose.yml down

# Tail logs
docker compose -f development/docker-compose.yml logs -f

# Restart stack
docker compose -f development/docker-compose.yml down && docker compose -f development/docker-compose.yml up -d

# Show status
docker compose -f development/docker-compose.yml ps
```

### Service URLs

| Service | URL | Credentials |
|---------|-----|-------------|
| Grafana | http://localhost:3000 | admin / admin |
| Jaeger | http://localhost:16686 | — |
| Prometheus | http://localhost:9090 | — |
| AI Server API | http://localhost:8000 | — |
| AI Server Swagger | http://localhost:8000/docs | — |
| AI Server Health (liveness) | http://localhost:8001/health/live | — |
| AI Server Health (readiness) | http://localhost:8001/health/ready | — |

---

## Quick Reference (mise tasks)

All commands below assume you're in the project root (`/Volumes/Development/personal/elioseverojunior/github/ai/ai-screening-assistant`).

### macOS App

```bash
# Build
mise run build:macOS              # from project (Debug)
mise run build:macOS -- -c Release
mise run build:macOS:workspace    # from workspace

# Test
mise run test:macOS               # from project
mise run test:macOS:workspace     # from workspace (recommended)

# Clean
mise run clean:macOS

# Lint & Format
mise run lint:macOS
mise run format:macOS
```

### iOS App

```bash
# Build
mise run build:iOS                                      # Debug, iPhone 16
mise run build:iOS -- -c Release                        # Release
mise run build:iOS -- -d "platform=iOS Simulator,name=iPhone 16 Pro"  # Custom destination
mise run build:iOS:workspace                            # from workspace

# Test
mise run test:iOS               # from project
mise run test:iOS:workspace     # from workspace (recommended)
```

### AI Server

```bash
mise run sync:ai-server         # uv sync
mise run test:ai-server         # unit tests
mise run test:ai-server-e2e     # e2e tests
mise run test:ai-server-all     # all tests
```

### Observability

```bash
mise run compose-up             # docker compose up -d
mise run compose-down           # docker compose down
mise run compose-logs           # docker compose logs -f
mise run compose-restart        # restart stack
mise run compose-status         # docker compose ps
mise run compose-rebuild        # build + up
```

### UI Access

```bash
mise run grafana                # http://localhost:3000
mise run jaeger                 # http://localhost:16686
mise run prometheus             # http://localhost:9090
mise run swagger                # http://localhost:8000/docs
```

### Utilities

```bash
mise run list:schemes:macOS     # list macOS schemes
mise run list:schemes:iOS       # list iOS schemes
mise run list:destinations:macOS  # list macOS destinations
mise run list:destinations:iOS    # list iOS simulators
mise run envs                   # show key environment variables
```

---

## Troubleshooting

### Logging Timeout in Xcode

If you see: `Logging Error: Failed to initialize logging system due to time out`

The fix is already applied in the scheme (`macos-ai-screening-assistant.xcscheme`):

```xml
<EnvironmentVariables>
  <EnvironmentVariable key="IDEPreferLogStreaming" value="YES" isEnabled="YES"/>
</EnvironmentVariables>
```

This is set in both `TestAction` and `LaunchAction`.

### Tests Fail with Double-Free

`ScreenshotStore` must inherit from `NSObject` (not a pure Swift class) to avoid double-free crashes under XCTest. This is already implemented.

### Simulator Not Found

```bash
# List available runtimes
xcrun simctl list runtimes

# Create a new simulator if needed
xcrun simctl create "iPhone 16" "iOS 18.0"
```

### Derived Data Issues

```bash
# Clean all derived data for this project
rm -rf ~/Library/Developer/Xcode/DerivedData/macos-ai-screening-assistant-*
rm -rf ~/Library/Developer/Xcode/DerivedData/ios-ai-screening-assistant-*
```

---

## Project Structure

```
ai-screening-assistant/
├── clients/
│   └── ai-screening-assistant/
│       ├── ai-screening-assistant.xcworkspace
│       ├── ios-ai-screening-assistant/
│       ├── ios-ai-screening-assistant.xcodeproj
│       ├── macos-ai-screening-assistant/
│       ├── macos-ai-screening-assistant.xcodeproj
│       └── macos-ai-screening-assistantTests/
├── services/
│   └── ai-server/
│       ├── src/ai_server/
│       ├── configs/
│       ├── tests/
│       └── Dockerfile
├── development/
│   ├── docker-compose.yml
│   ├── otel-collector/
│   ├── prometheus/
│   ├── grafana/
│   └── loki/
├── docs/
│   ├── README.md       # Architecture & roadmap
│   └── RUNBOOK.md      # This file
└── mise.toml           # Task runner config
```

---

*Generated from project configuration. Update when schemes, destinations, or paths change.*