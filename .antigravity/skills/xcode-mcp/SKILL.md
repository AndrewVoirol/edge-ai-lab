---
name: xcode-mcp
description: "Guidelines for using the two Xcode MCP servers: Apple xcode-tools (IDE integration) and Sentry XcodeBuildMCP (headless automation). Activate when building, testing, deploying, or debugging."
---

# Xcode MCP Architecture

This project uses **two** MCP servers for Xcode integration, each with a distinct role. Together they provide ~85 tools across IDE integration and headless automation.

## Server Comparison

| Capability | Apple `xcode-tools` | Sentry `xcodebuild-mcp` |
|---|---|---|
| **When to use** | Active development, rapid TDD | Automated pipelines, headless builds |
| **Requires Xcode open** | ✅ Yes | ❌ No (headless via xcodebuild) |

### Build & Run

| Capability | `xcode-tools` | `xcodebuild-mcp` |
|---|---|---|
| Build (Simulator) | `BuildProject` | `build_sim` |
| Build + Run (Simulator) | — | `build_run_sim` |
| Build (Device) | — | `build_device` |
| Build + Run (Device) | — | `build_run_device` |
| Build (macOS) | — | `build_macos` |
| Build + Run (macOS) | — | `build_run_macos` |

### Testing

| Capability | `xcode-tools` | `xcodebuild-mcp` |
|---|---|---|
| Run Tests (quick) | `RunAllTests`, `RunSomeTests` | — |
| Simulator Tests | — | `test_sim` (structured JSON results) |
| Device Tests | — | `test_device` |
| macOS Tests | — | `test_macos` |
| Code Coverage | — | `get_coverage_report`, `get_file_coverage` |
| Test Results | Xcode UI only | Structured JSON with `durationMs` per test |

### Diagnostics & Code Navigation

| Capability | `xcode-tools` | `xcodebuild-mcp` |
|---|---|---|
| Live Diagnostics | `XcodeListNavigatorIssues`, `XcodeRefreshCodeIssuesInFile` | Build log filtering by severity |
| Build Log | `GetBuildLog` | — |
| Code Navigation | `XcodeRead`, `XcodeWrite`, `XcodeGrep`, `XcodeGlob`, `XcodeLS` | — |
| File Operations | `XcodeWrite`, `XcodeUpdate`, `XcodeMV`, `XcodeRM`, `XcodeMakeDir` | — |
| SwiftUI Preview | `RenderPreview` ✅ | — |
| Documentation | `DocumentationSearch` ✅ | — |
| Code Execution | `ExecuteSnippet` ✅ | — |

### Simulator & Device Management

| Capability | `xcode-tools` | `xcodebuild-mcp` |
|---|---|---|
| List Simulators | — | `list_sims` |
| Boot/Open Simulator | — | `boot_sim`, `open_sim` |
| Install App (Sim) | — | `install_app_sim` |
| Launch/Stop App (Sim) | — | `launch_app_sim`, `stop_app_sim` |
| Screenshot | — | `screenshot` (path or base64) |
| Record Video | — | `record_sim_video` |
| UI Snapshot | — | `snapshot_ui` (view hierarchy + coordinates) |
| List Devices | — | `list_devices` |
| Install App (Device) | — | `install_app_device` |
| Launch/Stop App (Device) | — | `launch_app_device`, `stop_app_device` |
| Get App Path (Sim) | — | `get_sim_app_path` |
| Get App Path (Device) | — | `get_device_app_path` |

### LLDB Debugging

| Capability | `xcode-tools` | `xcodebuild-mcp` |
|---|---|---|
| Attach Debugger | — | `debug_attach_sim` |
| Add Breakpoint | — | `debug_breakpoint_add` |
| Remove Breakpoint | — | `debug_breakpoint_remove` |
| Continue Execution | — | `debug_continue` |
| Detach | — | `debug_detach` |
| LLDB Command | — | `debug_lldb_command` |
| View Stack | — | `debug_stack` |
| Inspect Variables | — | `debug_variables` |

