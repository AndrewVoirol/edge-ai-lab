#!/usr/bin/env bash
# ci_test_runner.sh — Orchestrates the full test pyramid for GemmaEdgeGallery.
#
# Test Pyramid:
#   1. UnitTests    — Fast, no model needed (MUST pass)
#   2. IntegrationTests — Model needed, functional verification (MUST pass)
#   3. PerformanceTests — Model needed, baseline regression check (informational)
#
# Usage:
#   ./automation/ci_test_runner.sh [--macOS | --simulator | --device]
#   ./automation/ci_test_runner.sh --macOS --skip-integration --skip-performance
#
# Environment:
#   PERFORMANCE_TEST_MODEL_PATH  — Path to .litertlm model file (optional, auto-discovers)
#   CI_OUTPUT_DIR               — Directory for JSON results (default: metrics/)
#
# Exit codes:
#   0 — All required tests passed
#   1 — Unit tests failed (critical)
#   2 — Integration tests failed (critical)
#   3 — Performance tests failed (informational — exit 0 if --no-fail-perf)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUT_DIR="${CI_OUTPUT_DIR:-$PROJECT_DIR/metrics}"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Defaults
PLATFORM="macos"
SKIP_INTEGRATION=false
SKIP_PERFORMANCE=false
NO_FAIL_PERF=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --macOS|--macos)      PLATFORM="macos"; shift ;;
        --simulator)          PLATFORM="simulator"; shift ;;
        --device)             PLATFORM="device"; shift ;;
        --skip-integration)   SKIP_INTEGRATION=true; shift ;;
        --skip-performance)   SKIP_PERFORMANCE=true; shift ;;
        --no-fail-perf)       NO_FAIL_PERF=true; shift ;;
        -h|--help)
            echo "Usage: $0 [--macOS|--simulator|--device] [--skip-integration] [--skip-performance] [--no-fail-perf]"
            exit 0 ;;
        *)
            echo "Unknown argument: $1" >&2
            exit 1 ;;
    esac
done

# Ensure output directory exists
mkdir -p "$OUTPUT_DIR"

# Results tracking
RESULTS_FILE="$OUTPUT_DIR/ci_results_$(date +%Y%m%d_%H%M%S).json"
UNIT_STATUS="skipped"
INTEGRATION_STATUS="skipped"
PERFORMANCE_STATUS="skipped"
EXIT_CODE=0

echo "╔══════════════════════════════════════════════════════╗"
echo "║  GemmaEdgeGallery CI Test Runner                     ║"
echo "║  Platform: $PLATFORM                                ║"
echo "║  Timestamp: $TIMESTAMP                              ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

# ──────────────────────────────────────────────────────────
# Step 1: Unit Tests (required, no model needed)
# ──────────────────────────────────────────────────────────
echo "🧪 Step 1/3: Unit Tests (no model required)"
echo "─────────────────────────────────────────────"

SCHEME="GemmaEdgeGallery_macOS"
if [[ "$PLATFORM" == "simulator" || "$PLATFORM" == "device" ]]; then
    SCHEME="GemmaEdgeGallery_iOS"
fi

UNIT_START=$(date +%s)
if xcodebuild test \
    -project "$PROJECT_DIR/GemmaEdgeGallery.xcodeproj" \
    -scheme "$SCHEME" \
    -destination "platform=macOS" \
    -only-testing:GemmaEdgeGallery_macOSTests \
    -quiet 2>&1; then
    UNIT_STATUS="passed"
    echo "✅ Unit tests PASSED"
else
    UNIT_STATUS="failed"
    echo "❌ Unit tests FAILED"
    EXIT_CODE=1
fi
UNIT_DURATION=$(( $(date +%s) - UNIT_START ))
echo "   Duration: ${UNIT_DURATION}s"
echo ""

# ──────────────────────────────────────────────────────────
# Step 2: Integration Tests (model required)
# ──────────────────────────────────────────────────────────
if [[ "$SKIP_INTEGRATION" == "true" ]]; then
    echo "⏭️  Step 2/3: Integration Tests — SKIPPED"
    echo ""
elif [[ "$EXIT_CODE" -ne 0 ]]; then
    echo "⏭️  Step 2/3: Integration Tests — SKIPPED (unit tests failed)"
    INTEGRATION_STATUS="skipped_dependency"
    echo ""
