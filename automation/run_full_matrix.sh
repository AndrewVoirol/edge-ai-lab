#!/usr/bin/env bash
# run_full_matrix.sh — Single-command orchestrator for the complete EdgeAILab test pyramid.
#
# Runs the canonical 14-tier testing matrix (see TESTING.md):
#   Tier 0:  0a Device Health Check, 0b Flow JSON Validation
#   Tier 1:  1a macOS Unit Tests, 1b iOS Simulator Unit Tests
#   Tier 2:  2a macOS UI Tests, 2b macOS Automation Harness,
#            2c iOS Simulator UI Tests, 2d iOS Device UI Tests
#   Tier 3:  3a macOS Integration Tests, 3b macOS Performance Tests
#   Tier 4:  4a iOS Device Benchmark Pipeline, 4b iOS Device Eval Pipeline
#   Tier 5:  5a Benchmark Regression Check, 5b Cross-Platform Eval Report
#
# Usage:
#   ./automation/run_full_matrix.sh                          # Full matrix, auto-detect device
#   ./automation/run_full_matrix.sh --device <UDID>          # Target specific device
#   ./automation/run_full_matrix.sh --skip-device            # macOS + Simulator only
#   ./automation/run_full_matrix.sh --skip-benchmarks        # Skip Tier 4 (Release pipelines)
#   ./automation/run_full_matrix.sh --skip-integration       # Skip Tier 3 (model-dependent)
#   ./automation/run_full_matrix.sh --skip-device --only-unit  # Just unit tests (Tier 0 + 1)
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
SKIP_INTEGRATION=false
ONLY_UNIT=false
DEVICE_ID=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --skip-device)       SKIP_DEVICE=true; shift ;;
        --skip-benchmarks)   SKIP_BENCHMARKS=true; shift ;;
        --skip-integration)  SKIP_INTEGRATION=true; shift ;;
        --only-unit)         ONLY_UNIT=true; shift ;;
        --device)            DEVICE_ID="$2"; shift 2 ;;
        -h|--help)
            echo "Usage: $0 [--device <UDID>] [--skip-device] [--skip-benchmarks] [--skip-integration] [--only-unit]"
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
    # Match available/connected iPhones, excluding Watch/iPad/unavailable
    DEVICE_ID=$(xcrun devicectl list devices 2>/dev/null | grep -E "available|connected" | grep -v "Watch\|iPad\|unavailable" | awk '{print $3}' | head -1)
    if [[ -z "$DEVICE_ID" ]]; then
        echo "⚠️  No connected device found. Running macOS-only (use --device <UDID> to specify)."
        SKIP_DEVICE=true
    else
        echo "📱 Auto-detected device: $DEVICE_ID"
    fi
fi

# ──────────────────────────────────────────────────────────
# Step numbering (sequential 1-14, mapped to tiers in labels)
# ──────────────────────────────────────────────────────────
# Step  1 = Tier 0a: Device Health Check
# Step  2 = Tier 0b: Flow JSON Validation
# Step  3 = Tier 1a: macOS Unit Tests
# Step  4 = Tier 1b: iOS Simulator Unit Tests
# Step  5 = Tier 2a: macOS UI Tests
# Step  6 = Tier 2b: macOS Automation Harness
# Step  7 = Tier 2c: iOS Simulator UI Tests
# Step  8 = Tier 2d: iOS Device UI Tests
# Step  9 = Tier 3a: macOS Integration Tests
# Step 10 = Tier 3b: macOS Performance Tests
# Step 11 = Tier 4a: iOS Device Benchmark Pipeline
# Step 12 = Tier 4b: iOS Device Eval Pipeline
# Step 13 = Tier 5a: Benchmark Regression Check
# Step 14 = Tier 5b: Cross-Platform Eval Report

MAX_STEPS=14

# Calculate planned steps based on flags
TOTAL_STEPS=$MAX_STEPS
if [[ "$ONLY_UNIT" == "true" ]]; then
    # Tiers 0 + 1 only (steps 1-4)
    TOTAL_STEPS=4