### UI Automation

| Capability | `xcode-tools` | `xcodebuild-mcp` |
|---|---|---|
| Tap | — | `tap` |
| Touch | — | `touch` |
| Long Press | — | `long_press` |
| Swipe | — | `swipe` |
| Custom Gesture | — | `gesture` |
| Hardware Button | — | `button` |
| Key Press | — | `key_press` |
| Key Sequence | — | `key_sequence` |
| Type Text | — | `type_text` |

### Session & Project Management

| Capability | `xcode-tools` | `xcodebuild-mcp` |
|---|---|---|
| List Windows | `XcodeListWindows` | — |
| Session Defaults | — | `session_show_defaults`, `session_set_defaults`, `session_clear_defaults` |
| Profile Management | — | `session_use_defaults_profile` |
| Discover Projects | — | `discover_projs` |
| List Schemes | — | `list_schemes` |
| Build Settings | — | `show_build_settings` |
| Bundle ID | — | `get_app_bundle_id` |
| Manage Workflows | — | `manage_workflows` (runtime enable/disable) |
| Clean | — | `clean` |

## Usage Rules

### Apple `xcode-tools` — IDE Integration
**Use for:** Rapid development when Xcode is open
- SwiftUI previews (`RenderPreview`)
- Live diagnostics (`XcodeListNavigatorIssues`, `XcodeRefreshCodeIssuesInFile`)
- Code navigation and search (`XcodeRead`, `XcodeGrep`, `XcodeGlob`)
- Documentation lookup (`DocumentationSearch`)
- Quick code execution (`ExecuteSnippet`)
- Rapid TDD test runs (`RunAllTests`, `RunSomeTests`)

**Requires:** Xcode must be open with the workspace loaded. Get `tabIdentifier` via `XcodeListWindows`.

**`tabIdentifier` workflow:**
1. Call `XcodeListWindows` (no args needed)
2. Extract `tabIdentifier` from the response
3. Pass `tabIdentifier` to all subsequent xcode-tools calls

**String escaping:**
- `XcodeRead` output is JSON-encoded: backslashes, quotes, newlines appear escaped (`\\`, `\"`, `\n`)
- When using `XcodeUpdate`, input `oldString`/`newString` use **literal characters**: if `XcodeRead` shows `\\d`, use `\d` in parameters

### Sentry `xcodebuild-mcp` — Headless Automation
**Use for:** Automated build/test/deploy pipelines
- Building for simulator, device, or macOS
- Running tests with structured results (JSON output with per-test duration)
- Code coverage reports
- Simulator management (boot, screenshot, record-video)
- Physical device deployment
- LLDB debugging sessions
- UI automation (tap, swipe, type-text, screenshot, snapshot-ui)

**Does NOT require Xcode to be open.**

**Session defaults workflow:**
1. Call `session_show_defaults` to verify active project/workspace, scheme, and simulator
2. If defaults are missing, call `session_set_defaults` or `discover_projs` + `list_schemes`
3. Once defaults are set, most tools can be called with empty/minimal args

## Test Execution Strategy

| Context | Use This |
|---|---|
| Quick test during active coding | `xcode-tools` → `RunSomeTests` (fast, results in Xcode UI) |
| Full test suite, coverage, CI | `xcodebuild-mcp` → `test_sim` (structured results, coverage) |
| Performance test runs | `xcodebuild-mcp` → `test_sim` (metrics captured by hook) |
| Device-specific testing | `xcodebuild-mcp` → `test_device` |
| macOS testing | `xcodebuild-mcp` → `test_macos` |

## Common Patterns

### Build for iOS Simulator
```
Server: xcodebuild-mcp
Tool: build_sim
Args: (empty — uses session defaults)
```

### Build + Run on iOS Simulator
```
Server: xcodebuild-mcp
Tool: build_run_sim
Args: (empty — uses session defaults)
```

### Build for macOS
```
Server: xcodebuild-mcp
Tool: build_macos
Args: scheme=GemmaEdgeGallery_macOS
```