else
    echo "🔗 Step 2/3: Integration Tests (model required)"
    echo "─────────────────────────────────────────────"

    # Check for model availability
    MODEL_PATH="${PERFORMANCE_TEST_MODEL_PATH:-}"
    if [[ -z "$MODEL_PATH" ]]; then
        # Auto-discover model in models/ directory
        MODEL_PATH=$(find "$PROJECT_DIR/models" -name "*.litertlm" -type f 2>/dev/null | head -1)
    fi

    if [[ -z "$MODEL_PATH" || ! -f "$MODEL_PATH" ]]; then
        echo "⚠️  No model found — skipping integration tests"
        echo "   Set PERFORMANCE_TEST_MODEL_PATH or place a .litertlm in models/"
        INTEGRATION_STATUS="skipped_no_model"
    else
        echo "   Using model: $(basename "$MODEL_PATH")"
        INTEG_START=$(date +%s)
        if xcodebuild test \
            -project "$PROJECT_DIR/GemmaEdgeGallery.xcodeproj" \
            -scheme "$SCHEME" \
            -destination "platform=macOS" \
            -only-testing:GemmaEdgeGallery_macOSTests/SmartFallbackIntegrationTests \
            -quiet 2>&1; then
            INTEGRATION_STATUS="passed"
            echo "✅ Integration tests PASSED"
        else
            INTEGRATION_STATUS="failed"
            echo "❌ Integration tests FAILED"
            EXIT_CODE=2
        fi
        INTEG_DURATION=$(( $(date +%s) - INTEG_START ))
        echo "   Duration: ${INTEG_DURATION}s"
    fi
    echo ""
fi

# ──────────────────────────────────────────────────────────
# Step 3: Performance Tests (model required, informational)
# ──────────────────────────────────────────────────────────
if [[ "$SKIP_PERFORMANCE" == "true" ]]; then
    echo "⏭️  Step 3/3: Performance Tests — SKIPPED"
    echo ""
elif [[ "$EXIT_CODE" -ne 0 ]]; then
    echo "⏭️  Step 3/3: Performance Tests — SKIPPED (earlier failures)"
    PERFORMANCE_STATUS="skipped_dependency"
    echo ""
else
    echo "📊 Step 3/3: Performance Tests (model required, informational)"
    echo "─────────────────────────────────────────────"

    MODEL_PATH="${PERFORMANCE_TEST_MODEL_PATH:-}"
    if [[ -z "$MODEL_PATH" ]]; then
        MODEL_PATH=$(find "$PROJECT_DIR/models" -name "*.litertlm" -type f 2>/dev/null | head -1)
    fi

    if [[ -z "$MODEL_PATH" || ! -f "$MODEL_PATH" ]]; then
        echo "⚠️  No model found — skipping performance tests"
        PERFORMANCE_STATUS="skipped_no_model"
    else
        echo "   Using model: $(basename "$MODEL_PATH")"
        PERF_START=$(date +%s)
        if xcodebuild test \
            -project "$PROJECT_DIR/GemmaEdgeGallery.xcodeproj" \
            -scheme "$SCHEME" \
            -destination "platform=macOS" \
            -only-testing:GemmaEdgeGallery_macOSTests/PerformanceTests \
            -quiet 2>&1; then
            PERFORMANCE_STATUS="passed"
            echo "✅ Performance tests PASSED"
        else
            PERFORMANCE_STATUS="failed"
            echo "⚠️  Performance tests FAILED (informational)"
            if [[ "$NO_FAIL_PERF" != "true" ]]; then
                EXIT_CODE=3
            fi
        fi
        PERF_DURATION=$(( $(date +%s) - PERF_START ))
        echo "   Duration: ${PERF_DURATION}s"
    fi
    echo ""
fi

# ──────────────────────────────────────────────────────────
# Results Summary
# ──────────────────────────────────────────────────────────
echo "╔══════════════════════════════════════════════════════╗"
echo "║  Test Results Summary                                ║"
echo "╠══════════════════════════════════════════════════════╣"
printf "║  Unit Tests:        %-32s ║\n" "$UNIT_STATUS"
printf "║  Integration Tests: %-32s ║\n" "$INTEGRATION_STATUS"
printf "║  Performance Tests: %-32s ║\n" "$PERFORMANCE_STATUS"
echo "╠══════════════════════════════════════════════════════╣"
printf "║  Exit Code: %-40s ║\n" "$EXIT_CODE"
echo "╚══════════════════════════════════════════════════════╝"

# Write JSON results
cat > "$RESULTS_FILE" <<EOF
{
  "timestamp": "$TIMESTAMP",
  "platform": "$PLATFORM",
  "results": {
    "unit_tests": "$UNIT_STATUS",
    "integration_tests": "$INTEGRATION_STATUS",
    "performance_tests": "$PERFORMANCE_STATUS"
  },
  "exit_code": $EXIT_CODE
}
EOF

echo ""
echo "📄 Results written to: $RESULTS_FILE"

exit $EXIT_CODE
