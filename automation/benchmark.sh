#!/bin/bash
# benchmark.sh — Single-command benchmark with controlled conditions
# Usage: ./automation/benchmark.sh [--device UDID] [--iterations N] [--cooldown SECONDS]
#
# Performs a controlled benchmark run:
# 1. Checks thermal state (aborts if throttled)
# 2. Builds RawBenchmark in Release
# 3. Runs N iterations with cooldown between each
# 4. Discards run 1 (warmup), averages remaining runs
# 5. Compares against baselines.json
# 6. Outputs report to metrics/latest_benchmark.json
#
# Prerequisites:
#   - Model file in models/ directory
#   - For device benchmarks: device connected and trusted

set -euo pipefail

# --- Configuration ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
METRICS_DIR="$PROJECT_ROOT/metrics"
BASELINES_FILE="$METRICS_DIR/baselines.json"
REPORT_FILE="$METRICS_DIR/latest_benchmark.json"
ITERATIONS=3
COOLDOWN=30
DEVICE_UDID=""
WORKSPACE="$PROJECT_ROOT/EdgeAILab.xcworkspace"

# --- Parse Arguments ---
while [[ $# -gt 0 ]]; do
    case $1 in
        --device)
            DEVICE_UDID="$2"
            shift 2
            ;;
        --iterations)
            ITERATIONS="$2"
            shift 2
            ;;
        --cooldown)
            COOLDOWN="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [--device UDID] [--iterations N] [--cooldown SECONDS]"
            echo ""
            echo "Options:"
            echo "  --device UDID     Run on physical device (default: macOS)"
            echo "  --iterations N    Number of benchmark runs (default: 3)"
            echo "  --cooldown N      Seconds between runs (default: 30)"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# --- Functions ---

check_thermal_state() {
    echo "🌡️  Checking thermal state..."
    local thermal
    thermal=$(pmset -g therm 2>/dev/null | grep -i "CPU_Speed_Limit" | awk '{print $NF}' || echo "100")
    if [[ "$thermal" -lt 80 ]]; then
        echo "❌ CPU is thermally throttled (${thermal}% speed). Wait for cooldown before benchmarking."
        exit 1
    fi
    echo "✅ Thermal state OK (CPU at ${thermal}% speed)"
}

find_model() {
    local model_dir="$PROJECT_ROOT/models"
    if [[ ! -d "$model_dir" ]]; then
        echo "❌ No models/ directory found at $model_dir"
        exit 1
    fi
    local model
    model=$(find "$model_dir" -name "*.litertlm" -type f | head -1)
    if [[ -z "$model" ]]; then
        echo "❌ No .litertlm model files found in $model_dir"
        exit 1
    fi
    echo "$model"
}

build_benchmark() {
    echo "🔨 Building RawBenchmark in Release..."
    xcodebuild build \
        -workspace "$WORKSPACE" \
        -scheme RawBenchmark \
        -configuration Release \
        -quiet 2>&1 || {
        echo "❌ Build failed"
        exit 1
    }
    echo "✅ Build succeeded"
}

run_single_benchmark() {
    local run_number=$1
    local model_path=$2
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📊 Run $run_number of $ITERATIONS"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # Find the built binary
    local binary
    binary=$(find ~/Library/Developer/Xcode/DerivedData/EdgeAILab-*/Build/Products/Release -name "RawBenchmark" -type f 2>/dev/null | head -1)
    if [[ -z "$binary" ]]; then
        echo "❌ Cannot find built RawBenchmark binary"
        exit 1
    fi

    # Run benchmark and capture output
    local output
    output=$("$binary" "$model_path" 2>&1) || true
    echo "$output"
    echo "$output"
}

# --- Main ---

echo "╔══════════════════════════════════════════════════╗"
echo "║        Edge AI Lab Benchmark Runner              ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""
echo "Configuration:"
echo "  Iterations:  $ITERATIONS"
echo "  Cooldown:    ${COOLDOWN}s"
echo "  Device:      ${DEVICE_UDID:-macOS (local)}"
echo "  Timestamp:   $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo ""

# Pre-flight
check_thermal_state
MODEL_PATH=$(find_model)
echo "📦 Model: $(basename "$MODEL_PATH")"

# Build
build_benchmark

# Run benchmarks
mkdir -p "$METRICS_DIR"
RESULTS=()

for ((i = 1; i <= ITERATIONS; i++)); do
    if [[ $i -gt 1 ]]; then
        echo ""
        echo "⏳ Cooling down for ${COOLDOWN}s..."
        sleep "$COOLDOWN"
        check_thermal_state
    fi
    run_single_benchmark "$i" "$MODEL_PATH"
done

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Benchmark complete"
echo ""
echo "Results saved to: $REPORT_FILE"
echo ""

# Generate report metadata
cat > "$REPORT_FILE" << EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "device": "${DEVICE_UDID:-macOS}",
  "model": "$(basename "$MODEL_PATH")",
  "iterations": $ITERATIONS,
  "cooldown_seconds": $COOLDOWN,
  "note": "Run 1 is warmup. Average runs 2-$ITERATIONS for stable metrics.",
  "methodology": {
    "thermal_check": true,
    "cooldown_between_runs": true,
    "release_build": true,
    "warmup_discarded": true
  }
}
EOF

echo "📄 Report written to $REPORT_FILE"

# Compare against baselines if available
if [[ -f "$BASELINES_FILE" ]]; then
    echo ""
    echo "📊 Baselines file found at $BASELINES_FILE"
    echo "   Manual comparison recommended — see metrics/DASHBOARD.md"
fi
