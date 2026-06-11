---
name: device-testing
description: Deploy and test GemmaEdgeGallery on physical iOS devices, including code signing, device connection, and running XCTest and automation flows on hardware.
---

# Device Testing

This skill covers deploying GemmaEdgeGallery to physical iOS devices, handling code signing, and running the full test suite on hardware.

## Known Device

| Property | Value |
|---|---|
| Device Name | Phactivity Monitor |
| Model | iPhone 16 Pro Max |
| OS | iOS 26 |
| UDID | 3B50314A-0702-5188-A321-BCD5CA5F8184 |
| Connection | USB / Wi-Fi |

## ✅ On-Device XCTest Works

On-device XCTest works correctly. **418 tests complete in ~3.4 seconds** with 0 failures.

### History: The PhaseAnimator Hang (Resolved)

Previous sessions documented an "iOS 26 beta XCTest hang." The actual root cause was `PhaseAnimator` in `PulsingGlowModifier` — it cycles between phases forever, saturating the test host's runloop at 130%+ CPU. The fix: `PulsingGlowModifier` detects `XCTestConfigurationFilePath` in the environment and applies a static shadow instead of the animation. No animation → no runloop saturation → tests complete normally.

> **If you add a new perpetual animation (PhaseAnimator, withAnimation(.repeatForever)), wrap it with the XCTest guard:**
> ```swift
> private static let isRunningTests =
>     ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
> ```

## Code Signing Configuration

| Property | Value |
|---|---|
| Signing Style | Automatic |
| Team ID | `Y7J7WUK693` |
| Bundle ID | `com.andrewvoirol.GemmaEdgeGallery` |
| Entitlements | `GemmaEdgeGallery_iOS.entitlements` |

The Team ID is configured in `Project.swift` with environment variable override:

```swift
let teamId = ProcessInfo.processInfo.environment["DEVELOPMENT_TEAM"] ?? "Y7J7WUK693"
```

### Override Team ID

```bash
export DEVELOPMENT_TEAM=YOUR_TEAM_ID
tuist generate  # Regenerate with new team
```

### iOS Entitlements

The iOS entitlements include:
- `com.apple.developer.kernel.increased-memory-limit` — Required for large model inference (2B+ parameter models consume significant RAM)

## Checking Device Connection

### CLI

```bash
# List all connected devices
xcrun devicectl list devices

# Check specific device
xcrun devicectl list devices | grep "Phactivity"
```

### MCP

```
Tool: xcodebuild-mcp → list_devices
```

### Troubleshooting Connection

1. **USB:** Ensure device is unlocked, trust dialog accepted
2. **Wi-Fi:** Device and Mac must be on same network; device must have been paired via USB first
3. **Developer Mode:** Must be enabled on device: Settings → Privacy & Security → Developer Mode

```bash
# If device not showing, restart usbmuxd
sudo killall usbmuxd
```

## Building for Device

### MCP (xcodebuild-mcp) — Recommended

**Set defaults first:**
```
Tool: xcodebuild-mcp → session_set_defaults
Arguments:
  deviceId: "3B50314A-0702-5188-A321-BCD5CA5F8184"
  scheme: "GemmaEdgeGallery_iOS"
  workspacePath: "<project_root>/GemmaEdgeGallery.xcworkspace"
  bundleId: "com.andrewvoirol.GemmaEdgeGallery"
```

**Build only:**
```
Tool: xcodebuild-mcp → build_device
```

**Build & Run:**
```
Tool: xcodebuild-mcp → build_run_device
```

### CLI

```bash
xcodebuild build \
  -workspace GemmaEdgeGallery.xcworkspace \
  -scheme GemmaEdgeGallery_iOS \
  -destination 'id=3B50314A-0702-5188-A321-BCD5CA5F8184' \
  -configuration Debug \
  -quiet \
  2>&1
```

## Running XCTest on Device

### Recommended Command

```bash
xcodebuild test \
  -workspace GemmaEdgeGallery.xcworkspace \
  -scheme GemmaEdgeGallery_iOS \
  -destination 'id=3B50314A-0702-5188-A321-BCD5CA5F8184' \
  -only-testing:GemmaEdgeGallery_iOSTests \
  -allowProvisioningUpdates \
  2>&1
```

**Expected results:** 418 tests, 0 failures, ~3.4 seconds, `** TEST SUCCEEDED **`

### Output to File (Avoids SIGPIPE)

When piping xcodebuild output through `grep | tail`, SIGPIPE can kill the process. Redirect to a file instead:

```bash
xcodebuild test \
  -workspace GemmaEdgeGallery.xcworkspace \
  -scheme GemmaEdgeGallery_iOS \
  -destination 'id=3B50314A-0702-5188-A321-BCD5CA5F8184' \
  -only-testing:GemmaEdgeGallery_iOSTests \
  -allowProvisioningUpdates \
  > test_results.log 2>&1

# Then parse:
grep -E "** TEST|Executed.*tests" test_results.log
```

