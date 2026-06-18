#!/usr/bin/env bash
# run_full_matrix.sh — Single-command orchestrator for the complete EdgeAILab test pyramid.
#
# Runs the full testing matrix across macOS and iOS, including:
#   1. macOS unit tests (Debug)
#   2. macOS UI tests (Debug)
#   3. macOS automation harness dry-run
#   4. iOS device unit tests (Debug)
#   5. iOS device UI smoke tests (Debug)
#   6. iOS device benchmark pipeline (Release)
#   7. iOS device eval pipeline (Release)
#   8. Cross-platform comparison report
#
# Usage:
#   ./automation/run_full_matrix.sh                          # Full matrix, auto-detect device
#   ./automation/run_full_matrix.sh --device <UDID>          # Target specific device
#   ./automation/run_full_matrix.sh --skip-device            # macOS-only
#   ./automation/run_full_matrix.sh --skip-benchmarks        # Skip Release build steps (6, 7)
#   ./automation/run_full_matrix.sh --skip-device --only-unit  # Just macOS unit tests
#
# Exit codes:
#   0 — All critical steps passed
#   1 — One or more critical steps failed

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUT_DIR="$PROJECT_DIR/metrics"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
RESULTS_FILE="$OUTPUT_DIR/matrix_results_$(date +%Y%m%d_%H%M%S).json"

# Defaults
SKIP_DEVICE=false
SKIP_BENCHMARKS=false
ONLY_UNIT=false
DEVICE_ID=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --skip-device)       SKIP_DEVICE=true; shift ;;
        --skip-benchmarks)   SKIP_BENCHMARKS=true; shift ;;
        --only-unit)         ONLY_UNIT=true; shift ;;
        --device)            DEVICE_ID="$2"; shift 2 ;;
        -h|--help)
            echo "Usage: $0 [--device <UDID>] [--skip-device] [--skip-benchmarks] [--only-unit]"
            exit 0 ;;
        *)
            echo "Unknown argument: $1" >&2
            exit 1 ;;
    esac
done

mkdir -p "$OUTPUT_DIR"

# ──────────────────────────────────────────────────────────
# Device detection (if needed)
# ──────────────────────────────────────────────────────────
if [[ "$SKIP_DEVICE" == "false" && -z "$DEVICE_ID" ]]; then
    DEVICE_ID=$(xcrun devicectl list devices 2>/dev/null | grep "connected" | awk '{print $3}')
    if [[ -z "$DEVICE_ID" ]]; then
        echo "⚠️  No connected device found. Running macOS-only (use --device <UDID> to specify)."
        SKIP_DEVICE=true
    else
        echo "📱 Auto-detected device: $DEVICE_ID"
    fi
fi

# Tracking
declare -A STEP_STATUS
declare -A STEP_DURATION
CRITICAL_FAILURE=false
TOTAL_STEPS=8
if [[ "$ONLY_UNIT" == "true" ]]; then TOTAL_STEPS=1; fi
if [[ "$SKIP_DEVICE" == "true" ]]; then TOTAL_STEPS=3; fi
if [[ "$SKIP_BENCHMARKS" == "true" && "$SKIP_DEVICE" == "false" ]]; then TOTAL_STEPS=5; fi

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  EdgeAILab — Full Test Matrix                                ║"
echo "║  Timestamp: $TIMESTAMP                ║"
echo "║  Steps: $TOTAL_STEPS planned                                           ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

run_step() {
    local step_num="$1"
    local step_name="$2"
    local is_critical="$3"
    shift 3

    echo "──────────────────────────────────────────────────────────────"
    echo "  Step $step_num: $step_name"
    echo "──────────────────────────────────────────────────────────────"

    local start_time=$(date +%s)

    if "$@"; then
        STEP_STATUS[$step_num]="✅ PASSED"
        echo "  ✅ $step_name — PASSED"
    else
        if [[ "$is_critical" == "true" ]]; then
            STEP_STATUS[$step_num]="❌ FAILED (critical)"
            CRITICAL_FAILURE=true
            echo "  ❌ $step_name — FAILED (critical)"
        else
            STEP_STATUS[$step_num]="⚠️  FAILED (informational)"
            echo "  ⚠️  $step_name — FAILED (informational)"
        fi
    fi

    STEP_DURATION[$step_num]=$(( $(date +%s) - start_time ))
    echo "  Duration: ${STEP_DURATION[$step_num]}s"
    echo ""
}

skip_step() {
    local step_num="$1"
    local step_name="$2"
    local reason="$3"
    STEP_STATUS[$step_num]="⏭️  SKIPPED ($reason)"
    STEP_DURATION[$step_num]=0
    echo "  ⏭️  Step $step_num: $step_name — SKIPPED ($reason)"
}

# ──────────────────────────────────────────────────────────
# Step 1: macOS Unit Tests (Debug)
# ──────────────────────────────────────────────────────────
run_step 1 "macOS Unit Tests (Debug, 730+ tests)" true \
    xcodebuild test \
        -workspace "$PROJECT_DIR/EdgeAILab.xcworkspace" \
        -scheme "Edge AI Lab" \
        -destination 'platform=macOS' \
        -only-testing:EdgeAILab_macOSTests \
        -quiet

if [[ "$ONLY_UNIT" == "true" ]]; then
    echo "  --only-unit specified, skipping remaining steps."
    # Jump to summary
else

# ──────────────────────────────────────────────────────────
# Step 2: macOS UI Tests (Debug)
# ──────────────────────────────────────────────────────────
run_step 2 "macOS UI Tests (Debug, 10 flow-driven)" true \
    xcodebuild test \
        -workspace "$PROJECT_DIR/EdgeAILab.xcworkspace" \
        -scheme "Edge AI Lab" \
        -destination 'platform=macOS' \
        -only-testing:EdgeAILab_macOSUITests/EdgeAILabUITests \
        -quiet

