#!/bin/bash
# Hook: Check for model file before builds/tests
# Trigger: PreToolUse on build and test MCP tool calls
# Warns (but doesn't block) if no model files are found

set -euo pipefail

input=$(cat)

workspace=$(echo "$input" | jq -r '.workspacePaths[0] // "."')
models_dir="$workspace/models"

# Check if any .litertlm model files exist
if [ -d "$models_dir" ]; then
  model_count=$(find "$models_dir" -name "*.litertlm" -maxdepth 1 2>/dev/null | wc -l | tr -d ' ')
else
  model_count=0
fi

if [ "$model_count" -eq 0 ]; then
  echo "⚠️  No .litertlm model files found in models/ directory" >&2
  echo "   Unit tests will work, but performance tests require a model." >&2
  echo "   Copy a model: cp /path/to/model.litertlm $models_dir/" >&2
fi

# Always allow the build/test to proceed (fail-open)
echo '{}'
