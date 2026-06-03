# Workflow Discipline

These rules ensure safe, recoverable workflows during agent-assisted development.

## Session Initialization

> [!IMPORTANT]
> **Always verify MCP session defaults before the first build or test.** Call `session_show_defaults` to confirm workspace, scheme, and simulator/device are configured.

### Rules
1. At the start of a new conversation, call `session_show_defaults` before any build/test
2. If defaults are missing, use `session_set_defaults` with:
   - `workspacePath`: `GemmaEdgeGallery.xcworkspace`
   - `scheme`: `GemmaEdgeGallery_iOS` (or `GemmaEdgeGallery_macOS`)
3. For device workflows, verify `deviceId` is set
4. The `session-init` hook runs automatically but does not set defaults — it only warns

## Commit-Before-Change

> [!IMPORTANT]
> **Always commit working state before making significant changes.** This ensures a clean rollback point if changes introduce breaking issues.

### Rules
1. Before starting a new feature or refactor, ensure the working tree is clean with a descriptive commit
2. Use descriptive commit messages that reference the implementation step when following a plan
3. After verifying a change works (builds, tests pass), commit before moving to the next step
4. If a change breaks something, revert to the last known-good commit before debugging

### Commit Message Format
```
<Type>: <Short description>

<Body explaining what changed and why>
```

Types: `Fix`, `Feature`, `Refactor`, `Test`, `Docs`, `Chore`

## Test Stability on Physical Devices

> [!WARNING]
> iOS device testing has known stability issues. Follow these precautions.

### Pre-flight Checks
1. Ensure the device is **unlocked** and the screen is on
2. Stop any active Xcode debug sessions (press ⏹ in Xcode) before running CLI tests
3. Verify device connectivity: use `list_devices` MCP tool
4. The app must be trusted on the device (no "Untrusted Developer" dialogs)
5. Always use MCP tools (`build_device`, `test_device`) — never raw `xcodebuild` for device workflows

### Device Failure Recovery
If device tests fail:
1. **First**: Kill stuck processes and retry
2. **Second**: Restart the iPhone (fixes ~90% of testmanagerd/DTDeviceKit issues)
3. **Third**: Unpair → Re-pair → Restart iPhone
4. See `.antigravity/skills/device-recovery/SKILL.md` for detailed procedures

### Known CLI Test Pitfalls
- `test_device` can hang during "device preparation" — kill and retry if no output after 2 minutes
- The host app's `onAppear` fires when the test runner launches it — any auto-loading logic competes with test engine instances for GPU resources.
- After a crash, the test runner may restart the app but find 0 tests — this is expected.
- **SwiftUI Layout watchdogs (`0x8BADF00D`)**: Synchronously calling state check methods (such as looking up model download status) inside a view rendering body can cause layout cycles/re-render storms that lock the main thread, leading to a SIGKILL by the OS watchdog. **Fix**: Store and retrieve download states via dedicated lookups on published properties (e.g. `viewModel.downloadManager.downloadStates`) rather than querying status methods synchronously during render.

### LiteRT-LM C++ Stream Cancellation & Deinit Leaks
- Calling `conversation.cancel()` stops the background inference worker thread, but the underlying C++ LiteRT-LM framework leaks the stream context (since it doesn't trigger the Swift stream callback with `isFinal = true` or `errorMessage`).
- Consequently, the `Conversation` object is leaked and can outlive the `Engine`, leading to a segmentation fault (`SIGSEGV`) when `Engine.deinit` runs.
- **Workaround**: Keep references to the engine and viewmodel elements asynchronous or leverage process-isolated runners (such as our Python runner script) to run tests in discrete lifecycles where memory cleanup is cleanly handled by the OS.

### Context Accumulation in Single-Conversation Tests
When reusing a single `Conversation` across multiple inference runs:
- Context grows with each turn (prompt + response accumulates)
- Run 3+ can crash with `Token id X is out of range. Vocab size is Y` — a context overflow
- **Fix**: Create a new `Conversation` per run (keep the same `Engine`) instead of reusing one conversation


## Stack Audit Workflow

> [!TIP]
> When performing a stack audit or SDK update, follow this procedure:

1. **Safety net**: Create a branch and tag the pre-audit state
2. **SDK update**: Run `tuist generate` to pull latest `main` HEAD, build both targets
3. **API discovery**: Read SDK source files in `DerivedData/SourcePackages/checkouts/LiteRT-LM/swift/` for new APIs
4. **Integration**: Wire new APIs through `InstrumentedEngineProtocol` → `InstrumentedEngine` → `ConversationViewModel`
5. **Protocol defaults**: Add protocol extensions for backward-compatible new parameters (Swift protocols don't inherit default values from implementations)
6. **Test expansion**: Update test plans, add new test methods, verify count assertions
7. **Automation**: Update `DeveloperAutomationHarness.swift` and `automation/run_matrix.py` with new configs
8. **Verify**: Build iOS + macOS, run full unit test suite, commit

## macOS Testing

### Rules
1. Use `build_macos` and `test_macos` MCP tools — same session defaults pattern
2. Switch scheme to `GemmaEdgeGallery_macOS` for macOS builds: `session_set_defaults` with `scheme: GemmaEdgeGallery_macOS`
3. macOS tests support both GPU and CPU backends — no simulator limitations
4. `linkd.autoShortcut` connection errors in macOS test output are noise — tests still pass, ignore them
