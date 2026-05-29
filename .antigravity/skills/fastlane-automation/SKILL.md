---
name: fastlane-automation
description: Automation guidelines for building, deploying, and signing the iOS and macOS app.
---

# Fastlane Automation for GemmaEdgeGallery

Use Fastlane as the primary CI/CD and build tool for this project to ensure reproducible builds and avoid Xcode UI reliance.

## Code Signing & Free Accounts
This project uses a Free Personal Developer Team (`ASX83B274M`). 
- **Do not attempt** to use `fastlane match` or `fastlane sigh` to generate profiles, as free accounts do not have access to the Developer Portal APIs.
- Code signing relies on local automatic provisioning. The user must manually "Trust" the device and generate the profile once via Xcode UI.
- Once generated, Fastlane can build using `CODE_SIGNING_ALLOWED=YES` or `NO` depending on the target destination (device vs simulator).

## Fastlane Usage
When building or deploying the app, prefer running Fastlane lanes over manual `xcodebuild` commands.

### iOS Simulator
To build and test for the iOS simulator, use:
```bash
fastlane ios build
```
*(Or the equivalent `deploy_to_simulator` lane if available in Fastfile).*

### macOS App
To build the macOS app, use:
```bash
fastlane mac build
```

Always rely on Fastlane for heavy compilation to ensure the correct workspace and schemes (`GemmaEdgeGallery.xcworkspace`) are used consistently.

## Tool Responsibility Boundary

> **IMPORTANT**: Fastlane's role is limited to **build and distribution** only.
>
> - **Fastlane DOES**: Build iOS/macOS apps, manage code signing, create distribution builds
> - **Fastlane DOES NOT**: Run tests, parse test results, or execute performance benchmarks
> - **Test execution** is handled by the XcodeBuildMCP server (`xcodebuildmcp`). See the `xcode-build-mcp` and `performance-testing` skills.
> - **Do NOT** create Fastlane test lanes (e.g., `lane :test` or `lane :performance_test`). Use XcodeBuildMCP's `test` and `getTestResults` tools instead.