elif [[ "$SKIP_DEVICE" == "true" && "$SKIP_INTEGRATION" == "true" ]]; then
    # Steps 1-7, 9-10 skipped for device, 9-10 skipped for integration → steps 1-7
    TOTAL_STEPS=7
elif [[ "$SKIP_DEVICE" == "true" ]]; then
    # No device steps (8, 11, 12 skipped), no 5a/5b without tier 4 → steps 1-7, 9-10
    TOTAL_STEPS=9
elif [[ "$SKIP_BENCHMARKS" == "true" && "$SKIP_INTEGRATION" == "true" ]]; then
    # Steps 1-8, skip 9-14
    TOTAL_STEPS=8
elif [[ "$SKIP_BENCHMARKS" == "true" ]]; then
    # Steps 1-10, skip 11-14
    TOTAL_STEPS=10
elif [[ "$SKIP_INTEGRATION" == "true" ]]; then
    # Steps 1-8, 11-14
    TOTAL_STEPS=12
fi

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  EdgeAILab — Full Test Matrix (14-tier)                      ║"
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

# Tracking
STEP_STATUS=()
STEP_DURATION=()
CRITICAL_FAILURE=false

# ──────────────────────────────────────────────────────────
# Tier 0 — Pre-flight Gates (always run, informational)
# ──────────────────────────────────────────────────────────

# Step 1 = Tier 0a: Device Health Check
if [[ "$SKIP_DEVICE" == "true" ]]; then
    skip_step 1 "Device Health Check (0a)" "no device"
else
    run_step 1 "Device Health Check (0a)" false \
        "$SCRIPT_DIR/device_health_check.sh" "$DEVICE_ID"
fi

# Step 2 = Tier 0b: Flow JSON Validation
run_step 2 "Flow JSON Validation (0b)" false \
    "$SCRIPT_DIR/validate_flows.sh"

# ──────────────────────────────────────────────────────────
# Tier 1 — Unit Tests (no model needed)
# ──────────────────────────────────────────────────────────

# Step 3 = Tier 1a: macOS Unit Tests (Debug)
run_step 3 "macOS Unit Tests (1a, 730+ tests)" true \
    xcodebuild test \
        -workspace "$PROJECT_DIR/EdgeAILab.xcworkspace" \
        -scheme "Edge AI Lab" \
        -destination 'platform=macOS' \
        -only-testing:EdgeAILab_macOSTests \
        -quiet

# Step 4 = Tier 1b: iOS Simulator Unit Tests (Debug)
if [[ "$ONLY_UNIT" == "true" ]]; then
    run_step 4 "iOS Sim Unit Tests (1b)" true \
        xcodebuild test \
            -workspace "$PROJECT_DIR/EdgeAILab.xcworkspace" \
            -scheme EdgeAILab_iOS \
            -testPlan SimulatorTests \
            -destination 'platform=iOS Simulator,name=iPhone 16 Pro Max' \
            -only-testing:EdgeAILab_iOSTests \
            -quiet

    echo "  --only-unit specified, skipping remaining steps."
    # Jump to summary
else

run_step 4 "iOS Sim Unit Tests (1b)" true \
    xcodebuild test \
        -workspace "$PROJECT_DIR/EdgeAILab.xcworkspace" \
        -scheme EdgeAILab_iOS \
        -testPlan SimulatorTests \
        -destination 'platform=iOS Simulator,name=iPhone 16 Pro Max' \
        -only-testing:EdgeAILab_iOSTests \
        -quiet

# ──────────────────────────────────────────────────────────
# Tier 2 — UI Tests (no model needed)
# NOTE: Never run concurrent UI test processes — they share
# the screen, keyboard, and accessibility session.
# ──────────────────────────────────────────────────────────

# Step 5 = Tier 2a: macOS UI Tests (Debug)
run_step 5 "macOS UI Tests (2a, 10 flow-driven)" true \
    xcodebuild test \
        -workspace "$PROJECT_DIR/EdgeAILab.xcworkspace" \
        -scheme "Edge AI Lab" \
        -testPlan macOSUITests \
        -destination 'platform=macOS' \
        -only-testing:EdgeAILab_macOSUITests/EdgeAILabUITests \
        -quiet

