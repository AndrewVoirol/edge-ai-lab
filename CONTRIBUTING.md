# Contributing to Edge AI Lab

Thank you for your interest in contributing to Edge AI Lab! This document provides guidelines and instructions for contributing.

## Prerequisites

- **macOS 26.0+** (Tahoe)
- **Xcode 26** with Swift 6.0
- **Apple Silicon** (M1 or later) — required for on-device inference
- **[Tuist](https://tuist.dev)** — project generation tool
- **16 GB RAM minimum** (32 GB+ recommended for the 12B model)

## Getting Started

### 1. Clone the Repository

```bash
git clone https://github.com/AndrewVoirol/edge-ai-lab.git
cd edge-ai-lab
```

### 2. Set Up Code Signing

The project requires a development team for code signing. Set your team ID as an environment variable:

```bash
export DEVELOPMENT_TEAM="YOUR_TEAM_ID"
```

> **Tip:** Find your team ID in Xcode → Settings → Accounts → your Apple ID → Manage Certificates. Or run: `security find-identity -p codesigning -v`

For CI builds without signing, you can skip this — the project defaults to no team, allowing unsigned builds with `CODE_SIGNING_REQUIRED=NO`.

### 3. Generate the Xcode Project

```bash
tuist generate
```

This resolves SPM dependencies (LiteRT-LM, MarkdownUI) and generates the `.xcworkspace`.

### 4. Build and Run

Open `GemmaEdgeGallery.xcworkspace` in Xcode, select the **Edge AI Lab** scheme, and run (⌘R).

### 5. Get a Model

Download a Gemma model in `.litertlm` format from:
- The in-app Community Browser (sidebar → Models section)
- [HuggingFace litert-community](https://huggingface.co/litert-community)

Recommended for development: **Gemma 4 E2B Standard** (~2.6 GB, fastest inference).

Model files should be placed in the app's Documents directory or the project's `models/` directory (for debug builds). Both locations are gitignored.

## Project Structure

```
Sources/           # All app source code (50 Swift files)
Tests/             # Unit tests (27+ test files)
UITests/           # UI tests
RawBenchmark/      # CLI benchmark tool
automation/        # CI scripts & benchmark matrix runner
```

### Architecture

- **MVVM** with `@Observable` (Swift 6 concurrency)
- **`ConversationViewModel`** — central state management (@Environment-injected)
- **`InstrumentedEngine`** — wraps LiteRT-LM with GPU/CPU fallback + instrumentation
- **`ConversationStore`** — JSON file-based persistence
- **`DesignSystem`** — centralized design tokens (colors, typography, spacing)

### Key Files

| File | Purpose |
|------|---------|
| `ContentView.swift` | 3-column NavigationSplitView layout |
| `ConversationViewModel.swift` | Core business logic + state |
| `InstrumentedEngine.swift` | LiteRT-LM engine wrapper |
| `ModelMetadata.swift` | Model registry with capabilities |
| `DesignSystem.swift` | Design tokens and theme |
| `DeveloperAutomationHarness.swift` | Benchmark automation (launch-arg activated) |

## Dependencies

| Package | Source | Notes |
|---------|--------|-------|
| **LiteRT-LM** | `branch("main")` | Pinned to branch because tagged releases have SPM packaging issues ([Issue #2407](https://github.com/google-ai-edge/LiteRT-LM/issues/2407)). We'll migrate to a tagged release when one ships with the fix. |
| **MarkdownUI** | `v2.4.1` | Stable, pinned to next major from 2.0.0 |

## Running Tests

```bash
# Unit tests (~2 minutes)
xcodebuild test -workspace GemmaEdgeGallery.xcworkspace \
  -scheme "Edge AI Lab" \
  -only-testing:GemmaEdgeGallery_macOSTests \
  -destination 'platform=macOS,arch=arm64'

# UI tests
xcodebuild test -workspace GemmaEdgeGallery.xcworkspace \
  -scheme "Edge AI Lab" \
  -only-testing:GemmaEdgeGallery_macOSUITests \
  -destination 'platform=macOS,arch=arm64'
```

## Code Style

- **SwiftUI** for all views
- **`@Observable`** (not `ObservableObject`) for state
- **`@MainActor`** for all UI-touching code
- **Design system tokens** — use `AppColors`, `AppTypography`, `AppSpacing` instead of hardcoded values
- **Accessibility identifiers** on all interactive elements (format: `type_name`, e.g., `button_send`, `textField_prompt`)
- **`os.Logger`** for diagnostic output (not `print()`)
- **Apache 2.0 license headers** on all source files

### SwiftLint

The project includes a `.swiftlint.yml` with minimal safety-focused rules. Run it locally:

```bash
brew install swiftlint
swiftlint
```

SwiftLint also runs in CI on every push to `main`.

## Submitting Changes

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/my-feature`)
3. Make your changes
4. Ensure all tests pass
5. Run SwiftLint: `swiftlint`
6. Commit with [conventional commit](https://www.conventionalcommits.org/) messages
7. Open a Pull Request

## License

By contributing, you agree that your contributions will be licensed under the [Apache License 2.0](LICENSE).
