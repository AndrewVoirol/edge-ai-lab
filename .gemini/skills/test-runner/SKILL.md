---
name: test-runner
description: Run XCTest test plans, execute specific tests, parse xcresult bundles, and interpret test results for EdgeAILab. Use this skill when running unit tests, integration tests, performance tests, or debugging test failures.
---

# Test Runner

This skill covers running the EdgeAILab test suite, using test plans, executing specific tests, and parsing results.

## Test Architecture

### Test Targets

| Target | Platform | Source Dir | Host App |
|---|---|---|---|
| `EdgeAILab_iOSTests` | iOS | `Tests/**` | `EdgeAILab_iOS` |
| `EdgeAILab_macOSTests` | macOS | `Tests/**` | `Edge AI Lab` |
| `EdgeAILab_macOSUITests` | macOS | `UITests/**` | `EdgeAILab_macOS` |
| `EdgeAILab_iOSUITests` | iOS | `iOSUITests/**` | `EdgeAILab_iOS` |

> **NOTE:** iOS and macOS test targets share the same `Tests/**` source files. The tests are compiled for both platforms.

### Test Plans

| Test Plan | Purpose | Timeout | Test Classes |
|---|---|---|---|
| `UnitTests.xctestplan` | Fast CI tests, no model needed | 60s per test | 46 classes (see below) |
| `IntegrationTests.xctestplan` | Cross-component + real-model inference tests | 300s per test | 4 classes |
| `PerformanceTests.xctestplan` | Regression benchmarks, model needed | 600s per test | 2 classes |

### Test Pyramid

Tests are organized into a layered pyramid. Higher layers provide more confidence but take longer:

| Layer | What It Tests | Examples | Speed |
|---|---|---|---|
| **Unit** | Single function/type in isolation | `ChatMessageTests`, `ThinkingParserTests` | Fast (~0.01s) |
| **Behavioral** | State machines, lifecycle, real persistence | `DownloadManagerBehaviorTests`, `ViewModelE2ETests` | Medium (~0.2s) |
| **Integration** | Real engine + real models, cross-component | `InferenceQualityTests`, `SmartFallbackIntegrationTests` | Slow (~5-50s) |
| **E2E / Automation** | Full app via DeveloperAutomationHarness | `automation/flows/*.json` | Very slow (~60s+) |

> **When to run which layer:**
> - **After any code change:** Run the relevant unit + behavioral tests
> - **After engine/model changes:** Run integration tests (requires models in `models/` directory)
> - **Before release:** Run all layers including automation harness

### Flow-Driven UI Tests (macOS)

The macOS UI test suite uses **flow-driven testing** — test logic is defined in JSON flow files under `automation/flows/ui/`, not hardcoded in Swift. Each `testFlow*` method in `EdgeAILabUITests.swift` loads a flow JSON and executes it via `FlowDrivenUITestRunner`.

| Test Method | Flow File | Tests |
|---|---|---|
| `testFlowBasicNavigation` | `macos_basic_navigation_flow.json` | Three-column layout, sidebar, detail column |
| `testFlowSettingsInteractions` | `macos_settings_flow.json` | Settings tabs, toggles, sampler controls |
| `testFlowSidebarStructure` | `macos_sidebar_flow.json` | Sidebar sections, empty states |
| `testFlowInputAreaComponents` | `macos_input_area_flow.json` | Prompt field, send button |
| `testFlowChatInteractions` | `macos_chat_flow.json` | Chat send and response |
| `testFlowQuickActions` | `macos_quick_actions_flow.json` | Quick action hints |
| `testFlowMCPServerManagement` | `macos_mcp_server_flow.json` | MCP server add via settings |
| `testFlowMenuCommands` | `macos_menu_commands_flow.json` | macOS menu bar commands |
| `testFlowURLImport` | `macos_url_import_flow.json` | URL import sheet and components |
| `testFlowCommunityBrowser` | `macos_community_browser_flow.json` | Community model browser |

> **Adding new UI tests:** Create a new flow JSON in `automation/flows/ui/`, add a `testFlow*` method that calls `FlowDrivenUITestRunner.runFlow(named:)`, and register it in the XCUITest class.

