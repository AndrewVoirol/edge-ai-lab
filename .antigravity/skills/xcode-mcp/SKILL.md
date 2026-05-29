---
name: xcode-mcp
description: "Guidelines for using the two Xcode MCP servers: Apple xcode-tools (IDE integration) and Sentry XcodeBuildMCP (headless automation). Activate when building, testing, deploying, or debugging."
---

# Xcode MCP Architecture

This project uses **two** MCP servers for Xcode integration, each with a distinct role.

## Server Comparison

| Capability | Apple `xcode-tools` | Sentry `xcodebuild-mcp` |
|---|---|---|
| **When to use** | Active development, rapid TDD | Automated pipelines, headless builds |
| **Requires Xcode open** | ✅ Yes | ❌ No (headless via xcodebuild) |
| **Building** | `BuildProject` | `simulator build`, `device build`, `macos build` |
| **Testing** | `RunAllTests`, `RunSomeTests` | `simulator test`, `device test`, `macos test` |
| **Test Results** | In Xcode UI only | Structured JSON with `durationMs` per test |
| **Code Coverage** | ❌ | `get-coverage-report`, `get-file-coverage` |
| **Diagnostics** | `XcodeListNavigatorIssues`, `XcodeRefreshCodeIssuesInFile` | Build log filtering by severity |
| **Code Navigation** | `XcodeRead`, `XcodeWrite`, `XcodeGrep`, `XcodeGlob`, `XcodeLS` | ❌ |
| **SwiftUI Preview** | `RenderPreview` ✅ | ❌ |
| **Documentation** | `DocumentationSearch` ✅ | ❌ |
| **Code Execution** | `ExecuteSnippet` ✅ | ❌ |
| **Simulator Mgmt** | ❌ | `simulator list`, `boot`, `erase`, `screenshot`, `record-video` |
| **Device Deploy** | ❌ | `device build-and-run`, `device list`, `device install` |
| **LLDB Debugging** | ❌ | `attach`, `add-breakpoint`, `variables`, `stack`, `lldb-command` |
| **UI Automation** | ❌ | `tap`, `swipe`, `type-text`, `snapshot-ui`, `screenshot` |

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

### Sentry `xcodebuild-mcp` — Headless Automation
**Use for:** Automated build/test/deploy pipelines
- Building for simulator or device
- Running tests with structured results (JSON output with per-test duration)
- Code coverage reports
- Simulator management (boot, screenshot, record-video)
- Physical device deployment (avoids Keychain security blocking that raw `xcodebuild` hits)
- LLDB debugging sessions
- UI automation

**Does NOT require Xcode to be open.**

## Test Execution Strategy

| Context | Use This |
|---|---|
| Quick test during active coding | `xcode-tools` → `RunSomeTests` (fast, results in Xcode UI) |
| Full test suite, coverage, CI | `xcodebuild-mcp` → `simulator test` (structured results, coverage) |
| Performance test runs | `xcodebuild-mcp` → `simulator test` (metrics captured by hook) |
| Device-specific testing | `xcodebuild-mcp` → `device test` |

## Common Patterns

### Build for iOS Simulator
```
Server: xcodebuild-mcp
Tool: simulator build
Args: scheme=GemmaEdgeGallery_iOS, workspace=GemmaEdgeGallery.xcworkspace
```

### Build for macOS
```
Server: xcodebuild-mcp
Tool: macos build
Args: scheme=GemmaEdgeGallery_macOS, workspace=GemmaEdgeGallery.xcworkspace
```

### Run Unit Tests
```
Server: xcodebuild-mcp
Tool: simulator test
Args: scheme=GemmaEdgeGallery_iOS, workspace=GemmaEdgeGallery.xcworkspace, testPlan=UnitTests
```

> [!IMPORTANT]
> **Never use raw `xcodebuild` CLI** when MCP tools are available. MCP tools provide structured output, error handling, and integrate with hooks for automatic metrics capture.

> [!WARNING]
> **Physical device deployment** via raw `xcodebuild` will fail due to Keychain security blocking code signing in non-interactive sessions. Always use `xcodebuild-mcp device build-and-run` for device deployment.
