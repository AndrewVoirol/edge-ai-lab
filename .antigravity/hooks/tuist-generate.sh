#!/bin/bash
# Hook: Auto-regenerate Xcode project when Project.swift is modified
# Trigger: PostToolUse on file write operations
# Only fires when the written file is Project.swift

set -euo pipefail

input=$(cat)

# Extract the file path from tool arguments
# Different tools use different argument names
file_path=$(echo "$input" | jq -r '
  .arguments.TargetFile //
  .arguments.AbsolutePath //
  .arguments.filePath //
  .arguments.file_path //
  ""
' 2>/dev/null || echo "")

# Only run if the edited file is Project.swift
if echo "$file_path" | grep -q "Project\.swift$"; then
  workspace=$(echo "$input" | jq -r '.workspacePaths[0] // "."')
  echo "🔄 Project.swift was modified — running tuist generate..." >&2
  
  cd "$workspace"
  
  if command -v tuist &> /dev/null; then
    if tuist generate 2>&2; then
      echo "✅ tuist generate completed successfully" >&2
    else
      echo "⚠️  tuist generate failed — manual regeneration needed" >&2
    fi
  else
    echo "⚠️  tuist not found in PATH — cannot auto-regenerate" >&2
  fi
fi

# Always return empty JSON (success, no blocking)
echo '{}'