### ⚠️ macOS Window Launch Fix (CRITICAL)

On macOS, `XCUIApplication().launch()` starts the app but **creates no window**. This is because:
1. XCUITest `terminate()` in `tearDown` causes macOS to save window state as "0 windows open"
2. On the next `launch()`, macOS restores that empty state = no window, just menu bar

**The fix** (in `launchApp()` in `EdgeAILabUITests.swift`):
```swift
app.launch()
app.activate()
sleep(2)
#if os(macOS)
if app.windows.count == 0 {
    app.typeKey("n", modifierFlags: .command)  // Force WindowGroup to create window
    sleep(3)
}
#endif
```

**Without this fix**: `app.windows.count == 0`, `app.buttons.count == 0`, all UI queries fail.
**With this fix**: Window at (264, 175, 1200×800), 851 buttons, 72 staticTexts, all 10 flows pass.

**DO NOT:**
- Assume this is a framework regression — it's standard macOS state restoration behavior
- Try `.defaultLaunchBehavior(.presented)` alone — necessary but insufficient
- Try `-ApplePersistenceIgnoreState YES` alone — necessary but insufficient
- Try `XCUIApplication(bundleIdentifier:)` — doesn't help

### macOS Scroll Coordinate Fix

`FlowDrivenUITestRunner.performScrollTo()` uses `scrollTarget.coordinate(withNormalizedOffset:)` for drag scrolling. The scroll target must use the **window's** coordinate space, not the app's. If the window frame is invalid, fall back to keyboard `Page Down`.

```swift
let scrollTarget = app.windows.count > 0 ? app.windows.firstMatch : app
let frame = scrollTarget.frame
if frame.origin.x.isFinite && frame.width > 0 {
    // coordinate-based drag
} else {
    app.typeKey(.pageDown, modifierFlags: [])  // keyboard fallback
}
```

### UnitTests Test Plan Classes (49 classes)

**Unit Tests (wiring, parsing, data):**
- `AutomationFlowRunnerTests`, `BatchEvalTests`, `BenchmarkCardTests`, `BenchmarkPipelineTests`, `BugFixTests`
- `BuiltInEvalSuitesTests`, `ChatMessageTests`, `CommunityDownloadTests`
- `ConversationForkTests`, `ConversationStoreTests`
- `ConversationViewModelSamplerTests`, `ConversationViewModelTests`
- `DeveloperAutomationHarnessTests`, `DeviceMetricsSnapshotTests`
- `DownloadInfrastructureTests`, `DownloadManagerTests`
- `DynamicModelCatalogTests`, `DynamicModelMetadataTests`
- `EnvironmentInjectionTests` — Guards against singleton re-introduction
- `EvalResultTests`, `EvalRegressionCheckerTests`, `EvalRunnerTests`, `EvalScoringTests`, `EvalStoreTests`, `EvalSuiteTests`, `EvalPipelineTests`
- `ExperimentConfigTests`, `ExperimentalFlagsStateTests`, `FlowResultTests`
- `GalleryModelDiscoveryTests`, `HFModelBrowserTests`, `HFRetryTests`
- `InferenceMetricsIntegrationTests`, `InferenceMetricsTests`
- `KaggleImportTests`, `MCPClientTests`
- `MetricsStoreInferenceMetricsTests`, `MetricsStoreTests`
- `ModelCardParserTests`, `ModelLifecycleTests`, `ModelMetadataTests`, `ModelRegistryTests`
- `OnboardingTests`, `PerformanceTierTests`
- `SettingsToggleTests`, `SidebarSectionTests`, `SprintFeatureIntegrationTests`
- `ThermalLevelTests`, `ThinkingParserTests`, `ToolCallingTests`
- `URLImportE2ETests`, `URLImportIntegrationTests`, `URLImportManagerTests`
- `iOSConversationPickerTests`, `iOSEvalExportTests`, `iOSSuiteEditorTests`