# ──────────────────────────────────────────────────────────
# Step 3: macOS Automation Harness Dry-Run
# ──────────────────────────────────────────────────────────
run_step 3 "macOS Automation Harness Dry-Run (4 tests)" true \
    xcodebuild test \
        -workspace "$PROJECT_DIR/EdgeAILab.xcworkspace" \
        -scheme "Edge AI Lab" \
        -destination 'platform=macOS' \
        -only-testing:EdgeAILab_macOSUITests/AutomationHarnessXCTests \
        -quiet

# ──────────────────────────────────────────────────────────
# iOS Steps (4-7)
# ──────────────────────────────────────────────────────────
# NOTE: Steps 4-5 use iOS Simulator because xcodebuild test on physical
# device hits an Xcode 26 beta bug ("continuity display" timeout).
# Steps 6-7 use devicectl via deploy_device.sh, which works on device.

# Step 4: iOS Simulator Unit Tests (Debug)
# Note: InferenceQualityTests are excluded because they find local model files
# but can't load them on Simulator (requires real GPU). They pass on macOS (Step 1).
run_step 4 "iOS Simulator Unit Tests (Debug)" true \
    xcodebuild test \
        -workspace "$PROJECT_DIR/EdgeAILab.xcworkspace" \
        -scheme EdgeAILab_iOS \
        -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
        -only-testing:EdgeAILab_iOSTests \
        -skip-testing:EdgeAILab_iOSTests/InferenceQualityTests \
        -quiet

# Step 5: iOS Simulator UI Smoke Tests (Debug)
run_step 5 "iOS Simulator UI Tests (Debug, 13 tests)" true \
    xcodebuild test \
        -workspace "$PROJECT_DIR/EdgeAILab.xcworkspace" \
        -scheme EdgeAILab_iOS \
        -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
        -only-testing:EdgeAILab_iOSUITests \
        -quiet

if [[ "$SKIP_DEVICE" == "true" || "$SKIP_BENCHMARKS" == "true" ]]; then
    if [[ "$SKIP_DEVICE" == "true" ]]; then
        skip_step 6 "iOS Device Benchmark Pipeline" "no device"
        skip_step 7 "iOS Device Eval Pipeline" "no device"
    else
        skip_step 6 "iOS Device Benchmark Pipeline" "skipped"
        skip_step 7 "iOS Device Eval Pipeline" "skipped"
    fi
else

# Step 6: iOS Device Benchmark Pipeline (Release, via devicectl)
echo "  Building Release for device benchmarks..."
run_step 6 "iOS Device Benchmark Pipeline (Release)" false \
    env BUILD_CONFIG=Release "$SCRIPT_DIR/deploy_device.sh" "$DEVICE_ID" -RunBenchmarkPipeline

# Step 7: iOS Device Eval Pipeline (Release, via devicectl)
run_step 7 "iOS Device Eval Pipeline (Release)" false \
    env BUILD_CONFIG=Release SKIP_BUILD=1 "$SCRIPT_DIR/deploy_device.sh" "$DEVICE_ID" -RunEvalPipeline

fi # skip-benchmarks/device

# ──────────────────────────────────────────────────────────
# Step 8: Cross-Platform Comparison Report
# ──────────────────────────────────────────────────────────
if [[ -x "$SCRIPT_DIR/eval_comparison.sh" ]]; then
    run_step 8 "Cross-Platform Comparison Report" false \
        "$SCRIPT_DIR/eval_comparison.sh"
else
    skip_step 8 "Cross-Platform Comparison Report" "script not found"
fi

fi # only-unit

# ──────────────────────────────────────────────────────────
# Summary
# ──────────────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  Test Matrix Results                                         ║"
echo "╠══════════════════════════════════════════════════════════════╣"

for step_num in $(seq 1 8); do
    status="${STEP_STATUS[$step_num]:-⏭️  SKIPPED}"
    duration="${STEP_DURATION[$step_num]:-0}"
    case $step_num in
        1) name="macOS Unit Tests" ;;
        2) name="macOS UI Tests" ;;
        3) name="macOS Automation Harness" ;;
        4) name="iOS Simulator Unit Tests" ;;
        5) name="iOS Simulator UI Tests" ;;
        6) name="iOS Benchmark Pipeline" ;;
        7) name="iOS Eval Pipeline" ;;
        8) name="Cross-Platform Report" ;;
    esac
    printf "║  %d. %-26s %s (%ds)\n" "$step_num" "$name" "$status" "$duration"
done

echo "╠══════════════════════════════════════════════════════════════╣"
if [[ "$CRITICAL_FAILURE" == "true" ]]; then
    echo "║  Result: ❌ CRITICAL FAILURES DETECTED                       ║"
else
    echo "║  Result: ✅ ALL CRITICAL STEPS PASSED                        ║"
fi
echo "╚══════════════════════════════════════════════════════════════╝"

# Write JSON results
cat > "$RESULTS_FILE" <<EOF
{
  "timestamp": "$TIMESTAMP",
  "steps": {
$(for step_num in $(seq 1 8); do
    status="${STEP_STATUS[$step_num]:-skipped}"
    duration="${STEP_DURATION[$step_num]:-0}"
    printf '    "%d": {"status": "%s", "duration_s": %d}' "$step_num" "$status" "$duration"
    [[ $step_num -lt 8 ]] && echo ","
done)
  },
  "critical_failure": $CRITICAL_FAILURE
}
EOF

echo ""
echo "📄 Results written to: $RESULTS_FILE"

if [[ "$CRITICAL_FAILURE" == "true" ]]; then
    exit 1
else
    exit 0
fi