# Step 6 = Tier 2b: macOS Automation Harness Dry-Run
run_step 6 "macOS Automation Harness (2b, 4 tests)" true \
    xcodebuild test \
        -workspace "$PROJECT_DIR/EdgeAILab.xcworkspace" \
        -scheme "Edge AI Lab" \
        -testPlan macOSUITests \
        -destination 'platform=macOS' \
        -only-testing:EdgeAILab_macOSUITests/AutomationHarnessXCTests \
        -quiet

# Step 7 = Tier 2c: iOS Simulator UI Tests (Debug)
run_step 7 "iOS Sim UI Tests (2c, 13 tests)" true \
    xcodebuild test \
        -workspace "$PROJECT_DIR/EdgeAILab.xcworkspace" \
        -scheme EdgeAILab_iOS \
        -testPlan iOSUITests \
        -destination 'platform=iOS Simulator,name=iPhone 16 Pro Max' \
        -only-testing:EdgeAILab_iOSUITests \
        -quiet

# Cooldown: Shut down the simulator and give testmanagerd time to tear down
# its session before starting device tests. Without this, the device's
# "enabling automation mode" request can time out (60s) due to session
# contention with the simulator's testmanagerd session.
# Evidence: Step 8 passes 26/26 when run in isolation after this cooldown.
if [[ "$SKIP_DEVICE" != "true" ]]; then
    echo "  ⏳ Shutting down simulator and waiting for testmanagerd cooldown..."
    xcrun simctl shutdown all 2>/dev/null || true
    sleep 15
fi

# Step 8 = Tier 2d: iOS Device UI Tests (Debug)
if [[ "$SKIP_DEVICE" == "true" ]]; then
    skip_step 8 "iOS Device UI Tests (2d)" "no device"
else
    run_step 8 "iOS Device UI Tests (2d)" true \
        xcodebuild test \
            -workspace "$PROJECT_DIR/EdgeAILab.xcworkspace" \
            -scheme EdgeAILab_iOS \
            -testPlan iOSUITests \
            -destination "platform=iOS,id=$DEVICE_ID" \
            -only-testing:EdgeAILab_iOSUITests \
            -quiet
fi

# ──────────────────────────────────────────────────────────
# Tier 3 — Model-Dependent Tests (real GPU required)
# Requires .litertlm model files in models/ directory.
# Skip with --skip-integration if models aren't staged.
# ──────────────────────────────────────────────────────────

# Step 9 = Tier 3a: macOS Integration Tests
if [[ "$SKIP_INTEGRATION" == "true" ]]; then
    skip_step 9 "macOS Integration Tests (3a)" "skip-integration"
else
    run_step 9 "macOS Integration Tests (3a)" true \
        xcodebuild test \
            -workspace "$PROJECT_DIR/EdgeAILab.xcworkspace" \
            -scheme "Edge AI Lab" \
            -testPlan macOSIntegrationTests \
            -destination 'platform=macOS' \
            -quiet
fi

# Step 10 = Tier 3b: macOS Performance Tests
if [[ "$SKIP_INTEGRATION" == "true" ]]; then
    skip_step 10 "macOS Performance Tests (3b)" "skip-integration"
else
    run_step 10 "macOS Performance Tests (3b)" false \
        xcodebuild test \
            -workspace "$PROJECT_DIR/EdgeAILab.xcworkspace" \
            -scheme "Edge AI Lab" \
            -testPlan macOSPerformanceTests \
            -destination 'platform=macOS' \
            -quiet
fi

# ──────────────────────────────────────────────────────────
# Tier 4 — Device Pipelines (Release build, physical device)
# ──────────────────────────────────────────────────────────

if [[ "$SKIP_DEVICE" == "true" || "$SKIP_BENCHMARKS" == "true" ]]; then
    if [[ "$SKIP_DEVICE" == "true" ]]; then
        skip_step 11 "iOS Device Benchmark Pipeline (4a)" "no device"
        skip_step 12 "iOS Device Eval Pipeline (4b)" "no device"
    else
        skip_step 11 "iOS Device Benchmark Pipeline (4a)" "skip-benchmarks"
        skip_step 12 "iOS Device Eval Pipeline (4b)" "skip-benchmarks"
    fi
