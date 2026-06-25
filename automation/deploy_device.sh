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
    echo "App launched. Monitor via: idevicesyslog -u $DEVICE_ID -m EdgeAILab | grep AUTOMATION"
else
    echo "Launching with --console log streaming..."
    # Default timeout: 10 minutes (600s). Override with CONSOLE_TIMEOUT env var.
    CONSOLE_TIMEOUT="${CONSOLE_TIMEOUT:-600}"
    OUTPUT_DIR="$DIR/metrics"
    mkdir -p "$OUTPUT_DIR"
    LOG_OUTPUT="$OUTPUT_DIR/device_console_$(date +%Y%m%d_%H%M%S).log"

    echo "Log output: $LOG_OUTPUT"
    echo "Timeout: ${CONSOLE_TIMEOUT}s"

    # Helper: pull results from device after successful completion
    pull_device_results() {
        echo ""
        echo "Pulling results from device..."
        local PULL_DIR="$OUTPUT_DIR/device_pull_$(date +%Y%m%d_%H%M%S)"
        mkdir -p "$PULL_DIR"

        # Pull benchmark results
        xcrun devicectl device copy from \
            --device "$DEVICE_ID" \
            --source Documents/metrics/ \
            --domain-type appDataContainer \
            --domain-identifier "$BUNDLE_ID" \
            --destination "$PULL_DIR/" 2>/dev/null && \
            echo "   📄 Pulled metrics/ from device" || \
            echo "   ⚠️  No metrics/ found on device (may not apply to this run)"

        # Pull eval results
        xcrun devicectl device copy from \
            --device "$DEVICE_ID" \
            --source Documents/eval_results/ \
            --domain-type appDataContainer \
            --domain-identifier "$BUNDLE_ID" \
            --destination "$PULL_DIR/" 2>/dev/null && \
            echo "   📄 Pulled eval_results/ from device" || \
            echo "   ⚠️  No eval_results/ found on device (may not apply to this run)"

        echo ""
        echo "Results directory: $PULL_DIR"
    }
    echo ""

    # Use `devicectl --console` which connects the app's stdout/stderr to this terminal.
    # The app's automationLog() calls print() → stdout, so all [AUTOMATION] output is captured.
    #
    # --console waits for the app to terminate. signalComplete() calls exit() when NOT
    # under XCUITest, so --console should return naturally. We still run in the background
    # with a timeout as a safety net in case exit() hangs (e.g., LiteRT thread cleanup).
    #
    # We wrap in a subshell so $! captures the group leader. Killing -$PID kills
    # both devicectl and tee (a bare pipeline's $! is only the last element).
    if [ -n "$LAUNCH_ARGS" ]; then
        ( xcrun devicectl device process launch \
            --device "$DEVICE_ID" \
            --terminate-existing \
            --console \
            "$BUNDLE_ID" \
            -- $LAUNCH_ARGS 2>&1 | stdbuf -oL tee "$LOG_OUTPUT" ) &
    else
        ( xcrun devicectl device process launch \
            --device "$DEVICE_ID" \
            --terminate-existing \
            --console \
            "$BUNDLE_ID" 2>&1 | stdbuf -oL tee "$LOG_OUTPUT" ) &
    fi
    CONSOLE_PID=$!

    echo "Watching for [AUTOMATION] completion signal..."

    # Watch the log file for the completion signal
    ELAPSED=0
    while [ "$ELAPSED" -lt "$CONSOLE_TIMEOUT" ]; do
        sleep 2
        ELAPSED=$((ELAPSED + 2))

        # Check if --console exited on its own (app crashed or terminated)
        if ! kill -0 "$CONSOLE_PID" 2>/dev/null; then
            echo ""
            echo "⚠️  App process exited after ${ELAPSED}s."
            wait "$CONSOLE_PID" 2>/dev/null
            CONSOLE_EXIT=$?
            if [ -f "$LOG_OUTPUT" ] && grep -q "Signaling completion" "$LOG_OUTPUT" 2>/dev/null; then
                echo "✅ Completion signal found in log output."
                pull_device_results
                exit 0
            else
                echo "❌ No completion signal found. Console exit code: $CONSOLE_EXIT"
                exit 1
            fi
        fi

        # Check for completion signal while --console is still running
        if [ -f "$LOG_OUTPUT" ] && grep -q "Signaling completion" "$LOG_OUTPUT" 2>/dev/null; then
            echo ""
            echo "✅ Automation completion detected after ${ELAPSED}s."

            # Extract the exit code from the completion signal line
            COMPLETION_LINE=$(grep "Signaling completion" "$LOG_OUTPUT" | tail -1)
            echo "   $COMPLETION_LINE"

            # Kill the entire --console pipeline (subshell + devicectl + tee).
            # Using negative PID kills the process group. The app continues running
            # on device (harmless — it already completed) until iOS reclaims it.
            kill -- -"$CONSOLE_PID" 2>/dev/null || kill "$CONSOLE_PID" 2>/dev/null || true
            wait "$CONSOLE_PID" 2>/dev/null || true

            pull_device_results
            exit 0
        fi
    done

    echo ""
    echo "⚠️  Timeout (${CONSOLE_TIMEOUT}s) reached without completion signal."
    # Kill the entire --console pipeline and clean up
    kill -- -"$CONSOLE_PID" 2>/dev/null || kill "$CONSOLE_PID" 2>/dev/null || true
    wait "$CONSOLE_PID" 2>/dev/null || true
    exit 1
fi
