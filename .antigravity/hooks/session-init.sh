#!/bin/bash
# Hook: Verify XcodeBuildMCP session defaults before first build/test
# Trigger: PreToolUse on build/test MCP calls
# 
# Checks that workspace, scheme, and simulator/device are configured.
# Warns (but doesn't block) if defaults are missing.

set -euo pipefail

input=$(cat)

workspace=$(echo "$input" | jq -r '.workspacePaths[0] // "."')
tool_name=$(echo "$input" | jq -r '.toolName // "unknown"')

# Only check for xcodebuild-mcp tools
if ! echo "$tool_name" | grep -q "xcodebuild-mcp"; then
  echo '{}'
  exit 0
fi

# Check for .xcodebuildmcp/config.yaml
config_file="$workspace/.xcodebuildmcp/config.yaml"
if [ ! -f "$config_file" ]; then
  echo "⚠️  No .xcodebuildmcp/config.yaml found — XcodeBuildMCP may use defaults only" >&2
fi

# Check enabled workflows
if [ -f "$config_file" ]; then
  workflows=$(grep -o 'enabledWorkflows' "$config_file" 2>/dev/null || true)
  if [ -z "$workflows" ]; then
    echo "⚠️  enabledWorkflows not set in config.yaml — only simulator tools may be available" >&2
  else
    # Count enabled workflows
    wf_count=$(grep -c '^\s*-' "$config_file" 2>/dev/null || echo "0")
    echo "✅ XcodeBuildMCP: $wf_count workflows enabled" >&2
  fi
fi

# Detect if this is a device tool call
if echo "$tool_name" | grep -qi "device"; then
  echo "📱 Device tool detected — ensure device is unlocked, trusted, and connected" >&2
  
  # Check if devicectl can see any devices
  if command -v xcrun &> /dev/null; then
    device_count=$(xcrun devicectl list devices 2>/dev/null | grep -c "iPhone\|iPad" || echo "0")
    if [ "$device_count" -eq 0 ]; then
      echo "⚠️  No iOS devices detected via devicectl — is the device connected and unlocked?" >&2
    else
      echo "📱 $device_count iOS device(s) detected" >&2
    fi
  fi
fi

# Always allow to proceed (fail-open)
echo '{}'
