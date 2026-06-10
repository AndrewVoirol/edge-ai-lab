---
name: device-testing
description: Deploy and test GemmaEdgeGallery on physical iOS devices, including code signing, device connection, and the critical XCTest hang workaround. Use this skill when you need to run the app on a real iPhone for performance testing, model inference, or E2E validation.
---

# Device Testing

This skill covers deploying GemmaEdgeGallery to physical iOS devices, handling code signing, and working around known iOS 26 beta issues.

## Known Device

| Property | Value |
|---|---|
| Device Name | Phactivity Monitor |
| Model | iPhone 16 Pro Max |
| OS | iOS 26 beta |
| Connection | USB / Wi-Fi |

## ⚠️ CRITICAL WARNING: On-Device XCTest Hang

> **On-device XCTest currently hangs** due to an iOS 26 beta bug. The `@Observable` macro triggers a feedback loop in `NavigationStackHostingController` that freezes the test runner indefinitely. This affects ALL XCTest-based tests when run on a physical device.
>
> **Do NOT run `xcodebuild test` targeting a physical device.** It will hang and never complete.

### Workaround: Use DeveloperAutomationHarness

Instead of XCTest on device, use the in-app automation harness:

```bash
# Launch with automation arguments
xcrun devicectl device process launch \
  --device "Phactivity Monitor" \
  com.andrewvoirol.GemmaEdgeGallery \
  -- -RunAllTests
```

Or for specific flows:
```bash
xcrun devicectl device process launch \
  --device "Phactivity Monitor" \
  com.andrewvoirol.GemmaEdgeGallery \
  -- -RunFlow benchmark_flow
```

See the `automation-harness` skill for full details on automation flows and parsing output.

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

Expected output:
```
Phactivity Monitor    iPhone 16 Pro Max    XXXXXXXX-XXXX...    connected
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

### MCP (xcodebuild-mcp)

**Build only:**
```
Tool: xcodebuild-mcp → build_device
Arguments:
  scheme: "GemmaEdgeGallery_iOS"
  device: "Phactivity Monitor"
  workspace: "GemmaEdgeGallery.xcworkspace"
  project_path: "<project_root>"
```

**Build & Run:**
```
Tool: xcodebuild-mcp → build_run_device
Arguments:
  scheme: "GemmaEdgeGallery_iOS"
  device: "Phactivity Monitor"
  workspace: "GemmaEdgeGallery.xcworkspace"
  project_path: "<project_root>"
```

### CLI

```bash
xcodebuild build \
  -workspace GemmaEdgeGallery.xcworkspace \
  -scheme GemmaEdgeGallery_iOS \
  -destination 'platform=iOS,name=Phactivity Monitor' \
  -configuration Debug \
  -quiet \
  2>&1
```

## Installing the App

### MCP

```
Tool: xcodebuild-mcp → install_app_device
Arguments:
  device: "Phactivity Monitor"
  app_path: "<path_to_built_app>"
```

### CLI

```bash
xcrun devicectl device install app \
  --device "Phactivity Monitor" \
  "$APP_PATH/GemmaEdgeGallery_iOS.app"
```

## Launching the App

### MCP

```
Tool: xcodebuild-mcp → launch_app_device
Arguments:
  device: "Phactivity Monitor"
  bundle_id: "com.andrewvoirol.GemmaEdgeGallery"
  arguments: ["-RunAllTests"]
```

### CLI

```bash
# Basic launch
xcrun devicectl device process launch \
  --device "Phactivity Monitor" \
  com.andrewvoirol.GemmaEdgeGallery

# Launch with automation arguments
xcrun devicectl device process launch \
  --device "Phactivity Monitor" \
  com.andrewvoirol.GemmaEdgeGallery \
  -- -RunAllTests

# Launch with specific flow
xcrun devicectl device process launch \
  --device "Phactivity Monitor" \
  com.andrewvoirol.GemmaEdgeGallery \
  -- -RunFlow inference_flow
```

### Capture Console Output

To see `[AUTOMATION]` stdout on device, use the console option:
```bash
xcrun devicectl device process launch \
  --device "Phactivity Monitor" \
  --console \
  com.andrewvoirol.GemmaEdgeGallery \
  -- -RunAllTests
```

## Stopping the App

### MCP

```
Tool: xcodebuild-mcp → stop_app_device
Arguments:
  device: "Phactivity Monitor"
  bundle_id: "com.andrewvoirol.GemmaEdgeGallery"
```

### CLI

```bash
xcrun devicectl device process terminate \
  --device "Phactivity Monitor" \
  com.andrewvoirol.GemmaEdgeGallery
```

## Getting App Data Path

```
Tool: xcodebuild-mcp → get_device_app_path
Arguments:
  device: "Phactivity Monitor"
  bundle_id: "com.andrewvoirol.GemmaEdgeGallery"
```

## Running Tests on Device (NOT RECOMMENDED)

> **DO NOT DO THIS** — XCTest hangs on iOS 26 beta devices. Use the automation harness instead.

If you absolutely must try (for future reference when the bug is fixed):

### MCP

```
Tool: xcodebuild-mcp → test_device
Arguments:
  scheme: "GemmaEdgeGallery_iOS"
  device: "Phactivity Monitor"
  workspace: "GemmaEdgeGallery.xcworkspace"
```

### CLI

```bash
# WARNING: Will likely hang on iOS 26 beta
xcodebuild test \
  -workspace GemmaEdgeGallery.xcworkspace \
  -scheme GemmaEdgeGallery_iOS \
  -destination 'platform=iOS,name=Phactivity Monitor' \
  -only-testing:GemmaEdgeGallery_iOSTests/ChatMessageTests \
  -quiet \
  2>&1
```

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

## Debugging on Device

### Attach Debugger

```
Tool: xcodebuild-mcp → debug_attach_sim  (note: also works for devices in some setups)
```

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

## Recommended Device Testing Workflow

1. **Build for device:** Use `build_device` MCP tool
2. **Install:** Use `install_app_device` MCP tool
3. **Launch with harness:** Use `launch_app_device` with `-RunFlow <name>` arguments
4. **Monitor output:** Watch for `[AUTOMATION_SUCCESS]` or `[AUTOMATION_FAILURE]` in console
5. **Parse results:** Look for `[AUTOMATION_RESULTS_JSON]` block in output
6. **Run XCTests on simulator instead:** Use `test_sim` for actual XCTest execution
