---
name: screening-architecture
description: |
  Use when making architecture decisions about the Screening LLM Assistant.
  Covers the macOS capture node, AI server design, iOS client, data flow
  between components, and Mermaid diagram updates. Use ONLY when the task
  involves cross-component architecture or changes to the data pipeline.
---

# Screening LLM Assistant — Architecture Skill

## Data flow

1. **macOS** captures screen on hotkey (`⌘⌥⇧+.`), stores locally in
   `ScreenshotStore`, and sends PNG to AI server via `POST /api/analyze`
2. **AI Server** (Python/Rust) receives the image, routes to a free vision LLM
   endpoint, returns JSON analysis
3. **macOS** receives the response, attaches it to the `CapturedScreenshot`,
   and forwards to the iOS client via WebSocket
4. **iOS/iPadOS** displays the analysis in a SwiftUI view

## Key invariants

- macOS never renders AI response text (headless background agent)
- `ScreenshotStore: NSObject` (required to prevent XCTest double-free)
- `ScreenCaptureService.captureFullScreen()` is a stub returning `NSImage(size: .zero)`
  until `ScreenCaptureKit` integration is added
- Test suite: `xcodebuild test ... -parallel-testing-enabled NO` (34 tests)

## Design references

- `docs/README.md` — full Mermaid architecture diagrams
- `CLAUDE.md` — project-level instructions for this codebase
- `opencode.json` — project opencode configuration