**Behavioral Tests (lifecycle, state machines, real persistence):**
- `DownloadManagerBehaviorTests` — URLProtocol-intercepted download state machine (7 tests)
  - Tests: state transitions, cancel, pause/resume, queue, error handling, delete, storage check
  - Uses injectable `URLSessionConfiguration` via `init(configuration:documentsDirectory:)`
- `ViewModelE2ETests` — Mock engine + real stores lifecycle tests (5 tests)
  - Tests: full conversation lifecycle, fork divergence, model switch, tool calling, eval suite
  - Uses `MockInstrumentedEngine` with real `ConversationStore`, `MetricsStore`, `EvalStore`

### IntegrationTests Test Plan Classes (4 classes)
- `InferenceQualityTests` — Real engine + real models (6 tests, ~30s)
  - Tests: coherent output, deterministic sampling, context retention, thinking mode, init/shutdown cycles, multimodal vision
  - Requires `.litertlm` models in `models/` directory (auto-skips if none found)
- `SmartFallbackIntegrationTests`
- `ConversationViewModelSamplerTests`
- `ModelRegistryTests`

### PerformanceTests Test Plan Classes
- `PerformanceTests`
- `SmartFallbackIntegrationTests`

## Expected Results

| Platform | Total Tests | Skipped | Expected Failures | Duration |
|----------|-------------|---------|-------------------|----------|
| iOS Simulator | 418+ | ~12 | 0 | ~23s |
| macOS | 216+ | 0 | 0 | ~10s |
| macOS (UI) | 10 | 0 | 0 | ~270s |
| iOS Device | 418+ | ~15 | 0 | ~3.4s |

> **NOTE:** macOS has fewer tests because `GalleryParityBenchmarkTests` requires a real model file on disk.

## ⚠️ Animation Safety for Tests

`PulsingGlowModifier` uses `PhaseAnimator` which cycles forever. In test host contexts, this saturates the runloop and hangs tests. The modifier detects `XCTestConfigurationFilePath` and applies a static shadow instead.

**If you add a new perpetual animation**, follow the same pattern:
```swift
private static let isRunningTests =
    ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

func body(content: Content) -> some View {
    if Self.isRunningTests {
        content // static fallback
    } else {
        content.phaseAnimator(...) // real animation
    }
}
```

## Running Tests with MCP Tools (Preferred)

### xcodebuild-mcp

**Run all tests (iOS simulator):**
```
Tool: xcodebuild-mcp → test_sim
Arguments:
  scheme: "EdgeAILab_iOS"
  simulator: "iPhone 16 Pro"
  workspace: "EdgeAILab.xcworkspace"
  project_path: "<project_root>"
```

**Run all tests (macOS):**
```
Tool: xcodebuild-mcp → test_macos
Arguments:
  scheme: "Edge AI Lab"
  workspace: "EdgeAILab.xcworkspace"
  project_path: "<project_root>"
```

### xcode-tools

**Run all tests:**
```
Tool: xcode-tools → RunAllTests
Arguments:
  scheme: "EdgeAILab_iOS"
```

**Run specific tests:**
```
Tool: xcode-tools → RunSomeTests
Arguments:
  tests: ["EdgeAILab_iOSTests/DownloadInfrastructureTests"]
```

## Running Tests with xcodebuild CLI

### Run All Tests (UnitTests plan)

```bash
xcodebuild test \
  -workspace EdgeAILab.xcworkspace \
  -scheme EdgeAILab_iOS \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -testPlan UnitTests \
  -resultBundlePath TestResults.xcresult \
  -quiet \
  2>&1
```

### Run a Specific Test Plan

```bash
# Integration tests
xcodebuild test \
  -workspace EdgeAILab.xcworkspace \
  -scheme EdgeAILab_iOS \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -testPlan IntegrationTests \
  -quiet \
  2>&1

# Performance tests
xcodebuild test \
  -workspace EdgeAILab.xcworkspace \
  -scheme EdgeAILab_iOS \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -testPlan PerformanceTests \
  -quiet \
  2>&1
```

### Run a Specific Test Class

