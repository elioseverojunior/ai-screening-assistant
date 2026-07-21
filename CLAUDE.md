# AI Screening Assistant — Project

## Overview

Multi-platform screen intelligence pipeline. macOS background agent captures screen frames via hotkeys, stores locally, and posts to an AI server for analysis.

## Project Structure

```
apps/
  screening-assistant/         # Single Xcode project (macOS + shared)
    screening-assistant/       # App source
    screening-assistantTests/  # XCTest suite
  shared/                      # ScreeningShared Swift package
development/                    # OTel + Grafana + Prometheus stack
docs/                           # Architecture docs with Mermaid diagrams
services/ai-server/             # Python FastAPI AI server
```

## macOS App Modules

- **`ScreeningAssistantApp.swift`** — `@main` entry, `Settings` scene, `MenuBarLifecycleManager`, keyboard hooks, log window
- **`Screenshots.swift`** — `ScreenCaptureProviding` protocol, `ScreenCaptureService`, `ScreenCaptureManager`, `ScreenshotStore: NSObject`, `CapturedScreenshot`, `ScreenshotGalleryView`
- **`KeyBindings.swift`** — `KeyBindings` Codable model, `Modifier` enum, `modifierFlags()`, `KeyBindingsController` (persists to plist)
- **`OtelTracing.swift`** — `OtelTracer` singleton, OTLP HTTP exporter, span lifecycle, log records
- **`ContentView.swift`** — Placeholder (unused)

## Test Suite (36 passing)

KeyBindingsTests (26 tests) — Codable, controller, modifier flags, conflicts, toggle integration
ScreenshotsTests (8 tests) — capture service, store CRUD, manager integration, disk persistence
UploadServiceTests (2 tests) — upload-and-analyze, server error handling

Run: `xcodebuild test -project apps/screening-assistant/screening-assistant.xcodeproj -scheme "screening-assistant" -destination "platform=macOS" -parallel-testing-enabled NO`

## Critical Rules

- **`ScreenshotStore` must inherit from `NSObject`** — pure Swift class deallocation causes a double-free crash at address `0x7ffd56525e40` under XCTest
- **`captureManager` is `lazy`** — prevents initialization during test processes
- **`dispatchScreenCapture()` guards against XCTest** — checks `XCTestConfigurationFilePath` env var
- **All LLM output renders ONLY on clients** — macOS is capture-only (WebSocket broadcasts analysis)
- **macOS app runs as background agent** — no Dock icon (`LSUIElement`)
- **Hotkeys**: `⌘⌥⇧ + '` (toggle menu bar), `⌘⌥⇧ + .` (capture screen)

## Architecture (future)

1. **AI Server** — Python FastAPI consuming free endpoints (HuggingFace, Groq, Gemini, Cloudflare Workers AI)
2. **macOS → Server** — `POST /api/analyze` with image payload, response stored alongside local `CapturedScreenshot`
3. **Server → Clients** — WebSocket broadcast to all connected clients (macOS + iOS)

See `docs/README.md` for full architecture diagrams and roadmap.
