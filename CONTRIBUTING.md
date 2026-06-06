# Contributing to Edge AI Lab

Thank you for your interest in contributing! This guide covers development setup, coding standards, and contribution workflow.

## Development Setup

### Prerequisites

- **Xcode 26.0+** (Swift 6.0)
- **[Tuist](https://tuist.dev)** — `brew install tuist`
- **macOS 26.0 (Tahoe)** or later

### Getting Started

```bash
git clone https://github.com/your-username/gemma-edgegallery.git
cd gemma-edgegallery
tuist generate
open GemmaEdgeGallery.xcworkspace
```

### Project Structure

```
Sources/
├── GemmaEdgeGalleryApp.swift   # App entry point
├── ContentView.swift            # Main UI
├── ConversationViewModel.swift  # MVVM ViewModel
├── InstrumentedEngine.swift     # LiteRT-LM wrapper + benchmarking
├── DesignSystem.swift           # Colors, typography, animations
├── ChatBubbleView.swift         # Chat message rendering
├── ToolRegistry.swift           # 6 built-in tools
├── ThinkingParser.swift         # <think> tag streaming parser
├── ModelMetadata.swift          # Model registry & metadata
├── MetricsStore.swift           # Persistent metrics storage
└── ...

Tests/
├── MockInstrumentedEngine.swift # Protocol-based mock
├── ChatMessageTests.swift       # Message model tests
├── ThinkingParserTests.swift    # Parser edge cases
├── ToolCallingTests.swift       # Tool execution tests
└── ...
```

## Coding Standards

### Swift 6 Concurrency

- Use `@MainActor` for all UI-related code
- Use `async/await` for all asynchronous operations
- Mark types as `Sendable` where appropriate
- Avoid `nonisolated(unsafe)` — use proper actor isolation

### Architecture

- **MVVM** with `@Observable` (not ObservableObject)
- **Protocol-based DI** via `InstrumentedEngineProtocol`
- All engine interactions go through the protocol — never access LiteRT-LM directly from views

### UI

- Use `DesignSystem.swift` tokens — never hardcode colors or fonts
- Add `.accessibilityIdentifier()` to every interactive element
- Dark-mode-first — test in dark mode by default

### Tests

- All tests must pass before submitting a PR
- Current baseline: **142+ tests** across 12 test files
- Use `MockInstrumentedEngine` for engine tests — no real model required
- Test target: `GemmaEdgeGallery_macOSTests` (macOS) or `GemmaEdgeGallery_iOSTests` (iOS)

```bash
# Run tests
xcodebuild -workspace GemmaEdgeGallery.xcworkspace \
  -scheme GemmaEdgeGallery_macOS \
  -destination 'platform=macOS' \
  test
```

## Pull Request Workflow

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/my-feature`
3. Make your changes following the coding standards above
4. Run the full test suite and ensure all tests pass
5. Submit a PR with a clear description

### PR Checklist

- [ ] All existing tests pass
- [ ] New functionality has test coverage
- [ ] No hardcoded colors/fonts — using DesignSystem tokens
- [ ] Interactive elements have accessibility identifiers
- [ ] Documentation updated if applicable

## License

By contributing, you agree that your contributions will be licensed under the Apache License 2.0.