```bash
xcodebuild test \
  -workspace EdgeAILab.xcworkspace \
  -scheme EdgeAILab_iOS \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:EdgeAILab_iOSTests/DownloadInfrastructureTests \
  -quiet \
  2>&1
```

### Run a Specific Test Method

```bash
xcodebuild test \
  -workspace EdgeAILab.xcworkspace \
  -scheme EdgeAILab_iOS \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:EdgeAILab_iOSTests/DownloadInfrastructureTests/testDownloadStateEquality \
  -quiet \
  2>&1
```

### Run Multiple Specific Classes

```bash
xcodebuild test \
  -workspace EdgeAILab.xcworkspace \
  -scheme EdgeAILab_iOS \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:EdgeAILab_iOSTests/DownloadInfrastructureTests \
  -only-testing:EdgeAILab_iOSTests/ChatMessageTests \
  -only-testing:EdgeAILab_iOSTests/ThinkingParserTests \
  -quiet \
  2>&1
```

### Run on macOS

Replace the scheme and destination:
```bash
xcodebuild test \
  -workspace EdgeAILab.xcworkspace \
  -scheme "Edge AI Lab" \
  -destination 'platform=macOS' \
  -only-testing:EdgeAILab_macOSTests/DownloadInfrastructureTests \
  -quiet \
  2>&1
```

## Parsing Test Results

### Quick Result from stdout

Look for the summary line at the end of xcodebuild output:
```
Test Suite 'All tests' passed at ...
     Executed N tests, with M failures (X unexpected) in T (U) seconds
** TEST SUCCEEDED **
```

Or on failure:
```
** TEST FAILED **
```

### Parsing xcresult Bundles

Generate a result bundle by adding `-resultBundlePath`:
```bash
xcodebuild test \
  -workspace EdgeAILab.xcworkspace \
  -scheme EdgeAILab_iOS \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -testPlan UnitTests \
  -resultBundlePath /tmp/TestResults.xcresult \
  2>&1
```

Then parse:
```bash
# Full JSON summary
xcrun xcresulttool get --path /tmp/TestResults.xcresult --format json

# Test action summary (test counts)
xcrun xcresulttool get --path /tmp/TestResults.xcresult --format json | \
  python3 -c "import sys,json; d=json.load(sys.stdin); print(json.dumps(d.get('metrics', {}), indent=2))"

# List failed tests only
xcrun xcresulttool get --path /tmp/TestResults.xcresult --format json | \
  grep -A5 '"testStatus" : "Failure"'
```

### Coverage Report (via MCP)

```
Tool: xcodebuild-mcp → get_coverage_report
Arguments:
  xcresult_path: "/tmp/TestResults.xcresult"
```

```
Tool: xcodebuild-mcp → get_file_coverage
Arguments:
  xcresult_path: "/tmp/TestResults.xcresult"
  file_path: "Sources/ConversationViewModel.swift"
```

## Known Skipped Tests

Some tests are conditionally skipped:
- Tests requiring a downloaded `.litertlm` model file (skip when no model present)
- Tests that exercise device-specific thermal monitoring APIs
- Tests marked with `@available` guards for specific OS versions

These are expected and should appear as `skipped` (not `failed`) in results.

## Adding New Tests

### 1. Create the Test File

Add a new `.swift` file under `Tests/<Category>/`. Categories:
- `Tests/Engine/` — Inference engine and model tests
- `Tests/Conversation/` — ViewModel and chat tests
- `Tests/Downloads/` — Download manager tests
- `Tests/Integration/` — Cross-component lifecycle tests
- `Tests/Evaluation/` — Eval runner and scoring tests
- `Tests/Models/` — Model metadata and registry tests

```swift
import XCTest
#if os(iOS)
@testable import EdgeAILab_iOS
#elseif os(macOS)
@testable import EdgeAILab_macOS
#endif

final class MyNewTests: XCTestCase {
    func testSomething() {
        // ...
    }
}
```

### 2. Add to Xcode Project Targets

