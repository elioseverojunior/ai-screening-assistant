# Task Checklist — Project Intent Implementation

- [x] macOS Client — HTTP Upload & Server Integration
  - [x] Create `ScreenCaptureUploadService.swift` for HTTP multipart posting to AI Server (`/api/analyze`)
  - [x] Update `CapturedScreenshot` schema in `Screenshots.swift` to store AI analysis results
  - [x] Integrate upload service into `ScreenCaptureManager`
- [x] iOS Client — SwiftUI Analysis Viewer
  - [x] Create `WebSocketClientManager.swift` to receive analysis payloads from macOS agent
  - [x] Update `ContentView.swift` to display formatted vision analysis and status dashboard
- [x] macOS Unit Tests & Verification
  - [x] Add `UploadServiceTests.swift` for HTTP upload testing
  - [x] Run `mise run test:macOS` to verify Swift test suite (36 tests passed)
  - [x] Run `mise run test:ai-server` to verify Python AI server suite (113 tests passed, 100% coverage)

