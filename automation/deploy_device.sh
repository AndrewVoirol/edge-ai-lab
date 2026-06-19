#!/bin/bash
# deploy_device.sh — Build, install, and launch Edge AI Lab on a physical iOS device.
#
# Adapted from the IO 2026 Concierge deploy_ios.sh pattern.
#
# Usage:
#   ./automation/deploy_device.sh                           # Auto-detect first device
#   ./automation/deploy_device.sh <DEVICE_ID>               # Target a specific device
#   ./automation/deploy_device.sh <DEVICE_ID> -RunBenchmarkPipeline  # Pass launch args
#
# Environment variables:
#   NO_CONSOLE=1    Skip --console mode (avoids Jetsam on iOS with large models)
#   SKIP_BUILD=1    Skip the build step (use existing installed app)
#   BUILD_CONFIG=Release  Build with Release configuration (recommended for benchmarks)
#
set -e

BUNDLE_ID="com.andrewvoirol.EdgeAILab"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_CONFIG="${BUILD_CONFIG:-Debug}"

# --- Device ID ---
if [ -n "$1" ] && [[ "$1" != -* ]]; then
    DEVICE_ID="$1"
    shift
else
    echo "Auto-detecting connected device..."
    DEVICE_ID=$(xcrun devicectl list devices 2>/dev/null | grep "connected" | awk '{print $3}')
    if [ -z "$DEVICE_ID" ]; then
        echo "ERROR: No connected device found. Pass a DEVICE_ID argument or connect a device."
        exit 1
    fi
    echo "Detected device: $DEVICE_ID"
fi

LAUNCH_ARGS="$@"

# --- Build ---
if [ "${SKIP_BUILD}" != "1" ]; then
    echo ""
    echo "═══════════════════════════════════════════════"
    echo "  Building EdgeAILab_iOS for device $DEVICE_ID"
    echo "  Configuration: $BUILD_CONFIG"
    echo "═══════════════════════════════════════════════"
    cd "$DIR"
    xcodebuild build \
        -workspace EdgeAILab.xcworkspace \
        -scheme EdgeAILab_iOS \
        -destination "id=$DEVICE_ID" \
        -configuration "$BUILD_CONFIG" \
        -allowProvisioningUpdates \
        SYMROOT="$DIR/build" \
        -quiet

    APP_PATH=$(find "$DIR/build" -name "EdgeAILab_iOS.app" -path "*/${BUILD_CONFIG}-iphoneos/*" | head -1)
    if [ -z "$APP_PATH" ]; then
        echo "ERROR: Could not find built .app. Check build output."
        exit 1
    fi

    # --- Install ---
    echo ""
    echo "Installing to device $DEVICE_ID..."
    xcrun devicectl device install app --device "$DEVICE_ID" "$APP_PATH"
fi

# --- Launch ---
echo ""
if [ -n "$LAUNCH_ARGS" ]; then
    echo "Launch arguments: $LAUNCH_ARGS"
fi

if [ "${NO_CONSOLE}" = "1" ]; then
    echo "Launching WITHOUT console (NO_CONSOLE=1)..."
    echo "Results will be persisted to Documents/metrics/ on device."
    echo "Pull results with: xcrun devicectl device info files --device $DEVICE_ID --domain-identifier $BUNDLE_ID"
    if [ -n "$LAUNCH_ARGS" ]; then
        xcrun devicectl device process launch \
            --device "$DEVICE_ID" \
            --terminate-existing \
            "$BUNDLE_ID" \
            -- $LAUNCH_ARGS
    else
        xcrun devicectl device process launch \
            --device "$DEVICE_ID" \
            --terminate-existing \
            "$BUNDLE_ID"
    fi
    echo ""
    echo "App launched. Monitor via: log stream --device $DEVICE_ID --predicate 'subsystem == \"com.andrewvoirol.EdgeAILab\"' --level info"
else
    echo "Launching with log streaming..."
    # Default timeout: 10 minutes (600s). Override with CONSOLE_TIMEOUT env var.
    CONSOLE_TIMEOUT="${CONSOLE_TIMEOUT:-600}"
    LOG_OUTPUT="$OUTPUT_DIR/device_console_$(date +%Y%m%d_%H%M%S).log"

    # Launch app without --console (which hangs indefinitely)
    if [ -n "$LAUNCH_ARGS" ]; then
        xcrun devicectl device process launch \
            --device "$DEVICE_ID" \
            --terminate-existing \
            "$BUNDLE_ID" \
            -- $LAUNCH_ARGS
    else
        xcrun devicectl device process launch \
            --device "$DEVICE_ID" \
            --terminate-existing \
            "$BUNDLE_ID"
    fi

    echo "Streaming device logs to $LOG_OUTPUT (timeout: ${CONSOLE_TIMEOUT}s)..."
    echo "Watching for [AUTOMATION] completion signal..."

    # Stream logs in the background, teeing to file and stdout.
    # Use `log stream` with a predicate for our subsystem.
    log stream --device "$DEVICE_ID" \
        --predicate 'subsystem == "com.andrewvoirol.EdgeAILab"' \
        --level info 2>&1 | tee "$LOG_OUTPUT" &
    LOG_PID=$!

    # Watch the log file for the completion signal
    ELAPSED=0
    while [ "$ELAPSED" -lt "$CONSOLE_TIMEOUT" ]; do
        sleep 2
        ELAPSED=$((ELAPSED + 2))
        if [ -f "$LOG_OUTPUT" ] && grep -q "Signaling completion" "$LOG_OUTPUT" 2>/dev/null; then
            echo ""
            echo "✅ Automation completion detected after ${ELAPSED}s."
            kill "$LOG_PID" 2>/dev/null || true
            wait "$LOG_PID" 2>/dev/null || true
            exit 0
        fi
    done

    echo ""
    echo "⚠️  Timeout (${CONSOLE_TIMEOUT}s) reached without completion signal."
    kill "$LOG_PID" 2>/dev/null || true
    wait "$LOG_PID" 2>/dev/null || true
    exit 1
fi
