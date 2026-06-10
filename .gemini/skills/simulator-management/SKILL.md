---
name: simulator-management
description: Manage iOS simulators for GemmaEdgeGallery — boot, install, launch, take screenshots, inspect UI trees, and automate UI interactions. Use this skill when deploying to simulator, debugging UI, or running automation flows on a simulated device.
---

# Simulator Management

This skill covers creating, booting, and interacting with iOS Simulators for GemmaEdgeGallery development and testing.

## Preferred Simulator

| Property | Value |
|---|---|
| Device | Dynamic — use `xcrun simctl list devices available \| grep iPhone` |
| Current | iPhone 17 Pro Max (iOS 26.5, UDID: C6E6FFA0-2646-4FF2-ABA1-AD78DC64B2D8) |
| OS | iOS 26.5 |
| Bundle ID | `com.andrewvoirol.GemmaEdgeGallery` |

> **IMPORTANT:** Always discover simulators dynamically. The available simulator names change with Xcode/iOS SDK updates. Use UDID-based destination for reliability.

## Listing Available Simulators

### CLI

```bash
xcrun simctl list devices available
```

Filter for specific devices:
```bash
xcrun simctl list devices available | grep "iPhone 16"
```

Output format:
```
-- iOS 26.0 --
    iPhone 16 Pro (XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX) (Shutdown)
    iPhone 16 Pro Max (YYYYYYYY-YYYY-YYYY-YYYY-YYYYYYYYYYYY) (Booted)
```

### MCP (xcodebuild-mcp)

```
Tool: xcodebuild-mcp → list_sims
```

Returns a list of all available simulators with their UDIDs and states.

## Booting a Simulator

### CLI

```bash
# Boot by name (picks first match)
xcrun simctl boot "iPhone 16 Pro"

# Boot by UDID (more precise)
xcrun simctl boot XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX

# Open the Simulator.app window
open -a Simulator
```

### MCP (xcodebuild-mcp)

```
Tool: xcodebuild-mcp → boot_sim
Arguments:
  simulator: "iPhone 16 Pro"
```

```
Tool: xcodebuild-mcp → open_sim
Arguments:
  simulator: "iPhone 16 Pro"
```

### Check if Already Booted

```bash
xcrun simctl list devices booted
```

## Building & Running on Simulator

### Build Only

```
Tool: xcodebuild-mcp → build_sim
Arguments:
  scheme: "GemmaEdgeGallery_iOS"
  simulator: "iPhone 16 Pro"
  workspace: "GemmaEdgeGallery.xcworkspace"
```

### Build & Run

```
Tool: xcodebuild-mcp → build_run_sim
Arguments:
  scheme: "GemmaEdgeGallery_iOS"
  simulator: "iPhone 16 Pro"
  workspace: "GemmaEdgeGallery.xcworkspace"
```

### CLI Build & Install

```bash
# Build for simulator
xcodebuild build \
  -workspace GemmaEdgeGallery.xcworkspace \
  -scheme GemmaEdgeGallery_iOS \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -quiet \
  2>&1

# Find the built app
APP_PATH=$(xcodebuild -workspace GemmaEdgeGallery.xcworkspace \
  -scheme GemmaEdgeGallery_iOS \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -showBuildSettings 2>/dev/null | grep ' BUILT_PRODUCTS_DIR' | awk '{print $3}')
echo "$APP_PATH/GemmaEdgeGallery_iOS.app"
```

## Installing the App

### CLI

```bash
# Install by simulator name (uses booted sim)
xcrun simctl install booted "$APP_PATH/GemmaEdgeGallery_iOS.app"

# Install by UDID
xcrun simctl install <udid> "$APP_PATH/GemmaEdgeGallery_iOS.app"
```

### MCP

```
Tool: xcodebuild-mcp → install_app_sim
Arguments:
  simulator: "iPhone 16 Pro"
  app_path: "<path_to_built_app>"
```

## Launching the App

### Basic Launch

```bash
xcrun simctl launch booted com.andrewvoirol.GemmaEdgeGallery
```

### Launch with Automation Arguments

```bash
# Run all automation tests (full benchmark)
xcrun simctl launch booted com.andrewvoirol.GemmaEdgeGallery -- -RunAllTests

# Run a specific automation flow
xcrun simctl launch booted com.andrewvoirol.GemmaEdgeGallery -- -RunFlow model_setup

# Run matrix benchmark
xcrun simctl launch booted com.andrewvoirol.GemmaEdgeGallery -- -RunMatrixBenchmark
```

### Launch and Capture stdout

```bash
# Use --console to see stdout (including [AUTOMATION] output)
xcrun simctl launch --console booted com.andrewvoirol.GemmaEdgeGallery -- -RunAllTests
```

