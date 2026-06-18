# Testing Guide

EdgeAILab uses two complementary testing strategies: **XCTest** for fast unit/integration testing and the **DeveloperAutomationHarness** for end-to-end validation with real model inference.

## Quick Start

```bash
# iOS Simulator — unit tests
xcodebuild test \
  -workspace EdgeAILab.xcworkspace \
  -scheme EdgeAILab_iOS \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -only-testing:EdgeAILab_iOSTests

# macOS — unit tests
xcodebuild test \
  -workspace EdgeAILab.xcworkspace \
  -scheme "Edge AI Lab" \
  -destination 'platform=macOS' \
  -only-testing:EdgeAILab_macOSTests

# Physical device — unit tests
xcodebuild test \
  -workspace EdgeAILab.xcworkspace \
  -scheme EdgeAILab_iOS \
  -destination 'id=<DEVICE_UDID>' \
  -only-testing:EdgeAILab_iOSTests \
  -allowProvisioningUpdates

# iOS Simulator — UI smoke tests
xcodebuild test \
  -workspace EdgeAILab.xcworkspace \
  -scheme EdgeAILab_iOS \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -only-testing:EdgeAILab_iOSUITests

# macOS — UI tests
xcodebuild test \
  -workspace EdgeAILab.xcworkspace \
  -scheme "Edge AI Lab" \
  -destination 'platform=macOS' \
  -only-testing:EdgeAILab_macOSUITests

# Physical device — UI smoke tests
xcodebuild test \
  -workspace EdgeAILab.xcworkspace \
  -scheme EdgeAILab_iOS \
  -destination 'id=<DEVICE_UDID>' \
  -only-testing:EdgeAILab_iOSUITests \
  -allowProvisioningUpdates

# Full test matrix (all platforms, all test types)
./automation/run_full_matrix.sh

# Full test matrix (macOS only, no device)
./automation/run_full_matrix.sh --skip-device
```

## Expected Results

| Platform | Tests | Skipped | Failures | Duration |
|----------|-------|---------|----------|----------|
| iOS Simulator (Unit) | 730+ | ~12 | 0 | ~45s |
| macOS (Unit) | 730+ | ~15 | 0 | ~30s |
| iOS Simulator (UI) | 13 | 0 | 0 | ~120s |
| macOS (UI) | 10 | 0 | 0 | ~270s |
| iOS Device (Unit) | 730+ | ~15 | 0 | ~5s |
| iOS Device (UI) | 13 | 0 | 0 | ~60s |

## Test Architecture

The iOS and macOS test targets share the same `Tests/**` source files. Each test is compiled for both platforms via Tuist glob patterns.

### Test Suites

| Suite | Tests | What It Covers |
|-------|-------|----------------|
| `ChatMessageTests` | Message parsing, role assignment, ID generation |
| `ConversationViewModelTests` | ViewModel lifecycle, state transitions |
| `ConversationViewModelSamplerTests` | Sampler configuration, greedy vs sampling presets |
| `DownloadManagerTests` | Download state machine, progress tracking |
| `DownloadInfrastructureTests` | URLSession delegate, background session reconnection |
| `EnvironmentInjectionTests` | Singleton absence guard, DI compatibility |
| `GalleryModelDiscoveryTests` | Local model file discovery, directory scanning |
| `InferenceMetricsTests` | TTFT, decode speed, token latency calculations |
| `MetricsStoreTests` | Benchmark result persistence, historical comparison |
| `ModelRegistryTests` | Model catalog, variant resolution |
| `SettingsToggleTests` | Experimental flags, sampler defaults |
| `ThinkingParserTests` | `<think>` tag extraction, streaming boundary handling |
| `ToolCallingTests` | Tool schema generation, invocation parsing |

#### v2.0 Test Suites

