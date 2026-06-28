# Changelog

All notable changes to Edge AI Lab will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **Flow-Driven UI Test Framework** — 33 JSON automation flows (6 core + 27 UI) with `FlowDrivenUITestRunner` covering both macOS and iOS platforms. Each flow defines navigation steps, element assertions, and expected states.
- **iOS UI Test Parity** — Dedicated `iOSUITests` target with platform-specific `FlowDrivenUITestRunner.swift` and 13 iOS UI flow files.
- **macOS UI Test Suite** — 14 macOS-specific UI flow files covering chat, settings, model hub, eval, benchmark, and navigation flows.
- **Device Benchmarking Pipeline** — `deploy_device.sh` with `--console` stdout streaming, `SKIP_BUILD=1` support, and `devicectl` result pulling for physical iOS device benchmarks.
- **Eval Baselines** — Real device-measured eval baselines (`eval_baselines.json`) with pass rates across Math, Tool Calling, Reasoning, and Multimodal suites.
- **Coverage Enforcement** — CI coverage threshold at 28% floor with `coverage_baseline.json` tracking. Codecov integration with macOS/iOS flags.
- **Automation Harness Improvements** — `AutomationFlowRunner` with flow validation (`validate_flows.sh`), benchmark comparison (`benchmark_compare.sh`), and eval comparison (`eval_comparison.sh`) scripts.
- **Logic Extraction for Testability** — Extracted pure logic from SwiftUI views into `enum` namespaces (`EvalRunnerLogic`, `ModelDetailFormatters`, etc.) for unit testing.
- **~900 New Tests** — Coverage push adding 10+ new test files and ~900 test methods across unit, integration, and UI test targets.
- **Location Tool** (`get_location`) — GPS coordinates + reverse-geocoded address via CoreLocation. Wi-Fi triangulation on macOS, full GPS on iOS.
- **Motion Tool** (`get_device_motion`) — Accelerometer, gyroscope, and attitude data from CoreMotion. iOS only with graceful macOS degradation.
- **Camera Tool** (`take_photo`) — Triggers the system photo picker via notification so the model can request photo attachments during conversation.
- **Instruction Following Eval Suite** — 15 prompts testing format compliance (bullet counts, lowercase-only, JSON format, numbered lists, word avoidance, paragraph structure, markdown headers).
- **Gemma 4 Capabilities Eval Suite** — 12 prompts testing multi-tool chains, correct tool selection vs. avoidance, complex reasoning, context retention, and combined instruction+tool workflows.

### Fixed

- **macOS Model Loading Regression** — Fixed path resolution and download-to-load lifecycle that prevented models from loading on macOS.
- **iOS Eval View Layout** — Fixed alignment, wrapping, and layout consistency issues in the iOS evaluation runner view.
- **iOS Navigation Dead-Ends** — Eliminated navigation dead-ends in Chat, Eval, and Model Detail tabs on iOS.
- **UI Clipping** — Fixed clipping in Chat and EvalComparison views.
- **Compiler Warnings** — Resolved compiler errors and warnings across the codebase.
- **CalculatorTool NSExpression Crash** — Added structural validation (`CalculatorValidation`) to prevent uncatchable ObjC exceptions from malformed model-generated math expressions (empty strings, unbalanced parens, consecutive operators).
- **Auto-Save Race Condition** — Captured conversation identity at the start of inference so switching conversations mid-stream no longer corrupts saved data. Added generation token to prevent stale tool callbacks from mutating finalized state.
- **Tool Call Events Silently Dropped** — Fixed `updateLastAssistantMessage()` to search backwards for the last assistant message instead of only checking the very last message, preventing tool result messages from blocking updates.
- **ConversationStore Corrupt File Recovery** — Added index staleness detection (file count vs index count mismatch triggers rebuild) and corrupt file quarantine (renames to `.json.corrupt` instead of losing data).

### Changed

- **xcresulttool Made Non-Blocking** — `kishikawakatsumi/xcresulttool@v1` now runs with `continue-on-error: true` due to Node.js 20 deprecation on macos-26 runners.
- **SwiftLint Severity** — Downgraded SwiftLint severity levels to reduce noise in CI.
- **CI Hardening** — Fixed Git LFS smudge filter conflicts with LiteRT-LM Android binaries, added SPM resolution retry with `clonedSourcePackagesDirPath` fallback, improved cache busting.

