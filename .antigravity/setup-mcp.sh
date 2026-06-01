#!/bin/bash
# Setup script for Xcode MCP configuration
# This script updates protected config files that the agent cannot modify directly.
# Run this script once after the agent has made all other changes.

set -euo pipefail

echo "🔧 Xcode MCP Setup Script"
echo "========================="
echo ""

# 1. Update mcp_config.json
MCP_CONFIG="$HOME/.gemini/config/mcp_config.json"

if [ ! -f "$MCP_CONFIG" ]; then
  echo "❌ mcp_config.json not found at $MCP_CONFIG"
  exit 1
fi

echo "📝 Updating $MCP_CONFIG..."
echo "   Adding XCODEBUILDMCP_ENABLED_WORKFLOWS env var..."

# Create updated config
cat > "$MCP_CONFIG" << 'EOF'
{
  "mcpServers": {
    "web-agent": {
      "command": "/Users/andrewvoirol/.gemini/antigravity/skills/launch_chrome_agent.sh",
      "args": [],
      "disabled": true
    },
    "xcode-tools": {
      "command": "/Users/andrewvoirol/.gemini/antigravity/skills/launch_xcode_agent.sh",
      "args": [],
      "disabled": false
    },
    "xcodebuild-mcp": {
      "command": "/opt/homebrew/bin/xcodebuildmcp",
      "args": ["mcp"],
      "disabled": false,
      "env": {
        "XCODEBUILDMCP_ENABLED_WORKFLOWS": "simulator,device,ui-automation,debugging,macos,coverage,session-management,project-discovery,workflow-discovery"
      }
    }
  }
}
EOF

echo "   ✅ mcp_config.json updated"

# 2. Update xcode-tools instructions.md
XCODE_TOOLS_INSTRUCTIONS="$HOME/.gemini/antigravity/mcp/xcode-tools/instructions.md"

echo ""
echo "📝 Updating $XCODE_TOOLS_INSTRUCTIONS..."

cat > "$XCODE_TOOLS_INSTRUCTIONS" << 'EOF'
# Apple xcode-tools MCP Server

Apple's native Xcode MCP bridge (`xcrun mcpbridge`). Provides IDE integration features that require Xcode to be open.

## Setup
1. Xcode must be open with the workspace loaded
2. Call `XcodeListWindows` first to get the `tabIdentifier`
3. Pass `tabIdentifier` to all subsequent tool calls

## Key Tools

| Tool | Purpose |
|---|---|
| `XcodeListWindows` | List open windows — get `tabIdentifier` here |
| `BuildProject` | Trigger a build in Xcode |
| `XcodeRead` | Read file contents (JSON-encoded output) |
| `XcodeWrite` | Create/overwrite files (auto-adds to project) |
| `XcodeUpdate` | Replace text in files (oldString → newString) |
| `XcodeGrep` | Search files by regex |
| `XcodeGlob` | Find files by glob pattern |
| `XcodeLS` | List directory contents |
| `RenderPreview` | Render SwiftUI preview |
| `RunAllTests` / `RunSomeTests` | Quick test runs |
| `GetBuildLog` | Inspect build log with severity filtering |
| `XcodeListNavigatorIssues` | List errors/warnings from Issue Navigator |
| `XcodeRefreshCodeIssuesInFile` | Refresh diagnostics for a specific file |
| `DocumentationSearch` | Search Apple documentation |
| `ExecuteSnippet` | Execute Swift code snippets |
| `GetTestList` | List available tests |

## String Escaping
- `XcodeRead` returns JSON-encoded content: `\\d` in source appears as `\\\\d`
- `XcodeUpdate`: use **literal characters** — if source has `\d`, put `\d` in `oldString`/`newString`
- `XcodeWrite`: same literal characters rule for content

## When to Use
- SwiftUI previews and live diagnostics during active development
- Quick code navigation without leaving Xcode
- Rapid TDD with `RunSomeTests` (results appear in Xcode UI)
- Documentation lookups

## When NOT to Use
- Headless builds/tests → use `xcodebuild-mcp` instead
- Device deployment → use `xcodebuild-mcp` `build_device`/`build_run_device`
- Code coverage → use `xcodebuild-mcp` `get_coverage_report`
- LLDB debugging → use `xcodebuild-mcp` debugging tools
EOF

echo "   ✅ xcode-tools instructions.md updated"

echo ""
echo "✅ Setup complete!"
echo ""
echo "⚠️  IMPORTANT: Restart Antigravity (or the MCP servers) for changes to take effect."
echo "   After restart, verify by checking for device tools:"
echo "   - Call 'session_show_defaults' via xcodebuild-mcp"
echo "   - Call 'build_device' — should no longer return 'Tool not found'"
echo "   - Call 'list_devices' — should show connected devices"
