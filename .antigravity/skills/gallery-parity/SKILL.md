---
name: gallery-parity
description: Reference guide for achieving feature parity with the Google AI Edge Gallery iOS app. Documents the Gallery's architecture, allowlist config, accelerator selection, MTP, and model routing.
---

# Google AI Edge Gallery Parity Guide

This skill documents the architecture and capabilities of the [Google AI Edge Gallery](https://github.com/nicklkfoster/GoogleAIEdgeGallery) iOS app, providing a reference for achieving feature parity in GemmaEdgeGallery.

## Gallery iOS App Architecture

The AI Edge Gallery is a closed-source iOS app (with an open-source Android counterpart) that demonstrates on-device LLM inference using LiteRT-LM. Key architectural patterns are understood from the Android codebase and the published allowlist configurations.

### Key Architectural Components
- **Allowlist-driven model catalog**: Remote JSON configs define which models are available
- **HuggingFace download system**: Models are downloaded from HF repos at runtime
- **Multi-task routing**: Models are mapped to task types (chat, summarization, code, etc.)
- **Accelerator auto-selection**: GPU/CPU/NPU selection based on device capabilities
- **Multi-turn chat**: Full conversation history management
- **Multimodal input**: Image and audio input support for capable models

## CRITICAL: iOS Gallery Uses Gemma 3n, NOT Gemma 4

> [!CAUTION]
> The iOS Gallery app uses **Gemma-3n-E2B-it** (from `google/gemma-3n-E2B-it-litert-lm`), NOT Gemma 4. The iOS and Android allowlists specify different models!

| Platform | Allowlist File | Primary Model | Source Repo |
|---|---|---|---|
| iOS | `ios_1_0_0.json` | Gemma-3n-E2B-it | `google/gemma-3n-E2B-it-litert-lm` |
| Android | `1_0_15.json` | Various (Gemma 3n + Gemma 4) | Multiple repos |

This distinction is critical for benchmarking comparisons — Gallery iOS benchmarks are for Gemma 3n, not Gemma 4.

## Allowlist Schema

The allowlist JSON defines available models with the following schema:

```json
{
  "name": "Gemma-3n-E2B-it",
  "modelId": "google/gemma-3n-E2B-it-litert-lm",
  "modelFile": "gemma-3n-E2B-it-int4.litertlm",
  "description": "Compact Gemma model optimized for edge deployment",
  "sizeInBytes": 3640655872,
  // NOTE: An additional HW-accelerated variant exists: gemma-3n-E2B-HW.litertlm
  "minDeviceMemoryInGb": 6,
  "commitHash": "<commit-sha>",
  "llmSupportImage": true,
  "llmSupportAudio": false,
  "capabilities": ["speculative_decoding"],
  "defaultConfig": {
    "topK": 1,
    "topP": 1.0,
    "temperature": 1.0,
    "maxTokens": 8192,
    "accelerators": "gpu",
    "visionAccelerator": "gpu"
  },
  "taskTypes": ["LLM_CHAT", "LLM_SUMMARIZE", "LLM_REWRITE", "LLM_CODE"],
  "bestForTaskTypes": ["LLM_CHAT"],
  "capabilityToTaskTypes": {
    "speculative_decoding": ["LLM_CHAT"]
  },
  "updatableModelFiles": []
}
```

### Key Fields

| Field | Description |
|---|---|
| `name` | Display name for the model |
| `modelId` | HuggingFace repository ID |
| `modelFile` | Filename of the `.litertlm` file in the repo |
| `sizeInBytes` | Total download size |
| `minDeviceMemoryInGb` | Minimum device RAM required |
| `commitHash` | Pinned HF commit for reproducibility |
| `llmSupportImage` / `llmSupportAudio` | Multimodal capability flags |
| `capabilities` | Feature flags (e.g., `speculative_decoding`) |
| `defaultConfig` | Default inference parameters |
| `taskTypes` | All task types this model supports |
| `bestForTaskTypes` | Task types where this model excels |
| `capabilityToTaskTypes` | Maps capabilities to applicable task types |
| `updatableModelFiles` | Files that can be updated independently |

## Accelerator Selection

The Gallery uses the `accelerators` field in `defaultConfig` to determine compute backend:

### Priority Order
```
NPU > GPU > CPU
```

### Configuration Values
- `"gpu"` — GPU only, no fallback
- `"gpu,cpu"` — Try GPU first, fall back to CPU
- `"cpu"` — CPU only

### Platform-Specific Behavior
- **iOS devices**: Mobile Metal GPU shaders (A-series / M-series chips)
- **Android devices**: GPU delegate with OpenCL/Vulkan
- The `visionAccelerator` field controls the backend for image/vision processing separately

## MTP (Multi-Token Prediction) via Speculative Decoding

The Gallery supports Multi-Token Prediction through LiteRT-LM's speculative decoding API.

### Enablement
- Model must have `"speculative_decoding"` in its `capabilities` array
- Enabled via `ExperimentalFlags`:

```swift
ExperimentalFlags.optIntoExperimentalAPIs()
ExperimentalFlags.enableSpeculativeDecoding = true
```

### Impact
- Significantly improves prefill throughput
- Gallery achieves 305 tok/s prefill with MTP enabled vs ~71 tok/s without
- Recommended for GPU backends where the speculative overhead is minimal

### MTP Caveats

> [!WARNING]
> **Cold-Start Init Penalty:** Enabling MTP incurs a ~30-40x cold-start initialization penalty on first engine creation (e.g., ~30s vs ~0.8s without MTP). This is a one-time cost per engine init — subsequent inferences are fast.

> [!CAUTION]
> **`BenchmarkInfo` returns `nil` with MTP enabled.** When `enableSpeculativeDecoding = true`, the `BenchmarkInfo` struct from LiteRT-LM returns `nil` for prefill/decode metrics. Use `os_signpost` timing or wall-clock measurement instead.

## Gallery Benchmark Baseline (Session 3b — 2026-05-31)

User-captured from iOS Gallery app v1.0.6 on iPhone 16 Pro Max:

| Model | Accel | Prefill (tok/s) | Decode (tok/s) | TTFT (s) | Init (ms) | Config |
|---|---|---|---|---|---|---|
| Gemma-4-E2B-it | GPU | **360.35** | **41.65** | **0.74** | **9192** | 256 prefill/decode, 3 runs |
| Gemma-3n-E2B-it | GPU | **392.86** | **25.57** | **0.70** | **8194** | 256 prefill/decode, 3 runs |
| Gemma-4-E2B-it | CPU | 0.00 | 0.00 | 0.00 | 0.00 | CPU fails silently |

> [!NOTE]
> The Gallery enables MTP (speculative decoding) by default. Init times (9.2s/8.2s) include MTP drafter compilation. CPU accelerator returns all zeros for Gemma 4 E2B — the model has no XNNPACK CPU subgraph.

> [!IMPORTANT]
> **Gallery uses `topK: 1` (greedy decoding).** This is faster than our default `topK: 64` (sampling). When comparing decode speeds, note this discrepancy.

### Verified GemmaEdgeGallery Decode Speeds vs Gallery

| Model | Our Decode (tok/s) | Gallery Decode (tok/s) | Delta |
|---|---|---|---|
| Gemma-3n-E2B-it (GPU) | 24.0 | 25.47 | -5.8% |
| Gemma-3n-E2B-it-web (GPU) | 43.5 | — | Web variant not in Gallery |
| Gemma-4-E2B-it (CPU) | 24.3 | — | Gemma 4 not in iOS Gallery |
| Gemma-4-E2B-it-web (GPU) | 42.9 | 39.23 (user-benchmarked) | +9.4% |

> [!NOTE]
> **Session-to-session variance is expected.** Session 2 device measurements were 7-9% lower than Session 1 baselines (e.g., Gemma 3n: 21.9 vs 24.0 tok/s, Web: 39.9 vs 43.5, Standard CPU: 22.6 vs 24.3). This variance is normal and attributable to thermal state, background processes, and battery level. The Session 1 numbers above are retained as canonical baselines.

### Benchmark Methodology Differences

The Gallery and GemmaEdgeGallery benchmarks use **different methodologies** and are **not directly comparable** without matching test parameters.

| Parameter | Gallery (iOS) | GemmaEdgeGallery |
|---|---|---|
| **Prefill tokens** | 256 | ~10 (short prompt, e.g., "What is 2+2?") |
| **Decode tokens** | 256 | 8-20 (varies by response) |
| **Runs** | 3 (averaged) | Single run |
| **MTP enabled** | ✅ Yes | Varies (tested with and without) |
| **Primary model (iOS)** | Gemma-3n-E2B-it | Gemma-4 variants (E2B-it, E2B-it-web) |

> [!WARNING]
> **Numbers are NOT directly comparable.** Differences in prefill/decode token counts, number of runs, MTP state, and model variant mean that raw tok/s numbers from Gallery and GemmaEdgeGallery benchmarks cannot be compared 1:1. To make a valid comparison, match the methodology: use the same model, same token counts, same number of runs, and same MTP setting.

## Gap Analysis: GemmaEdgeGallery vs Gallery

### What We Have ✅
| Feature | Status |
|---|---|
| LiteRT-LM integration | ✅ Working |
| GPU/CPU backend selection with smart fallback | ✅ `InstrumentedEngine.initializeWithFallback()` |
| Model metadata registry | ✅ `ModelRegistry` |
| Benchmark capture | ✅ `BenchmarkInfo` via ExperimentalFlags |
| Metrics persistence | ✅ `metrics/history.json` |
| Experimental flags management | ✅ `ExperimentalFlagsState` |
| Dual iOS + macOS targets | ✅ Via Tuist |
| os_signpost instrumentation | ✅ Model load, inference, TTFT |
| System message support | ✅ `ConversationConfig(systemMessage:)` |
| Reproducible generation | ✅ `SamplerConfig(seed:)` |
| Gemma 4 12B model support | ✅ `ModelRegistry.gemma4_12B` — 256K context, multimodal |
| Inference cancellation | ✅ `Conversation.cancel()` |

### What We're Missing ❌
| Feature | Priority | SDK Ready? | Notes |
|---|---|---|---|
| Multi-turn chat | 🔴 High | ✅ Yes | `ConversationConfig.initialMessages` supports history |
| Image input (multimodal) | 🔴 High | ✅ Yes | `Content.imageData/imageFile` — SDK ready, 12B supports it |
| Audio input (multimodal) | 🔴 High | ✅ Yes | `Content.audioData/audioFile` — SDK ready, 12B supports it |
| Tool use / Function calling | 🔴 High | ✅ Yes | `Tool` protocol + `@ToolParam` + `ToolManager` — full SDK support |
| System message / persona | ✅ Done | ✅ Yes | `ConversationConfig.systemMessage` — integrated in stack audit |
| Reproducible generation | ✅ Done | ✅ Yes | `SamplerConfig.seed` — integrated in stack audit |
| HuggingFace download system | 🟡 Medium | — | Gallery downloads models at runtime from HF repos |
| Remote allowlist fetching | 🟡 Medium | — | Gallery fetches model catalog from remote config |
| Model management UI | 🟡 Medium | — | Download, delete, update models from UI |
| Thinking mode UI | 🟢 Low | — | Show/hide model reasoning steps |
| Task type routing | 🟢 Low | — | Route to best model per task type |
| Remote config updates | 🟢 Low | — | Hot-update model catalog without app update |

> [!TIP]
> **The June 2026 stack audit revealed that the SDK now has full support for multimodal input, function calling, and system messages.** These were previously listed as medium-priority because the SDK didn't support them. They are now unblocked and promoted to high priority.

## Reference Links

- **Gallery Repository**: [GoogleAIEdgeGallery](https://github.com/nicklkfoster/GoogleAIEdgeGallery)
- **iOS Allowlist**: `ios_1_0_0.json` in Gallery repo
- **Android Allowlist**: `1_0_15.json` in Gallery repo
- **LiteRT-LM SDK**: [google-ai-edge/LiteRT-LM](https://github.com/google-ai-edge/LiteRT-LM)
- **LiteRT-LM iOS Docs**: [LiteRT-LM Swift API](https://github.com/nicklkfoster/LiteRT-LM/tree/main/docs)
- **Gemma 3n Model**: [google/gemma-3n-E2B-it-litert-lm](https://huggingface.co/google/gemma-3n-E2B-it-litert-lm)
- **Gemma 4 Models**: [litert-community/gemma-4-E2B-it-litert-lm](https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm)
