---
name: macos-swiftui
description: "Guidelines and best practices for building native SwiftUI apps for macOS. Includes Apple Human Interface Guidelines (HIG) adherence and macOS-specific text/window behaviors. Activate when designing or modifying macOS UI."
---

# macOS SwiftUI Development Guidelines

When developing cross-platform SwiftUI for macOS, strict adherence to Apple's Human Interface Guidelines (HIG) ensures the application feels like a premium, native macOS citizen rather than a ported iPad app.

## 1. Application Window Archetypes (HIG)

macOS differentiates sharply between settings, main views, and auxiliary feature views.

### Main App Window (`WindowGroup`)
- The primary interface. Should be resizable and support standard macOS window controls (traffic lights).
- Use `ToolbarItem(placement: .principal)` cautiously, as macOS truncates toolbars easily when windows are resized.

### Settings / Preferences (`Settings`)
- **Must** be implemented using the `Settings` scene in the App entry point.
- **Behavior**: Opens as a non-resizable, standalone modal via the App Menu or `Cmd+,`.
- **UI Paradigm**: macOS expects settings to apply instantly. **Never** include a "Save" or "Done" button on a macOS Settings window.

### Feature Dashboards
- Auxiliary views (like a Performance Dashboard) should be secondary `WindowGroup` scenes or presented as `.sheet` overlays, not crammed into the Settings modal.

## 2. Text Input & Multi-line Fields

When building chat interfaces or code editors, preserving native macOS keyboard paradigms is critical.

### The `.onSubmit` Trap
In SwiftUI, attaching an `.onSubmit { ... }` modifier to a `TextField` (even with axis: `.vertical`) forces the control to consume the `Enter` / `Return` key entirely, breaking the user's ability to create multi-line paragraphs.

**Correct Approach for Chat Prompts**:
1. Remove `.onSubmit` entirely.
2. Allow native `Enter` to create new lines naturally.
3. Attach a `keyboardShortcut(.return, modifiers: .command)` to the "Send" button so users can dispatch the prompt with `Cmd+Enter`.

## 3. View State vs. Business Logic

macOS XCTest and the Accessibility Engine aggressively introspect the SwiftUI view tree. 
- Avoid placing deep text parsing (like Markdown chunking) or heavy synchronous data transformations directly inside `.onChange` or `body` properties.
- **Failure Mode**: The Accessibility Engine triggers continuous view invalidation, causing `XCTest` to crash or time out.
- **Fix**: Sequester heavy state manipulation in `@MainActor Observable` view models. The SwiftUI view should act purely as a dumb renderer.
