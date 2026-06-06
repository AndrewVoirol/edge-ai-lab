<p align="center">
  <img src=".github/assets/icon.png" width="120" alt="Edge AI Lab icon" />
</p>

<h1 align="center">Edge AI Lab</h1>

<p align="center">
  <strong>On-device Gemma 4 inference for iOS &amp; macOS</strong><br/>
  <em>Run 2B → 12B parameter models entirely on your device. No cloud. No API keys. No compromise.</em>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Gemma_4-12B_Dense-00897B?style=flat-square" alt="Gemma 4 12B" />
  <img src="https://img.shields.io/badge/LiteRT--LM-v0.13-blue?style=flat-square" alt="LiteRT-LM" />
  <img src="https://img.shields.io/badge/Swift-6.0-FA7343?style=flat-square&logo=swift&logoColor=white" alt="Swift 6" />
  <img src="https://img.shields.io/badge/iOS-26.5+-000000?style=flat-square&logo=apple" alt="iOS 26.5+" />
  <img src="https://img.shields.io/badge/macOS-26.0+-000000?style=flat-square&logo=apple" alt="macOS 26.0+" />
  <img src="https://img.shields.io/badge/license-Apache_2.0-green?style=flat-square" alt="License" />
</p>

---

## What is Edge AI Lab?

Edge AI Lab is a research-grade iOS & macOS application that runs Google's [Gemma 4](https://blog.google/technology/google-deepmind/gemma-4/) language models directly on-device using [LiteRT-LM](https://github.com/google-ai-edge/LiteRT-LM). It's designed for developers, researchers, and power users who want to explore the capabilities of on-device AI without sending a single byte to the cloud.

### Key Capabilities

| Feature | Description |
|---------|-------------|
| **Multi-Model Gallery** | Switch between Gemma 4 E2B, E4B, and 12B Dense models. Download from HuggingFace or load from disk. |
| **Tool Calling** | 6 built-in tools (Calculator, DateTime, DeviceInfo, UnitConverter, TextAnalyzer, SystemHealth). The model invokes them autonomously during conversation. |
| **Thinking Mode** | Watch the model reason in real-time with collapsible `<think>` blocks. See the thought process behind every response. |
| **Multimodal Input** | Attach images and audio files directly in your prompts. Gemma 4's vision capabilities work entirely on-device. |
| **Deep Benchmarking** | Per-token latency histograms, P95 metrics, TTFT, memory deltas, and thermal state tracking. No other edge AI app goes this deep. |
| **Smart GPU Fallback** | Automatic GPU → CPU fallback with detailed diagnostics. Metal acceleration on supported hardware, XNNPACK fallback everywhere else. |
| **Performance Dashboard** | Historical metrics visualization with Swift Charts. Track decode speed trends across sessions and models. |

---

## Quick Start

### Prerequisites

