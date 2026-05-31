#!/bin/bash
# Hook: Check for model file before builds/tests
# Trigger: PreToolUse on build and test MCP tool calls
# Reports model inventory with platform compatibility info.
# Warns (but doesn't block) if no model files are found.

set -euo pipefail

input=$(cat)

workspace=$(echo "$input" | jq -r '.workspacePaths[0] // "."')
models_dir="$workspace/models"

# Check if any .litertlm model files exist
if [ -d "$models_dir" ]; then
  model_files=$(find "$models_dir" -name "*.litertlm" -maxdepth 1 2>/dev/null || true)
  model_count=$(echo "$model_files" | grep -c '.' 2>/dev/null || echo 0)
else
  model_files=""
  model_count=0
fi

if [ "$model_count" -eq 0 ]; then
  echo "⚠️  No .litertlm model files found in models/ directory" >&2
  echo "   Unit tests will work, but performance tests require a model." >&2
  echo "   Copy a model: cp /path/to/model.litertlm $models_dir/" >&2
else
  echo "📦 Model Inventory ($model_count models found):" >&2
  echo "$model_files" | while read -r filepath; do
    [ -z "$filepath" ] && continue
    filename=$(basename "$filepath")
    size_bytes=$(stat -f%z "$filepath" 2>/dev/null || echo "?")
    size_gb=$(echo "scale=2; $size_bytes / 1073741824" | bc 2>/dev/null || echo "?")

    # Platform compatibility from known model registry
    case "$filename" in
      "gemma-3n-E2B-it-int4.litertlm")
        compat="iOS: GPU ✅ | macOS: Unknown | Sim: Unknown | [Gallery iOS model]"
        ;;
      "gemma-3n-E2B-HW.litertlm")
        compat="iOS: GPU ✅ | macOS: GPU ✅ | Sim: Unknown | [HW-optimized, GPU-only]"
        ;;
      "gemma-4-E2B-it.litertlm")
        compat="iOS: GPU+CPU ✅ | macOS: GPU+CPU ✅ | Sim: CPU ✅"
        ;;
      "gemma-4-E2B-it-web.litertlm")
        compat="iOS: GPU ✅ | macOS: Unknown | Sim: Unknown | [GPU-only, no CPU]"
        ;;
      "gemma-4-E4B-it.litertlm")
        compat="iOS: GPU+CPU ✅ | macOS: GPU+CPU ✅ | Sim: CPU ✅"
        ;;
      "gemma-4-E4B-it-web.litertlm")
        compat="iOS: GPU ✅ | macOS: Unknown | Sim: Unknown | [GPU-only, no CPU]"
        ;;
      *)
        compat="Unknown model — backend compatibility will be probed at runtime"
        ;;
    esac

    echo "  • $filename (${size_gb} GB)" >&2
    echo "    $compat" >&2
  done
fi

# Always allow the build/test to proceed (fail-open)
echo '{}'
