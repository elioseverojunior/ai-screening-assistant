# AGENTS.md

## Project

Multi-platform screen intelligence pipeline: **macOS background agent** (SwiftUI/AppKit, no Dock icon) captures screen silently via ScreenCaptureKit → **AI inference server** (Python FastAPI, uv-managed) → **iOS/iPadOS client** (scaffold only).

## Commands

Use `mise run <task>` — not raw xcodebuild/pytest directly. Key tasks:

| Task | What it runs |
|------|-------------|
| `mise run test:macOS` | macOS XCTest suite (34 tests) |
| `mise run test:ai-server` | AI server unit tests (109 tests, 100% cov) |
| `mise run build:macOS` | Build macOS app (Debug) |
| `mise run compose-up` | Start OTel + Jaeger + Loki + Prometheus + Grafana |
| `mise run lint:macOS` | SwiftLint (strict mode) |
| `mise run format:macOS` | SwiftFormat |

For raw xcodebuild/pytest commands see `docs/RUNBOOK.md`.

## Principles

- **100% coverage** at all times.
- **TDD** for new code AND when refactoring existing code (test first, then refactor).
- **KISS/DRY/YAGNI/TDA/SOLID** — apply what fits, don't over-engineer.

## Structure

```
clients/ai-screening-assistant/   # NOT apps/ — this is the actual path
├── macos-ai-screening-assistant/   # Source: 6 Swift files
├── macos-ai-screening-assistantTests/  # XCTest suite
├── ios-ai-screening-assistant/     # Scaffold only
├── ai-screening-assistant.xcworkspace/
services/ai-server/                 # Python FastAPI, uv, 16 modules
├── src/ai_server/
├── tests/                          # 109 tests
development/docker-compose.yml      # Full observability stack
docs/                               # README.md, RUNBOOK.md, MANIFEST.md
```

## macOS Gotchas

- `ScreenshotStore` **must** inherit `NSObject` — pure Swift class causes double-free crash in XCTest.
- `captureManager` is `lazy` — test processes never initialize capture pipeline.
- `dispatchScreenCapture()` guards against XCTest via `XCTestConfigurationFilePath` env var.
- Tests require `-parallel-testing-enabled NO` (scheme already sets this).
- Screen capture uses `SCScreenshotManager` — silent, no blink/flash.
- Swift 6.2.4 (`.swift-version`), SwiftLint strict (many rules disabled), SwiftFormat.
- App Sandbox is **disabled** (keybindings use global event monitor; sandbox blocks it).
- App name defaults to **"Assistant"** in Finder/Menu Bar; rename the `.app` file in `/Applications/` to change it after deployment. Replace icon via Get Info > Paste.
- App runs as background agent (`LSUIElement` + `NSApp.setActivationPolicy(.accessory)`) — no Dock icon.

## Test Suites

### KeyBindingsTests (26 tests)

| Group | Tests | What it covers |
|-------|-------|---------------|
| Codable | 4 | Round-trip encode/decode, empty/all modifiers, property defaults |
| Controller | 2 | Default values from controller, save-then-read |
| Modifier enum | 3 | Symbols, count, raw values |
| `modifierFlags()` | 5 | All, subset, empty, invalid strings, order independence |
| `SystemShortcutConflict` | 5 | Conflict for `d`, no conflict for default/other keys, case insensitivity |
| Integration | 2 | Modifier flags match keybinding properties |
| Menu bar toggle | 6 | Hide/show with matching/wrong keybinding/modifiers, updated keybindings |

Run: `mise run test:macOS` or `mise run test:macOS:workspace`

### ScreenshotsTests (8 tests)

| Test | What it covers |
|------|---------------|
| `testMakeTestImage` | Helper creates valid NSImage |
| `testCaptureServiceUsesScreenCaptureService` | Protocol-based capture works |
| `testStoreAddsScreenshot` | Store count increments |
| `testStoreRetrievesScreenshot` | Image lookup by ID |
| `testStoreCountIncrements` | Multiple adds increment correctly |
| `testCaptureManagerCapturesAndStores` | Manager integrates service + store |
| `testStoreWithStorageDirectory` | Disk persistence + cleanup |
| `testStoreUsesSharedInstance` | Singleton shared instance |

Run: same commands as above.

## AI Server Gotchas

- Package manager is **`uv`** (not pip, not poetry). Run `uv sync` in `services/ai-server/`.
- Python 3.14+ required.
- Config: TOML + env vars with `AI_SERVER_` prefix. See `docs/RUNBOOK.md` for full table.
- Providers: Ollama (local) and Zen (OpenCode). Circuit breaker: 5 failures → open, 30s recovery.
- `/docs` blocked from public IPs (local_only middleware).

## OpenCode Config

- `opencode.json` references `CLAUDE.md` as instructions file.
- Skill `screening-architecture` at `.opencode/skills/screening-architecture/SKILL.md` — use for cross-component decisions.
- References: `docs/` for architecture/roadmap; `xcode-scheme` (hidden) for scheme config.
