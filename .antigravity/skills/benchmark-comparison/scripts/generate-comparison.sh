#!/bin/bash
# Generate a cross-dimensional benchmark comparison table from metrics/history.json
# Usage: ./.antigravity/skills/benchmark-comparison/scripts/generate-comparison.sh [session_filter]
#
# If session_filter is provided, only show entries matching that session ID prefix.
# Output is markdown suitable for direct inclusion in walkthrough artifacts.

set -euo pipefail

WORKSPACE="${1:-.}"
METRICS_FILE="$WORKSPACE/metrics/history.json"
SESSION_FILTER="${2:-}"

if [ ! -f "$METRICS_FILE" ]; then
  echo "❌ No metrics/history.json found at $METRICS_FILE" >&2
  echo "Run some benchmark tests first to populate metrics." >&2
  exit 1
fi

echo "# Benchmark Comparison Report"
echo ""
echo "Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
echo ""

# Count entries
total=$(jq 'length' "$METRICS_FILE")
echo "Total metric entries: $total"
echo ""

if [ "$total" -eq 0 ]; then
  echo "No benchmark data available. Run GalleryParityBenchmarkTests to populate."
  exit 0
fi

# Extract unique sessions
echo "## Sessions"
echo ""
jq -r '[.[] | {session: .sessionId, ts: .timestamp, platform: .platform}] | unique_by(.session) | .[] | "- **\(.session | .[0:8])...** (\(.platform), \(.ts))"' "$METRICS_FILE" 2>/dev/null || true
echo ""

# Extract all benchmarks
echo "## Our App Benchmarks"
echo ""
echo "| Session | Platform | Label | Decode (tok/s) | Prefill (tok/s) | TTFT (s) | Init (ms) | Tokens |"
echo "|---|---|---|---|---|---|---|---|"

if [ -n "$SESSION_FILTER" ]; then
  filter=".sessionId | contains(\"$SESSION_FILTER\")"
else
  filter="true"
fi

jq -r --arg filter "$SESSION_FILTER" '
  .[] | select(if ($filter | length) > 0 then .sessionId | contains($filter) else true end) |
  .sessionId as $sid | .platform as $plat | .timestamp as $ts |
  (.benchmarks // [])[] |
  "| \($sid | .[0:8])... | \($plat) | \(.label) | \(.decodeSpeed | tostring) | \(.prefillSpeed | tostring) | \(.ttft | tostring) | \(.initTimeMs | tostring) | \(.avgTokens | tostring) |"
' "$METRICS_FILE" 2>/dev/null || echo "| — | — | No benchmark data | — | — | — | — | — |"

echo ""

# Known Gallery baselines
echo "## Gallery Baselines (iPhone 16 Pro Max, v1.0.6)"
echo ""
echo "| Model | Accel | Prefill (tok/s) | Decode (tok/s) | TTFT (s) | Init (ms) |"
echo "|---|---|---|---|---|---|"
echo "| Gemma-4-E2B-it | GPU+MTP | 360.35 | 41.65 | 0.74 | 9192 |"
echo "| Gemma-3n-E2B-it | GPU+MTP | 392.86 | 25.57 | 0.70 | 8194 |"
echo "| Gemma-4-E2B-it | CPU | 0.00 | 0.00 | 0.00 | 0.00 |"
echo ""

# Known HuggingFace baselines
echo "## HuggingFace Baselines (Model Cards)"
echo ""
echo "| Model | Device | Prefill (tok/s) | Decode (tok/s) | Config |"
echo "|---|---|---|---|---|"
echo "| Gemma-4-E2B-it | iPhone 17 Pro | ~2,878 | ~56 | 1024 prefill, GPU |"
echo "| Gemma-4-E2B-it | MacBook M4 | ~7,835 | ~160 | 1024 prefill, GPU |"
echo ""

# Test summary
echo "## Test Summary"
echo ""
echo "| Session | Passed | Failed | Skipped |"
echo "|---|---|---|---|"
jq -r '
  .[] | select(.testResults) |
  "| \(.sessionId | .[0:8])... | \(.testResults.passed) | \(.testResults.failed) | \(.testResults.skipped) |"
' "$METRICS_FILE" 2>/dev/null || echo "| — | — | — | — |"
echo ""

echo "---"
echo ""
echo "> [!NOTE]"
echo "> Gallery uses topK=1 (greedy), MTP ON, 256 tokens. HuggingFace uses 1024 prefill tokens."
echo "> Our app uses topK=64 (sampling), MTP OFF (default), variable tokens."
echo "> Numbers are NOT directly comparable without matching methodology."