> **CRITICAL:** The project uses explicit file membership, NOT filesystem globs. New `.swift` files on disk are NOT automatically discovered. You MUST add them to both test targets:
> - `EdgeAILab_iOSTests`
> - `EdgeAILab_macOSTests`
>
> Use one of:
> - **Xcode UI:** Drag the file into the test target in the Project Navigator
> - **Ruby script:** Use the `xcodeproj` gem to programmatically add the file
> - **xcode-tools MCP:** Not directly supported for target membership changes
>
> Verify membership: `grep 'MyNewTests' EdgeAILab.xcodeproj/project.pbxproj | wc -l` should show 6 lines (PBXFileReference + PBXBuildFile×2 + group child + Sources×2).

### 3. Add to Test Plan

Edit the appropriate `.xctestplan` JSON file to include the new class:

```json
"selectedTests" : [
    "ExistingTests",
    "MyNewTests"
]
```

> **IMPORTANT:** If a test plan uses `selectedTests`, only listed classes run. You MUST add your new class name to the `selectedTests` array.

### 4. Verify

```bash
xcodebuild test \
  -project EdgeAILab.xcodeproj \
  -scheme "Edge AI Lab" \
  -destination 'platform=macOS' \
  -only-testing:EdgeAILab_macOSTests/MyNewTests \
  2>&1 | grep -E "Test Case|Executed|SUCCEEDED|FAILED"
```

## Post-Feature Testing Workflow

**After completing any feature, refactor, or library update, run the appropriate tests to verify nothing broke.**

### Quick Verification (After Any Code Change)

Run the behavioral tests — they're fast (~3s) and catch lifecycle regressions:

```bash
xcodebuild test \
  -project EdgeAILab.xcodeproj \
  -scheme "Edge AI Lab" \
  -destination 'platform=macOS' \
  -only-testing:EdgeAILab_macOSTests/DownloadManagerBehaviorTests \
  -only-testing:EdgeAILab_macOSTests/ViewModelE2ETests \
  2>&1 | grep -E "Test Case|Executed|SUCCEEDED|FAILED"
```

### After Engine or Model Changes

Run the inference quality tests (requires models in `models/`):

```bash
xcodebuild test \
  -project EdgeAILab.xcodeproj \
  -scheme "Edge AI Lab" \
  -destination 'platform=macOS' \
  -only-testing:EdgeAILab_macOSTests/InferenceQualityTests \
  2>&1 | grep -E "Test Case|Executed|SUCCEEDED|FAILED"
```

### After Download Manager Changes

Run the download behavioral tests:

```bash
xcodebuild test \
  -project EdgeAILab.xcodeproj \
  -scheme "Edge AI Lab" \
  -destination 'platform=macOS' \
  -only-testing:EdgeAILab_macOSTests/DownloadManagerBehaviorTests \
  2>&1 | grep -E "Test Case|Executed|SUCCEEDED|FAILED"
```

### After ViewModel or Conversation Changes

Run the ViewModel E2E tests:

```bash
xcodebuild test \
  -project EdgeAILab.xcodeproj \
  -scheme "Edge AI Lab" \
  -destination 'platform=macOS' \
  -only-testing:EdgeAILab_macOSTests/ViewModelE2ETests \
  2>&1 | grep -E "Test Case|Executed|SUCCEEDED|FAILED"
```

### Full Test Suite (Pre-Release)

Run all behavioral + integration tests:

```bash
xcodebuild test \
  -project EdgeAILab.xcodeproj \
  -scheme "Edge AI Lab" \
  -destination 'platform=macOS' \
  -only-testing:EdgeAILab_macOSTests/DownloadManagerBehaviorTests \
  -only-testing:EdgeAILab_macOSTests/ViewModelE2ETests \
  -only-testing:EdgeAILab_macOSTests/InferenceQualityTests \
  2>&1 | grep -E "Test Case|Executed|SUCCEEDED|FAILED"
```

### Source File → Test Mapping

