---
name: device-recovery
description: "Diagnose and recover from common iOS physical device testing failures. Activate when device builds, tests, or deployments fail — especially testmanagerd hangs, DTDeviceKit crashes, pairing issues, and Keychain security blocks."
---

# Device Recovery Procedures

This skill documents common physical device testing failures and their recovery procedures, based on patterns observed across multiple development sessions.

## Failure Taxonomy

### 1. `testmanagerd` Hung Connection

**Symptoms:**
- `xcodebuild test` starts but hangs at 0% CPU indefinitely
- No test output appears after 2+ minutes
- Process is alive but doing nothing

**Diagnosis:**
```bash
# Check if testmanagerd is running
ps aux | grep testmanagerd

# Check device connectivity
xcrun devicectl list devices
```

**Recovery:**
1. Kill any stuck xcodebuild processes: `pkill -f 'xcodebuild test'`
2. **Restart the iPhone** (Settings → General → Shut Down)
3. After restart, unlock the phone and trust the computer if prompted
4. Wait 30 seconds for CoreDevice tunnel to re-establish
5. Verify: `xcrun devicectl list devices` shows the device

> [!WARNING]
> This is the most common and most disruptive failure. There is no software-only fix — the device **must** be physically restarted.

---

### 2. DTDeviceKit / notification_proxy Crash

**Symptoms:**
```
The test runner hung before establishing connection.
❌ 1 test failed, 0 passed, 0 skipped (⏱️ 346.1s)
```
- Native crash stack traces mentioning `DTDeviceKitBase` → `DTDKExecuteWithConnection`

**Recovery:**
1. Same as testmanagerd — **restart the iPhone**
2. If the crash happened during a previous test attempt, ensure no stale `xcodebuild` processes remain
3. After restart, wait for the CoreDevice tunnel to re-establish before retrying

---

### 3. "Outstanding Termination Assertions"

**Symptoms:**
```
ERROR: The application failed to launch. (com.apple.dt.CoreDeviceError error 10002)
BSErrorCodeDescription = RequestDenied
NSLocalizedFailureReason = The request was denied by service delegate (SBMainWorkspace) 
for reason: Busy ("Application cannot be launched because it has outstanding termination assertions").
```

**Recovery:**
1. Kill any stuck xcodebuild/test processes: `pkill -f 'xcodebuild'`
2. Wait 30 seconds for the device to clean up assertions
3. Force-quit the app on the device (swipe up from app switcher)
4. Retry the build/launch

> [!NOTE]
> This is usually a transient issue caused by a previous crashed test run leaving the app in a zombie state.

---

### 4. Device Pairing Issues

**Symptoms:**
- "Manual pairing of this device is already in progress"
- "The device must be paired before it can be connected"
- `xcrun devicectl manage pair` fails

**Recovery:**
1. **DO NOT** unpair the device unless absolutely necessary
2. If already unpaired:
   - `xcrun devicectl manage pair --device <UDID>`
   - Tap "Trust" on the iPhone when prompted
   - **Restart the iPhone** (required after re-pairing for testmanagerd)
3. Verify: `xcrun devicectl list devices` shows the device as "available"

---

### 5. Keychain Security Blocking (Code Signing)

**Symptoms:**
- Raw `xcodebuild` command hangs waiting for Keychain password
- Code signing fails in non-interactive sessions
- Build succeeds in Xcode.app but fails via CLI

**Recovery:**
- **NEVER use raw `xcodebuild` for device builds** — always use XcodeBuildMCP `build_device` or `build_run_device`
- XcodeBuildMCP handles Keychain interaction properly
- If you must use raw xcodebuild: `security unlock-keychain -p <password> login.keychain` (requires password)

> [!IMPORTANT]
> This is the #1 reason to always use MCP tools for device builds. The project rule `build-tool-boundaries.md` explicitly forbids raw `xcodebuild` for this reason.

---

### 6. Test Plan Not Linked to Scheme

**Symptoms:**
```
xcodebuild: error: The flag -testPlan <name> cannot be used since the scheme does not use test plans.
```

**Recovery:**
- Use `-only-testing:GemmaEdgeGallery_iOSTests` instead of `-testPlan UnitTests`
- Or run `tuist generate` to ensure the scheme has test plans linked
- With XcodeBuildMCP: test plans should work if Tuist generated the scheme correctly

---

### 7. Test Bundle Loading Failure

**Symptoms:**
```
Unable to initialize test bundle from .../GemmaEdgeGallery_iOSTests.xctest
Failed to load test bundle from .../GemmaEdgeGallery_iOSTests.xctest: (null)
```

**Recovery:**
1. Clean build: `clean` tool via XcodeBuildMCP
2. Rebuild: `build_device` or `build_sim`
3. If persists, run `tuist generate` to regenerate the project

---

## Pre-Flight Checklist (Before Device Testing)

Run this checklist before attempting any device test:

1. ✅ Device is **unlocked** and screen is on
2. ✅ Device is **trusted** (no "Trust This Computer" dialogs)
3. ✅ No active Xcode debug sessions (press ⏹ in Xcode first)
4. ✅ `xcrun devicectl list devices` shows the device as available
5. ✅ App is installed on device: use `install_app_device` MCP tool
6. ✅ No stuck `xcodebuild` processes: `pkill -f 'xcodebuild test'` if needed
7. ✅ Model files pushed to device Documents/ (for performance tests)

## Escalation Path

If recovery steps don't work:

```
Kill stuck processes → Wait 30s → Retry
    ↓ (still failing)
Restart iPhone → Wait for tunnel → Retry
    ↓ (still failing)
Unpair → Re-pair → Restart iPhone → Retry
    ↓ (still failing)
Restart Mac → Restart iPhone → Re-pair → Retry
```

> [!CAUTION]
> Each escalation level is progressively more disruptive. Start at the top and only escalate if the simpler fix doesn't work. iPhone restart fixes ~90% of device test issues.
