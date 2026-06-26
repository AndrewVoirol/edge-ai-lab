---
name: test-runner
description: Run XCTest test plans, execute specific tests, parse xcresult bundles, and interpret test results for EdgeAILab. Use this skill when running unit tests, integration tests, UI tests, device tests, performance tests, verification runs, or debugging test failures.
---

# Test Runner

This skill covers running the EdgeAILab test suite, using test plans, executing specific tests, parsing results, and verification discipline.

## Prefer xcodebuild-mcp Over Shell Commands

The project has `xcodebuild-mcp` configured. **Always prefer MCP tools** (`test_device`, `test_macos`, `test_sim`) over raw `xcodebuild` commands. They handle build-deploy cycles, signing, and DerivedData management correctly.

### xcodebuild-mcp Rules

- **Call `session_show_defaults` before the first build/test/run** in every session. Set defaults with `session_set_defaults` if missing.
- `extraArgs` = xcodebuild flags (e.g., `-testPlan`, `-only-testing:`). `launchArgs` = runtime app args (NOT available on `test_*` tools).
- **When MCP tools fail unexpectedly**, read the MCP build log (path in tool output) and compare the exact `xcodebuild` command to what works from terminal. Common differences: `-derivedDataPath`, `-destination`, `-configuration`. Don't assume "permissions" or "environment" without evidence.
- **macOS UI tests**: If a "Timed out while enabling automation mode" error occurs, it means the XCUITest runner binary hasn't been authorized for UI automation. macOS TCC keys this authorization to the binary's **absolute path** in DerivedData — every rebuild invalidates it. The permanent fix is `automationmodetool enable-automationmode-without-authentication` (requires user password once). See `TESTING.md` Prerequisites.
- **`scheme` passed as a tool parameter may not override session defaults** on all MCP tools. When switching between macOS (`"Edge AI Lab"`) and iOS (`EdgeAILab_iOS`) testing, always update session defaults via `session_set_defaults` rather than relying on per-call parameter overrides. Reset defaults back after.
- **`config.yaml` `sessionDefaults` take precedence over `session_set_defaults`**. The `.xcodebuildmcp/config.yaml` file's `sessionDefaults` section cannot be overridden at runtime. For macOS tests (scheme `"Edge AI Lab"`), use raw `xcodebuild` commands directly instead of MCP tools, or temporarily edit `config.yaml`.

### Session Setup (Required Once Per Session)

Before your first build, test, or run call, call `session_show_defaults` to verify the active configuration. If defaults are not set:

```
session_set_defaults:
  workspacePath: <project-root>/EdgeAILab.xcworkspace
  scheme: EdgeAILab_iOS          # or "Edge AI Lab" for macOS
  deviceId: 3B50314A-0702-5188-A321-BCD5CA5F8184   # for device tests
```

## Test Architecture

### Test Targets

| Target | Platform | Source Dir | Host App |
|---|---|---|---|
| `EdgeAILab_iOSTests` | iOS | `Tests/**` | `EdgeAILab_iOS` |
| `EdgeAILab_macOSTests` | macOS | `Tests/**` | `Edge AI Lab` |
| `EdgeAILab_macOSUITests` | macOS | `UITests/**` | `EdgeAILab_macOS` |
| `EdgeAILab_iOSUITests` | iOS | `iOSUITests/**` | `EdgeAILab_iOS` |

> **NOTE:** iOS and macOS test targets share the same `Tests/**` source files.

### Test Plans

| Test Plan | Purpose | Timeout | Scheme |
|---|---|---|---|
| `UnitTests.xctestplan` | Fast CI tests, no model needed | 60s per test | Both |
| `IntegrationTests.xctestplan` | Cross-component + real-model | 300s per test | `EdgeAILab_iOS` |
| `PerformanceTests.xctestplan` | Regression benchmarks | 600s per test | `EdgeAILab_iOS` |
| `macOSUITests.xctestplan` | macOS UI flows | — | `Edge AI Lab` |
| `iOSUITests.xctestplan` | iOS UI flows | — | `EdgeAILab_iOS` |
| `SimulatorTests.xctestplan` | Simulator-specific | — | `EdgeAILab_iOS` |

**Critical rule**: A test target MUST be included in a `.xctestplan` referenced by the scheme. Otherwise `-only-testing:` will fail with *"isn't a member of the specified test plan or scheme."*

### Test Pyramid

| Layer | What It Tests | Examples | Speed |
|---|---|---|---|
| **Unit** | Single function/type in isolation | `ChatMessageTests`, `ThinkingParserTests` | Fast (~0.01s) |
| **Behavioral** | State machines, lifecycle, real persistence | `DownloadManagerBehaviorTests`, `ViewModelE2ETests` | Medium (~0.2s) |
| **Integration** | Real engine + real models, cross-component | `InferenceQualityTests`, `SmartFallbackIntegrationTests` | Slow (~5-50s) |
| **E2E / Automation** | Full app via DeveloperAutomationHarness | `automation/flows/*.json` | Very slow (~60s+) |