| Suite | What It Covers |
|-------|----------------|
| `URLImportManagerTests` | URL parsing, HuggingFace URL validation, state machine |
| `URLImportIntegrationTests` | Full pipeline lifecycle, known model shortcut, catalog integration |
| `URLImportE2ETests` | End-to-end import with real HuggingFace API calls |
| `KaggleImportTests` | Kaggle URL parsing, download URL construction, auth header |
| `ModelCardParserTests` | Runtime type inference, parameter detection, capability analysis |
| `DynamicModelCatalogTests` | CRUD operations, merge/dedup, search, persistence |
| `DynamicModelMetadataTests` | Metadata factories, provenance tracking, confidence scoring |
| `HFModelBrowserTests` | Format detection, API URL construction, model info parsing |
| `CommunityDownloadTests` | Community model download URL construction, state management |
| `BatchEvalTests` | Batch eval orchestration, plan estimation, sequential execution |
| `BugFixTests` | Photo picker activation, pause/resume wiring verification |
| `OnboardingTests` | Onboarding state management, page navigation |
| `iOSConversationPickerTests` | iOS conversation browser, search, sort, rename |
| `iOSEvalExportTests` | Eval export JSON/CSV formats, share sheet |
| `iOSSuiteEditorTests` | Custom eval suite editing, prompt CRUD |
| `ModelLifecycleTests` | Import → delete → re-import lifecycle, stale catalog cleanup |
| `KaggleTokenStorageTests` | Kaggle Keychain credential storage round-trip |
| `HFRetryTests` | HuggingFace API retry with exponential backoff |
| `AutomationFlowRunnerTests` | Automation flow execution, step sequencing |
| `BenchmarkCardTests` | Benchmark card rendering, data formatting |
| `BuiltInEvalSuitesTests` | Built-in eval suite definitions, prompt content |
| `ConversationForkTests` | Conversation forking, UUID reassignment |
| `ConversationStoreTests` | Conversation CRUD, JSON persistence |
| `DeveloperAutomationHarnessTests` | Developer automation harness, launch arg parsing |
| `EvalResultTests` | Eval result data model, pass/fail scoring |
| `EvalRunnerTests` | Eval suite execution, scoring pipeline |
| `EvalScoringTests` | Individual scoring variant logic |
| `EvalStoreTests` | Eval result persistence, retrieval |
| `EvalSuiteTests` | Eval suite definition, serialization |
| `ExperimentConfigTests` | Experiment configuration, flag management |
| `GalleryParityBenchmarkTests` | Gallery parity verification benchmarks |
| `MCPClientTests` | MCP client connection, JSON-RPC messaging |
| `MultiTurnIntegrationTests` | Multi-turn conversation coherence |
| `PerformanceTests` | XCTest performance measurements |
| `SmartFallbackIntegrationTests` | GPU → CPU fallback integration |
| `SprintFeatureIntegrationTests` | Sprint feature end-to-end integration |
| `ToolCallingIntegrationTests` | Tool calling end-to-end integration |

### Test Plans

| Plan | Purpose | When to Use |
|------|---------|-------------|
| `UnitTests.xctestplan` | Fast CI tests, no model needed | Every PR |
| `IntegrationTests.xctestplan` | Cross-component tests (`SmartFallbackIntegrationTests`) | Pre-merge |
| `PerformanceTests.xctestplan` | Regression benchmarks, needs model | Release validation |

### UI Test Suites

UI tests run on the built app via XCUITest. They verify critical user flows without requiring model files.

#### iOS UI Tests (13 tests: 5 smoke + 8 flow-driven)

##### Smoke Tests

| Test | What It Verifies |
|------|------------------|
| `testAppLaunchesToModelHub` | Tab bar visible, Models tab selected, hub sections present |
| `testModelCardTapShowsDetail` | Tapping a model card opens detail view without crash |
| `testChatTabNavigation` | Chat tab switch, prompt field and send button exist |
| `testSettingsAccessible` | Settings tab shows configuration toggles |
| `testEmptyStateGraceful` | App remains responsive with no models downloaded |

##### Flow-Driven Tests

