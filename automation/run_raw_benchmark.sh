#!/bin/bash
# ============================================================================
# run_raw_benchmark.sh — Build and run the RawBenchmark CLI with xctrace
# ============================================================================
#
# Usage:
#   ./automation/run_raw_benchmark.sh [--no-trace]
#
# Options:
#   --no-trace    Skip xctrace recording; just run the binary directly
#
# Output:
#   - JSON benchmark report to stdout
#   - Instruments .trace file saved to metrics/ (unless --no-trace)
#   - All log messages on stderr
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

NO_TRACE=false
if [[ "${1:-}" == "--no-trace" ]]; then
    NO_TRACE=true
fi

if [[ -n "${MODEL_PATH:-}" ]]; then
    : # User-provided via environment variable, use as-is
else
    MODEL_PATH=$(find "$PROJECT_ROOT/models" -name '*.litertlm' -type f 2>/dev/null | head -1)
    if [[ -z "$MODEL_PATH" ]]; then
        echo "❌ No .litertlm model found in $PROJECT_ROOT/models/" >&2
        echo "   Set MODEL_PATH environment variable or place a model in models/" >&2
        exit 1
    fi
fi

echo "═══════════════════════════════════════════════════════════" >&2
echo "  RawBenchmark Runner" >&2
echo "═══════════════════════════════════════════════════════════" >&2
echo "" >&2

# ── Step 1: Generate Xcode project via Tuist ──────────────────────────────
echo "[1/4] Running tuist generate..." >&2
tuist generate --no-open 2>&1 | tail -3 >&2
echo "" >&2

# ── Step 2: Build in Release mode ─────────────────────────────────────────
echo "[2/4] Building RawBenchmark (Release)..." >&2
xcodebuild \
    -workspace EdgeAILab.xcworkspace \
    -scheme RawBenchmark \
    -configuration Release \
    -derivedDataPath Derived/RawBenchmark \
    build 2>&1 | grep -E "(Build Succeeded|BUILD|error:)" >&2 || true
echo "" >&2

# ── Locate the binary ────────────────────────────────────────────────────
BINARY=$(find Derived/RawBenchmark/Build/Products/Release* -name "RawBenchmark" -type f -not -path "*.dSYM*" 2>/dev/null | head -1)
if [[ -z "$BINARY" ]]; then
    echo "❌ Could not find RawBenchmark binary in Derived/RawBenchmark/" >&2
    echo "   Attempting to find it..." >&2
    find Derived/RawBenchmark -name "RawBenchmark" -type f >&2
    exit 1
fi
echo "[3/4] Binary found: $BINARY" >&2
echo "" >&2

# ── Step 3: Verify model exists ──────────────────────────────────────────
if [[ ! -f "$MODEL_PATH" ]]; then
    echo "❌ Model not found: $MODEL_PATH" >&2
    exit 1
fi
MODEL_SIZE=$(stat -f%z "$MODEL_PATH" 2>/dev/null || stat --printf="%s" "$MODEL_PATH" 2>/dev/null)
echo "   Model: $(basename "$MODEL_PATH") ($((MODEL_SIZE / 1048576)) MB)" >&2
echo "" >&2

# ── Step 4: Run ──────────────────────────────────────────────────────────
mkdir -p metrics

if [[ "$NO_TRACE" == true ]]; then
    echo "[4/4] Running benchmark (no xctrace)..." >&2
    echo "" >&2
    "$BINARY" "$MODEL_PATH"
else
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    TRACE_OUT="metrics/raw_benchmark_${TIMESTAMP}.trace"

    echo "[4/4] Running benchmark with xctrace (Time Profiler + Metal System Trace)..." >&2
    echo "   Trace output: $TRACE_OUT" >&2
    echo "" >&2

    # xctrace record with Time Profiler template
    # Metal System Trace would be added with: --template "Metal System Trace"
    # For combined profiling, we use Time Profiler which captures CPU + scheduling.
    # Metal GPU timeline can be captured in a separate run if needed.
    xctrace record \
        --template "Time Profiler" \
        --output "$TRACE_OUT" \
        --launch -- "$BINARY" "$MODEL_PATH" 2>&1

    echo "" >&2
    echo "═══════════════════════════════════════════════════════════" >&2
    echo "  Trace saved: $TRACE_OUT" >&2
    echo "  Open in Instruments: open $TRACE_OUT" >&2
    echo "═══════════════════════════════════════════════════════════" >&2
fi