### Infrastructure

- **Dependabot Bumps** — `codecov/codecov-action` v5→v7, `softprops/action-gh-release` v2→v3, `actions/stale` v9→v10.
- **AGENTS.md Rules** — Added CI debugging, strategic recommendations, Codecov policy, JSONSerialization safety, NSExpression safety, and verification integrity rules.
- **Automation Scripts** — Added `run_full_matrix.sh`, `ci_test_runner.sh`, `eval_comparison.sh`, `benchmark_compare.sh`, `validate_flows.sh`, `device_health_check.sh`, `monitor_device.sh`, and `update_eval_baselines.sh`.

## [2.0.0-rc1] - 2026-06-13

### Added

- **URL Import — "Paste and Go"** — Paste any HuggingFace model URL to parse metadata, preview capabilities, and download directly into the app.
  - macOS: `macOSURLImportSheet` with 8-state rendering (idle → parsing → fetching → analyzing → readyToDownload → downloading → complete / failed), progressive metadata disclosure, and multi-file picker for repos with multiple `.litertlm` files.
  - iOS: `iOSURLImportSheet` with equivalent pipeline and mobile-optimized layout.
  - ⌘I keyboard shortcut opens the import sheet on macOS.
  - Inline quick-paste field in the Community Models browser for fast URL entry.
