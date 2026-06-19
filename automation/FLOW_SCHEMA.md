# Flow JSON Schema Reference

> **Version:** 1.0  
> **Last Updated:** 2026-06-18  
> **Consumers:** `FlowDrivenUITestRunner` (macOS: `UITests/`, iOS: `iOSUITests/`)

This document defines the JSON schema for automation flow files consumed by the `FlowDrivenUITestRunner`. Both the macOS and iOS runners share the same schema, with minor platform-specific differences noted below.

---

## Table of Contents

- [Overview](#overview)
- [File Location](#file-location)
- [Top-Level Schema](#top-level-schema)
- [Step Schema](#step-schema)
- [Step Types Reference](#step-types-reference)
  - [verify_ui](#verify_ui)
  - [tap](#tap)
  - [type_text](#type_text)
  - [wait](#wait)
  - [keyboard_shortcut](#keyboard_shortcut)
  - [scroll_to](#scroll_to)
  - [navigate_tab](#navigate_tab)
  - [open_sheet](#open_sheet)
  - [dismiss_sheet](#dismiss_sheet)
  - [verify_not_exists](#verify_not_exists)
  - [verify_enabled](#verify_enabled)
  - [verify_value](#verify_value)
  - [tap_first_match](#tap_first_match) *(iOS only)*
  - [tap_if_exists](#tap_if_exists) *(iOS only)*
  - [screenshot](#screenshot) *(iOS only)*
- [Post-Step Assertions](#post-step-assertions)
- [Element Resolution Strategy](#element-resolution-strategy)
- [Platform Differences](#platform-differences)
- [Environment Variable Interpolation](#environment-variable-interpolation)
- [Complete Examples](#complete-examples)

---

## Overview

Flow JSON files are declarative test scripts that describe a sequence of UI interactions and verifications. They are executed by `FlowDrivenUITestRunner`, which translates each step into `XCUIElement` queries. This is **Path 2** of the dual-path automation strategy:

| Path | Runner | Resolution |
|------|--------|------------|
| Path 1 (in-app) | `AutomationFlowRunner` | `AccessibilityTreeInspector` |
| Path 2 (XCUITest) | `FlowDrivenUITestRunner` | `XCUIElement` queries |

Both paths consume the same flow JSON files.

## File Location

```
automation/flows/ui/          ← XCUITest flow files (primary)
automation/flows/             ← Fallback search location
```

### Naming Convention

```
<platform>_<feature>_flow.json
```

Examples:
- `macos_settings_flow.json`
- `ios_smoke_flow.json`
- `macos_url_import_flow.json`

---

## Top-Level Schema

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `name` | `String` | ✅ | Human-readable name of the flow |
| `description` | `String` | ✅ | Detailed description of what the flow tests. Should reference the test methods it maps to. |
| `platform` | `String` | Recommended | Target platform: `"macOS"` or `"iOS"`. Used for documentation; the runner itself uses compile-time `#if os()`. |
| `prerequisites` | `[String]` | ❌ | List of preconditions (e.g., `"model_downloaded"`, `"settings_open"`). Informational only — not enforced by the runner. |
| `steps` | `[FlowStep]` | ✅ | Ordered array of test steps to execute sequentially |

### Example

```json
{
  "name": "macOS Settings Interactions",
  "description": "Tests Settings sheet: open → navigate tabs → verify toggles → close.",
  "platform": "macOS",
  "steps": [ ... ]
}
```

---

## Step Schema

Every step in the `steps` array has the following shape:

| Field | JSON Key | Type | Required | Description |
|-------|----------|------|----------|-------------|
| Step Number | `step` | `Int` | ✅ | 1-indexed sequential step number |
| Action | `action` | `String` | ✅ | Step type (see [Step Types Reference](#step-types-reference)) |
| Description | `description` | `String` | ✅ | Human-readable description of the step's purpose |
| Target Element | `target_element` | `String` | Per-action | Accessibility identifier or label of the target element |
| Target Elements | `target_elements` | `[String]` | Per-action | Array of candidate element identifiers (for multi-match actions) |
| Value | `value` | `String` | Per-action | Text to type, screenshot filename, or expected value |
| Expected Elements | `expected_elements` | `[String]` | Per-action | Array of element identifiers that must ALL exist |
| Expected Elements Any | `expected_elements_any` | `[String]` | Per-action | Array of element identifiers where ANY ONE must exist |
| Condition | `condition` | `String` | Per-action | Wait condition string (format: `type:value`) |
| Timeout | `timeout_seconds` | `Number` | ❌ | Override default timeout (default: 5.0s) |
| Key | `key` | `String` | Per-action | Keyboard key for shortcuts |
| Modifiers | `modifiers` | `[String]` | ❌ | Key modifiers: `"command"`, `"shift"`, `"option"`, `"control"` |
| Button ID | `button_id` | `String` | ❌ | Button identifier for dismiss actions |
| Label | `label` | `String` | Per-action | Tab label for navigation |
| Expected | `expected` | `String` | Per-action | Expected value for verification |
| Max Attempts | `max_attempts` | `Int` | ❌ | Maximum scroll/swipe attempts (default: 6) |
| Assertion | `assertion` | `Object` | ❌ | Post-step assertion (see [Post-Step Assertions](#post-step-assertions)) |

---

## Step Types Reference

### `verify_ui`

Verifies that UI elements exist in the accessibility tree. Supports two modes:

- **All mode** (`expected_elements`): Every listed element must exist — fails if any are missing.
- **Any mode** (`expected_elements_any`): At least one listed element must exist — fails only if none are found.

Both modes can be combined in a single step.

| Field | Required | Notes |
|-------|----------|-------|
| `expected_elements` | ✅ (or `expected_elements_any`) | All must exist |
| `expected_elements_any` | ✅ (or `expected_elements`) | At least one must exist *(iOS runner only; see [Platform Differences](#platform-differences))* |
| `timeout_seconds` | ❌ | Per-element timeout |

```json
{
  "step": 1,
  "action": "verify_ui",
  "description": "Verify toolbar is available.",
  "expected_elements": ["button_settings", "button_newChat"]
}
```

```json
{
  "step": 2,
  "action": "verify_ui",
  "description": "Verify at least one model section is shown.",
  "expected_elements_any": ["Now Running", "On This Device", "Get More Models"]
}
```

---

### `tap`

Taps/clicks an element. Uses `resolveElement()` for multi-strategy lookup. Falls back to coordinate-based tap if the element exists but is not hittable.

| Field | Required | Notes |
|-------|----------|-------|
| `target_element` | ✅ | Accessibility identifier or label |
| `timeout_seconds` | ❌ | Element resolution timeout |

```json
{
  "step": 2,
  "action": "tap",
  "description": "Open settings sheet.",
  "target_element": "button_settings"
}
```

---

### `type_text`

Types text into a text field. Supports environment variable interpolation (`$VAR_NAME`).

| Field | Required | Notes |
|-------|----------|-------|
| `target_element` | ✅ | Text field identifier |
| `value` | ✅ | Text to type. `$ENV_VAR` patterns are interpolated. |
| `timeout_seconds` | ❌ | Element resolution timeout |

```json
{
  "step": 7,
  "action": "type_text",
  "description": "Enter a HuggingFace URL.",
  "target_element": "urlImport_urlField",
  "value": "https://huggingface.co/google/gemma-3n-E2B-it-litert-preview"
}
```

---

### `wait`

Waits for a condition to be met, or simply pauses for a duration.

**With condition** — polls until the condition is satisfied or times out:

| Condition Format | Description |
|-----------------|-------------|
| `element_exists:<identifier>` | Wait until element appears |
| `element_not_exists:<identifier>` | Wait until element disappears |

**Without condition** — simple delay for UI stabilization (iOS runner only):

| Field | Required | Notes |
|-------|----------|-------|
| `condition` | ❌ | Condition string. If omitted, acts as a simple delay. |
| `timeout_seconds` | ✅ | Timeout in seconds (also used as delay duration when no condition) |

```json
{
  "step": 3,
  "action": "wait",
  "description": "Wait for settings sheet to appear.",
  "condition": "element_exists:button_doneSettings",
  "timeout_seconds": 5
}
```

```json
{
  "step": 11,
  "action": "wait",
  "description": "Wait for UI to stabilize.",
  "timeout_seconds": 3
}
```

---

### `keyboard_shortcut`

Presses a keyboard shortcut. **macOS only** — skipped silently on iOS.

| Field | Required | Notes |
|-------|----------|-------|
| `key` | ✅ | Key character or special key name |
| `modifiers` | ❌ | Array of modifier names (default: `[]`) |

**Special key names:** `escape`/`esc`, `return`/`enter`, `tab`, `delete`/`backspace`, `space`, `up`, `down`, `left`, `right`

**Modifier names:** `command`/`cmd`, `shift`, `option`/`alt`, `control`/`ctrl`

```json
{
  "step": 2,
  "action": "keyboard_shortcut",
  "description": "Press ⌘I to open URL Import sheet.",
  "key": "i",
  "modifiers": ["command"]
}
```

---

### `scroll_to`

Scrolls until the target element becomes visible. Uses coordinate-based drag on macOS, `swipeUp()` on iOS.

| Field | Required | Notes |
|-------|----------|-------|
| `target_element` | ✅ | Element identifier to scroll into view |
| `max_attempts` | ❌ | Max scroll attempts (default: 6) |

```json
{
  "step": 5,
  "action": "scroll_to",
  "description": "Scroll down to find the MCP server toggle.",
  "target_element": "toggle_mcpServer",
  "max_attempts": 8
}
```

---

### `navigate_tab`

Navigates to a settings tab by label. Resolution order:
1. Radio button (macOS SwiftUI `TabView` renders tabs as radio buttons)
2. Button
3. Broad label search

On iOS, searches the tab bar buttons.

| Field | Required | Notes |
|-------|----------|-------|
| `label` | ✅ (or `target_element`) | Tab label text |
| `target_element` | ✅ (or `label`) | Fallback if `label` is not specified |

```json
{
  "step": 4,
  "action": "navigate_tab",
  "description": "Navigate to the Sampler tab.",
  "target_element": "Sampler"
}
```

---

### `open_sheet`

Opens a modal sheet by tapping the trigger element. Functionally identical to `tap` — exists for semantic clarity in flows.

| Field | Required | Notes |
|-------|----------|-------|
| `target_element` | ✅ | Trigger button identifier |
| `timeout_seconds` | ❌ | Element resolution timeout |

```json
{
  "step": 3,
  "action": "open_sheet",
  "description": "Open the model details sheet.",
  "target_element": "button_modelDetails"
}
```

---

### `dismiss_sheet`

Dismisses a modal sheet. If `button_id` or `target_element` is provided, taps that button. Otherwise sends Escape (macOS).

| Field | Required | Notes |
|-------|----------|-------|
| `button_id` | ❌ | Close button identifier (preferred) |
| `target_element` | ❌ | Fallback if `button_id` not set |

```json
{
  "step": 10,
  "action": "dismiss_sheet",
  "description": "Dismiss the URL Import sheet.",
  "target_element": "urlImport_done"
}
```

---

### `verify_not_exists`

Asserts that an element does **NOT** exist in the accessibility tree.

| Field | Required | Notes |
|-------|----------|-------|
| `target_element` | ✅ | Element that should be absent |

```json
{
  "step": 11,
  "action": "verify_not_exists",
  "description": "Verify URL Import sheet is dismissed.",
  "target_element": "urlImport_urlField"
}
```

---

### `verify_enabled`

Asserts that an element exists **and** is enabled (interactive).

| Field | Required | Notes |
|-------|----------|-------|
| `target_element` | ✅ | Element to check |
| `timeout_seconds` | ❌ | Resolution timeout |

```json
{
  "step": 6,
  "action": "verify_enabled",
  "description": "Verify the send button is enabled.",
  "target_element": "button_send"
}
```

---

### `verify_value`

Asserts that an element's accessibility value matches an expected string.

| Field | Required | Notes |
|-------|----------|-------|
| `target_element` | ✅ | Element to check |
| `expected` | ✅ (or `value`) | Expected accessibility value string |
| `value` | ✅ (or `expected`) | Fallback for expected value |
| `timeout_seconds` | ❌ | Resolution timeout |

```json
{
  "step": 8,
  "action": "verify_value",
  "description": "Verify temperature slider is at default.",
  "target_element": "slider_temperature",
  "expected": "0.8"
}
```

---

### `tap_first_match`

> **iOS runner only.** Not supported by the macOS runner.

Taps the first matching element from a list of candidates. Useful for dynamic content where exact identifiers are unknown (e.g., model cards).

| Field | Required | Notes |
|-------|----------|-------|
| `target_elements` | ✅ (or `expected_elements` or `target_element`) | Ordered list of candidates to try |
| `timeout_seconds` | ❌ | Per-candidate resolution timeout |

Falls back to tapping the first cell in a collection/table if no candidates match.

```json
{
  "step": 4,
  "action": "tap_first_match",
  "description": "Tap the first available model card.",
  "target_elements": ["Gemma 4 E2B", "Gemma 4 E4B", "Gemma 4 12B"],
  "timeout_seconds": 5
}
```

---

### `tap_if_exists`

> **iOS runner only.** Not supported by the macOS runner.

Taps an element if it exists, otherwise skips silently. Used for optional UI elements (e.g., onboarding screens that may not appear).

| Field | Required | Notes |
|-------|----------|-------|
| `target_element` | ✅ | Element to conditionally tap |
| `timeout_seconds` | ❌ | Resolution timeout |

```json
{
  "step": 7,
  "action": "tap_if_exists",
  "description": "Dismiss detail view if close button is available.",
  "target_element": "Close",
  "timeout_seconds": 3
}
```

---

### `screenshot`

> **iOS runner only.** Not supported by the macOS runner.

Captures a screenshot and attaches it to the test results.

| Field | Required | Notes |
|-------|----------|-------|
| `value` | ❌ | Custom filename (auto-generated if omitted) |

```json
{
  "step": 5,
  "action": "screenshot",
  "description": "Capture the model detail view.",
  "value": "model_detail_view"
}
```

---

## Post-Step Assertions

Any step can include an optional `assertion` object that runs **after** the step's primary action completes.

### Assertion Schema

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `type` | `String` | ✅ | Assertion type (see below) |
| `element` | `String` | Per-type | Target element identifier |
| `expected` | `String` | Per-type | Expected value for comparison |

### Assertion Types

| Type | Required Fields | Description |
|------|----------------|-------------|
| `element_exists` | `element` | Asserts the element exists in the accessibility tree |
| `element_value_contains` | `element`, `expected` | Asserts the element's value contains the expected string (case-insensitive) |
| `element_value_equals` | `element`, `expected` | Asserts the element's value exactly equals the expected string |

### Example

```json
{
  "step": 5,
  "action": "tap",
  "description": "Toggle the benchmark flag.",
  "target_element": "toggle_enableBenchmark",
  "assertion": {
    "type": "element_exists",
    "element": "toggle_enableBenchmark"
  }
}
```

```json
{
  "step": 8,
  "action": "type_text",
  "description": "Enter a temperature value.",
  "target_element": "textField_temperature",
  "value": "0.9",
  "assertion": {
    "type": "element_value_equals",
    "element": "textField_temperature",
    "expected": "0.9"
  }
}
```

---

## Element Resolution Strategy

The `resolveElement()` function uses a 3-strategy waterfall to find elements:

| Priority | Strategy | Predicate | Timeout |
|----------|----------|-----------|---------|
| 1 | Accessibility Identifier | `identifier == target` | Full `timeout_seconds` |
| 2 | Accessibility Label | `label == target` | min(timeout, 2s) |
| 3 | Partial Match | `identifier CONTAINS[cd] target OR label CONTAINS[cd] target` | min(timeout, 2s) |

> [!TIP]
> Always prefer accessibility identifiers (e.g., `button_settings`) over labels (e.g., `"Settings"`) for reliable element resolution. Labels may change with localization.

---

## Platform Differences

| Feature | macOS Runner | iOS Runner |
|---------|-------------|-----------|
| `tap` interaction | `element.click()` | `element.tap()` |
| `scroll_to` method | Coordinate-based drag or Page Down key | `swipeUp()` on scrollView/table |
| `keyboard_shortcut` | Full support | Skipped (prints warning) |
| `expected_elements_any` | ❌ Not supported | ✅ Supported |
| `tap_first_match` | ❌ Not supported | ✅ Supported |
| `tap_if_exists` | ❌ Not supported | ✅ Supported |
| `screenshot` | ❌ Not supported | ✅ Supported |
| `wait` without condition | Requires `condition` field | Acts as simple delay |
| `navigate_tab` resolution | radioButton → button → label | button (tab bar) |
| `dismiss_sheet` fallback | Sends Escape key | No-op |
| `target_elements` field | ❌ Not in model | ✅ Supported |

> [!IMPORTANT]
> When writing cross-platform flows, stick to actions supported by both runners: `verify_ui`, `tap`, `type_text`, `wait` (with condition), `scroll_to`, `navigate_tab`, `open_sheet`, `dismiss_sheet`, `verify_not_exists`, `verify_enabled`, `verify_value`.

---

## Environment Variable Interpolation

The `type_text` action supports environment variable interpolation. Variables matching `$VAR_NAME` (uppercase letters, digits, underscores) are replaced with their values from `ProcessInfo.processInfo.environment`.

```json
{
  "action": "type_text",
  "target_element": "textField_apiKey",
  "value": "$HF_API_TOKEN"
}
```

---

## Complete Examples

### Minimal Flow (iOS)

```json
{
  "name": "iOS Smoke Tests",
  "description": "Critical-path smoke tests for iOS.",
  "platform": "iOS",
  "steps": [
    {
      "step": 1,
      "action": "verify_ui",
      "description": "Verify app launched with tab bar.",
      "expected_elements": ["Models", "Chat"]
    },
    {
      "step": 2,
      "action": "tap",
      "description": "Navigate to Chat tab.",
      "target_element": "Chat"
    },
    {
      "step": 3,
      "action": "verify_ui",
      "description": "Verify Chat tab is selected.",
      "expected_elements": ["Chat"]
    }
  ]
}
```

### Complex Flow (macOS)

```json
{
  "name": "macOS Settings Persistence",
  "description": "Tests settings persist across sheet dismiss/reopen.",
  "platform": "macOS",
  "steps": [
    {
      "step": 1,
      "action": "tap",
      "description": "Open settings sheet.",
      "target_element": "button_settings"
    },
    {
      "step": 2,
      "action": "wait",
      "description": "Wait for settings sheet.",
      "condition": "element_exists:button_doneSettings",
      "timeout_seconds": 5
    },
    {
      "step": 3,
      "action": "navigate_tab",
      "description": "Navigate to the General tab.",
      "target_element": "General"
    },
    {
      "step": 4,
      "action": "verify_ui",
      "description": "Verify benchmark toggle exists.",
      "expected_elements": ["toggle_enableBenchmark"]
    },
    {
      "step": 5,
      "action": "tap",
      "description": "Toggle the benchmark flag.",
      "target_element": "toggle_enableBenchmark"
    },
    {
      "step": 6,
      "action": "tap",
      "description": "Dismiss settings.",
      "target_element": "button_doneSettings"
    },
    {
      "step": 7,
      "action": "wait",
      "description": "Wait for sheet to fully dismiss.",
      "condition": "element_not_exists:button_doneSettings",
      "timeout_seconds": 5
    },
    {
      "step": 8,
      "action": "tap",
      "description": "Reopen settings.",
      "target_element": "button_settings"
    },
    {
      "step": 9,
      "action": "wait",
      "description": "Wait for settings sheet to reappear.",
      "condition": "element_exists:button_doneSettings",
      "timeout_seconds": 5
    },
    {
      "step": 10,
      "action": "navigate_tab",
      "description": "Navigate back to General tab.",
      "target_element": "General"
    },
    {
      "step": 11,
      "action": "verify_ui",
      "description": "Verify toggle state persisted.",
      "expected_elements": ["toggle_enableBenchmark"]
    },
    {
      "step": 12,
      "action": "tap",
      "description": "Dismiss settings to clean up.",
      "target_element": "button_doneSettings"
    }
  ]
}
```

---

## Existing Flows

| File | Platform | Description |
|------|----------|-------------|
| `macos_basic_navigation_flow.json` | macOS | Basic app navigation |
| `macos_chat_interactions_flow.json` | macOS | Chat UI interactions |
| `macos_community_browser_flow.json` | macOS | Community browser |
| `macos_eval_execution_flow.json` | macOS | Evaluation execution |
| `macos_input_area_flow.json` | macOS | Input area interactions |
| `macos_mcp_server_flow.json` | macOS | MCP server configuration |
| `macos_menu_commands_flow.json` | macOS | Menu commands |
| `macos_navigation_efficiency_flow.json` | macOS | Navigation performance |
| `macos_quick_actions_flow.json` | macOS | Quick action shortcuts |
| `macos_settings_flow.json` | macOS | Settings sheet interactions |
| `macos_settings_persistence_flow.json` | macOS | Settings persistence |
| `macos_sidebar_flow.json` | macOS | Sidebar navigation |
| `macos_tool_calling_flow.json` | macOS | Tool calling UI |
| `macos_url_import_flow.json` | macOS | URL import pipeline |
| `ios_accessibility_audit_flow.json` | iOS | Accessibility audit |
| `ios_conversation_persistence_flow.json` | iOS | Conversation persistence |
| `ios_download_lifecycle_flow.json` | iOS | Download lifecycle UI |
| `ios_error_recovery_flow.json` | iOS | Error recovery / stress test |
| `ios_model_lifecycle_flow.json` | iOS | Model lifecycle management |
| `ios_navigation_efficiency_flow.json` | iOS | Navigation performance |
| `ios_onboarding_flow.json` | iOS | First-run onboarding |
| `ios_orientation_flow.json` | iOS | Orientation handling |
| `ios_smoke_flow.json` | iOS | Critical-path smoke tests |
| `ios_thinking_mode_flow.json` | iOS | Thinking mode toggle |
| `ios_url_import_flow.json` | iOS | URL import on iOS |
