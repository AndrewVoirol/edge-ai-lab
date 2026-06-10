---
name: build-verification
description: Build the GemmaEdgeGallery project for iOS and macOS platforms, verify zero errors, and troubleshoot common build failures. Use this skill whenever you need to compile the app, verify a code change builds cleanly, or diagnose build errors.
---

# Build Verification

This skill covers building GemmaEdgeGallery for both iOS (simulator) and macOS, interpreting build results, and fixing common issues.

## Project Configuration

| Property | Value |
|---|---|
| Workspace | `GemmaEdgeGallery.xcworkspace` |
| Xcode Project | `GemmaEdgeGallery.xcodeproj` |
| Project Manifest | `Project.swift` (Tuist) |
| Team ID | `Y7J7WUK693` |

### Schemes

| Scheme | Platform | Target | Product |
|---|---|---|---|
| `GemmaEdgeGallery_iOS` | iOS | `GemmaEdgeGallery_iOS` | App |
| `Edge AI Lab` | macOS | `GemmaEdgeGallery_macOS` | App |
| `RawBenchmark` | macOS | `RawBenchmark` | CLI Tool |

### Build Destinations

- **iOS Simulator:** Use dynamic selection (see below). Currently: `iPhone 17 Pro Max` (iOS 26.5)
- **macOS:** `platform=macOS`
- **Physical Device:** `platform=iOS,name=Phactivity Monitor` (iPhone 16 Pro Max)

> **IMPORTANT:** Always discover simulators dynamically. Simulator names change with Xcode/iOS versions.
> ```bash
> # Find first available iPhone simulator
> SIM_UDID=$(xcrun simctl list devices available -j | python3 -c "
> import json, sys
> data = json.load(sys.stdin)
> for runtime, devices in sorted(data['devices'].items(), reverse=True):
>     if 'iOS' in runtime:
>         for d in devices:
>             if 'iPhone' in d['name'] and d['isAvailable']:
>                 print(d['udid']); sys.exit(0)
> sys.exit(1)")
> # Then use: -destination "platform=iOS Simulator,id=$SIM_UDID"
> ```

## Building with MCP Tools (Preferred)

### Option A: xcodebuild-mcp (Recommended)

**iOS Simulator Build:**
```
Tool: xcodebuild-mcp → build_sim
Arguments:
  scheme: "GemmaEdgeGallery_iOS"
  simulator: "iPhone 17 Pro Max"  # Use `xcrun simctl list devices available | grep iPhone` to find correct name
  workspace: "GemmaEdgeGallery.xcworkspace"
  project_path: "<project_root>"
```

**macOS Build:**
```
Tool: xcodebuild-mcp → build_macos
Arguments:
  scheme: "Edge AI Lab"
  workspace: "GemmaEdgeGallery.xcworkspace"
  project_path: "<project_root>"
```

### Option B: xcode-tools

```
Tool: xcode-tools → BuildProject
Arguments:
  scheme: "GemmaEdgeGallery_iOS"  (or "Edge AI Lab")
  configuration: "Debug"
```

## Building with xcodebuild CLI

### iOS Simulator

```bash
xcodebuild build \
  -workspace GemmaEdgeGallery.xcworkspace \
  -scheme GemmaEdgeGallery_iOS \
  -destination "platform=iOS Simulator,id=$SIM_UDID" \  # Use dynamic UDID from above
  -configuration Debug \
  -quiet \
  2>&1
```

### macOS

```bash
xcodebuild build \
  -workspace GemmaEdgeGallery.xcworkspace \
  -scheme "Edge AI Lab" \
  -destination 'platform=macOS' \
  -configuration Debug \
  -quiet \
  2>&1
```

### RawBenchmark (macOS CLI)

```bash
xcodebuild build \
  -workspace GemmaEdgeGallery.xcworkspace \
  -scheme RawBenchmark \
  -destination 'platform=macOS' \
  -configuration Release \
  -quiet \
  2>&1
```

## Interpreting Build Results

### Success Indicators
- Exit code `0`
- Output contains `** BUILD SUCCEEDED **`
- No lines matching `error:` pattern

