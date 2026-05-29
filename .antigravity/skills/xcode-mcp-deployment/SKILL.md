---
name: XcodeBuildMCP Deployment
description: Standardized loop for headless testing and physical device deployment using XcodeBuildMCP.
---

# XcodeBuildMCP Automation

This project relies heavily on the **XcodeBuildMCP** server to interact with physical iOS devices, simulators, and Xcode IDE instances headlessly.

## Rules for Device Deployment
- Do **not** run generic `xcodebuild -destination "id=..."` commands in your terminal to deploy to a physical device. macOS Keychain security blocks raw `xcodebuild` CLI processes from generating App Development provisioning profiles.
- **Instead**, use the MCP tools:
  1. `xcodebuildmcp device list` to find the target UDID.
  2. `xcodebuildmcp device build-and-run --scheme=GemmaEdgeGallery_iOS --workspace-path=GemmaEdgeGallery.xcworkspace --device-id=UUID` to deploy.
- Note: This works because `XcodeBuildMCP` hooks into the cached Xcode credentials.

## When to use Simulators vs Physical Devices
- **Simulators** (`xcodebuildmcp simulator list`): Good for basic UI/UX testing. However, LiteRT-LM inference performance is not representative of real-world hardware.
- **Physical Devices**: Mandatory for validating CoreML/Metal GPU acceleration with the LiteRT-LM engine.
