# Screening LLM Assistant — Project

## Overview

Multi-platform screen intelligence pipeline. macOS background agent captures screen frames via hotkeys, stores locally, and will post to an AI server for analysis. Results render on iPad/iPhone.

## Project Structure

```
apps/
  macos-screening-llm-assistant/     # macOS capture node
    macos-screening-llm-assistant/    # App source
    macos-screening-llm-assistantTests/  # XCTest suite
  ios-screening-llm-assistant/        # Future mobile client
development/                          # OTel + Grafana + Prometheus stack
docs/                                 # Architecture docs with Mermaid diagrams
services/                             # Future AI server (Python/Rust)
```

## macOS App Modules

- **`macos_screening_llm_assistantApp.swift`** — `@main` entry, `Settings` scene, `MenuBarLifecycleManager`, keyboard hooks, log window
- **`Screenshots.swift`** — `ScreenCaptureProviding` protocol, `ScreenCaptureService`, `ScreenCaptureManager`, `ScreenshotStore: NSObject`, `CapturedScreenshot`, `ScreenshotGalleryView`
- **`KeyBindings.swift`** — `KeyBindings` Codable model, `Modifier` enum, `modifierFlags()`, `KeyBindingsController` (persists to plist)
- **`OtelTracing.swift`** — `OtelTracer` singleton, OTLP HTTP exporter, span lifecycle, log records
- **`ContentView.swift`** — Placeholder (unused)

## Test Suite (34 passing)

KeyBindingsTests (26 tests) — Codable, controller, modifier flags, conflicts, toggle integration
ScreenshotsTests (8 tests) — capture service, store CRUD, manager integration, disk persistence

Run: `xcodebuild test -project apps/macos-screening-llm-assistant/... -scheme "macos-screening-llm-assistant" -destination "platform=macOS" -parallel-testing-enabled NO`

## Critical Rules

- **`ScreenshotStore` must inherit from `NSObject`** — pure Swift class deallocation causes a double-free crash at address `0x7ffd56525e40` under XCTest
- **`captureManager` is `lazy`** — prevents initialization during test processes
- **`dispatchScreenCapture()` guards against XCTest** — checks `XCTestConfigurationFilePath` env var
- **All LLM output renders ONLY on iPad/iPhone** — macOS never displays AI response text
- **macOS app runs as background agent** — no Dock icon (`LSUIElement`)
- **Hotkeys**: `⌘⌥⇧ + '` (toggle menu bar), `⌘⌥⇧ + .` (capture screen)

## Architecture (future)

1. **AI Server** — Python FastAPI or Rust Axum consuming free endpoints (HuggingFace, Groq, Gemini, Cloudflare Workers AI)
2. **macOS → Server** — `POST /api/analyze` with image payload, response stored alongside local `CapturedScreenshot`
3. **Server → iOS** — WebSocket push from macOS to iPad/iPhone client for AI result rendering

See `docs/README.md` for full architecture diagrams and roadmap.