- **Dynamic Model Catalog** — Persistent JSON catalog that merges known registry models with user-imported community models. Imported models survive app restarts and appear alongside built-in models.
- **HuggingFace Search** — Freeform search across all HuggingFace models from the Community Models browser. Powered by `HFModelBrowser.searchModels()`.
- **Model Card Parser** — Infers runtime type, vision/audio capabilities, architecture, context window, and quantization from HuggingFace model card metadata with confidence levels (verified → high → medium → low).
- **Kaggle URL Import** — Paste Kaggle model URLs (`kaggle.com/models/*`) to import models. Requires Kaggle API credentials (username + API key) stored in Settings/Keychain.
- **Kaggle Credentials UI** — Settings tab for saving Kaggle username and API key in Keychain (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`). Credentials auto-loaded by `URLImportManager` on import.
- **iOS Conversation History** — Conversation picker sheet accessible from the Chat tab toolbar. Lists saved conversations with rename, fork, export, and delete actions.
- **iOS Eval Export** — Share/export button in the Eval tab for exporting evaluation results as JSON or CSV.
- **Batch Eval "Run All" Mode** — Run all evaluation suites across all downloaded models with time estimation and sequential execution. Results available as comparison view on completion.
- **iOS Custom Suite Editor** — Create and edit evaluation suites on iOS with a mobile-friendly sheet interface, prompt editor, and 7 scoring variant picker.
- **Onboarding** — First-run welcome flow introducing the app's capabilities: on-device inference, model management, evaluation, and benchmarking.
- **iOS Model Hub Pause/Resume** — Pause and resume buttons now functional in the iOS model download list.

### Fixed

- **"Analyze an image" quick action** — The quick action card now correctly opens the photo picker via `.photosPicker(isPresented:)` modifier. Previously, the notification set a state variable that nothing read. ([InputAreaView.swift](Sources/InputAreaView.swift))
- **Dead `showSettings` state** — Removed unused `@State private var showSettings` from `iOSChatTabView`. ([iOSChatTabView.swift](Sources/iOSChatTabView.swift))
- **Dead `hfTokenAlert` property** — Removed unreferenced `@ViewBuilder` property from `ContentView` (the alert was already inlined elsewhere). ([ContentView.swift](Sources/ContentView.swift))
- **"Coming Soon" placeholder** — Replaced the non-functional "Coming Soon" badge in the Community Models browser with a live URL paste field connected to the import pipeline. ([DetailColumnView.swift](Sources/DetailColumnView.swift))
- **Model lifecycle: stale catalog entries** — `URLImportManager` now verifies model files exist on disk before shortcutting to `.complete`. If a model was deleted but still appears in the catalog, the stale entry is removed and re-import proceeds normally.
- **Known registry shortcut** — The known model shortcut in URL import now checks local disk before completing. If a known model file is missing, the pipeline falls through to the HF API fetch step for download.
- **Duplicate `12b` condition** — Fixed `ModelCardParser.inferParameterInfo()` where `12b` was checked twice instead of checking `12b || 13b`.
- **HuggingFace API rate limiting** — `HFModelBrowser` now retries on HTTP 429 (rate limit) and 5xx (server errors) with exponential backoff (1s → 2s → 4s, max 3 retries).

### Architecture

- `URLImportManager` state machine: idle → parsing → fetching → analyzing → readyToDownload → downloading → complete / failed.
- `KaggleModelParser` for Kaggle model metadata extraction via REST API with Basic Auth.
- `DynamicModelMetadata` with `MetadataConfidence` levels for import accuracy transparency.
- `ConversationViewModel` extended with `pendingImportURL`, `showURLImportSheet`, and `loadImportedModel()` for coordinating the import flow across views.

### Tests

- 10 URL Import integration tests (state machine, ViewModel integration, E2E pipeline, HF search).
- 5 macOS UI tests for ⌘I shortcut, URL import sheet, HF search, community browser, inline URL paste.
- Bug fix verification tests for notification wiring and callback plumbing.
- iOS feature tests for conversation history, eval export, batch eval, suite editor, and onboarding.
- Model lifecycle tests: catalog add/remove round-trip, stale entry cleanup, garbage URL rejection.
- KaggleTokenStorage tests: save/retrieve/delete/overwrite Keychain round-trip.
- HuggingFace API retry tests: error classification, graceful 401/404 handling.


## [1.0.0] - 2026-06-08

### Added

- **Layout** — 3-column `NavigationSplitView` layout (macOS) with Sidebar → Lab → Chat panes.
- **Multi-model support** — Gemma 4 E2B (Standard / Web), E4B (Standard / Web), and 12B Dense.
- **On-device inference** via LiteRT-LM with Metal GPU acceleration.
- **Smart GPU → CPU fallback** with detailed diagnostics when Metal is unavailable or fails.
- **6 built-in tools** — Calculator, DateTime, DeviceInfo, UnitConverter, TextAnalyzer, SystemHealth — for structured tool-calling workflows.
- **Agent Skills [Beta]** — Wikipedia and Maps skills (network-dependent, behind feature flag).
- **Thinking mode** with streaming `<think>` block parser and collapsible UI disclosure.
- **Multimodal input** — image attachments via `PhotosPicker` and audio file attachments (`.wav`, `.mp3`, `.aac`).
- **Deep benchmarking** — per-token latency, P95, time-to-first-token (TTFT), memory delta, and thermal-state tracking.
- **Performance dashboard** with historical metrics rendered via Swift Charts.
- **MCP server support** (macOS) via stdio-based JSON-RPC for external tool integration.
- **HuggingFace model browser** with organization listing and format detection.
- **Conversation persistence** with auto-save, fork, rename, export (JSON), and delete.
- **Dark Forest design system** with a curated color palette and centralized design tokens.
- **Developer automation harness** for benchmark matrix runs across models and backends.
- **282 unit tests** + UI test suite covering core inference, tool-calling, and navigation flows.

### Architecture

- MVVM with `@Observable` and full Swift 6 concurrency (`Sendable`, `actor` isolation).
- Protocol-based dependency injection (`InstrumentedEngineProtocol`) for testability.
- Centralized design tokens in `DesignSystem.swift` — no hardcoded colors or spacing.
- `os.Logger` + `os_signpost` instrumentation throughout for profiling and diagnostics.

### Known Limitations

- LiteRT-LM SDK is tracked on `branch("main")` — tagged releases currently have SPM packaging issues.
- App Sandbox is disabled (required for model file access and MCP subprocess spawning).
- iOS support is present in the codebase but is not the primary shipping target for v1.0.
- E4B and 12B benchmarks may not have formal numbers at launch.

[Unreleased]: https://github.com/AndrewVoirol/edge-ai-lab/compare/v2.0.0-rc1...HEAD
[2.0.0-rc1]: https://github.com/AndrewVoirol/edge-ai-lab/compare/v1.0.0...v2.0.0-rc1
[1.0.0]: https://github.com/AndrewVoirol/edge-ai-lab/releases/tag/v1.0.0
