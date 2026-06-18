#!/bin/bash
# monitor_device.sh — Launch Edge AI Lab on a device and capture automation output.
#
# Uses os_log (via log stream) instead of --console to avoid iOS Jetsam kills.
# The app logs automation output to both stdout (macOS) and os_log (iOS).
#
# Adapted from the IO 2026 Concierge monitor_inference.sh pattern.
#
# Usage:
#   ./automation/monitor_device.sh <DEVICE_ID>
#   ./automation/monitor_device.sh <DEVICE_ID> -RunBenchmarkPipeline
#   ./automation/monitor_device.sh <DEVICE_ID> -RunEvalPipeline
#   ./automation/monitor_device.sh <DEVICE_ID> -RunValidation
#
set -e

BUNDLE_ID="com.andrewvoirol.EdgeAILab"
LOG_SUBSYSTEM="com.andrewvoirol.EdgeAILab"
LOG_CATEGORY="automation"

if [ -z "$1" ]; then
    echo "Usage: $0 <DEVICE_ID> [launch args...]"
    echo ""
    echo "Example:"
    echo "  $0 3B50314A-0702-5188-A321-BCD5CA5F8184"
    echo "  $0 3B50314A-0702-5188-A321-BCD5CA5F8184 -RunBenchmarkPipeline"
    echo "  $0 3B50314A-0702-5188-A321-BCD5CA5F8184 -RunEvalPipeline"
    echo "  $0 3B50314A-0702-5188-A321-BCD5CA5F8184 -RunValidation"
    exit 1
fi

DEVICE_ID="$1"
shift
LAUNCH_ARGS="$@"

echo "═══════════════════════════════════════════════"
echo "  Monitoring Edge AI Lab on device $DEVICE_ID"
echo "═══════════════════════════════════════════════"
echo "Capture method: os_log (subsystem: $LOG_SUBSYSTEM, category: $LOG_CATEGORY)"
echo "Filtering for: AUTOMATION | BENCHMARK | VALIDATION | EVAL"
echo "Press Ctrl+C to stop."
echo "─────────────────────────────────────────────────"
echo ""

# Launch the app WITHOUT --console (avoids Jetsam memory pressure)
echo "[monitor] Launching app..."
xcrun devicectl device process launch \
    --device "$DEVICE_ID" \
    --terminate-existing \
    "$BUNDLE_ID" \
    -- $LAUNCH_ARGS 2>&1

echo "[monitor] App launched. Streaming os_log output..."
echo ""

# Stream device logs filtered to our subsystem+category
# This captures automationLog() output without --console overhead
if command -v idevicesyslog &> /dev/null; then
    # Preferred: libimobiledevice (lighter weight, works in CI)
    idevicesyslog -u "$DEVICE_ID" -m "EdgeAILab" 2>&1 | \
        grep -E "AUTOMATION|BENCHMARK|VALIDATION|EVAL"
else
    # Fallback: Xcode's log stream via devicectl
    # Note: This requires the device to be paired and trusted
    xcrun devicectl device info dumpstate --device "$DEVICE_ID" 2>&1 | \
        grep -E "AUTOMATION|BENCHMARK|VALIDATION|EVAL"
fi
