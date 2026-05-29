---
name: xcode-mcp-workflow
description: Defines the boundary and usage rules for xcode-tools MCP vs XcodeBuildMCP.
---

# Xcode MCP Workflow

This project is equipped with two Xcode-related MCPs. You must understand their boundaries and use them appropriately to maximize DX (Developer Experience).

## 1. `xcode-tools` MCP
**Purpose:** Editor-level granular context and local code navigation.

**When to use:**
- **Code Navigation:** Use `XcodeRead`, `XcodeGrep`, and `XcodeGetCurrentFile` to understand the codebase and see what the user is currently working on.
- **Diagnostics:** Use `XcodeListNavigatorIssues` and `XcodeRefreshCodeIssuesInFile` to get real-time compiler warnings and syntax errors without doing a full headless build.
- **Testing:** Use `GetTestList`, `RunAllTests`, or `RunSomeTests` for rapid test-driven development.
- **Documentation:** Use `DocumentationSearch` for Apple API lookups.

## 2. `xcodebuildmcp` (getsentry/XcodeBuildMCP)
**Purpose:** Headless workhorse for heavy builds, simulator management, and deep logs.

**When to use:**
- **Building & Simulators:** When you need to boot a specific simulator, deploy an app to it, or capture UI automation logs.
- **Deep Build Logs:** When a `fastlane` build fails and you need deep, structured logs, use XcodeBuildMCP tools to query the exact compiler failure.
- **Headless Actions:** Use this when you want to avoid interfering with the user's active Xcode UI window.
- **Test Execution Pipeline:** For automated test execution and result parsing, `xcodebuildmcp` is the primary tool. Use its `test` tool to run tests and `getTestResults` to parse xcresult bundles. See the `performance-testing` and `xcode-build-mcp` skills for detailed usage patterns.
- **Do NOT** use Fastlane for test execution. Fastlane is for build/distribution only.

**Rule of Thumb:**
Use `xcode-tools` to *read and navigate* code alongside the user. Use `xcodebuildmcp` to *build, test, and deploy*. Use Fastlane for *distribution builds* only.