| Test Method | Flow File | What It Verifies |
|---|---|---|
| `testFlowIOSSmokeTest` | `ios_smoke_flow.json` | Basic tab navigation and element presence |
| `testFlowAccessibilityAudit` | `ios_accessibility_audit_flow.json` | A11y elements across all tabs |
| `testFlowOrientation` | `ios_orientation_flow.json` | Layout stability across tabs |
| `testFlowOnboarding` | `ios_onboarding_flow.json` | First-launch onboarding flow |
| `testFlowDownloadLifecycle` | `ios_download_lifecycle_flow.json` | Model download UI states |
| `testFlowConversationPersistence` | `ios_conversation_persistence_flow.json` | Chat state survives tab switches |
| `testFlowModelLifecycle` | `ios_model_lifecycle_flow.json` | Model card → detail → back |
| `testFlowErrorRecovery` | `ios_error_recovery_flow.json` | Rapid tab switching stability |

##### Accessibility Audit

`testAccessibilityAudit` calls `performAccessibilityAudit()` (iOS 17+) to automatically detect common accessibility issues including missing labels, insufficient contrast, and small hit targets.

Source: `iOSUITests/EdgeAILabiOSUITests.swift`

#### macOS UI Tests (10 flow-driven tests)

The macOS UI test suite uses **flow-driven testing** — test logic is defined in JSON flow files under `automation/flows/ui/`, not hardcoded in Swift. Each `testFlow*` method in `EdgeAILabUITests.swift` loads a flow JSON and executes it via `FlowDrivenUITestRunner`.

| Test Method | Flow File | What It Verifies |
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

Source: `UITests/EdgeAILabUITests.swift`

> **Adding new UI tests:** Create a new flow JSON in `automation/flows/ui/`, add a `testFlow*` method that calls `FlowDrivenUITestRunner.runFlow(named:)`, and register it in the XCUITest class.

> **Note**: iOS UI tests run in CI via a dedicated job (`build-ios-uitests`). macOS UI tests are not currently run in CI due to GHA macOS runner limitations with windowed apps.

## Dependency Injection Pattern

Views receive dependencies via `@Environment`, not singletons:

```swift
// ✅ Correct — used by all views
@Environment(ConversationViewModel.self) private var viewModel

// ❌ Wrong — singleton was removed
@Bindable private var viewModel = ConversationViewModel.shared
```

Tests create isolated instances:

```swift
func testExample() {
    let vm = ConversationViewModel()       // Fresh, isolated instance
    let vm2 = ConversationViewModel(engine: MockInstrumentedEngine())  // With mock
    // Each test gets its own state — no shared mutable globals
}
```

### Singleton Guard

`EnvironmentInjectionTests.testNoSharedSingleton()` uses Swift's `Mirror` to inspect `ConversationViewModel` at the type level. If anyone adds `static let shared`, the test fails. The CI workflow also runs `grep -r "ConversationViewModel\.shared" Sources/` as a build step.

## ⚠️ Animation Safety

### The Problem

`PhaseAnimator` cycles between phases forever. When the test host app launches the full SwiftUI view hierarchy, this animation runs on the main runloop — consuming 130%+ CPU and starving the XCTest runner. Tests appear to hang indefinitely.

### The Fix

`PulsingGlowModifier` detects the XCTest environment and applies a static shadow:

```swift
private static let isRunningTests =
    ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

func body(content: Content) -> some View {
    if Self.isRunningTests {
        content.shadow(color: color.opacity(0.3), radius: 8)  // static
    } else {
        content.phaseAnimator([false, true]) { ... }  // animated
    }
}
```

### For Contributors

If you add a **perpetual animation** (`PhaseAnimator`, `withAnimation(.repeatForever)`, `TimelineView`), wrap it with the `isRunningTests` guard. Without this, tests will hang on all platforms.

## Automation Harness

For E2E testing with real model inference, use the in-app automation harness.

### Available Flows

| Flow | Steps | Purpose |
|------|-------|---------|
| `benchmark_flow` | 9 | Performance metrics: TTFT, decode speed, memory |
| `e2e_regression_flow` | 13 | Full user journey: model selection → chat → verify |
| `inference_flow` | 5 | Chat prompt → generate → verify response |
| `model_setup_flow` | 5 | Settings → HuggingFace token → close |
| `multimodal_flow` | 9 | Image attachment → multimodal inference |
| `settings_flow` | 9 | Sampler presets, MTP toggle, system message |

