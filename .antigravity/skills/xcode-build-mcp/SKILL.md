---
name: XcodeBuildMCP Usage
description: Guidelines for using the Sentry XcodeBuildMCP server for headless builds, test execution, and result parsing.
---

# XcodeBuildMCP Usage

## 1. What Is XcodeBuildMCP

- Open-source MCP server by Sentry ([getsentry/XcodeBuildMCP](https://github.com/getsentry/XcodeBuildMCP))
- Configured as `xcodebuildmcp` MCP server in this project
- Wraps `xcodebuild` CLI — works headlessly, no Xcode UI required
- ~80 tools across build, test, simulator management, debugging, and UI automation

## 2. Distinction from Apple's xcode-tools MCP

| Purpose | Use `xcode-tools` (Apple) | Use `xcodebuildmcp` (Sentry) |
|---|---|---|
| Code navigation | ✅ | ❌ |
| SwiftUI previews | ✅ | ❌ |
| Documentation search | ✅ | ❌ |
| IDE diagnostics | ✅ | ❌ |
| Headless builds | ❌ | ✅ |
| Test execution | Ad-hoc only | ✅ Primary |
| Test result parsing | ❌ | ✅ (`getTestResults`) |
| Simulator management | ❌ | ✅ |
| LLDB debugging | ❌ | ✅ |

**Rule**: Use `xcode-tools` to read and navigate code. Use `xcodebuildmcp` to build, test, and deploy.

## 3. Key Tools for Performance Pipeline

- `test` — Run tests with scheme, destination, and `additionalArgs` support.
- `getTestResults` — Parse xcresult bundles for structured test data.
- `listSchemes` — Discover available schemes.
- `listDestinations` — Discover available simulators/devices.

## 4. Test Execution Pattern

```
1. Call `test` with scheme and additionalArgs: ["-resultBundlePath", "/path/to/output.xcresult"]
2. Call `getTestResults` with xcresultPath to extract structured results
3. Parse results for pass/fail and performance data
```

Do NOT use Fastlane for test execution. Fastlane is for build/distribution only.