### Specific Test Class

```bash
xcodebuild test \
  -workspace GemmaEdgeGallery.xcworkspace \
  -scheme GemmaEdgeGallery_iOS \
  -destination 'id=3B50314A-0702-5188-A321-BCD5CA5F8184' \
  -only-testing:GemmaEdgeGallery_iOSTests/SettingsToggleTests \
  -allowProvisioningUpdates \
  2>&1
```

### MCP

```
Tool: xcodebuild-mcp → test_device
```

> **NOTE:** The MCP tool may fail with provisioning errors for the UITest runner. Use `xcodebuild test` with `-allowProvisioningUpdates` directly.

## Running Automation Flows on Device

For E2E user journeys, benchmarks, and multi-configuration testing, use the DeveloperAutomationHarness. See the `automation-harness` skill for full details.

### Quick Start

```bash
# Run all 6 flows
xcrun devicectl device process launch \
  --device 3B50314A-0702-5188-A321-BCD5CA5F8184 \
  --console \
  com.andrewvoirol.GemmaEdgeGallery \
  -- -RunAllFlows
```

**Expected:** 6/6 flows passed, 50/50 steps, exit code 0.

### Run a Specific Flow

```bash
xcrun devicectl device process launch \
  --device 3B50314A-0702-5188-A321-BCD5CA5F8184 \
  --console \
  com.andrewvoirol.GemmaEdgeGallery \
  -- -RunFlow settings_flow
```

## Recommended Device Testing Workflow

1. **Run XCTest on device** — fast validation (418 tests, 3.4s)
   ```bash
   xcodebuild test ... -only-testing:GemmaEdgeGallery_iOSTests -allowProvisioningUpdates
   ```
2. **Run automation flows** — E2E validation (6 flows, 37.7s)
   ```bash
   xcrun devicectl device process launch ... -- -RunAllFlows
   ```
3. **Run specific benchmark** — performance regression check
   ```bash
   xcrun devicectl device process launch ... -- -RunFlow benchmark_flow
   ```
4. **Parse results** — look for `** TEST SUCCEEDED **` or `[AUTOMATION_FLOW_SUMMARY] 6/6 flows passed`

## Two Testing Strategies

| Strategy | Tool | Speed | Scope | Use When |
|----------|------|-------|-------|----------|
| **XCTest** | `xcodebuild test` | 3.4s / 418 tests | Unit + Integration | Every PR, every commit |
| **Automation Harness** | `-RunAllFlows` | 37.7s / 50 steps | E2E user journeys | Release validation, benchmarks |

Both are proven working on the iPhone 16 Pro Max.

## Device-Specific Considerations

### Memory

The iPhone 16 Pro Max has 8 GB RAM. The app uses the `increased-memory-limit` entitlement. Model sizes:
- Gemma 4 E2B: ~1.3 GB (fits comfortably)
- Gemma 4 E4B: ~2.5 GB (fits with constraints)
- Gemma 4 12B: ~6+ GB (may trigger memory pressure warnings)

### Thermal Management

The `DeveloperAutomationHarness` includes thermal throttle detection. Between benchmark runs, it checks `ProcessInfo.processInfo.thermalState` and waits up to 60 seconds for the device to cool below `.serious` level before proceeding.

### File Sharing

The app supports iTunes/Finder file sharing (`UIFileSharingEnabled`). You can copy `.litertlm` model files to the device's Documents directory via Finder:
1. Connect device via USB
2. Open Finder → Select device → Files tab
3. Drag `.litertlm` files into GemmaEdgeGallery's Documents folder

## Stopping the App

### MCP

```
Tool: xcodebuild-mcp → stop_app_device
Arguments:
  deviceId: "3B50314A-0702-5188-A321-BCD5CA5F8184"
  processId: <PID from launch>
```

### CLI

```bash
xcrun devicectl device process terminate \
  --device 3B50314A-0702-5188-A321-BCD5CA5F8184 \
  com.andrewvoirol.GemmaEdgeGallery
```

## Debugging on Device

### View Device Logs

```bash
# Stream device logs filtered to the app
xcrun devicectl device process log stream \
  --device "Phactivity Monitor" \
  --predicate 'subsystem == "com.andrewvoirol.GemmaEdgeGallery"'
```

### Check Device Info

```bash
xcrun devicectl list devices --verbose
```

### Check Running Processes

```bash
xcrun devicectl device info processes \
  --device 3B50314A-0702-5188-A321-BCD5CA5F8184 \
  2>&1 | grep GemmaEdge
```
