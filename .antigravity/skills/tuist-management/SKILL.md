---
name: tuist-management
description: Strict guidelines for managing the Xcode project through Tuist.
---

# Tuist Management for GemmaEdgeGallery

When working on this project, adhere strictly to the following rules regarding Xcode project management.

## 🚫 NEVER Edit `.xcodeproj` or `.xcworkspace` Manually
The `.xcodeproj` and `.xcworkspace` files are **generated** artifacts. You must NEVER use `XcodeWrite`, `replace_file_content`, or any manual file editing tools to alter `GemmaEdgeGallery.xcodeproj` or any of its internal `.pbxproj` files.

## ✅ ALWAYS Use `Project.swift`
All structural changes to the project must be made by editing `Project.swift`. This includes:
- Adding or removing Targets.
- Modifying Bundle Identifiers (e.g., `com.andrewvoirol.GemmaEdgeGallery`).
- Changing Deployment Targets (e.g., `iOS("26.5")`).
- Updating Info.plist settings (e.g., `UILaunchScreen` configurations, Privacy descriptions).
- Adding or removing Package Dependencies (e.g., `LiteRT-LM`).
- Updating Build Settings (e.g., `DEVELOPMENT_TEAM`, `CODE_SIGN_STYLE`).

## Execution Workflow
After making **any** change to `Project.swift`, you MUST execute the following command in the terminal to regenerate the project:
```bash
tuist generate
```
Do not attempt to build the project until `tuist generate` has completed successfully.
