# Testing Guide

GemmaEdgeGallery uses two complementary testing strategies: **XCTest** for fast unit/integration testing and the **DeveloperAutomationHarness** for end-to-end validation with real model inference.

## Quick Start

```bash
# iOS Simulator — unit tests
xcodebuild test \
  -workspace GemmaEdgeGallery.xcworkspace \
  -scheme GemmaEdgeGallery_iOS \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -only-testing:GemmaEdgeGallery_iOSTests

# macOS — unit tests
xcodebuild test \
  -workspace GemmaEdgeGallery.xcworkspace \
  -scheme "Edge AI Lab" \
  -destination 'platform=macOS' \
  -only-testing:GemmaEdgeGallery_macOSTests

# Physical device — unit tests
xcodebuild test \
  -workspace GemmaEdgeGallery.xcworkspace \
  -scheme GemmaEdgeGallery_iOS \
  -destination 'id=<DEVICE_UDID>' \
  -only-testing:GemmaEdgeGallery_iOSTests \
  -allowProvisioningUpdates

# iOS Simulator — UI smoke tests
xcodebuild test \
  -workspace GemmaEdgeGallery.xcworkspace \
  -scheme GemmaEdgeGallery_iOS \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -only-testing:GemmaEdgeGallery_iOSUITests

# macOS — UI tests
xcodebuild test \
  -workspace GemmaEdgeGallery.xcworkspace \
  -scheme "Edge AI Lab" \
  -destination 'platform=macOS' \
  -only-testing:GemmaEdgeGallery_macOSUITests
```

## Expected Results

| Platform | Tests | Skipped | Failures | Duration |
|----------|-------|---------|----------|----------|
| iOS Simulator (Unit) | 730+ | ~12 | 0 | ~45s |
| macOS (Unit) | 730+ | ~15 | 0 | ~30s |
| iOS Simulator (UI) | 5 | 0 | 0 | ~90s |
| macOS (UI) | 26 | — | — | ~60s |
| iOS Device (Unit) | 730+ | ~15 | 0 | ~5s |

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

#### iOS UI Smoke Tests (5 tests)

| Test | What It Verifies |
|------|------------------|
| `testAppLaunchesToModelHub` | Tab bar visible, Models tab selected, hub sections present |
| `testModelCardTapShowsDetail` | Tapping a model card opens detail view without crash |
| `testChatTabNavigation` | Chat tab switch, prompt field and send button exist |
| `testSettingsAccessible` | Settings tab shows configuration toggles |
| `testEmptyStateGraceful` | App remains responsive with no models downloaded |

Source: `iOSUITests/GemmaEdgeGalleryiOSUITests.swift`

#### macOS UI Tests (26 tests)

| Test | What It Verifies |
|------|------------------|
| `testBasicNavigation` | Settings, dashboard, load model buttons |
| `testChatInteractions` | Attach image, refresh, prompt field, send |
| `testSettingsInteractions` | GPU toggle, benchmark toggle, HF token |
| `testQuickActionsAndModelShowcase` | Hint buttons (chat, thinking, tools, image) |
| `testAddMCPServer` | Tool calling toggle, MCP server CRUD |
| `testAllSettingsTogglesExist` | GPU, benchmark, MTP, constrained, thinking, tool calling, agent skills |
| `testSamplerControls` | Top-K stepper, Top-P slider, temperature, presets |
| `testSystemMessageEditor` | Text editor, clear button |
| `testModelCardStripExists` | Detail column verification |
| `testMultimodalAttachmentButtons` | Image/audio attachment buttons |
| `testNewChatFunctionality` | ⌘N menu command |
| `testInputAreaComponents` | Prompt field, send button, refresh, load model |
| `testMacOSMenuBarCommands` | ⌘R, ⌘D, ⌘O, ⌘N keyboard shortcuts |
| `testSidebarListExists` | Sidebar list in 3-column layout |
| `testSidebarActiveModelEmptyState` | Empty/loading/loaded model states |
| `testSidebarBenchmarksSectionExists` | Dashboard & compare links |
| `testSidebarConversationsEmptyState` | Conversations section |
| `testSidebarNewChatButton` | New chat button in sidebar |
| `testThreeColumnLayoutStructure` | Full 3-column layout verification |
| `testSendButtonAccessibilityStates` | Send button accessibility values |

Source: `UITests/GemmaEdgeGalleryUITests.swift`

#### macOS URL Import UI Tests (6 new tests)

| Test | What It Verifies |
|------|------------------|
| `testCommandIOpensURLImportSheet` | ⌘I keyboard shortcut opens import sheet |
| `testURLImportSheetComponents` | URL text field, import button, status area |
| `testKaggleURLImportFlow` | Kaggle URL detection and pipeline progression |
| `testHuggingFaceSearchField` | HF browser search functionality |
| `testCommunityModelsBrowserExists` | Community models section in sidebar |
| `testInlineURLPasteField` | Inline paste field in detail column |

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
  com.andrewvoirol.GemmaEdgeGallery \
  -- -RunAllFlows

# Specific flow
xcrun devicectl device process launch \
  --device <DEVICE_UDID> --console \
  com.andrewvoirol.GemmaEdgeGallery \
  -- -RunFlow benchmark_flow
```

### Adding a New Flow

1. Create a JSON file in `automation/flows/`:
```json
{
  "name": "My Flow",
  "steps": [
    {"step": 1, "action": "verify_ui", "description": "Check UI", "expected_elements": ["Models"]},
    {"step": 2, "action": "tap", "description": "Tap button", "target_element": "My Button"}
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

## Troubleshooting

### Tests Hang

If tests hang with 130%+ CPU, a perpetual animation is saturating the runloop. Check `DesignSystem.swift` and any new `PhaseAnimator` or `.repeatForever` usage. Add the `isRunningTests` guard.

### Module Import Errors

```
error: No such module 'GemmaEdgeGallery_iOS'
```
Fix: Build the main app target first, or run `tuist generate`.

### Test Target Not Found

```
error: Unable to find a target named 'GemmaEdgeGallery_iOSTests'
```
Fix: Run `tuist generate` to regenerate the Xcode project.

### Device Provisioning Error

```
No profiles for 'com.andrewvoirol.GemmaEdgeGallery.UITests.xctrunner'
```
Fix: Add `-allowProvisioningUpdates` to the xcodebuild command. Or use `-only-testing:GemmaEdgeGallery_iOSTests` (unit tests, not UI tests) which doesn't need a separate runner profile.
