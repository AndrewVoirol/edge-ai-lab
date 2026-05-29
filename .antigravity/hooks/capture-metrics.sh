#!/bin/bash
# Hook: Capture test metrics after test execution
# Trigger: PostToolUse on test MCP tool calls
# Appends test run metadata to metrics/history.json

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

# Get timestamp and tool info
timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
tool_name=$(echo "$input" | jq -r '.toolName // "unknown"')
conversation_id=$(echo "$input" | jq -r '.conversationId // "unknown"')

# Check for model info
model_file="unknown"
if [ -d "$workspace/models" ]; then
  first_model=$(find "$workspace/models" -name "*.litertlm" -maxdepth 1 2>/dev/null | head -1)
  if [ -n "$first_model" ]; then
    model_file=$(basename "$first_model")
  fi
fi

# Create new entry
new_entry=$(jq -n \
  --arg ts "$timestamp" \
  --arg tool "$tool_name" \
  --arg conv "$conversation_id" \
  --arg model "$model_file" \
  '{
    timestamp: $ts,
    toolName: $tool,
    conversationId: $conv,
    model: $model,
    note: "Auto-captured by PostToolUse hook"
  }')

# Append to history (atomic write via temp file)
tmp_file=$(mktemp)
if jq --argjson entry "$new_entry" '. + [$entry]' "$metrics_file" > "$tmp_file" 2>/dev/null; then
  mv "$tmp_file" "$metrics_file"
  echo "📊 Test metrics appended to metrics/history.json" >&2
else
  rm -f "$tmp_file"
  echo "⚠️  Failed to append metrics — history.json may be malformed" >&2
fi

echo '{}'
