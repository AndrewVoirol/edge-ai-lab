---
name: test-runner
description: Run XCTest test plans, execute specific tests, parse xcresult bundles, and interpret test results for GemmaEdgeGallery. Use this skill when running unit tests, integration tests, performance tests, or debugging test failures.
---

# Test Runner

This skill covers running the GemmaEdgeGallery test suite, using test plans, executing specific tests, and parsing results.

## Test Architecture

### Test Targets

| Target | Platform | Source Dir | Host App |
|---|---|---|---|
| `GemmaEdgeGallery_iOSTests` | iOS | `Tests/**` | `GemmaEdgeGallery_iOS` |
| `GemmaEdgeGallery_macOSTests` | macOS | `Tests/**` | `Edge AI Lab` |
| `GemmaEdgeGallery_macOSUITests` | macOS | `UITests/**` | `GemmaEdgeGallery_macOS` |

> **NOTE:** iOS and macOS test targets share the same `Tests/**` source files. The tests are compiled for both platforms.

### Test Plans

| Test Plan | Purpose | Timeout | Test Classes |
|---|---|---|---|
| `UnitTests.xctestplan` | Fast CI tests, no model needed | 60s per test | 20 classes (see below) |
| `IntegrationTests.xctestplan` | Cross-component tests, some need model | 300s per test | 3 classes |
| `PerformanceTests.xctestplan` | Regression benchmarks, model needed | 600s per test | 2 classes |

### UnitTests Test Plan Classes (20 classes)
- `ChatMessageTests`
- `CommunityDownloadTests`
- `ConversationViewModelSamplerTests`
- `ConversationViewModelTests` (in GemmaEdgeGalleryTests.swift)
- `DeviceMetricsSnapshotTests`
- `DownloadInfrastructureTests`
- `DownloadManagerTests`
- `ExperimentalFlagsStateTests`
- `GalleryModelDiscoveryTests`
- `InferenceMetricsIntegrationTests`
- `InferenceMetricsTests`
- `MCPClientTests`
- `MetricsStoreInferenceMetricsTests`
- `MetricsStoreTests`
- `ModelMetadataTests`
- `ModelRegistryTests`
- `SettingsToggleTests`
- `ThermalLevelTests`
- `ThinkingParserTests`
- `ToolCallingTests`

### IntegrationTests Test Plan Classes
- `SmartFallbackIntegrationTests`
- `ConversationViewModelSamplerTests`
- `ModelRegistryTests`

### PerformanceTests Test Plan Classes
- `PerformanceTests`
- `SmartFallbackIntegrationTests`

## Expected Results

- **Total tests:** 414+ on iOS simulator
- **Expected passing:** All tests should pass
- **Expected skipped:** ~12 tests (skipped due to model not being present or platform-specific conditions)
- **Expected failures:** 0

## Running Tests with MCP Tools (Preferred)

### xcodebuild-mcp

**Run all tests (iOS simulator):**
```
Tool: xcodebuild-mcp → test_sim
Arguments:
  scheme: "GemmaEdgeGallery_iOS"
  simulator: "iPhone 16 Pro"
  workspace: "GemmaEdgeGallery.xcworkspace"
  project_path: "<project_root>"
```

**Run all tests (macOS):**
```
Tool: xcodebuild-mcp → test_macos
Arguments:
  scheme: "Edge AI Lab"
  workspace: "GemmaEdgeGallery.xcworkspace"
  project_path: "<project_root>"
```

### xcode-tools

**Run all tests:**
```
Tool: xcode-tools → RunAllTests
Arguments:
  scheme: "GemmaEdgeGallery_iOS"
```

**Run specific tests:**
```
Tool: xcode-tools → RunSomeTests
Arguments:
  tests: ["GemmaEdgeGallery_iOSTests/DownloadInfrastructureTests"]
```

## Running Tests with xcodebuild CLI

### Run All Tests (UnitTests plan)

```bash
xcodebuild test \
  -workspace GemmaEdgeGallery.xcworkspace \
  -scheme GemmaEdgeGallery_iOS \
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
  -workspace GemmaEdgeGallery.xcworkspace \
  -scheme GemmaEdgeGallery_iOS \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -testPlan IntegrationTests \
  -quiet \
  2>&1

# Performance tests
xcodebuild test \
  -workspace GemmaEdgeGallery.xcworkspace \
  -scheme GemmaEdgeGallery_iOS \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -testPlan PerformanceTests \
  -quiet \
  2>&1
```

