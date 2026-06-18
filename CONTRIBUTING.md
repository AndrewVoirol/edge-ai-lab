# Contributing to Edge AI Lab

Thank you for your interest in contributing to Edge AI Lab! This document provides guidelines and instructions for contributing.

## Prerequisites

- **macOS 26.0+** (Tahoe)
- **Xcode 26** with Swift 6
- **Apple Silicon** (M1 or later) — required for on-device inference
- **[mise](https://mise.run)** — version manager (installs Tuist automatically from `.mise.toml`)
- **16 GB RAM minimum** (32 GB+ recommended for the 12B model)

## Getting Started

### 1. Clone the Repository

```bash
git clone https://github.com/AndrewVoirol/edge-ai-lab.git
cd edge-ai-lab
```

### 2. Install Development Tools

Install [mise](https://mise.run) if you don't have it, then install Tuist (version pinned by `.mise.toml`):

```bash
# Install mise (skip if already installed)
curl https://mise.run | sh

# Install Tuist (version pinned to .mise.toml)
mise install
```

### 3. Set Up Code Signing

The project requires a development team for code signing. Set your team ID as an environment variable:

```bash
export DEVELOPMENT_TEAM="YOUR_TEAM_ID"
```

> **Tip:** Find your team ID in Xcode → Settings → Accounts → your Apple ID → Manage Certificates. Or run: `security find-identity -p codesigning -v`

For CI builds without signing, you can skip this — the project defaults to no team, allowing unsigned builds with `CODE_SIGNING_REQUIRED=NO`.

### 4. Generate the Xcode Project

```bash
tuist generate
```

This resolves SPM dependencies (LiteRT-LM, MarkdownUI) and generates the `.xcworkspace`.

### 5. Build and Run

Open `EdgeAILab.xcworkspace` in Xcode, select the **Edge AI Lab** scheme, and run (⌘R).

### 6. Get a Model

Download a Gemma model in `.litertlm` format from:
- The in-app Community Browser (sidebar → Models section)
- [HuggingFace litert-community](https://huggingface.co/litert-community)

Recommended for development: **Gemma 4 E2B Standard** (~2.4 GB, fastest inference).

Model files should be placed in the app's Documents directory or the project's `models/` directory (for debug builds). Both locations are gitignored.

## Finding Your First Issue

New to Edge AI Lab? Welcome! Here's how to find something to work on:

- **[`good first issue`](https://github.com/AndrewVoirol/edge-ai-lab/issues?q=label%3A%22good+first+issue%22+is%3Aopen)** — Well-scoped tasks achievable in under an hour. These are the best starting point for your first contribution.
- **[`help wanted`](https://github.com/AndrewVoirol/edge-ai-lab/issues?q=label%3A%22help+wanted%22+is%3Aopen)** — Larger tasks where community contributions are especially welcome. Some experience with the codebase is helpful.

**What makes a good first PR?**

1. Pick an issue (or propose a small improvement)
2. Keep the scope small — a single tool, test, or doc fix
3. Follow the [Code Style](#code-style) guidelines below
4. Include tests for any new functionality
5. Run SwiftLint and the test suite before submitting

If you're not sure where to start, the [tutorial below](#tutorial-how-to-add-a-new-built-in-tool) walks through the entire process of adding a new tool — the most common type of first contribution.

## Project Structure

```
Sources/           # App source code in feature folders (85 Swift files)
  App/             # Entry point, app delegate
  Conversation/    # ViewModel, chat messages, MCP extension
  Engine/          # LiteRT-LM wrapper
  Models/          # Model metadata, discovery, showcase views
  Downloads/       # Download manager, HuggingFace browser
  Imports/         # URL import manager, coordinator, model card parser
  Evaluation/      # Eval runner, scorer, store, suites, views
  Benchmarking/    # Device metrics, performance dashboard
  Tools/           # Built-in tools + agent skills
  MCP/             # Model Context Protocol client
  Persistence/     # Conversation + metrics storage
  Settings/        # Inference settings, experiment config
  Onboarding/      # First-run flow
  DesignSystem/    # Dark Forest theme tokens
  Platform/iOS/    # iOS-specific views
  Platform/macOS/  # macOS-specific views
  Views/           # Shared UI (sidebar, chat bubbles, etc.)
  Utilities/       # Parsers, helpers
Tests/             # Unit + integration tests in mirrored feature folders (49 test files)
UITests/           # macOS UI tests (26 tests)
iOSUITests/        # iOS UI smoke tests (5 tests)
RawBenchmark/      # CLI benchmark tool
automation/        # CI scripts, benchmark matrix runner, 6 flow definitions
metrics/           # Benchmark result storage
models/            # Local model files (gitignored)
.github/           # CI workflows, issue/PR templates, CODEOWNERS, Dependabot
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
| `URLImportManager.swift` | URL import state machine (HuggingFace + Kaggle) |
| `EvalRunner.swift` | Evaluation suite runner and scoring |
| `BatchEvalOrchestrator.swift` | Multi-model batch evaluation |
| `DynamicModelCatalog.swift` | Persistent catalog merging registry + imported models |
| `KaggleModelParser.swift` | Kaggle API integration for model import |
| `ModelCardParser.swift` | Infers model capabilities from HuggingFace metadata |
| `OnboardingView.swift` | First-run welcome flow |
| `HFModelCard.swift` | HuggingFace model card metadata parsing |
| `HFTokenStorage.swift` | HuggingFace token Keychain management |
| `KaggleTokenStorage.swift` | Kaggle API key Keychain management |
| `DynamicModelMetadata.swift` | Runtime model metadata for imported models |

## Dependencies

| Package | Source | Notes |
|---------|--------|-------|
| **LiteRT-LM** | `branch("main")` | Pinned to branch because tagged releases have SPM packaging issues ([Issue #2407](https://github.com/google-ai-edge/LiteRT-LM/issues/2407)). We'll migrate to a tagged release when one ships with the fix. |
| **MarkdownUI** | `.upToNextMajor(from: "2.0.0")` | Stable range constraint (currently resolves to 2.4.1) |

## Running Tests

```bash
# Unit tests (~2 minutes)
xcodebuild test -workspace EdgeAILab.xcworkspace \
  -scheme "Edge AI Lab" \
  -only-testing:EdgeAILab_macOSTests \
  -destination 'platform=macOS,arch=arm64'

# UI tests
xcodebuild test -workspace EdgeAILab.xcworkspace \
  -scheme "Edge AI Lab" \
  -only-testing:EdgeAILab_macOSUITests \
  -destination 'platform=macOS,arch=arm64'
```

### iOS Simulator Tests

Boot a simulator before running iOS tests:

```bash
# List available simulators
xcrun simctl list devices available | grep iPhone

# Boot a simulator (e.g., iPhone 16 Pro)
xcrun simctl boot "iPhone 16 Pro"

# iOS unit tests
xcodebuild test -workspace EdgeAILab.xcworkspace \
  -scheme "Edge AI Lab" \
  -only-testing:EdgeAILab_iOSTests \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro'

# iOS UI tests
xcodebuild test -workspace EdgeAILab.xcworkspace \
  -scheme "Edge AI Lab" \
  -only-testing:iOSUITests \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
```

## Key v2.0 Subsystems

### URL Import Pipeline

The URL import system (`URLImportManager`) accepts HuggingFace and Kaggle URLs and walks through an 8-state pipeline: idle → parsing → fetching → analyzing → readyToDownload → downloading → complete / failed. The `ModelCardParser` infers runtime type, vision/audio capabilities, and quantization from model card metadata.

- macOS: `macOSURLImportSheet` (⌘I shortcut)
- iOS: `iOSURLImportSheet`

### Evaluation Framework

The eval system supports 4 built-in suites (Math, Tool Calling, Reasoning, Multimodal) plus user-defined custom suites. Key files:

- `EvalRunner.swift` — runs individual suites with 7 scoring variants (containsText, toolCall, toolCallWithArgs, toolCallChain, nonEmpty, matchesRegex, custom)
- `BatchEvalOrchestrator.swift` — runs all suites across all downloaded models
- `EvalStore.swift` — JSON persistence for results
- `EvalSuiteEditorView.swift` / `iOSSuiteEditorSheet.swift` — custom suite UI

## Code Style

- **SwiftUI** for all views
- **`@Observable`** (not `ObservableObject`) for state
- **`@MainActor`** for all UI-touching code
- **Design system tokens** — use `AppColors`, `AppTypography`, `AppSpacing` instead of hardcoded values. **Exception:** `.foregroundStyle(.secondary)` is acceptable in Settings views (`InferenceSettingsView+*.swift`) for native platform consistency — `.secondary` is a SwiftUI semantic color that adapts to appearance mode and platform, making it the correct choice for settings labels and descriptions.
- **Accessibility identifiers** on all interactive elements (format: `type_name`, e.g., `button_send`, `textField_prompt`)
- **`os.Logger`** for diagnostic output (not `print()`). **Exception:** `DeveloperAutomationHarness.swift` and `AutomationFlowRunner.swift` use `print()` for structured stdout output consumed by CI scripts and the automation playbook.
- **Apache 2.0 license headers** on all source files

### SwiftLint

The project includes a `.swiftlint.yml` with minimal safety-focused rules. Run it locally:

```bash
brew install swiftlint
swiftlint
```

SwiftLint also runs in CI as a blocking check on every push to `main`.

## Tutorial: How to Add a New Built-in Tool

This step-by-step guide walks you through adding a new built-in tool — the most common (and most fun) type of first contribution. We'll use a `DiceRollerTool` as the running example.

**Time estimate:** 30–45 minutes

**Files you'll touch:**
1. `Sources/Tools/DiceRollerTool.swift` — New tool implementation
2. `Sources/Tools/ToolRegistry.swift` — Register the tool
3. `Sources/Settings/InferenceSettingsView.swift` — Add to Settings display

#### Step 1: Create the Tool

Create `Sources/Tools/DiceRollerTool.swift` with the Apache 2.0 license header:

```swift
// Copyright 2026 Andrew Voirol
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import Foundation
import LiteRTLM
```

### Step 2: Implement the `Tool` Protocol

The `Tool` protocol (from LiteRT-LM) requires:
- `static var name: String` — unique identifier the model uses to call the tool
- `static var description: String` — human-readable description for the LLM
- `@ToolParam` properties — parameters with automatic JSON schema generation
- `func run() async throws -> Any` — the tool's logic

```swift
// MARK: - DiceRollerTool

/// Rolls one or more dice and returns the results.
///
/// Example prompts:
/// - `roll_dice()` → rolls 1d6
/// - `roll_dice(count: 3, sides: 20)` → rolls 3d20
struct DiceRollerTool: Tool {
    static let name = "roll_dice"
    static let description = "Roll one or more dice and return the individual results and total"

    @ToolParam(description: "Number of dice to roll (1-10)")
    var count: Int = 1

    @ToolParam(description: "Number of sides per die (4, 6, 8, 10, 12, 20)")
    var sides: Int = 6

    func run() async throws -> Any {
        let startTime = CFAbsoluteTimeGetCurrent()
        let argumentsDict: [String: Any] = ["count": count, "sides": sides]
        var resultString = ""
        defer {
            let duration = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0
            let succeeded = !resultString.isEmpty && !resultString.contains("\"error\"")
            let event = ToolCallEvent(
                toolName: Self.name,
                arguments: jsonString(from: argumentsDict),
                result: resultString,
                durationMs: duration,
                timestamp: Date(),
                succeeded: succeeded
            )
            ToolExecutionTracker.shared.notify(event)
        }

        let clampedCount = max(1, min(count, 10))
        let validSides = [4, 6, 8, 10, 12, 20]
        guard validSides.contains(sides) else {
            resultString = jsonString(from: [
                "error": "Invalid number of sides: \(sides)",
                "valid_sides": validSides.map { String($0) }.joined(separator: ", ")
            ])
            return resultString
        }

        let rolls = (0..<clampedCount).map { _ in Int.random(in: 1...sides) }
        let total = rolls.reduce(0, +)

        resultString = jsonString(from: [
            "rolls": rolls,
            "total": total,
            "notation": "\(clampedCount)d\(sides)",
            "count": clampedCount,
            "sides": sides
        ])
        return resultString
    }
}
```

**Key patterns to follow:**
- Use `jsonString(from:)` to serialize results (defined in `ToolRegistry.swift`)
- Include the `ToolExecutionTracker` defer block for observability
- Return error JSON (not throw) for invalid input
- Keep tools side-effect-free and offline-capable

### Step 3: Register in ToolRegistry

Open `Sources/Tools/ToolRegistry.swift` and add your tool to the `defaultTools` array:

```swift
static let defaultTools: [Tool] = [
    CalculatorTool(),
    DateTimeTool(),
    DeviceInfoTool(),
    UnitConverterTool(),
    TextAnalyzerTool(),
    SystemHealthTool(),
    DiceRollerTool(),       // ← Add your tool here
]
```

### Step 4: Add to Settings Display

Open `Sources/Settings/InferenceSettingsView.swift` and add a `ToolDisplayItem` to `toolDisplayItems`:

```swift
var toolDisplayItems: [ToolDisplayItem] {
    var items = [
        // ...existing tools...
        ToolDisplayItem(name: SystemHealthTool.name, desc: SystemHealthTool.description),
        ToolDisplayItem(name: DiceRollerTool.name, desc: DiceRollerTool.description),  // ← Add here
    ]
    // ...
}
```

### Step 5: Write Tests

Open `Tests/ToolCallingTests.swift` and add test cases:

```swift
// MARK: - DiceRollerTool Tests

func testDiceRollerDefaultRoll() async throws {
    let tool = DiceRollerTool()
    let result = try await tool.run()
    let resultString = result as! String
    XCTAssertTrue(resultString.contains("rolls"), "Result should contain 'rolls' key")
    XCTAssertTrue(resultString.contains("total"), "Result should contain 'total' key")
    XCTAssertTrue(resultString.contains("1d6"), "Default should be 1d6")
}

func testDiceRollerMultipleDice() async throws {
    var tool = DiceRollerTool()
    tool.count = 3
    tool.sides = 20
    let result = try await tool.run()
    let resultString = result as! String
    XCTAssertTrue(resultString.contains("3d20"), "Should show 3d20 notation")
}

func testDiceRollerInvalidSides() async throws {
    var tool = DiceRollerTool()
    tool.sides = 7
    let result = try await tool.run()
    let resultString = result as! String
    XCTAssertTrue(resultString.contains("error"), "Invalid sides should produce error")
}
```

Also update the registry count assertion:

```swift
func testDefaultToolsCount() {
    XCTAssertEqual(
        ToolRegistry.defaultTools.count, 7,  // ← Update from 6 to 7
        "Default tools should contain exactly 7 tools"
    )
}
```

### Step 6: Verify

```bash
# Run SwiftLint
swiftlint

# Run unit tests
xcodebuild test -workspace EdgeAILab.xcworkspace \
  -scheme "Edge AI Lab" \
  -only-testing:EdgeAILab_macOSTests \
  -destination 'platform=macOS,arch=arm64'
```

### Step 7: Submit Your PR

Follow the [Submitting Changes](#submitting-changes) checklist below. Your PR description should mention which tool you added and link to the issue if there is one.

**That's it!** You've just added a new tool to Edge AI Lab. 🎉

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
