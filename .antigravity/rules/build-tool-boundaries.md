# Build Tool Boundaries

This project uses a specific build toolchain. Follow these boundaries at all times.

## Build Stack
- **Tuist** — Project generation only (`tuist generate`)
- **XcodeBuildMCP** (`xcodebuild-mcp` MCP server) — All builds, tests, deployment, coverage, debugging
- **Apple xcode-tools** (`xcode-tools` MCP server) — IDE integration only (previews, diagnostics, code nav, documentation)

## Rules

1. **Never use raw `xcodebuild` CLI commands** when MCP tools are available. Use `xcodebuild-mcp` tools instead — they provide structured output and integrate with automation hooks.

   **Why this matters — known failure modes with raw xcodebuild:**
   - Device builds: Keychain security blocks code signing in non-interactive sessions (hangs forever)
   - Device tests: `testmanagerd` connection issues produce no useful error output
   - No structured JSON results — harder to parse pass/fail
   - Hooks (metrics-capture, session-init) don't fire for raw CLI commands

2. **Never use Fastlane.** Fastlane has been removed from this project. If you see references to `fastlane` commands, they are outdated.

3. **Use `xcodebuild-mcp` for:**
   - **Simulator:** `build_sim`, `build_run_sim`, `test_sim`, `install_app_sim`, `launch_app_sim`, `stop_app_sim`
   - **Device:** `build_device`, `build_run_device`, `test_device`, `install_app_device`, `launch_app_device`, `stop_app_device`, `list_devices`
   - **macOS:** `build_macos`, `build_run_macos`, `test_macos`, `launch_mac_app`, `stop_mac_app`
   - **Coverage:** `get_coverage_report`, `get_file_coverage`
   - **Debugging:** `debug_attach_sim`, `debug_breakpoint_add`, `debug_breakpoint_remove`, `debug_continue`, `debug_detach`, `debug_lldb_command`, `debug_stack`, `debug_variables`
   - **UI Automation:** `tap`, `swipe`, `type_text`, `screenshot`, `snapshot_ui`
   - **Session Management:** `session_show_defaults`, `session_set_defaults`, `session_clear_defaults`
   - **Project Discovery:** `discover_projs`, `list_schemes`, `show_build_settings`

4. **Use `xcode-tools` for:**
   - SwiftUI previews (`RenderPreview`)
   - Live diagnostics (`XcodeListNavigatorIssues`)
   - Build log inspection (`GetBuildLog`)
   - Code navigation (`XcodeRead`, `XcodeGrep`)
   - Documentation (`DocumentationSearch`)
   - Code snippets (`ExecuteSnippet`)
   - Quick ad-hoc test runs during active development (`RunAllTests`, `RunSomeTests`)

5. **Tuist generates, MCP executes.** After editing `Project.swift`, run `tuist generate`. Then use MCP tools to build/test.

6. **Session defaults first.** Before the first build/test in a session, verify defaults: `session_show_defaults`. Set workspace, scheme, and simulator/device if missing.

7. **Device builds require MCP.** Physical device deployment via raw `xcodebuild` will fail due to Keychain security blocking. **Always** use `build_device` or `build_run_device`.
