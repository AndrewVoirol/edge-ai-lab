#!/usr/bin/env bash
# device_health_check.sh — Pre-flight check for physical device testing.
#
# Verifies device connectivity, DDI services, and automation readiness.
#
# Usage:
#   ./automation/device_health_check.sh                  # Auto-detect device
#   ./automation/device_health_check.sh <DEVICE_UDID>    # Specific device
#
# Exit codes:
#   0 — Device is ready for testing
#   1 — Device has issues that need resolution

set -uo pipefail

# --- Device Detection ---
if [[ -n "${1:-}" ]]; then
    DEVICE_ID="$1"
else
    DEVICE_ID=$(xcrun devicectl list devices 2>/dev/null | grep "connected" | awk '{print $3}')
    if [[ -z "$DEVICE_ID" ]]; then
        echo "❌ No connected device found."
        echo "   Connect an iOS device via USB and ensure it's unlocked."
        exit 1
    fi
fi

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  Device Health Check                                         ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

FAILURES=0

# --- Check 1: Device Connection ---
echo "  1. Device Connection..."
DEVICE_INFO=$(xcrun devicectl list devices 2>/dev/null | grep "$DEVICE_ID")
if [[ -n "$DEVICE_INFO" ]]; then
    DEVICE_NAME=$(echo "$DEVICE_INFO" | awk '{print $1}')
    DEVICE_STATE=$(echo "$DEVICE_INFO" | awk '{print $4}')
    echo "     ✅ $DEVICE_NAME ($DEVICE_ID) — $DEVICE_STATE"
else
    echo "     ❌ Device $DEVICE_ID not found in device list"
    FAILURES=$((FAILURES + 1))
fi

# --- Check 2: DDI Services ---
echo "  2. Developer Disk Image Services..."
DDI_OUTPUT=$(xcrun devicectl device info ddiServices --device "$DEVICE_ID" 2>&1)
if echo "$DDI_OUTPUT" | grep -q "isUsable: true"; then
    XCTEST_VER=$(echo "$DDI_OUTPUT" | grep "XCTest" | awk -F'-' '{print $2}')
    echo "     ✅ DDI usable, XCTest-${XCTEST_VER:-unknown}"
else
    echo "     ❌ DDI not usable. Try: Xcode → Window → Devices and Simulators"
    echo "     $DDI_OUTPUT" | head -5
    FAILURES=$((FAILURES + 1))
fi

# --- Check 3: App Installation ---
echo "  3. App Installation..."
APP_INFO=$(xcrun devicectl device info apps --device "$DEVICE_ID" 2>/dev/null | grep "com.andrewvoirol.EdgeAILab " || true)
if [[ -n "$APP_INFO" ]]; then
    echo "     ✅ EdgeAILab installed on device"
else
    echo "     ⚠️  EdgeAILab not installed. Run: ./automation/deploy_device.sh $DEVICE_ID"
fi

# --- Check 4: UI Test Runner Installation ---
echo "  4. UI Test Runner..."
RUNNER_INFO=$(xcrun devicectl device info apps --device "$DEVICE_ID" 2>/dev/null | grep "xctrunner" || true)
if [[ -n "$RUNNER_INFO" ]]; then
    echo "     ✅ XCTRunner installed on device"
else
    echo "     ⚠️  XCTRunner not installed. Will be installed on first test run."
fi

# --- Check 5: Quick Launch Test ---
echo "  5. Launch Test (dry-run)..."
LAUNCH_OUTPUT=$(xcrun devicectl device process launch --device "$DEVICE_ID" --terminate-existing com.andrewvoirol.EdgeAILab -- -RunAllFlows -DryRun 2>&1)
if echo "$LAUNCH_OUTPUT" | grep -q "Launched application"; then
    echo "     ✅ App launched successfully via devicectl"
else
    echo "     ❌ App launch failed:"
    echo "     $LAUNCH_OUTPUT" | head -5
    FAILURES=$((FAILURES + 1))
fi

# --- Summary ---
echo ""
if [[ $FAILURES -eq 0 ]]; then
    echo "  ✅ Device is ready for testing."
    exit 0
else
    echo "  ❌ $FAILURES check(s) failed. Resolve issues before testing."
    echo "  💡 Try: Reboot device, reconnect USB, or toggle Developer Mode."
    exit 1
fi
