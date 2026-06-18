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

## Code Style
- Use `@Observable` (not `ObservableObject`) — Swift 5.9+ Observation framework.
- Environment injection via `.environment(viewModel)` — no singletons.
- All UI elements must have `.accessibilityIdentifier()` for test automation.