### Failure Indicators
- Exit code non-zero
- Output contains `** BUILD FAILED **`
- Error lines follow the format: `<file>:<line>:<col>: error: <message>`

### Reading Build Logs

Use the xcode-tools MCP to get detailed build logs:
```
Tool: xcode-tools → GetBuildLog
```

Parse errors from logs by looking for:
- `error:` — Compilation errors (must fix)
- `warning:` — Compiler warnings (should review)
- `note:` — Contextual info about errors
- `linker command failed` — Linking issues

## When to Run `tuist generate` First

You MUST run `tuist generate` before building if any of these changed:

1. **`Project.swift`** was modified (targets, dependencies, schemes, settings)
2. **New targets** were added or removed
3. **Dependencies** were added, removed, or updated (LiteRT-LM, MarkdownUI)
4. **Entitlements files** were added or changed
5. **Scheme configurations** were modified
6. **The `.xcodeproj` or `.xcworkspace` is missing or corrupted**

```bash
cd <project_root>
tuist generate
```

> **NOTE:** You do NOT need to regenerate after adding/removing `.swift` source files — the project uses `Sources/**` glob patterns that automatically pick up new files.

## Common Build Issues & Fixes

### 1. SPM Package Resolution Failure

**Symptom:** `unable to resolve dependencies`, `package resolution failed`

**Fix:**
```bash
# Reset SPM caches
xcodebuild -resolvePackageDependencies \
  -workspace GemmaEdgeGallery.xcworkspace \
  -scheme GemmaEdgeGallery_iOS

# Nuclear option: clear derived data
rm -rf ~/Library/Developer/Xcode/DerivedData/GemmaEdgeGallery-*
```

### 2. Code Signing Errors

**Symptom:** `Signing requires a development team`, `No signing certificate`

**Fix:** Ensure Team ID is set. The project reads from the `DEVELOPMENT_TEAM` environment variable, falling back to `Y7J7WUK693`:
```bash
export DEVELOPMENT_TEAM=Y7J7WUK693
```
For simulator builds, code signing is not required. Add `CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO` to xcodebuild if needed.

### 3. Missing Generated Files

**Symptom:** `No such module 'GemmaEdgeGallery_iOS'`, missing `Info.plist`

**Fix:**
```bash
cd <project_root>
tuist generate
```

### 4. LiteRT-LM Build Errors

**Symptom:** Errors in `LiteRTLM` module, `unsafeFlags` warnings

**Note:** The project uses `.branch("main")` instead of a tagged version to bypass SPM `unsafeFlags` restriction. If LiteRT-LM's `main` branch has breaking changes:
```bash
# Force re-resolve to latest main
rm -rf .build
rm -rf ~/Library/Developer/Xcode/DerivedData/GemmaEdgeGallery-*
xcodebuild -resolvePackageDependencies -workspace GemmaEdgeGallery.xcworkspace -scheme GemmaEdgeGallery_iOS
```

### 5. Stale Tuist Cache

**Symptom:** Build uses outdated settings, scheme not found

**Fix:**
```bash
tuist clean
tuist generate
```

### 6. Destination Not Found

**Symptom:** `Unable to find a destination matching the provided destination specifier`

**Fix:** List available simulators and use an exact match:
```bash
xcrun simctl list devices available | grep iPhone
```

## Verification Checklist

After making code changes, verify both platforms build:

1. ✅ iOS Simulator build: `0 errors`
2. ✅ macOS build: `0 errors`
3. ✅ Review any new warnings (ideally 0 new warnings)
4. ✅ If Project.swift changed: `tuist generate` first, then build both

## Full Verification Command (Both Platforms)

```bash
# iOS
xcodebuild build -workspace GemmaEdgeGallery.xcworkspace -scheme GemmaEdgeGallery_iOS -destination "platform=iOS Simulator,id=$SIM_UDID" -quiet 2>&1 | tail -5

# macOS
xcodebuild build -workspace GemmaEdgeGallery.xcworkspace -scheme "Edge AI Lab" -destination 'platform=macOS' -quiet 2>&1 | tail -5
```

Both should output `** BUILD SUCCEEDED **`.
