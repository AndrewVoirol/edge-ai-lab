#!/bin/bash
# Hook: Capture test metrics after test execution
# Trigger: PostToolUse on test MCP tool calls
# 
# Enhanced in Session 3b to:
# - Parse test output for benchmark values (tok/s, TTFT, init time)
# - Tag each run with session ID, device, model, and config
# - Store structured data in metrics/history.json
#
# Parses output patterns from GalleryParityBenchmarkTests:
#   ║ Decode speed (avg): 103.16 tokens/sec
#   ║ Prefill speed (avg): 360.35 tokens/sec
#   ║ Time to first token (avg): 0.25 sec
#   ║ First init time: 1118.82 ms
#   ║ Avg tokens generated: 256
#   Test Case '...' passed (65.470 seconds).

set -euo pipefail

input=$(cat)

workspace=$(echo "$input" | jq -r '.workspacePaths[0] // "."')
metrics_dir="$workspace/metrics"
metrics_file="$metrics_dir/history.json"

# Ensure metrics directory exists
mkdir -p "$metrics_dir"

# Initialize history.json if it doesn't exist
if [ ! -f "$metrics_file" ]; then
  echo '[]' > "$metrics_file"
  echo "📊 Created metrics/history.json" >&2
fi

# Get context
timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
tool_name=$(echo "$input" | jq -r '.toolName // "unknown"')
conversation_id=$(echo "$input" | jq -r '.conversationId // "unknown"')
tool_output=$(echo "$input" | jq -r '.toolOutput // ""')

# Detect platform from tool output or tool name
platform="unknown"
if echo "$tool_output" | grep -qi "iOS\|iPhone\|iPad"; then
  platform="iOS-device"
elif echo "$tool_output" | grep -qi "Simulator"; then
  platform="iOS-simulator"
elif echo "$tool_output" | grep -qi "macOS\|Mac"; then
  platform="macOS"
fi

# Detect available models
models=()
if [ -d "$workspace/models" ]; then
  while IFS= read -r f; do
    models+=("$(basename "$f")")
  done < <(find "$workspace/models" -name "*.litertlm" -maxdepth 1 2>/dev/null)
fi
model_list=$(printf '%s\n' "${models[@]}" 2>/dev/null | jq -R . | jq -s '.' 2>/dev/null || echo '[]')

# Extract benchmark results from RESULTS blocks
# Pattern: ║ RESULTS: <label> — <N> runs averaged
# Followed by metric lines
results=()
if echo "$tool_output" | grep -q "RESULTS:"; then
  # Parse each RESULTS block
  while IFS= read -r results_line; do
    label=$(echo "$results_line" | sed 's/.*RESULTS: //' | sed 's/ —.*//' | xargs)
    
    # Extract metrics following this RESULTS line
    # We need to find the block after this line
    block=$(echo "$tool_output" | sed -n "/RESULTS: ${label}/,/╚/p" 2>/dev/null || true)
    
    decode=$(echo "$block" | grep -o 'Decode speed (avg): [0-9.]*' | grep -o '[0-9.]*' | head -1)
    prefill=$(echo "$block" | grep -o 'Prefill speed (avg): [0-9.]*' | grep -o '[0-9.]*' | head -1)
    ttft=$(echo "$block" | grep -o 'Time to first token (avg): [0-9.]*' | grep -o '[0-9.]*' | head -1)
    init_time=$(echo "$block" | grep -o 'First init time: [0-9.]*' | grep -o '[0-9.]*' | head -1)
    avg_tokens=$(echo "$block" | grep -o 'Avg tokens generated: [0-9]*' | grep -o '[0-9]*' | head -1)
    
    # Extract individual run data
    run_data=$(echo "$block" | grep "Run [0-9]" | sed 's/║ *//' | jq -R . | jq -s '.' 2>/dev/null || echo '[]')
    
    if [ -n "$decode" ] || [ -n "$prefill" ]; then
      result_entry=$(jq -n \
        --arg label "$label" \
        --arg decode "${decode:-0}" \
        --arg prefill "${prefill:-0}" \
        --arg ttft "${ttft:-0}" \
        --arg init "${init_time:-0}" \
        --arg tokens "${avg_tokens:-0}" \
        --argjson runs "$run_data" \
        '{
          label: $label,
          decodeSpeed: ($decode | tonumber),
          prefillSpeed: ($prefill | tonumber),
          ttft: ($ttft | tonumber),
          initTimeMs: ($init | tonumber),
          avgTokens: ($tokens | tonumber),
          individualRuns: $runs
        }')
      results+=("$result_entry")
    fi
  done < <(echo "$tool_output" | grep "RESULTS:")
fi

# Count test results
tests_passed=$(echo "$tool_output" | grep -c "passed" 2>/dev/null || echo "0")
tests_failed=$(echo "$tool_output" | grep -c "failed" 2>/dev/null || echo "0")
tests_skipped=$(echo "$tool_output" | grep -c "skipped" 2>/dev/null || echo "0")

# Build results array as JSON
if [ ${#results[@]} -gt 0 ]; then
  results_json=$(printf '%s\n' "${results[@]}" | jq -s '.')
else
  results_json="[]"
fi

# Create new entry with full benchmark data
new_entry=$(jq -n \
  --arg ts "$timestamp" \
  --arg tool "$tool_name" \
  --arg conv "$conversation_id" \
  --arg platform "$platform" \
  --argjson models "$model_list" \
  --argjson benchmarks "$results_json" \
  --argjson passed "$tests_passed" \
  --argjson failed "$tests_failed" \
  --argjson skipped "$tests_skipped" \
  '{
    timestamp: $ts,
    sessionId: $conv,
    toolName: $tool,
    platform: $platform,
    availableModels: $models,
    testResults: {
      passed: $passed,
      failed: $failed,
      skipped: $skipped
    },
    benchmarks: $benchmarks
  }')

# Append to history (atomic write via temp file)
tmp_file=$(mktemp)
if jq --argjson entry "$new_entry" '. + [$entry]' "$metrics_file" > "$tmp_file" 2>/dev/null; then
  mv "$tmp_file" "$metrics_file"
  bench_count=${#results[@]}
  echo "📊 Captured $bench_count benchmark(s) + test results → metrics/history.json" >&2
else
  rm -f "$tmp_file"
  echo "⚠️  Failed to append metrics — history.json may be malformed" >&2
fi

echo '{}'