## Testing Rules (from AGENTS.md)

### Test Plan Management
- **When adding a new test target**: (1) Create a `.xctestplan` JSON in the project root, (2) add it to the relevant scheme's `testAction` in `Project.swift`, (3) run `tuist generate`.
- **Tuist `testPlans` API**: Coverage is controlled by the `.xctestplan` JSON (`codeCoverageEnabled: true`), NOT by Tuist's `options: .options(coverage: true)`.

### Concurrency
- **Never run concurrent xcodebuild UI test processes.** macOS UI tests and iOS Simulator UI tests share the screen, keyboard, and accessibility session. Running two xcodebuild test sessions simultaneously produces false failures.
- **Never pipe `xcodebuild test` through `tail -N` for long-running UI tests.** `tail` buffers all output until the upstream process exits. Instead, redirect to a file and check it.

### Test Authoring
- **macOS UI tests require Cmd+N after launch** — `launchApp()` retries Cmd+N up to 3 times with increasing delays (2s, 3s, 4s).
- **Flow test `expected_elements` should use accessibility identifiers, not display text.** Display text in SwiftUI `Section` headers, `Label`, and `Text` views may not reliably appear in the iOS 27 accessibility tree.
- **Test resources don't bundle to physical iOS devices** via Tuist. Tests that load from `Bundle(for:)` must include an XCTSkip guard when the resource returns nil.
- **`/tmp` is not writable on physical iOS devices.** Use `NSTemporaryDirectory()` or add an `XCTSkip` guard.
- **Tuist bundles resources into macOS/Simulator test targets.** Never assert `loadImage() == nil` in a test that runs on macOS — the resource may be there.
- **`generate_image` produces JPEG data with `.png` extension.** Never assert PNG magic bytes. Accept both JPEG and PNG headers.
- **Swift Testing migration**: When creating a new `@Suite` that replaces an XCTest file, add the XCTest class name to `UnitTests.xctestplan` → `skippedTests` in the same commit.
- **Swift Testing name collisions**: Tuist compiles all test files into a single target. Before naming a new Swift Testing struct, grep for the name across `Tests/`.
- **UserDefaults cross-framework races**: `.serialized` only serializes within a single Swift Testing `@Suite`. XCTestCase methods touching the same keys run concurrently.
- **`ByteCountFormatter` output is locale/precision-dependent.** Use `contains("GB")`, not exact strings.
- **IEEE 754 rounding in format tests**: Never use `.5` boundary values.
- **When testing multi-path filesystem resolution**, mirror the method's search priority.

## Verification Run Discipline

- During a verification run, do NOT skip any item unless the user explicitly says to skip it.
- If an item fails, record the exact error output and continue. Do not stop to fix it.
- If a prerequisite is missing, record "BLOCKED: [reason]" and continue.
- At the start of every verification session, state which items you plan to run. At the end, state which items you actually ran. The two lists must match.
- Never use `--skip-benchmarks`, `--skip-device`, or `--only-unit` flags unless the user explicitly requests a partial run.
- **When the user asks to re-run tests, re-run ALL of them.** Do not selectively skip.
- **Never declare a failure "permanent" or "known" after a single occurrence.** Verify with at least one re-run.
- **Before declaring a tool "broken", verify you understand its intended behavior.** Read `--help` output and test with minimal cases.

## Test Result Reporting

When reporting test results, always distinguish between:
- **(a) Tests passed** — ran and succeeded
- **(b) Tests failed** — ran and failed
- **(c) Tests skipped at runtime** — xcodebuild reported as skipped (XCTSkip, etc.)
- **(d) Test classes excluded by the test plan** — never ran because `skippedTests` in the `.xctestplan` filtered them out

For category (d), name the excluded classes. UnitTests.xctestplan excludes 7 classes: `BatchEvalTests`, `GalleryParityBenchmarkTests`, `InferenceQualityTests`, `MetricsStoreTests` (XCTestCase version), `MultiTurnIntegrationTests`, `PerformanceTests`, `SmartFallbackIntegrationTests`.

IntegrationTests.xctestplan, PerformanceTests.xctestplan, and SimulatorTests.xctestplan are in the `EdgeAILab_iOS` scheme. They require explicit `-testPlan` flags.

- **Verify comparison/regression script outputs contain actual comparisons.** A script that reports "no regressions" with zero comparisons is a vacuous truth, not a meaningful pass.
- **When a script exits 0 (success), verify the output data matches expectations.** Exit code alone is insufficient.

## Flow-Driven UI Tests (macOS)