else

# Step 11 = Tier 4a: iOS Device Benchmark Pipeline (Release, via devicectl)
echo "  Building Release for device benchmarks..."
run_step 11 "iOS Device Benchmark Pipeline (4a, Release)" false \
    env BUILD_CONFIG=Release CONSOLE_TIMEOUT=5400 "$SCRIPT_DIR/deploy_device.sh" "$DEVICE_ID" -RunBenchmarkPipeline

# Step 12 = Tier 4b: iOS Device Eval Pipeline (Release, via devicectl)
run_step 12 "iOS Device Eval Pipeline (4b, Release)" false \
    env BUILD_CONFIG=Release SKIP_BUILD=1 "$SCRIPT_DIR/deploy_device.sh" "$DEVICE_ID" -RunEvalPipeline

fi # skip-benchmarks/device

# ──────────────────────────────────────────────────────────
# Tier 5 — Reporting (post-execution analysis)
# ──────────────────────────────────────────────────────────

# Step 13 = Tier 5a: Benchmark Regression Check
if [[ "$SKIP_BENCHMARKS" == "true" || "$SKIP_DEVICE" == "true" ]]; then
    skip_step 13 "Benchmark Regression Check (5a)" "no benchmark data"
elif [[ -x "$SCRIPT_DIR/benchmark_compare.sh" ]]; then
    LATEST_RESULTS=$(ls -t "$OUTPUT_DIR"/device_pull_*/benchmark-results.jsonl 2>/dev/null | head -1)
    if [[ -n "$LATEST_RESULTS" ]]; then
        run_step 13 "Benchmark Regression Check (5a)" false \
            "$SCRIPT_DIR/benchmark_compare.sh" \
                --results "$LATEST_RESULTS" \
                --baselines "$OUTPUT_DIR/baselines.json"
    else
        skip_step 13 "Benchmark Regression Check (5a)" "no benchmark results found in device_pull"
    fi
else
    skip_step 13 "Benchmark Regression Check (5a)" "script not found"
fi

# Step 14 = Tier 5b: Cross-Platform Eval Report
if [[ -x "$SCRIPT_DIR/eval_comparison.sh" ]]; then
    run_step 14 "Cross-Platform Eval Report (5b)" false \
        "$SCRIPT_DIR/eval_comparison.sh"
else
    skip_step 14 "Cross-Platform Eval Report (5b)" "script not found"
fi

fi # only-unit

# ──────────────────────────────────────────────────────────
# Summary
# ──────────────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  Test Matrix Results                                         ║"
echo "╠══════════════════════════════════════════════════════════════╣"

STEP_NAMES=(
    [1]="Device Health Check (0a)"
    [2]="Flow JSON Validation (0b)"
    [3]="macOS Unit Tests (1a)"
    [4]="iOS Sim Unit Tests (1b)"
    [5]="macOS UI Tests (2a)"
    [6]="macOS Automation Harness (2b)"
    [7]="iOS Sim UI Tests (2c)"
    [8]="iOS Device UI Tests (2d)"
    [9]="macOS Integration (3a)"
    [10]="macOS Performance (3b)"
    [11]="Device Benchmark (4a)"
    [12]="Device Eval (4b)"
    [13]="Benchmark Regression (5a)"
    [14]="Cross-Platform Report (5b)"
)

for step_num in $(seq 1 $MAX_STEPS); do
    status="${STEP_STATUS[$step_num]:-⏭️  SKIPPED}"
    duration="${STEP_DURATION[$step_num]:-0}"
    name="${STEP_NAMES[$step_num]}"
    printf "║  %2d. %-30s %s (%ds)\n" "$step_num" "$name" "$status" "$duration"
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
$(for step_num in $(seq 1 $MAX_STEPS); do
    status="${STEP_STATUS[$step_num]:-skipped}"
    duration="${STEP_DURATION[$step_num]:-0}"
    name="${STEP_NAMES[$step_num]}"
    printf '    "%d": {"name": "%s", "status": "%s", "duration_s": %d}' "$step_num" "$name" "$status" "$duration"
    [[ $step_num -lt $MAX_STEPS ]] && echo ","
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
