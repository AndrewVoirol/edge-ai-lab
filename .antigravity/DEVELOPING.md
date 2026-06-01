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
- **Developer Team ID:** `Y7J7WUK693` (Free Personal Team)
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

LLM weights are large (~2.0-3.7GB) and are **not committed to git**. Models live in the `models/` directory.

### Full Model Catalog

| Model | File | Size | GPU | CPU | iOS Device | macOS | Simulator | Source |
|---|---|---|---|---|---|---|---|---|
| Gemma-3n-E2B-it | `gemma-3n-E2B-it-int4.litertlm` | 3.39 GB | ✅ Mobile | ❌ | GPU-only | GPU Only | GPU Only | [google/gemma-3n-E2B-it-litert-lm](https://huggingface.co/google/gemma-3n-E2B-it-litert-lm) |
| Gemma-3n-E2B-HW | `gemma-3n-E2B-HW.litertlm` | 2.83 GB | ✅ Mobile | ❌ | GPU (24.0 tok/s decode, 7.8 tok/s prefill) | GPU Only (78.6 tok/s) | GPU Only (degenerate) | AI Edge Gallery hardware-optimized variant |
| Gemma-4-E2B-it (Standard) | `gemma-4-E2B-it.litertlm` | 2.59 GB | ✅ Desktop + Mobile | ✅ XNNPACK | GPU + CPU (GPU works on iPhone 16 Pro Max, 2.33s load) | GPU+CPU | CPU only | [litert-community/gemma-4-E2B-it-litert-lm](https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm) |
| Gemma-4-E2B-it (Mobile GPU) | `gemma-4-E2B-it-web.litertlm` | 2.01 GB | ✅ Mobile | ❌ | GPU-only | GPU Only (113.1 tok/s) | GPU Only (degenerate) | [litert-community/gemma-4-E2B-it-litert-lm](https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm) |
| Gemma-4-E4B-it (Standard) | `gemma-4-E4B-it.litertlm` | 3.66 GB | ✅ Desktop | ✅ XNNPACK | CPU only | GPU+CPU | CPU only | [litert-community/gemma-4-E4B-it-litert-lm](https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm) |
| Gemma-4-E4B-it (Mobile GPU) | `gemma-4-E4B-it-web.litertlm` | 2.97 GB | ✅ Mobile | ❌ | GPU-only | GPU Only | GPU Only (degenerate) | [litert-community/gemma-4-E4B-it-litert-lm](https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm) |

### Model Naming Convention

| Label | Meaning | Details |
|---|---|---|
| **Desktop GPU+CPU** | Desktop Metal + XNNPACK CPU subgraphs | Works on macOS (GPU or CPU) and iOS (GPU + CPU fallback). Contains both Metal GPU shaders compiled for desktop and XNNPACK CPU subgraphs. |
| **Mobile GPU** | Artisan mobile GPU shaders, no CPU fallback | Optimized for A-series/M-series mobile Metal GPUs. No XNNPACK CPU subgraph — GPU is the only backend. |
| **Mobile GPU (HW)** | Hardware-optimized mobile GPU shaders | Further hardware-optimized variant of Mobile GPU shaders. Best on-device GPU performance. |

> [!NOTE]
> Filenames on disk (e.g., `gemma-4-E2B-it-web.litertlm`) follow HuggingFace upstream naming conventions. The labels above describe the **shader/backend type**, not the filename.

> [!NOTE]
> The standard model (`gemma-4-E2B-it.litertlm`) is preferred for development — it supports both CPU and GPU backends on all platforms (including iOS devices), enabling the "Use GPU" toggle and inference on the iOS Simulator (CPU mode). GPU acceleration works on iPhone 16 Pro Max with a 2.33s load time.

> [!IMPORTANT]
> Gemma 3n (`google/gemma-3n-E2B-it-litert-lm`) is a **gated model** requiring HuggingFace authentication. This is the model used by the iOS Gallery app.

### Download Models

```bash
# Using HuggingFace CLI (recommended)
pip install huggingface-hub
huggingface-cli download litert-community/gemma-4-E2B-it-litert-lm gemma-4-E2B-it.litertlm --local-dir ./models

# Using curl
curl -L https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm -o ./models/gemma-4-E2B-it.litertlm

# For gated models (Gemma 3n)
huggingface-cli login
huggingface-cli download google/gemma-3n-E2B-it-litert-lm gemma-3n-E2B-it-int4.litertlm --local-dir ./models

# Check model availability
.antigravity/skills/performance-testing/scripts/provision-model.sh
```

### Provisioning Models to iOS Devices

Use `devicectl` to copy model files to the app's Documents directory on a physical device:

```bash
xcrun devicectl device copy to \
  --device <UDID> \
  --domain-type appDataContainer \
  --domain-identifier com.andrewvoirol.GemmaEdgeGallery \
  --source <file> \
  --destination Documents/<filename>
```

### Model Selection per Platform

| Platform | Recommended Model | Backend | Notes |
|---|---|---|---|
| macOS (development) | `gemma-4-E2B-it.litertlm` | GPU + CPU | Full flexibility, both backends work |
| iOS Simulator | `gemma-4-E2B-it.litertlm` | CPU only | Only standard models have CPU subgraph |
| iOS Device (GPU perf) | `gemma-4-E2B-it-web.litertlm` | GPU only | Mobile Metal shaders, best GPU perf |
| iOS Device (Standard GPU) | `gemma-4-E2B-it.litertlm` | GPU + CPU | GPU works on iPhone 16 Pro Max (2.33s load) |
| iOS Device (HW-optimized) | `gemma-3n-E2B-HW.litertlm` | GPU only | Hardware-optimized, 24.0 tok/s decode |
| iOS Device (Gallery compat) | `gemma-3n-E2B-it-int4.litertlm` | GPU only | Same model as iOS Gallery app |

- The `models/` directory is gitignored
- Unit tests work without a model (they use `MockInstrumentedEngine`)
- Performance tests auto-discover models via fallback: env var → `models/` dir → app Documents
- The app uses iOS Document Picker for user model selection at runtime

## Test Plans

| Plan | Model Required | Speed | What It Tests |
|---|---|---|---|
| **UnitTests** | ❌ No | Fast (seconds) | Logic, mocks, state management |
| **PerformanceTests** | ✅ Yes | Slow (minutes) | Real inference, latency, memory |
| **SimulatorCompatibilityTests** | ✅ Yes | Slow (minutes) | Model/backend compatibility matrix |

### Model Discovery (PerformanceTests)

The `PerformanceTests` suite discovers models automatically (no env var needed for local dev):
1. `PERFORMANCE_TEST_MODEL_PATH` env var (CI/automation — highest priority)
2. `models/` directory relative to project root (macOS local dev)
3. App Documents directory (simulator/device with provisioned model)

> [!WARNING]
> `#filePath`-based model discovery does **not** work on physical iOS devices (the path points to the build host, not the device filesystem). On-device tests use Documents/ directory scanning instead.

### Backend Selection

Tests automatically select the appropriate backend:
- **macOS / Physical iOS device:** GPU (Metal)
- **iOS Simulator:** CPU (XNNPACK) — Metal shader translation on the simulator is not bit-identical and produces corrupted inference output. See [Apple docs](https://developer.apple.com/documentation/metal/developing_metal_apps_that_run_in_simulator).

> [!NOTE]
> **TEST_HOST:** Device tests run inside the app's sandbox via `TEST_HOST`. Model files must be placed in the app's `Documents/` directory (use `devicectl` — see Model Provisioning above).

### Running Tests

```bash
# Run unit tests only (fast, no model)
xcodebuildmcp simulator test --scheme GemmaEdgeGallery_iOS --test-plan UnitTests

# Run performance tests (auto-discovers model, auto-selects backend)
xcodebuildmcp simulator test --scheme GemmaEdgeGallery_iOS --test-plan PerformanceTests

# Run performance tests with explicit model path (CI)
xcodebuildmcp simulator test --scheme GemmaEdgeGallery_iOS \
  --test-plan PerformanceTests \
  --testRunnerEnv PERFORMANCE_TEST_MODEL_PATH=/path/to/model.litertlm
```

### Platform Compatibility Matrix (Verified — iPhone 16 Pro Max)

| Model | Backend | macOS | iOS Sim | iOS Device | Decode | Prefill | TTFT | Init |
|---|---|---|---|---|---|---|---|---|
| Desktop GPU+CPU (`gemma-4-E2B-it`) | GPU | ✅ 33.8 tok/s | ❌ crash | ✅ **works** | 16.8 tok/s | 106.2 tok/s | 0.210s | 2.33s |
| Desktop GPU+CPU (`gemma-4-E2B-it`) | CPU | ✅ 30.8 tok/s | ✅ 29.4 tok/s | ✅ | 24.3 tok/s | 53.8 tok/s | 0.34s | 4.22s |
| Mobile GPU (`gemma-4-E2B-it-web`) | GPU | ✅ | ❌ degenerate | ✅ **42.9 tok/s** | 43.5 tok/s | 16.9 tok/s | 0.97s | 2.94s |
| Mobile GPU (`gemma-4-E2B-it-web`) | CPU | ❌ no subgraph | ❌ no subgraph | ❌ no subgraph | — | — | — | — |
| HW (`gemma-3n-E2B-HW`) | GPU | Unknown | Unknown | ✅ | 24.0 tok/s | 7.8 tok/s | 2.09s | 4.34s |

> [!NOTE]
> The earlier assumption that standard models' desktop Metal shaders fail on A-series mobile GPUs was **incorrect**. `gemma-4-E2B-it.litertlm` GPU acceleration works on iPhone 16 Pro Max (2.33s load time). **Web/mobile models** still have no CPU fallback — choose the right variant for your use case.

### macOS Benchmark Baselines (Session 2 — Apple Silicon Mac)

| Model | Backend | Decode (tok/s) | Prefill (tok/s) | TTFT (s) |
|---|---|---|---|---|
| Desktop GPU+CPU (`gemma-4-E2B-it`) | GPU | 109.9 | 324.8 | 0.058 |
| Mobile GPU (`gemma-4-E2B-it-web`) | GPU | 113.1 | 123.7 | 0.138 |
| Gemma 3n HW (`gemma-3n-E2B-HW`) | GPU | 78.6 | 89.8 | 0.191 |
| Desktop GPU+CPU (`gemma-4-E2B-it`) | CPU | 32.9 | 83.8 | 0.221 |

#### macOS MTP Baselines (Effective Throughput)

| Model | Backend | Effective tok/s | Tokens | Wall Time |
|---|---|---|---|---|
| Mobile GPU (`gemma-4-E2B-it-web`) | GPU + MTP | ~101 | 101 | 1.00s |
| Gemma 3n HW (`gemma-3n-E2B-HW`) | GPU + MTP | ~68 | 101 | 1.48s |
| Desktop GPU+CPU (`gemma-4-E2B-it`) | CPU + MTP | ~18 | 101 | 5.59s |

> [!NOTE]
> macOS numbers are significantly faster than iOS device numbers because the Mac's GPU/CPU has higher throughput than mobile A-series chips. These baselines are useful for development iteration speed but should not be compared directly to iOS device benchmarks.

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

## Gallery Parity Features

This project aims for feature parity with the [Google AI Edge Gallery](https://github.com/nicklkfoster/GoogleAIEdgeGallery) iOS app. See `.antigravity/skills/gallery-parity/SKILL.md` for the full gap analysis.

### Current Status
| Feature | Status | Notes |
|---|---|---|
| LiteRT-LM inference | ✅ Done | GPU + CPU with smart fallback |
| Model metadata registry | ✅ Done | `ModelRegistry` with variant detection |
| Benchmark capture | ✅ Done | `BenchmarkInfo` + metrics persistence |
| Experimental flags | ✅ Done | `ExperimentalFlagsState` management |
| Dual platform targets | ✅ Done | iOS + macOS via Tuist |
| HuggingFace downloads | ❌ Missing | Gallery downloads models at runtime |
| Multi-turn chat | ❌ Missing | Gallery maintains conversation history |
| Multimodal input | ❌ Missing | Image + audio input support |
| Model management UI | ❌ Missing | Download, delete, update models |
| Remote allowlist | ❌ Missing | Fetch model catalog from remote config |

### Gallery Benchmark Target (Session 3b — 2026-05-31)
User-captured from iOS Gallery app v1.0.6 on iPhone 16 Pro Max:

| Model | Accel | Prefill (tok/s) | Decode (tok/s) | TTFT (s) | Init (ms) |
|---|---|---|---|---|---|
| Gemma-4-E2B-it | GPU | **360.35** | **41.65** | **0.74** | **9192** |
| Gemma-3n-E2B-it | GPU | **392.86** | **25.57** | **0.70** | **8194** |
| Gemma-4-E2B-it | CPU | 0.00 | 0.00 | 0.00 | 0.00 |

> [!WARNING]
> **MTP / Speculative Decoding Caveats:**
> - **~30-40× cold-start init penalty**: Gallery init times (9.2s/8.2s) include MTP drafter compilation.
> - **`BenchmarkInfo` returns `nil`** when MTP is enabled (SDK limitation — metrics cannot be captured).
> - **Effective throughput may be lower on short prompts** due to drafter model overhead; MTP benefits are most visible on longer generations.
> - **MTP + CPU backend CRASHES on iOS device** — SDK crash at external symbol. MTP on device only works with GPU backend.
> - **CPU accelerator returns all zeros** in the Gallery for Gemma 4 E2B — model has no XNNPACK CPU subgraph.

## Known SDK Issues (Community-Validated)

| # | Issue | Community Ref | Status |
|---|---|---|---|
| 1 | MTP + Web GPU model SEGV crash on iOS | [LiteRT-LM #2243](https://github.com/google-ai-edge/LiteRT-LM/issues/2243) | Open — MTP on iOS is experimental |
| 2 | MTP + CPU crashes on iOS device | [LiteRT-LM #2243](https://github.com/google-ai-edge/LiteRT-LM/issues/2243) | Open — XNNPACK + MTP not fully supported |
| 3 | Gallery CPU returns all zeros | No exact match — likely silent model failure | Confirmed locally |
| 4 | BenchmarkInfo nil with MTP | No exact issue — SDK benchmarking predates MTP | Known SDK limitation |
| 5 | Simulator GPU produces garbage | [Apple docs](https://developer.apple.com/documentation/metal/developing_metal_apps_that_run_in_simulator), flutter_gemma docs | Well-documented platform limitation |
| 6 | MTP cold-start ~30-40× penalty | Expected behavior (JIT kernel compilation) | Not a bug |
| 7 | BenchmarkInfo nil WITHOUT MTP on macOS | No exact issue — `getBenchmarkInfo()` throws silently | Confirmed locally (Session 3b) |
| 8 | **Conversation.deinit use-after-free** | Discovered Session 4 | **FIXED** — use `withExtendedLifetime` in `shutdown()` |
| 9 | **BenchmarkInfo nil on first conversation turn** | No issue filed | **FIXED** (Session 6). Per-session limitation. Don't reset after warmup — benchmark runs as turn 2 with BenchmarkInfo available |
| 10 | **Context overflow on multi-turn reuse** | No issue filed | **FIXED** (Session 5). Added `resetConversation()` for fresh context per run |
| 11 | **Metal sampler dylib not bundled** | No issue filed | **Root cause**: Git LFS pointers in prebuilt/, xcframework excludes dylib. Falls back to C API. No impact for topK=1 |
| 12 | **resetConversation single-session race** | Discovered Session 6 | **FIXED** — `sendMessageStream` Task captured local Conversation ref. Await `activeInferenceTask` before niling |
| 13 | **SDK benchmark() decode token cap** | No issue filed | `benchmark()` only generates 32 decode tokens despite requesting 256. Native C++ loop hardcoded to 32 iterations. **Confirmed on-device** (Session 7): canary assertion validated, 34.48 tok/s avg on iPhone 16 Pro Max |
| 14 | **Gemma 3n SDK benchmark mode crash** | No issue filed | `benchmark()` mode crashes at `<external symbol>` for Gemma 3n models on iOS device. Natural language benchmark works fine (17.84 tok/s INT4). SDK limitation, not app code. |

> [!NOTE]
> See [LiteRT-LM #2227](https://github.com/google-ai-edge/LiteRT-LM/issues/2227) for MTP performance regression tracking. The `RunAsync` Metal decode bug may also contribute to SEGV crashes — a guard for `IsMetalMemory()` is needed on the decode path.

## Entitlements

| Entitlement | Purpose | Personal Team | Paid Team |
|---|---|---|---|
| `increased-memory-limit` | Allows app to use more RAM for large models | ✅ Works | ✅ Works |
| `extended-virtual-addressing` | Enables >4GB address space for very large models | ❌ Blocked | ✅ Works |

> [!NOTE]
> For development with a free personal team, `increased-memory-limit` is sufficient for E2B models. `extended-virtual-addressing` requires a paid Apple Developer account.

## InfoPlist Keys

The iOS target in `Project.swift` includes these `InfoPlist` keys to enable model file access:

| Key | Value | Purpose |
|---|---|---|
| `UIFileSharingEnabled` | `true` | Exposes Documents/ via iTunes/Finder file sharing |
| `LSSupportsOpeningDocumentsInPlace` | `true` | Allows opening documents in place from Files app |
| `UISupportsDocumentBrowser` | `true` | Enables the document browser for model selection |

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
│   ├── skills/           # Agent skills (tuist, xcode-mcp, litert-lm, performance-testing, gallery-parity, model-management, benchmark-comparison)
│   └── rules/            # Always-on agent rules (project-structure, build-tool-boundaries, benchmark-methodology, workflow-discipline)
├── .gitignore
├── GemmaEdgeGallery.xcodeproj/   # Tuist-generated (DO NOT EDIT)
├── GemmaEdgeGallery.xcworkspace/ # Tuist-generated (DO NOT EDIT)
└── Derived/                       # Tuist-generated (DO NOT EDIT)
```