### Running Flows

```bash
# All flows
xcrun devicectl device process launch \
  --device <DEVICE_UDID> --console \
  com.andrewvoirol.EdgeAILab \
  -- -RunAllFlows

# Specific flow
xcrun devicectl device process launch \
  --device <DEVICE_UDID> --console \
  com.andrewvoirol.EdgeAILab \
  -- -RunFlow benchmark_flow

# Dry-run mode (validates plumbing without models/UI)
xcrun devicectl device process launch \
  --device <DEVICE_UDID> --console \
  com.andrewvoirol.EdgeAILab \
  -- -RunAllFlows -DryRun
```

### Pipelines

| Pipeline | Launch Arg | Requires Model? | CI Gate? |
|----------|-----------|-----------------|----------|
| Benchmark Pipeline | `-RunBenchmarkPipeline` | Yes (or `-DryRun`) | Yes (critical regressions) |
| Eval Pipeline | `-RunEvalPipeline` | Yes (or `-DryRun`) | No (informational) |

```bash
# Benchmark pipeline (compares against metrics/baselines.json)
.../Edge\ AI\ Lab -RunBenchmarkPipeline

# Eval pipeline (runs built-in eval suites)
.../Edge\ AI\ Lab -RunEvalPipeline

# Dry-run: validate pipeline plumbing without models
.../Edge\ AI\ Lab -RunBenchmarkPipeline -DryRun
.../Edge\ AI\ Lab -RunEvalPipeline -DryRun
```

### CI Auto-Invocation

The `AutomationHarnessXCTests` class (in `UITests/`) auto-invokes the harness as XCUITests:
- `testAllFlowsDiscoverable` — validates `-ListFlows`
- `testE2ERegressionFlowDryRun` — validates `-RunFlow e2e_regression_flow -DryRun`
- `testBenchmarkFlowDryRun` — validates `-RunFlow benchmark_flow -DryRun`
- `testDryRunModifierAccepted` — validates `-RunAllFlows -DryRun`

These run in CI via the `automation-flows` job in `ci.yml`.

### Adding a New Flow

1. Create a JSON file in `automation/flows/`:
```json
{
  "name": "My Flow",
  "steps": [
    {"step": 1, "action": "verify_ui", "description": "Check UI", "expected_elements": ["Models"]},
    {"step": 2, "action": "tap", "description": "Tap button", "target_element": "My Button"},
    {"step": 3, "action": "verify_ui", "description": "Check result", "expected_elements": ["Result"],
     "assertion": {"type": "element_value_contains", "element": "Result", "expected": "success"}}
  ]
}
```

2. The file is automatically bundled via `automation/flows/**/*.json` in `Project.swift`.

3. Run: `... -- -RunFlow my_flow`

### Parsing Results

Look for the structured output protocol:
```
[AUTOMATION_FLOW_SUMMARY] 6/6 flows passed
[AUTOMATION_FLOW_SUMMARY]   [PASSED] Flow Name: N/N steps passed in Xms
```

Exit code: `0` = all passed, `1` = failure.

## CI Integration

The project uses GitHub Actions for continuous integration. The workflow:

1. **Singleton guard**: `grep -r "ConversationViewModel.shared" Sources/ Tests/` — fails if any singleton references exist
2. **Build**: Both iOS and macOS targets
3. **Test**: Full test suite on macOS and iOS Simulator

See `.github/workflows/ci.yml` for the full configuration.

## Self-Hosted Runners

For running benchmarks, eval pipelines, and integration tests that require model files, see [SELF_HOSTED_RUNNER.md](SELF_HOSTED_RUNNER.md) for setup instructions.

The project's `benchmark.yml` workflow targets `[self-hosted, apple-silicon]` runners for:
- Full inference benchmarks with regression detection
- Eval pipeline execution
- Model-dependent integration tests

## Troubleshooting

### Tests Hang

If tests hang with 130%+ CPU, a perpetual animation is saturating the runloop. Check `DesignSystem.swift` and any new `PhaseAnimator` or `.repeatForever` usage. Add the `isRunningTests` guard.