### Run a Specific Test Class

```bash
xcodebuild test \
  -workspace GemmaEdgeGallery.xcworkspace \
  -scheme GemmaEdgeGallery_iOS \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:GemmaEdgeGallery_iOSTests/DownloadInfrastructureTests \
  -quiet \
  2>&1
```

### Run a Specific Test Method

```bash
xcodebuild test \
  -workspace GemmaEdgeGallery.xcworkspace \
  -scheme GemmaEdgeGallery_iOS \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:GemmaEdgeGallery_iOSTests/DownloadInfrastructureTests/testDownloadStateEquality \
  -quiet \
  2>&1
```

### Run Multiple Specific Classes

```bash
xcodebuild test \
  -workspace GemmaEdgeGallery.xcworkspace \
  -scheme GemmaEdgeGallery_iOS \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:GemmaEdgeGallery_iOSTests/DownloadInfrastructureTests \
  -only-testing:GemmaEdgeGallery_iOSTests/ChatMessageTests \
  -only-testing:GemmaEdgeGallery_iOSTests/ThinkingParserTests \
  -quiet \
  2>&1
```

### Run on macOS

Replace the scheme and destination:
```bash
xcodebuild test \
  -workspace GemmaEdgeGallery.xcworkspace \
  -scheme "Edge AI Lab" \
  -destination 'platform=macOS' \
  -only-testing:GemmaEdgeGallery_macOSTests/DownloadInfrastructureTests \
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
  -workspace GemmaEdgeGallery.xcworkspace \
  -scheme GemmaEdgeGallery_iOS \
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

Add a new `.swift` file under `Tests/`. It will be automatically picked up by both `GemmaEdgeGallery_iOSTests` and `GemmaEdgeGallery_macOSTests` targets (both use `Sources: ["Tests/**"]` glob).

```swift
import XCTest
@testable import GemmaEdgeGallery_iOS  // or GemmaEdgeGallery_macOS

final class MyNewTests: XCTestCase {
    func testSomething() {
        // ...
    }
}
```

### 2. Add to Test Plan

Edit the appropriate `.xctestplan` JSON file to include the new class:

```json
{
  "testTargets": [
    {
      "target": {
        "containerPath": "container:GemmaEdgeGallery.xcodeproj",
        "identifier": "GemmaEdgeGallery_iOSTests",
        "name": "GemmaEdgeGallery_iOSTests"
      },
      "selectedTests": [
        "ExistingTests",
        "MyNewTests"
      ]
    }
  ]
}
```

> **IMPORTANT:** If a test plan uses `selectedTests`, only listed classes run. You MUST add your new class name to the `selectedTests` array. If the test plan has no `selectedTests`, all tests in the target run automatically.

### 3. Verify

```bash
xcodebuild test \
  -workspace GemmaEdgeGallery.xcworkspace \
  -scheme GemmaEdgeGallery_iOS \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:GemmaEdgeGallery_iOSTests/MyNewTests \
  -quiet \
  2>&1
```

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
error: Unable to find a target named 'GemmaEdgeGallery_iOSTests'
```
**Fix:** Run `tuist generate` to regenerate the project.

### Tests Hang on Device
**CRITICAL:** On-device XCTest currently hangs due to iOS 26 beta `@Observable` feedback loop. Use the simulator or macOS for XCTest. Use the `automation-harness` skill for on-device E2E testing.

### Module Import Errors
```
error: No such module 'GemmaEdgeGallery_iOS'
```
**Fix:** Build the main app target first, then run tests.

### Flaky Tests
If a test passes sometimes and fails others, try:
```bash
# Run with retry
xcodebuild test \
  -workspace GemmaEdgeGallery.xcworkspace \
  -scheme GemmaEdgeGallery_iOS \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:GemmaEdgeGallery_iOSTests/FlakyTestClass \
  -retry-tests-on-failure \
  -test-iterations 3 \
  2>&1
```