The macOS UI test suite uses **flow-driven testing** — test logic is defined in JSON flow files under `automation/flows/ui/`, not hardcoded in Swift.

| Test Method | Flow File |
|---|---|
| `testFlowBasicNavigation` | `macos_basic_navigation_flow.json` |
| `testFlowSettingsInteractions` | `macos_settings_flow.json` |
| `testFlowSidebarStructure` | `macos_sidebar_flow.json` |
| `testFlowInputAreaComponents` | `macos_input_area_flow.json` |
| `testFlowChatInteractions` | `macos_chat_flow.json` |
| `testFlowQuickActions` | `macos_quick_actions_flow.json` |
| `testFlowMCPServerManagement` | `macos_mcp_server_flow.json` |
| `testFlowMenuCommands` | `macos_menu_commands_flow.json` |
| `testFlowURLImport` | `macos_url_import_flow.json` |
| `testFlowCommunityBrowser` | `macos_community_browser_flow.json` |

### ⚠️ macOS Window Launch Fix (CRITICAL)

On macOS, `XCUIApplication().launch()` starts the app but **creates no window**. The `launchApp()` helper sends Cmd+N up to 3 times with increasing delays (2s, 3s, 4s).

## Expected Results

| Platform | Total Tests | Skipped | Duration |
|----------|-------------|---------|----------|
| iOS Simulator | 418+ | ~12 | ~23s |
| macOS | 216+ | 0 | ~10s |
| macOS (UI) | 10 | 0 | ~270s |
| iOS Device | 418+ | ~15 | ~3.4s |

## Running Tests

### With MCP (Preferred)

**iOS simulator:**
```
test_sim:
  extraArgs: ["-testPlan", "UnitTests"]
```

**macOS:**
```
session_set_defaults:
  scheme: Edge AI Lab
test_macos:
  extraArgs: ["-only-testing:EdgeAILab_macOSTests/SomeTestClass"]
```

**iOS device:**
```
test_device:
  extraArgs: ["-testPlan", "UnitTests"]
```

### With xcodebuild CLI

```bash
# iOS Simulator
xcodebuild test \
  -workspace EdgeAILab.xcworkspace \
  -scheme EdgeAILab_iOS \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro Max' \
  -testPlan UnitTests \
  -quiet 2>&1

# macOS
xcodebuild test \
  -workspace EdgeAILab.xcworkspace \
  -scheme "Edge AI Lab" \
  -destination 'platform=macOS' \
  -quiet 2>&1

# Specific test class
xcodebuild test \
  -workspace EdgeAILab.xcworkspace \
  -scheme EdgeAILab_iOS \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro Max' \
  -only-testing:EdgeAILab_iOSTests/DownloadInfrastructureTests \
  -quiet 2>&1
```

## Source File → Test Mapping

| If you changed... | Run these tests |
|---|---|
| `Sources/Downloads/ModelDownloadManager.swift` | `DownloadManagerBehaviorTests`, `DownloadManagerTests` |
| `Sources/Conversation/ConversationViewModel.swift` | `ViewModelE2ETests`, `ConversationViewModelTests` |
| `Sources/Engine/InstrumentedEngine.swift` | `InferenceQualityTests` |
| `Sources/Evaluation/EvalRunner.swift` | `ViewModelE2ETests/testEvalRunnerFullSuite`, `EvalRunnerTests` |
| `Sources/Conversation/ConversationStore.swift` | `ViewModelE2ETests`, `ConversationStoreTests` |
| `Sources/Models/ModelMetadata.swift` | `ModelMetadataTests`, `ModelRegistryTests` |
| LiteRTLM package update | `InferenceQualityTests` (full suite with real models) |
| Any UI change | Automation harness flows (see `automation-harness` skill) |

## Known Device Pitfalls

| Issue | Symptom | Workaround |
|-------|---------|------------|
| Liquid Glass XCUITest | Form internals not exposed on physical device | a11y flow verifies "Settings" tab only |
| `performScrollTo` on iOS | `app.swipeUp()` hung on iOS 26 physical devices | Uses coordinate-based `press(forDuration:thenDragTo:)` |
| Test resources missing | Tuist doesn't bundle resources to physical devices | XCTSkip guard when `Bundle(for:)` resource is nil |
| "Bad CPU type" | Stale DerivedData causes misleading launch error | Use MCP `test_device` instead of raw xcodebuild |
| MCP macOS UI automation | "Timed out while enabling automation mode" | Set `derivedDataPath` to standard Xcode DerivedData path |

## Troubleshooting

### Test Target Not Found
Run `tuist generate` to regenerate the project.

### Tests Hang
Likely cause: perpetual animation saturating the runloop. Check that any `PhaseAnimator` or `.repeatForever` animation has the `isRunningTests` guard.

### Module Import Errors
Build the main app target first, then run tests.