### Build + Deploy to Physical Device
```
Server: xcodebuild-mcp
Tool: build_run_device
Args: (empty — uses session defaults with deviceId)
```

### Run Unit Tests (Simulator)
```
Server: xcodebuild-mcp
Tool: test_sim
Args: (empty — uses session defaults)
```

### Run Device Tests
```
Server: xcodebuild-mcp
Tool: test_device
Args: (empty — uses session defaults with deviceId)
```

### Attach LLDB Debugger
```
Server: xcodebuild-mcp
Tool: debug_attach_sim
Args: (attaches to running app on simulator)
```

### UI Automation — Screenshot + Tap
```
Server: xcodebuild-mcp
Tool: screenshot
Args: returnFormat=base64

Tool: snapshot_ui
Args: (empty — returns view hierarchy with coordinates)

Tool: tap
Args: x=<x>, y=<y>
```

### Enable Additional Workflows at Runtime
```
Server: xcodebuild-mcp
Tool: manage_workflows
Args: (enable/disable workflow groups dynamically)
```

> [!IMPORTANT]
> **Never use raw `xcodebuild` CLI** when MCP tools are available. MCP tools provide structured output, error handling, and integrate with hooks for automatic metrics capture.

> [!WARNING]
> **Physical device deployment** via raw `xcodebuild` will fail due to Keychain security blocking code signing in non-interactive sessions. Always use `xcodebuild-mcp` `build_device` or `build_run_device` for device deployment.

> [!NOTE]
> **Device testing troubleshooting:** If device tests fail with testmanagerd hangs, DTDeviceKit crashes, or pairing issues, see the `device-recovery` skill for diagnosis and recovery procedures.

## Physical Device Testing

> [!NOTE]
> **TEST_HOST sandbox**: iOS unit tests run inside the host app's process via `TEST_HOST` (configured automatically by Tuist). This means tests share the app's sandbox — model files in the app's `Documents/` directory are accessible to tests. However, `#filePath` does NOT resolve to the project directory on physical devices; tests must discover models via `FileManager.urls(for: .documentDirectory)`.

### Device Test Workflow
1. Verify device connectivity: `list_devices`
2. Build and install the app: `build_run_device`
3. Push model files to Documents/: `xcrun devicectl device copy to`
4. Run tests: `test_device`
5. Results include benchmark data captured via os_signpost and BenchmarkInfo

## Enabled Workflows (v2.5.2)

This project has **9 workflows** enabled:

| Workflow | Tools | Purpose |
|---|---|---|
| `simulator` | 20 | iOS/tvOS/watchOS simulator development |
| `device` | 15 | Physical device build/test/deploy |
| `macos` | 13 | macOS app development |
| `debugging` | 8 | LLDB debugging (simulator) |
| `ui-automation` | 11 | Tap/swipe/type/screenshot |
| `coverage` | 2 | Code coverage reports |
| `session-management` | 5 | Session defaults and profiles |
| `project-discovery` | 5 | Project/workspace/scheme discovery |
| `workflow-discovery` | 1 | Runtime workflow management |

> [!IMPORTANT]
> If a tool is "not found", the MCP server may need to be restarted. Check `XCODEBUILDMCP_ENABLED_WORKFLOWS` env var in `~/.gemini/config/mcp_config.json` and `.xcodebuildmcp/config.yaml`.

## Troubleshooting

### Tools "Not Found"
If `build_device`, `test_device`, or other tools return "Tool not found":
1. Check `.xcodebuildmcp/config.yaml` has the workflow enabled
2. Check `mcp_config.json` has `XCODEBUILDMCP_ENABLED_WORKFLOWS` env var
3. Restart the MCP server (restart Antigravity)
4. As a fallback, use `manage_workflows` to enable workflows at runtime

### Device Not Detected
1. `xcrun devicectl list devices` — check device is connected
2. Device must be unlocked and trusted
3. If recently re-paired, **restart the iPhone**
4. See `device-recovery` skill for full troubleshooting
