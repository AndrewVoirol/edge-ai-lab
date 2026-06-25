---
name: test-runner
description: How to run unit tests, UI tests, and device tests for EdgeAILab. Read this before running any tests. Covers test plan architecture, xcodebuild-mcp tools, macOS Cmd+N requirement, and known device pitfalls.
---

# Test Runner

## Prefer xcodebuild-mcp Over Shell Commands

The project has `xcodebuild-mcp` configured. **Always prefer MCP tools** (`test_device`, `test_macos`, `test_sim`) over raw `xcodebuild` commands. They handle build-deploy cycles, signing, and DerivedData management correctly.

### Session Setup (Required Once Per Session)

Before your first build, test, or run call, you **MUST** call `session_show_defaults` to verify the active configuration. If defaults are not set:

```
session_set_defaults:
  workspacePath: <project-root>/EdgeAILab.xcworkspace
  scheme: EdgeAILab_iOS          # or "Edge AI Lab" for macOS
  deviceId: 3B50314A-0702-5188-A321-BCD5CA5F8184   # for device tests
```

### Parameter Rules

| Parameter | Purpose | Available On |
|-----------|---------|-------------|
| `extraArgs` | xcodebuild/build-settings flags (e.g., `-testPlan`, `-only-testing:`) | All tools |
| `launchArgs` | Runtime app arguments (e.g., `-DisableAnimations`) | `build_run_device`, `launch_app_device`, NOT `test_device` |
| `testRunnerEnv` | Env vars for the test runner (`TEST_RUNNER_` prefix added automatically) | `test_device`, `test_macos`, `test_sim` |

## Test Plan Architecture

The project uses Tuist-managed test plans. Each scheme references `.xctestplan` files configured in `Project.swift`:

| Scheme | Test Plans | Targets Covered |
|--------|-----------|-----------------|
| `EdgeAILab_iOS` | `UnitTests.xctestplan` (default), `iOSUITests.xctestplan`, `SimulatorTests.xctestplan`, `IntegrationTests.xctestplan`, `PerformanceTests.xctestplan` | `EdgeAILab_iOSTests`, `EdgeAILab_iOSUITests` |
| `Edge AI Lab` (macOS) | `UnitTests.xctestplan` (default), `macOSUITests.xctestplan` | `EdgeAILab_macOSTests`, `EdgeAILab_macOSUITests` |

**Critical rule**: A test target MUST be included in a `.xctestplan` referenced by the scheme. Otherwise `-only-testing:` will fail with *"isn't a member of the specified test plan or scheme."*

### Adding a New Test Plan

1. Create the `.xctestplan` JSON file in the project root
2. Add it to the scheme's `testAction` array in `Project.swift`
3. Run `tuist generate`
4. Never edit scheme files inside `.xcodeproj/` directly — they are gitignored

## Running iOS Device Tests

### Pre-flight
```bash
bash automation/device_health_check.sh
```

### Run specific tests
```
test_device:
  extraArgs: ["-testPlan", "iOSUITests", "-only-testing:EdgeAILab_iOSUITests/DynamicTypeTests"]
```

### Run unit tests
```
test_device:
  extraArgs: ["-testPlan", "UnitTests"]
```

### Why not raw xcodebuild?
Raw `xcodebuild test-without-building` with manually-located `.xctestrun` files produces **"Bad CPU type in executable"** on iOS 26 physical devices. This is a misleading launchd error from stale DerivedData, NOT an architecture mismatch.

## Running macOS Tests

Use `test_macos` with scheme set to `"Edge AI Lab"`:

```
session_set_defaults:
  scheme: Edge AI Lab

test_macos:
  extraArgs: ["-only-testing:EdgeAILab_macOSTests/SomeTestClass"]
```

**⚠️ macOS UI tests require Cmd+N after launch.** The app restores an empty window state after `app.terminate()`. The `launchApp()` helper retries Cmd+N up to 3 times with increasing delays (2s, 3s, 4s) because macOS 26 Liquid Glass doesn't always honor the first attempt.

## Running iOS Simulator Tests

```
session_set_defaults:
  scheme: EdgeAILab_iOS
  simulatorName: iPhone 16 Pro Max

test_sim:
  extraArgs: ["-testPlan", "SimulatorTests"]
```

## Coverage Reporting

After running tests, extract coverage from the `.xcresult` bundle:
```
get_coverage_report:
  xcresultPath: <path from test output>
  showFiles: true
  target: EdgeAILab_iOS
```

> **⚠️ MCP coverage limitation**: MCP's `get_coverage_report` only instruments the **test target** binary, not the app source code under `Sources/`. The reported percentage reflects test-file coverage, not app-code coverage. To get actual app-code coverage:
> 1. Run tests via `xcodebuild test` directly (not MCP) with the workspace's standard DerivedData
> 2. Use `xcrun xccov view --report <xcresult>` to extract per-file coverage
> 3. Or open the `.xcresult` in Xcode → Coverage tab

## Diagnostics

If tools are missing or device tests fail unexpectedly, run the MCP doctor:
```
doctor: {}
```

If device/macOS/debugging/UI-automation tools are unavailable, ensure workflows are enabled in `.xcodebuildmcp/config.yaml`:
```yaml
enabledWorkflows: ["simulator", "device", "debugging", "ui-automation"]
```

## Known Device Pitfalls

| Issue | Symptom | Workaround |
|-------|---------|------------|
| Liquid Glass XCUITest | Form internals not exposed on physical device | a11y flow verifies "Settings" tab only |
| `performScrollTo` on iOS | `app.swipeUp()` hung on iOS 26 physical devices | **Fixed**: Now uses coordinate-based `press(forDuration:thenDragTo:)` like macOS. Avoids XCUITest idle-wait. |
| `--console` hang | `devicectl --console` doesn't exit after automation | **Partial fix**: `deploy_device.sh` uses `idevicesyslog` for log streaming, but it doesn't reliably capture logs on iOS 26. Completion detection may fail. Use `devicectl device copy from` to pull results from device instead. Override timeout with `CONSOLE_TIMEOUT` env var. |
| idevicesyslog silent | `idevicesyslog -m "EdgeAILab"` produces zero output on iPhone 16 Pro Max / iOS 26 | Use `xcrun devicectl device copy from` to pull result files from the device's app container. Poll `devicectl device info files` for timestamp changes. |
| Test resources missing | Tuist doesn't bundle resources to physical devices | XCTSkip guard when `Bundle(for:)` resource is nil |
| "Bad CPU type" | Stale DerivedData causes misleading launch error | Use MCP `test_device` instead of raw xcodebuild |
| MCP macOS UI automation | `test_macos` fails with "Timed out while enabling automation mode" | Set `derivedDataPath` in session defaults to the standard Xcode DerivedData path (e.g., `~/Library/Developer/Xcode/DerivedData/EdgeAILab-<hash>`). MCP's isolated DerivedData produces a runner binary at an unrecognized path for macOS automation authorization. |
