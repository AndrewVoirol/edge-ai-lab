# EdgeAILab Project Rules

## Build System
- This is a **Tuist-managed** project. Use `EdgeAILab.xcworkspace` (NOT `.xcodeproj`).
- macOS scheme: `"Edge AI Lab"` (with spaces). iOS scheme: `EdgeAILab_iOS`.
- Regenerate project: `tuist generate` from project root.

## Testing
- Read the `test-runner` skill before running any tests.
- **macOS UI tests require Cmd+N after launch** — see `test-runner` skill for details.
- Physical device ID: `3B50314A-0702-5188-A321-BCD5CA5F8184` (iPhone 16 Pro Max).
- All perpetual animations MUST have `XCTestConfigurationFilePath` guard.
- **Test resources don't bundle to physical iOS devices** via Tuist. Tests that load from `Bundle(for:)` must include an XCTSkip guard when the resource returns nil.
- **`generate_image` produces JPEG data with `.png` extension.** Never assert PNG magic bytes (`0x89 0x50 0x4E 0x47`). Accept both JPEG (`0xFF 0xD8 0xFF`) and PNG headers.
- **Swift Testing migration**: When creating a new `@Suite` Swift Testing file that replaces an XCTest file, add the XCTest class name to `UnitTests.xctestplan` → `skippedTests` in the same commit. Never leave both versions running simultaneously.
- **Tuist `testPlans` API**: Coverage is controlled by the `.xctestplan` JSON (`codeCoverageEnabled: true`), NOT by Tuist's `options: .options(coverage: true)`.

## Code Style
- Use `@Observable` (not `ObservableObject`) — Swift 5.9+ Observation framework.
- Environment injection via `.environment(viewModel)` — no singletons.
- All UI elements must have `.accessibilityIdentifier()` for test automation.

## Plan Execution Discipline
- **Never silently drop or rename a plan item.** If a planned deliverable can't be completed or needs to change, update the plan artifact with a `> [!WARNING]` block explaining what changed and why BEFORE marking it done.
- **Never declare "100% complete" without line-by-line verification** against the original plan text. Cross-reference every numbered item, every listed file, every specific deliverable. Use the `plan-compliance-audit` skill.
- **Never use estimated/fabricated values as deliverables** without the word "ESTIMATED" in the value itself AND the surrounding context. Prefer leaving a placeholder like `"TBD — requires controlled run"` over a fake number.
- **Subagent outputs must be spot-checked** against the original task requirements. Don't forward subagent completion claims without verifying at least: (a) the files exist, (b) they address the specific plan items, (c) they don't conflict with other work.

## JSONSerialization Safety
- `JSONSerialization` throws `NSInvalidArgumentException` (ObjC exception) for non-finite `Double` values (Infinity, NaN). Swift `try?`/`try`/`catch` **cannot** catch ObjC exceptions — they crash the process.
- Always validate/sanitize `Double`/`Float` values before passing dictionaries to `JSONSerialization.data(withJSONObject:)`.
- Prefer `JSONEncoder` (Swift) which throws catchable `EncodingError` for non-finite values.
- Use `value.isFinite` guard before any `JSONSerialization` call that might contain computed numeric values.

## Post-Edit Git Verification
- After creating or editing files, verify they appear in `git status` before claiming "done".
- For files in potentially gitignored directories (e.g., `metrics/`, `build/`, `output/`), run `git check-ignore -v <path>` to confirm tracking.
- If a new file needs tracking in a gitignored directory, add an exclusion rule (`!path/to/file`) to `.gitignore` first.
- Never use `tail -N` on streaming console output from `deploy_device.sh` — it creates zombie background tasks when the stream ends before N lines. Use `head -N` or redirect to a file instead.