| If you changed... | Run these tests |
|---|---|
| `Sources/Downloads/ModelDownloadManager.swift` | `DownloadManagerBehaviorTests`, `DownloadManagerTests` |
| `Sources/Conversation/ConversationViewModel.swift` | `ViewModelE2ETests`, `ConversationViewModelTests` |
| `Sources/Engine/InstrumentedEngine.swift` | `InferenceQualityTests` |
| `Sources/Evaluation/EvalRunner.swift` | `ViewModelE2ETests/testEvalRunnerFullSuite`, `EvalRunnerTests` |
| `Sources/Conversation/ConversationStore.swift` | `ViewModelE2ETests`, `ConversationStoreTests` |
| `Sources/Models/ModelMetadata.swift` | `ModelMetadataTests`, `ModelRegistryTests`, `DownloadManagerBehaviorTests` |
| LiteRTLM package update | `InferenceQualityTests` (full suite with real models) |
| Any UI change | Automation harness flows (see `automation-harness` skill) |

## CI Integration

The project includes an automated test runner script:

```bash
# Run full test pyramid on macOS
./automation/ci_test_runner.sh --macOS

# Run on simulator
./automation/ci_test_runner.sh --simulator

# Skip slow tests
./automation/ci_test_runner.sh --macOS --skip-integration --skip-performance
```

Exit codes:
- `0` — All required tests passed
- `1` — Unit tests failed (critical)
- `2` — Integration tests failed (critical)
- `3` — Performance tests failed (informational)

## Troubleshooting Test Failures

### Test Target Not Found
```
error: Unable to find a target named 'EdgeAILab_iOSTests'
```
**Fix:** Run `tuist generate` to regenerate the project.

### Tests Hang (Any Platform)
If tests hang with high CPU (130%+), the likely cause is a perpetual animation (e.g., `PhaseAnimator`) saturating the test host's runloop. Check that any `PhaseAnimator` or `.repeatForever` animation has the `isRunningTests` guard (see "Animation Safety for Tests" above). On-device XCTest works correctly when animations are guarded — 418 tests complete in 3.4 seconds.

### Module Import Errors
```
error: No such module 'EdgeAILab_iOS'
```
**Fix:** Build the main app target first, then run tests.

### Flaky Tests
If a test passes sometimes and fails others, try:
```bash
# Run with retry
xcodebuild test \
  -workspace EdgeAILab.xcworkspace \
  -scheme EdgeAILab_iOS \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:EdgeAILab_iOSTests/FlakyTestClass \
  -retry-tests-on-failure \
  -test-iterations 3 \
  2>&1
```

## Device Pipeline Debugging

### deploy_device.sh Console Hang
- `devicectl --console` keeps streaming after the automation harness signals completion
- The harness calls `exit(0)` but `devicectl` may not exit immediately
- **Workaround**: Use `NO_CONSOLE=1` for unattended runs; pull results from device `Documents/metrics/` afterward using `xcrun devicectl device copy from`
- **Never pipe** `deploy_device.sh` output through `tail -N` — use `head -N` or redirect to a log file. `tail` buffers until N lines accumulate, creating zombie background tasks if the stream ends early.

### JSONSerialization Crash Pattern
If the app crashes with `NSInvalidArgumentException: Invalid number value (infinite) in JSON write`:
1. Search ALL `JSONSerialization.data(withJSONObject:)` callers (not just pipeline code)
2. Check tool execution paths (`CalculatorTool`, `UnitConverterTool`, etc.) — the model may request operations that produce `Infinity` (e.g., `1/0`)
3. The `jsonString(from:)` helper in `ToolRegistry.swift` sanitizes non-finite values, but new tools must also guard at the source
4. Swift `try?`/`catch` **cannot catch** ObjC `NSInvalidArgumentException` — values must be sanitized **before** the `JSONSerialization` call

### Build Configuration Notes
- **Debug build**: ~14 tok/s decode on iPhone 16 Pro Max
- **Release build**: ~26 tok/s decode — **always** use `BUILD_CONFIG=Release` for benchmark baselines
- Eval pipeline: ~5 min for 100 prompts on device (Release build)
- Pull results from device: `xcrun devicectl device copy from --device <ID> --domain-type appDataContainer --domain-identifier com.andrewvoirol.EdgeAILab --source Documents/metrics/<file> --destination /tmp/<file>`