### Module Import Errors

```
error: No such module 'EdgeAILab_iOS'
```
Fix: Build the main app target first, or run `tuist generate`.

### Test Target Not Found

```
error: Unable to find a target named 'EdgeAILab_iOSTests'
```
Fix: Run `tuist generate` to regenerate the Xcode project.

### Device Provisioning Error

```
No profiles for 'com.andrewvoirol.EdgeAILab.UITests.xctrunner'
```
Fix: Add `-allowProvisioningUpdates` to the xcodebuild command. Or use `-only-testing:EdgeAILab_iOSTests` (unit tests, not UI tests) which doesn't need a separate runner profile.

### iOS 27 / Liquid Glass Accessibility Audit Filters

The `testAccessibilityAudit` test filters known iOS 27 Liquid Glass false positives:

| Filter | Reason |
|--------|--------|
| `.dynamicType` | SF Symbol icons use fixed `.system(size:)` — acceptable per HIG |
| `.textClipped` | `.searchable` placeholder clips in Liquid Glass compositor (Apple bug FB14832017) |
| `.contrast` on nav/tab/toolbar | System-owned Liquid Glass surfaces cause transient contrast changes outside developer control |
| `.contrast` on `.searchField` | System search field placeholder text inherits system colors that produce borderline contrast on glass |

**Important**: The filter does NOT suppress contrast issues on app-owned content views. Only system glass surfaces are excluded.

### macOS Window Detection (macOS 26+)

macOS flow-driven UI tests (`EdgeAILabUITests`) may fail with "App window did not appear after launch" on macOS 26+ with Liquid Glass. The `WindowGroup` window does not register as a traditional `XCUIElement.window` in the accessibility tree, even though the process is running. The 4 `AutomationHarnessXCTests` tests continue to pass as they use filesystem markers instead of UI queries.

### Simulator GPU Tests

5 E2E test classes require a physical GPU (Metal) and are automatically skipped on the iOS Simulator via `#if targetEnvironment(simulator)` guards in `setUp()`:

| Class | Guard |
|-------|-------|
| `InferenceQualityTests` | `setUpWithError()` |
| `SmartFallbackIntegrationTests` | `setUpWithError()` |
| `MultiTurnIntegrationTests` | `setUp() async throws` |
| `GalleryParityBenchmarkTests` | `setUpWithError()` |
| `PerformanceTests` | `setUpWithError()` |

These are also in the `skippedTests` blocklist in `UnitTests.xctestplan` so they don't run during routine test plan execution. To run them on a physical device:

```bash
xcodebuild test \
  -workspace EdgeAILab.xcworkspace \
  -scheme EdgeAILab_iOS \
  -destination 'id=<DEVICE_UDID>' \
  -only-testing:EdgeAILab_iOSTests/InferenceQualityTests \
  -allowProvisioningUpdates
```

---

## Regression Policy

### Zero-Failure Bar

The test suite must maintain **zero failures** on both macOS and iOS Simulator at all times. There is no concept of "flaky" tests — every failure gets a root cause investigation.

### Intentional Regressions

If a change intentionally breaks a test (e.g., changing expected behavior, removing a feature):

1. **Commit prefix**: Use `BREAKING:` prefix in the commit message
2. **Baseline update**: Update the relevant baseline (eval baselines, benchmark baselines) in the **same commit**
3. **Test update**: Update or remove the affected test assertions in the **same commit**
4. **Documentation**: Add a `change_log` entry to the affected baseline JSON

Example:
```
BREAKING: Remove calculator precision mode

- Updated 3 math eval prompts that depended on high-precision mode
- Updated baselines.json with new expected scores
- Removed testCalculatorPrecisionMode from ToolCallingTests
```

### Coverage Targets

| Metric | Current | Target |
|--------|---------|--------|
| App code (Sources/) | 25.9% | ≥40% (Phase 1) → ≥60% (Phase 2) |
| Test code (Tests/) | 83.7% | Maintain ≥80% |
| Eval prompts | 100 | ≥100, expand as features grow |