### MCP Launch

```
Tool: xcodebuild-mcp → launch_app_sim
Arguments:
  simulator: "iPhone 16 Pro"
  bundle_id: "com.andrewvoirol.GemmaEdgeGallery"
  arguments: ["-RunFlow", "model_setup"]
```

## Stopping the App

```bash
xcrun simctl terminate booted com.andrewvoirol.GemmaEdgeGallery
```

```
Tool: xcodebuild-mcp → stop_app_sim
Arguments:
  simulator: "iPhone 16 Pro"
  bundle_id: "com.andrewvoirol.GemmaEdgeGallery"
```

## Taking Screenshots

### MCP (Preferred)

```
Tool: xcodebuild-mcp → screenshot
Arguments:
  simulator: "iPhone 16 Pro"
  save_path: "<output_path>/screenshot.png"
```

### CLI

```bash
xcrun simctl io booted screenshot screenshot.png
```

## UI Snapshots (Accessibility Tree)

Get the full accessibility tree of the current screen. Essential for debugging UI automation and understanding what elements are available.

```
Tool: xcodebuild-mcp → snapshot_ui
Arguments:
  simulator: "iPhone 16 Pro"
```

This returns a hierarchical JSON/text representation of all accessibility elements on screen, including:
- Element types (Button, StaticText, TextField, etc.)
- Labels and identifiers
- Frames and positions
- Enabled/disabled state

## UI Automation via MCP

The xcodebuild-mcp provides tools for programmatic UI interaction:

### Tap an Element

```
Tool: xcodebuild-mcp → tap
Arguments:
  simulator: "iPhone 16 Pro"
  element: "Generate Response"
```

### Touch at Coordinates

```
Tool: xcodebuild-mcp → touch
Arguments:
  simulator: "iPhone 16 Pro"
  x: 200
  y: 400
```

### Long Press

```
Tool: xcodebuild-mcp → long_press
Arguments:
  simulator: "iPhone 16 Pro"
  element: "Model Card"
  duration: 2.0
```

### Swipe

```
Tool: xcodebuild-mcp → swipe
Arguments:
  simulator: "iPhone 16 Pro"
  direction: "up"
```

### Type Text

```
Tool: xcodebuild-mcp → type_text
Arguments:
  simulator: "iPhone 16 Pro"
  text: "Describe the theory of general relativity"
```

### Press Buttons

```
Tool: xcodebuild-mcp → button
Arguments:
  simulator: "iPhone 16 Pro"
  button: "home"
```

### Key Press

```
Tool: xcodebuild-mcp → key_press
Arguments:
  simulator: "iPhone 16 Pro"
  key: "return"
```

## Getting App Data Path

Useful for inspecting app sandbox (Documents, Caches, etc.):

### MCP

```
Tool: xcodebuild-mcp → get_sim_app_path
Arguments:
  simulator: "iPhone 16 Pro"
  bundle_id: "com.andrewvoirol.GemmaEdgeGallery"
```

### CLI

```bash
xcrun simctl get_app_container booted com.andrewvoirol.GemmaEdgeGallery data
```

This returns the path to the app's data container. Useful subdirectories:
- `Documents/` — Downloaded model files (`.litertlm`)
- `Library/Caches/` — Model caches
- `Library/Preferences/` — UserDefaults plist

## Recording Video

```
Tool: xcodebuild-mcp → record_sim_video
Arguments:
  simulator: "iPhone 16 Pro"
  save_path: "<output_path>/recording.mp4"
```

## Common Simulator Issues

### Simulator Won't Boot

```bash
# Kill all simulator processes
killall "Simulator" 2>/dev/null
killall "SimulatorTrampoline" 2>/dev/null

# Erase and retry
xcrun simctl erase "iPhone 16 Pro"
xcrun simctl boot "iPhone 16 Pro"
```

### App Crashes on Launch

Check simulator logs:
```bash
# Tail system log for the app
xcrun simctl spawn booted log stream --predicate 'subsystem == "com.andrewvoirol.GemmaEdgeGallery"' --level debug
```

### Simulator Out of Disk Space

Models are large (1-4 GB). Clear old data:
```bash
# Get data path
DATA_PATH=$(xcrun simctl get_app_container booted com.andrewvoirol.GemmaEdgeGallery data)
# Remove cached models
rm -rf "$DATA_PATH/Documents/"*.litertlm
```

### Multiple Simulators with Same Name

Use UDID instead of name to avoid ambiguity:
```bash
xcrun simctl list devices | grep "iPhone 16 Pro"
# Pick the correct UDID
xcrun simctl boot <specific-udid>
```
