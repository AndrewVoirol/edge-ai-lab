---
name: ui-ux-testing
description: "Guidelines for implementing UI tests, maintaining accessibility identifiers, and following TDD for UX changes. Activate when making UI changes or fixing UI bugs."
---

# UI/UX Testing & Accessibility Guidelines

This project heavily relies on `XCTest` and the macOS `XCUIApplication` orchestrator for UI automation. Every interactive element must be discoverable and testable programmatically to prevent regressions.

## 1. Accessibility Identifiers

Every interactive component MUST have a unique `.accessibilityIdentifier()`. 

- **Buttons**: `button_saveToken`, `button_closeShowcase`, `button_deleteModel_[filename]`
- **Toggles**: `toggle_useGPU`, `toggle_enableToolCalling`
- **Sliders/Steppers**: `slider_topP`, `stepper_topK`
- **Text/Secure Fields**: `textField_prompt`, `secureField_hfToken`
- **Views/ScrollViews**: `view_modelShowcase`
- **Dynamic Elements**: Use interpolation for list items (e.g., `modelCard_\(model.filename)`).

> [!WARNING]
> Never complete UI features without adding these identifiers. Unmarked elements are invisible to automated test scripts.

## 2. Test Execution & Automation Harness

UI tests run with a special launch argument to prevent auto-loading cached states which can cause non-deterministic test behavior:

```swift
let app = XCUIApplication()
app.launchArguments = ["-RunAutomationHarness"]
app.launch()
```

When building TDD UI tests, place them in `UITests/GemmaEdgeGalleryUITests.swift`.

## 3. Best Practices for XCUI

- **Toggles / Switches**: In macOS XCTest, `Toggle` elements appear as `app.switches`. It is often easiest to detect if dependent UI is visible (e.g., waiting for an expanded menu) rather than relying on `.value`, or to click it if the dependent UI is missing (`!button.waitForExistence(timeout: 1.0)`).
- **Dynamic UI**: If a button (like "Add MCP Server") only appears when a toggle is on, your test must ensure the toggle is flipped before waiting for the button. Use `.waitForExistence(timeout: 2.0)` to handle SwiftUI animations gracefully.
- **Disabled States**: Verify that elements correctly disable during processing using `!button.isEnabled`. For example, verifying that the `button_send` is disabled while `viewModel.isGenerating == true`.
- **Modals/File Pickers**: macOS `NSOpenPanel` or file dialogs run out of process. You can dismiss them by sending the escape key: `app.typeKey(.escape, modifierFlags: [])`.

## 4. Automation Resiliency (macOS Sandboxing)

macOS apps run in a strict sandbox. When testing features that access the filesystem (e.g., `Documents` directory scans on launch), macOS throws "Allow access" system alerts which will block automation scripts.

**Rule**: Always include an interruption monitor in your XCTest `setUpWithError()`:
```swift
addUIInterruptionMonitor(withDescription: "System Dialog") { alert in
    let allowButton = alert.buttons["Allow"]
    if allowButton.exists {
        allowButton.click()
        return true
    }
    return false
}
```

## 5. Test Orchestration

Always run UI tests via `xcodebuild-mcp` to ensure comprehensive structured results.

```text
Server: xcodebuild-mcp
Tool: test_macos
Args: scheme=GemmaEdgeGallery_macOS
```
