# Build Tool Boundaries

This project uses a specific build toolchain. Follow these boundaries at all times.

## Build Stack
- **Tuist** — Project generation only (`tuist generate`)
- **XcodeBuildMCP** (`xcodebuild-mcp` MCP server) — All builds, tests, deployment, coverage, debugging
- **Apple xcode-tools** (`xcode-tools` MCP server) — IDE integration only (previews, diagnostics, code nav, documentation)

## Rules

1. **Never use raw `xcodebuild` CLI commands** when MCP tools are available. Use `xcodebuild-mcp` tools instead — they provide structured output and integrate with automation hooks.

2. **Never use Fastlane.** Fastlane has been removed from this project. If you see references to `fastlane` commands, they are outdated.

3. **Use `xcodebuild-mcp` for:**
   - Building (`simulator build`, `device build`, `macos build`)
   - Testing (`simulator test`, `device test`, `macos test`)
   - Deployment (`device build-and-run`)
   - Coverage (`get-coverage-report`)
   - Debugging (`attach`, `add-breakpoint`, `variables`)

4. **Use `xcode-tools` for:**
   - SwiftUI previews (`RenderPreview`)
   - Live diagnostics (`XcodeListNavigatorIssues`)
   - Code navigation (`XcodeRead`, `XcodeGrep`)
   - Documentation (`DocumentationSearch`)
   - Code snippets (`ExecuteSnippet`)
   - Quick ad-hoc test runs during active development (`RunAllTests`, `RunSomeTests`)

5. **Tuist generates, MCP executes.** After editing `Project.swift`, run `tuist generate`. Then use MCP tools to build/test.
