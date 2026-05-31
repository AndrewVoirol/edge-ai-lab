# Workflow Discipline

These rules ensure safe, recoverable workflows during agent-assisted development.

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
> iOS device testing via `xcodebuild` CLI has known stability issues. Follow these precautions.

### Pre-flight Checks
1. Ensure the device is **unlocked** and the screen is on
2. Stop any active Xcode debug sessions (press ⏹ in Xcode) before running CLI tests
3. Verify the app is installed: `xcrun devicectl device install app --device <UUID> <app-path>`
4. The app must be trusted on the device (no "Untrusted Developer" dialogs)

### Known CLI Test Pitfalls
- `xcodebuild test-without-building` can hang silently during "device preparation" — kill and retry if no output after 2 minutes
- The host app's `onAppear` fires when the test runner launches it — any auto-loading logic (like `checkForLocalModels()`) competes with test engine instances for GPU resources
- After a crash, the test runner may restart the app but find 0 tests — this is expected (tests are marked as failed from the first launch)
- Use `xcodebuild test` (build+test) if `test-without-building` hangs — it handles device preparation more reliably

### Context Accumulation in Single-Conversation Tests
When reusing a single `Conversation` across multiple inference runs:
- Context grows with each turn (prompt + response accumulates)
- Run 3+ can crash with `Token id X is out of range. Vocab size is Y` — a context overflow
- **Fix**: Create a new `Conversation` per run (keep the same `Engine`) instead of reusing one conversation
