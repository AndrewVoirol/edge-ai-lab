---
name: Tuist Workflow
description: Rules for managing the Xcode project lifecycle using Tuist in the Gemma Edge Gallery project.
---

# Tuist Workflow Rules

This project uses **Tuist** for Xcode project generation to maintain a clean and declarative infrastructure.

## CRITICAL RULES
1. **NEVER manually edit the `.xcodeproj` or `.xcworkspace` files.** Any changes made to the Xcode project structure (e.g., adding files, changing deployment targets, linking frameworks) will be immediately overwritten on the next `tuist generate`.
2. **Always edit `Project.swift`** at the root of the workspace to make structural changes.
3. **Run `tuist generate`** immediately after modifying `Project.swift` to regenerate the workspace.

## Code Signing
- The project is configured with a Personal Team ID: `ASX83B274M`. 
- This ID is hardcoded in `Project.swift`. Do **not** remove it or replace it with an empty string, otherwise physical device deployment will fail validation.
- `CODE_SIGN_STYLE` is set to `Automatic` by default.

## Adding Files
When you create a new Swift file in the `Sources/` or `Tests/` directories, it is not automatically added to the active Xcode project. You must run `tuist generate` for the new files to be included in the build graph.
