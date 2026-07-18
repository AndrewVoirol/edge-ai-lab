---
name: code-safety
description: Swift code safety patterns for JSONSerialization crashes, NSExpression vulnerabilities, SwiftUI didSet cascades, TextField submit behavior, notification timing, and FlowDrivenUITestRunner wait conditions. Activate when working with JSON serialization, math expressions, SwiftUI state management, or UI test flow files.
---

# Code Safety Patterns

## JSONSerialization Safety

- `JSONSerialization` throws `NSInvalidArgumentException` (ObjC exception) for non-finite `Double` values (Infinity, NaN). Swift `try?`/`try`/`catch` **cannot** catch ObjC exceptions — they crash the process.
- Always validate/sanitize `Double`/`Float` values before passing dictionaries to `JSONSerialization.data(withJSONObject:)`.
- Prefer `JSONEncoder` (Swift) which throws catchable `EncodingError` for non-finite values.
- Use `value.isFinite` guard before any `JSONSerialization` call that might contain computed numeric values.

## NSExpression Safety

- `NSExpression(format:)` interprets `%` as an Objective-C format specifier, throwing an uncatchable `NSInvalidArgumentException`. Swift `try`/`catch` **cannot** catch this.
- Never pass user-provided or model-generated strings directly to `NSExpression(format:)`. Sanitize first: convert `15%` → `(15/100)`, reject non-mathematical text (`of`, `==`, `is`), and whitelist allowed characters.
- `CalculatorTool.swift` applies this pattern — use it as reference.

## SwiftUI didSet Cascade Prevention

- When bulk-syncing multiple properties that have `didSet` side-effects (e.g., engine re-initialization), use a guard flag (e.g., `isSyncingSettings`) to suppress the side-effects during the sync block. Set the flag before the first assignment, clear it after the last, then perform any needed side-effect once. Without this, each assignment triggers the side-effect independently, causing redundant work and UI state flip-flopping.

## SwiftUI TextField Send on iOS

- `TextField(axis: .vertical)` with `lineLimit(1...N)` does NOT reliably fire `.onSubmit` on iOS — the return key inserts a newline instead. `.submitLabel(.send)` only changes the key's label.
- To implement "Return = Send" on iOS multi-line TextFields, use a `.onChange(of: text)` interceptor that detects a trailing newline, strips it, and calls the submit action. Keep `.onSubmit` as a fallback for edge cases where it does fire.
- On macOS, the return key correctly inserts newlines in multi-line fields; use Cmd+Enter for send.

## SwiftUI Notification Timing

- A parent view's `.onAppear` fires BEFORE conditionally-displayed child views are created. Notifications posted from parent `.onAppear` will NOT be received by children that appear later (e.g., gated by `if someState`). To reliably reach a child view, either:
  (a) Post from the child's own `.onAppear`, or
  (b) Set `@FocusState`/`@State` directly on the child rather than relying on notifications.
- This is especially relevant for keyboard dismissal: posting `.dismissKeyboardRequested` from a container `onAppear` doesn't reach `InputAreaView` if it's conditionally inserted.

## FlowDrivenUITestRunner Wait Conditions

- The `wait` action in flow JSON files only supports two condition types: `element_exists:<identifier>` and `element_not_exists:<identifier>`.
- There is NO `element_exists_any` condition for `wait`. If you need to wait for one of several elements, pick the most reliable single element (e.g., a container identifier that wraps all variants).
- The `verify_ui` action supports both `expected_elements` (all must exist) and `expected_elements_any` (at least one must exist). Do not confuse `verify_ui` capabilities with `wait` capabilities.

## Swift Testing @Suite Serialization

- Any `@Suite` whose tests read/write shared mutable state (singletons, global flags, shared file paths) **MUST** use `@Suite("Name", .serialized)`. Swift Testing runs `@Test` functions concurrently by default — without `.serialized`, tests on a shared singleton will interfere with each other, producing intermittent failures that only appear on slower platforms (iOS Simulator).
- `.serialized` only serializes within a single suite. Cross-suite singletons still race — use unique instances per test when possible.

## AsyncStream Test Patterns

- When testing `AsyncStream`-based event buses, **start iterating streams (via `for await` in separate `Task`s) BEFORE emitting events**. Sequential emit-then-iterate drops events because the consumer isn't demanding elements yet.
- Correct pattern:
  ```swift
  let task1 = Task<Event?, Never> { for await e in stream1 { return e }; return nil }
  try? await Task.sleep(nanoseconds: 50_000_000) // let for-await register
  bus.emit(event)
  bus.unsubscribe(id: id1)
  let result = await task1.value // non-nil
  ```
- Incorrect pattern:
  ```swift
  bus.emit(event)          // nobody iterating yet — event may be dropped
  bus.unsubscribe(id: id1) // stream finished before iteration starts
  for await e in stream1 { ... } // count == 0
  ```

## @ToolParam Property Wrapper Decodable Gotcha

- Swift's auto-synthesized `Decodable` for structs with `@ToolParam` property wrappers expects **ALL keys** to be present in the JSON, even non-required ones with default values. If a key is missing entirely, Swift throws `DecodingError.keyNotFound` before `ToolParam`'s `init(from:)` can apply its default — the property wrapper's decoder is never invoked.
- This means when a model omits an optional argument (e.g., calling `get_current_datetime` without `timezone`), the tool dispatch fails with a `DecodingError` even though the parameter has `var timezone: String = ""`.
- **Fix pattern:** In `ToolToAppToolAdapter.executeClosure`, inject type-appropriate defaults for any non-required parameter missing from the model's arguments BEFORE calling `JSONDecoder.decode()`:
  ```swift
  for (key, paramInfo) in paramTypes where !requiredParams.contains(key) {
      if coerced[key] == nil {
          switch paramInfo.type {
          case "string": coerced[key] = ""
          case "number": coerced[key] = 0.0
          case "integer": coerced[key] = 0
          case "boolean": coerced[key] = false
          default: coerced[key] = ""
          }
      }
  }
  ```
- The `isRequired` property on `ToolParamProtocol` correctly returns `false` for params with defaults, so the schema marks them as non-required. The issue is purely in the JSON decode step.
- **When adding new tools with optional parameters:** Verify they work when the model omits the parameter by testing with empty args `[:]`. The `ToolToAppToolAdapter` now handles this, but custom tool execution paths may not.

## Tool Argument Type Coercion

- LLMs frequently emit all argument values as strings (e.g., `"3"` instead of `3`). `ToolToAppToolAdapter` coerces string arguments to their schema-declared types before JSON decoding:
  - `"number"` params: `Double(stringValue)` 
  - `"integer"` params: `Int(stringValue)`
- Without coercion, `JSONDecoder` throws `DecodingError.typeMismatch` when a `@ToolParam var value: Double` receives `"3"` instead of `3`.
- When adding custom tool execution paths outside `ToolToAppToolAdapter`, implement the same coercion pattern.
