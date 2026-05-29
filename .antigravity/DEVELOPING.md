# Developing GemmaEdgeGallery

This document is the single source of truth for working on the GemmaEdgeGallery application. It serves both human contributors and AI agents.

## Project Overview
GemmaEdgeGallery is a SwiftUI app that runs Google Gemma 4 models on-device using the [LiteRT-LM](https://github.com/google-ai-edge/LiteRT-LM) library. It targets iOS 26.5+ and macOS 26.0+.

## Prerequisites

| Tool | Version | Install |
|---|---|---|
| Xcode | 26.5+ | Mac App Store |
| Tuist | 4.x | `brew install tuist` |
| XcodeBuildMCP | Latest | `brew tap getsentry/xcodebuildmcp && brew install xcodebuildmcp` |
| jq | Latest | `brew install jq` (required by hooks) |

## Project Specifications
- **Language:** Swift 6.0+
- **Platforms:** iOS 26.5+, macOS 26.0+
- **Developer Team ID:** `ASX83B274M` (Free Personal Team)
- **Bundle ID Base:** `com.andrewvoirol.GemmaEdgeGallery`
- **Project Generator:** Tuist — edit `Project.swift`, never `.xcodeproj`
- **Dependencies:** LiteRT-LM (via Swift Package Manager, branch: `main`)

## Quick Start

```bash
# 1. Clone the repo
git clone <repo-url> && cd gemma-edgegallery

# 2. Generate the Xcode project
tuist generate

# 3. Build (choose one)
xcodebuildmcp simulator build --scheme GemmaEdgeGallery_iOS    # iOS
xcodebuildmcp macos build --scheme GemmaEdgeGallery_macOS      # macOS

# 4. Run tests (no model needed)
xcodebuildmcp simulator test --scheme GemmaEdgeGallery_iOS --test-plan UnitTests
```

## Build Stack

```
Project.swift → tuist generate → XcodeBuildMCP (build/test/deploy)
                                 └─ xcode-tools MCP (previews/diagnostics)
```

| Tool | Role |
|---|---|
| **Tuist** | Project generation only. Edit `Project.swift`, run `tuist generate`. |
| **XcodeBuildMCP** | All builds, tests, deployment, coverage, debugging. Headless (no Xcode required). |
| **Apple xcode-tools** | IDE integration: SwiftUI previews, diagnostics, code navigation, documentation. Requires Xcode open. |

> **Note:** Fastlane has been removed from this project. XcodeBuildMCP replaces all former Fastlane lanes.

## Build & Run Pipeline

1. Edit code in `Sources/` or `Tests/`
2. If `Project.swift` is edited, run `tuist generate` (or let the auto-hook handle it)
3. Build: `xcodebuildmcp simulator build --scheme GemmaEdgeGallery_iOS`
4. Test: `xcodebuildmcp simulator test --scheme GemmaEdgeGallery_iOS --test-plan UnitTests`

## Model Provisioning

LLM weights are large (~1.5-2GB) and are **not committed to git**. Models live in the `models/` directory.

```bash
# Check model availability
.antigravity/skills/performance-testing/scripts/provision-model.sh

# Copy a model
cp /path/to/gemma-4-E2B-it-web.litertlm models/
```

- The `models/` directory is gitignored
- Unit tests work without a model (they use `MockInstrumentedEngine`)
- Performance tests require a model in `models/`
- The app uses iOS Document Picker for user model selection at runtime

## Test Plans

| Plan | Model Required | Speed | What It Tests |
|---|---|---|---|
| **UnitTests** | ❌ No | Fast (seconds) | Logic, mocks, state management |
| **PerformanceTests** | ✅ Yes | Slow (minutes) | Real inference, latency, memory |

```bash
# Run unit tests only (fast, no model)
xcodebuildmcp simulator test --scheme GemmaEdgeGallery_iOS --test-plan UnitTests

# Run performance tests (requires model)
xcodebuildmcp simulator test --scheme GemmaEdgeGallery_iOS --test-plan PerformanceTests
```

## MCP Architecture (for Agents)

This project has **two** Xcode MCP servers:

- **`xcode-tools`** — Apple's native Xcode MCP. Use for previews, diagnostics, code nav, documentation. Requires Xcode open.
- **`xcodebuild-mcp`** — Sentry's XcodeBuildMCP. Use for builds, tests, deployment, coverage, debugging. Works headlessly.

See `.antigravity/skills/xcode-mcp/SKILL.md` for the full capability matrix.

## Automation Hooks

Three hooks fire automatically during agent workflows:

| Hook | Trigger | Action |
|---|---|---|
| Auto-tuist-generate | File write to `Project.swift` | Runs `tuist generate` |
| Model check | Before build/test MCP calls | Warns if no model in `models/` |
| Metrics capture | After test MCP calls | Appends results to `metrics/history.json` |

## Project Structure

```
gemma-edgegallery/
├── Sources/              # App source code (Swift)
├── Tests/                # Test files (Swift)
├── Project.swift         # Tuist project manifest (source of truth)
├── .package.resolved     # Dependency lock file
├── models/               # LLM model files (gitignored)
├── metrics/              # Performance metrics (auto-generated)
├── .antigravity/         # Agent configuration
│   ├── DEVELOPING.md     # This file
│   ├── hooks.json        # Lifecycle hook configuration
│   ├── hooks/            # Hook scripts
│   ├── skills/           # Agent skills (tuist, xcode-mcp, litert-lm, performance-testing)
│   └── rules/            # Always-on agent rules
├── .gitignore
├── GemmaEdgeGallery.xcodeproj/   # Tuist-generated (DO NOT EDIT)
├── GemmaEdgeGallery.xcworkspace/ # Tuist-generated (DO NOT EDIT)
└── Derived/                       # Tuist-generated (DO NOT EDIT)
```