- **Xcode 26.0+** with Swift 6.0
- **[Tuist](https://tuist.dev)** — `brew install tuist`
- **macOS 26.0+** (Tahoe) or iOS 26.5+ device/simulator
- ~3 GB free disk space for the smallest model (E2B), ~7 GB for 12B

### Build & Run

```bash
# 1. Clone
git clone https://github.com/your-username/gemma-edgegallery.git
cd gemma-edgegallery

# 2. Generate Xcode project
tuist generate

# 3. Open in Xcode
open GemmaEdgeGallery.xcworkspace

# 4. Select scheme: GemmaEdgeGallery_macOS (or _iOS)
# 5. Build and Run (⌘R)
```

The app will auto-discover any `.litertlm` model files in your Documents folder. You can also download models directly from the built-in model gallery.

### Getting a Model

**Option A — Download in-app:**
Models from the `litert-community` HuggingFace org download without authentication. Tap the download button on any model card.

**Option B — Manual download:**
Download from [Kaggle](https://www.kaggle.com/models/google/gemma-4) or [HuggingFace](https://huggingface.co/litert-community), then place the `.litertlm` file in:
- **macOS:** `~/Documents/`
- **iOS:** Files app → Edge AI Lab → Documents/

---

## Model Compatibility

| Model | Parameters | Size | Context | Multimodal | MTP | Recommended For |
|-------|-----------|------|---------|------------|-----|-----------------|
| **Gemma 4 E2B Standard** | 2B MoE | 2.6 GB | 128K | Vision + Audio | ✓ | Mobile chat, quick responses |
| **Gemma 4 E2B Web** | 2B MoE | 2.0 GB | 128K | — | ✓ | Lightweight text generation |
| **Gemma 4 E4B Standard** | 4B MoE | 4.4 GB | 128K | Vision + Audio | ✓ | Balanced quality & speed |
| **Gemma 4 E4B Web** | 4B MoE | 3.4 GB | 128K | — | ✓ | Desktop text workflows |
| **Gemma 4 12B Dense** | 12B | 6.5 GB | 256K | Vision + Audio | ✓ | Desktop power users, coding, analysis |

> **Recommended default on macOS:** Gemma 4 12B Dense — released June 3, 2026. Best quality for devices with 16+ GB RAM.

---

## Architecture

```
┌─────────────────────────────────────────┐
│            GemmaEdgeGalleryApp           │
│  ┌─────────────┐  ┌──────────────────┐  │
│  │ ContentView │  │ SettingsView     │  │
│  │  (SwiftUI)  │  │  (SwiftUI Form)  │  │
│  └──────┬──────┘  └──────────────────┘  │
│         │                                │
│  ┌──────┴──────────────────────────┐    │
│  │    ConversationViewModel        │    │
│  │    (@Observable, @MainActor)    │    │
│  └──────┬──────────────────────────┘    │
│         │                                │
│  ┌──────┴──────────────────────────┐    │
│  │  InstrumentedEngineProtocol     │    │
│  │  ├─ InstrumentedEngine (prod)   │    │
│  │  └─ MockInstrumentedEngine      │    │
│  └──────┬──────────────────────────┘    │
│         │                                │
│  ┌──────┴──────┐  ┌──────────────────┐  │
│  │  LiteRT-LM  │  │  ToolRegistry    │  │
│  │  (SDK)       │  │  (6 tools)      │  │
│  └─────────────┘  └──────────────────┘  │
└─────────────────────────────────────────┘
```

**Design Principles:**
- **Protocol-based DI** — `InstrumentedEngineProtocol` enables full mocking for tests
- **MVVM** — `@Observable` ViewModel drives all UI state
- **Swift 6 Concurrency** — `@MainActor`, `async/await`, `Sendable` throughout
- **Dark-mode-first** — Custom `DesignSystem.swift` with curated color palette

---

## Built-in Tools

The app includes 6 side-effect-free tools that the model can invoke autonomously:

| Tool | Description |
|------|-------------|
| `calculator` | Evaluates mathematical expressions |
| `date_time` | Returns current date, time, and timezone |
| `device_info` | Reports device model, OS version, memory, CPU cores |
| `unit_converter` | Converts between units (length, weight, temperature, etc.) |
| `text_analyzer` | Counts words, characters, sentences in text |
| `system_health` | Reports thermal state, available memory, battery level |

All tools work fully offline. The model decides when to call them based on the conversation context.

---

## Performance Benchmarks

Measured on MacBook Pro (M4 Max, 36 GB RAM), macOS 26.0:

| Model | Backend | Decode Speed | TTFT | Notes |
|-------|---------|-------------|------|-------|
| E2B Standard | GPU (Metal) | 109.9 tok/s | 0.43s | MTP enabled |
| E2B Web | GPU (Metal) | 112.3 tok/s | 0.38s | MTP enabled |
| E2B Standard | CPU (XNNPACK) | 28.7 tok/s | 1.65s | Fallback backend |
| E4B Standard | GPU (Metal) | — | — | Awaiting formal benchmark |
| 12B Dense | GPU (Metal) | — | — | Awaiting formal benchmark (requires 16 GB+ RAM) |

The in-app benchmark bar shows real-time metrics including:
- **Decode speed** (color-coded by performance tier)
- **Time to First Token** (TTFT)
- **Memory delta** (start → end)
- **Thermal state transitions**
- **Per-token latency** (median, P95, min, max)

---

## Development

See [CONTRIBUTING.md](CONTRIBUTING.md) for setup instructions and coding standards.

```bash
# Run all tests
xcodebuild -workspace GemmaEdgeGallery.xcworkspace \
  -scheme GemmaEdgeGallery_macOS \
  -destination 'platform=macOS' \
  test

# Current: 142+ tests across 12 test files
```

---

## License

This project is licensed under the [Apache License 2.0](LICENSE).

Gemma models are subject to the [Gemma Terms of Use](https://ai.google.dev/gemma/terms).

---

<p align="center">
  Built with LiteRT-LM by Google AI Edge<br/>
  <sub>Gemma 4 — On-device AI that respects your privacy.</sub>
</p>
