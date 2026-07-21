# Project Intent & Roadmap Implementation Plan

Verification of the `clients/` codebase has been completed. All 34 macOS unit tests pass with zero failures. This plan outlines the technical path to evolve the system from **v0.1 (local capture & standalone server)** to **v1.0 (end-to-end screen intelligence pipeline)**.

---

## User Review Required

> [!IMPORTANT]
> - **Architecture Scope**: The macOS agent is intentionally designed to remain a **headless background agent** (`LSUIElement` enabled). AI analysis results will **not** be rendered on the macOS screen; they will be streamed to the iOS/iPadOS client.
> - **Communication Protocol**: WebSocket over local network (or direct HTTP/WebSocket relay) is planned between the macOS agent and the iOS viewer.

---

## Current Verification Findings (`clients/`)

| Target | Status | Notes |
|---|---|---|
| **macOS Agent** (`macos-ai-screening-assistant`) | ✅ Verified | Silent screen capture (`SCScreenshotManager`), global hotkey hooks (`⌘⌥⇧+.`), menu bar lifecycle, OTel tracing. |
| **macOS Test Suite** (`macos-ai-screening-assistantTests`) | ✅ 34/34 Passed | `KeyBindingsTests` (26 tests) & `ScreenshotsTests` (8 tests) pass in 0.138s. |
| **iOS Client Scaffold** (`ios-ai-screening-assistant`) | ⚠️ Scaffold Only | Basic `Hello, world!` view; requires WebSocket receiver & analysis UI. |

---

## Proposed Changes & Roadmap (v1.0 Intent)

### 1. macOS Client — HTTP Upload & Server Integration

#### [NEW] [ScreenCaptureUploadService.swift](file:///Volumes/Development/personal/elioseverojunior/github/ai/ai-screening-assistant/clients/ai-screening-assistant/macos-ai-screening-assistant/ScreenCaptureUploadService.swift)
- Implement HTTP multipart client to send captured screenshots (PNG/JPEG) to `http://localhost:8000/api/analyze`.
- Connect `CaptureManager` to upload service upon hotkey trigger.
- Save server JSON analysis into `CapturedScreenshot`.

#### [MODIFY] [Screenshots.swift](file:///Volumes/Development/personal/elioseverojunior/github/ai/ai-screening-assistant/clients/ai-screening-assistant/macos-ai-screening-assistant/Screenshots.swift)
- Update `CapturedScreenshot` schema to store AI response payload & analysis metadata.

#### [NEW] [WebSocketServerManager.swift](file:///Volumes/Development/personal/elioseverojunior/github/ai/ai-screening-assistant/clients/ai-screening-assistant/macos-ai-screening-assistant/WebSocketServerManager.swift)
- Create local WebSocket broadcast server to push incoming analysis results to connected iOS clients.

---

### 2. iOS/iPadOS Client — Real-Time Analysis Viewer

#### [MODIFY] [ContentView.swift](file:///Volumes/Development/personal/elioseverojunior/github/ai/ai-screening-assistant/clients/ai-screening-assistant/ios-ai-screening-assistant/ContentView.swift)
- Replace default placeholder UI with a dedicated SwiftUI Screen Intelligence dashboard.
- Render vision analysis markdown/JSON with formatted highlights and screenshot previews.

#### [NEW] [WebSocketClientManager.swift](file:///Volumes/Development/personal/elioseverojunior/github/ai/ai-screening-assistant/clients/ai-screening-assistant/ios-ai-screening-assistant/WebSocketClientManager.swift)
- WebSocket client for connecting to the macOS agent, managing connection status, auto-reconnecting, and decoding incoming analysis payloads.

---

### 3. macOS Unit Test Suite Expansion

#### [NEW] [UploadServiceTests.swift](file:///Volumes/Development/personal/elioseverojunior/github/ai/ai-screening-assistant/clients/ai-screening-assistant/macos-ai-screening-assistantTests/UploadServiceTests.swift)
- Add mock network protocol unit tests verifying HTTP multipart payload construction and API error handling.

---

## Verification Plan

### Automated Tests
- `mise run test:macOS` — Run existing 34 tests + new `UploadServiceTests`.
- `mise run test:ai-server` — Verify AI inference server endpoint integrity (109 unit tests).
- `mise run lint:macOS` — SwiftLint strict validation.

### Manual Verification
1. Run local AI server (`uv run uvicorn ai_server.main:app --port 8000`) or `docker compose`.
2. Trigger macOS hotkey `⌘⌥⇧+.`.
3. Verify screenshot is uploaded to `POST /api/analyze`, analyzed by vision LLM (Ollama/Zen), and stored locally.
4. Launch iOS simulator, connect to macOS agent via WebSocket, and verify real-time rendering of analysis.
