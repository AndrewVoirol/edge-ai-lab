---
name: model-management
description: Model catalog, download, variant detection, and backend compatibility for Gemma models in LiteRT-LM format.
---

# Model Management

This skill covers the full lifecycle of Gemma model management: catalog, download, variant detection, and backend compatibility.

## Model Catalog

| Model | File | Size | GPU | CPU | iOS Device | macOS | Simulator | MTP | Source |
|---|---|---|---|---|---|---|---|---|---|
| Gemma-3n-E2B-it | gemma-3n-E2B-it-int4.litertlm | 3.39 GB | ✅ Mobile | ❌ | GPU-only (24.0 tok/s) | Unknown | Unknown | ✅ | google/gemma-3n-E2B-it-litert-lm |
| Gemma-3n-E2B-HW | gemma-3n-E2B-HW.litertlm | 2.83 GB | ✅ Mobile | ❌ | GPU-only (24.0 tok/s) | Unknown | Unknown | ✅ | google/gemma-3n-E2B-it-litert-lm |
| Gemma-4-E2B-it (Standard) | gemma-4-E2B-it.litertlm | 2.59 GB | ✅ Desktop | ✅ XNNPACK | GPU+CPU (24.3 tok/s) | GPU+CPU | CPU only | ✅ | litert-community/gemma-4-E2B-it-litert-lm |
| Gemma-4-E2B-it (Mobile GPU) | gemma-4-E2B-it-web.litertlm | 2.01 GB | ✅ Mobile | ❌ | GPU-only (43.5 tok/s) | Unknown | Unknown | ✅ | litert-community/gemma-4-E2B-it-litert-lm |
| Gemma-4-E4B-it (Standard) | gemma-4-E4B-it.litertlm | 3.66 GB | ✅ Desktop | ✅ XNNPACK | GPU+CPU | GPU+CPU | CPU only | ✅ | litert-community/gemma-4-E4B-it-litert-lm |
| Gemma-4-E4B-it (Mobile GPU) | gemma-4-E4B-it-web.litertlm | 2.97 GB | ✅ Mobile | ❌ | GPU-only | Unknown | Unknown | ✅ | litert-community/gemma-4-E4B-it-litert-lm |
| **Gemma-4-12B-it (Dense)** | gemma-4-12B-it.litertlm | 6.50 GB | ✅ Desktop | ✅ XNNPACK | GPU+CPU (≥16GB) | GPU+CPU | CPU only | ✅ | google/gemma-4-12b-it-litert-lm |

### GPU Variant Notes

- **Standard models** (`*.litertlm`): Compiled with **desktop Metal GPU shaders**. Work on both macOS (Apple Silicon) and iOS devices (verified on iPhone 16 Pro Max, GPU loads in ~2.33s). Have both GPU and XNNPACK CPU subgraphs.
- **Web/Mobile models** (`*-web.litertlm`, `*-int4.litertlm`): Compiled with **mobile Metal GPU shaders** optimized for A-series chips. Work on iOS devices but have no CPU subgraph — GPU-only.
- **Hardware-optimized models** (`*-HW.litertlm`): Hardware-accelerated variants with mobile Metal shaders. GPU-only, no CPU fallback.
- **Gemma 3n**: Uses INT4 quantization with mobile Metal shaders. This is the model the iOS Gallery app ships with.

## Model Download

### Using HuggingFace CLI (Recommended)

```bash
# Install HuggingFace CLI
pip install huggingface-hub

# Download a specific model file
huggingface-cli download litert-community/gemma-4-E2B-it-litert-lm gemma-4-E2B-it.litertlm --local-dir ./models

# Download the web variant
huggingface-cli download litert-community/gemma-4-E2B-it-litert-lm gemma-4-E2B-it-web.litertlm --local-dir ./models

# Download Gemma 4 E4B
huggingface-cli download litert-community/gemma-4-E4B-it-litert-lm gemma-4-E4B-it.litertlm --local-dir ./models

# Download Gemma 3n (requires authentication — gated model)
huggingface-cli login
huggingface-cli download google/gemma-3n-E2B-it-litert-lm gemma-3n-E2B-it-int4.litertlm --local-dir ./models

# Download Gemma 4 12B (Dense Multimodal — 6.5GB)
huggingface-cli download google/gemma-4-12b-it-litert-lm gemma-4-12B-it.litertlm --local-dir ./models
```

### Using curl

```bash
# Gemma 4 E2B standard
curl -L https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm \
  -o ./models/gemma-4-E2B-it.litertlm

# Gemma 4 E2B web (mobile GPU)
curl -L https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it-web.litertlm \
  -o ./models/gemma-4-E2B-it-web.litertlm

# Gemma 4 E4B standard
curl -L https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm/resolve/main/gemma-4-E4B-it.litertlm \
  -o ./models/gemma-4-E4B-it.litertlm

# Gemma 4 E4B web (mobile GPU)
curl -L https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm/resolve/main/gemma-4-E4B-it-web.litertlm \
  -o ./models/gemma-4-E4B-it-web.litertlm
```

> [!IMPORTANT]
> **Gemma 3n** (`google/gemma-3n-E2B-it-litert-lm`) is a gated model. You must:
> 1. Accept the license at [huggingface.co/google/gemma-3n-E2B-it-litert-lm](https://huggingface.co/google/gemma-3n-E2B-it-litert-lm)
> 2. Run `huggingface-cli login` with a token that has access
> 3. Then download via CLI (curl won't work for gated models without auth headers)

### Post-Download Setup

After downloading, the model should be in the `models/` directory at the project root:

```
gemma-edgegallery/
└── models/
    ├── gemma-4-E2B-it.litertlm       # Standard (recommended for dev)
    ├── gemma-4-E2B-it-web.litertlm   # Mobile GPU variant
    ├── gemma-4-12B-it.litertlm       # 12B Dense Multimodal (≥16GB RAM)
    └── gemma-3n-E2B-it-int4.litertlm # Gallery-compatible model
```

For iOS device testing, copy the model to the app's Documents directory for auto-discovery.

#### Pushing to Physical Device via devicectl

```bash
xcrun devicectl device copy to \
  --device <UDID> \
  --domain-type appDataContainer \
  --domain-identifier com.andrewvoirol.GemmaEdgeGallery \
  --source <local-model-file> \
  --destination Documents/<filename>
```

> [!NOTE]
> Replace `<UDID>` with your device UDID (find via `xcrun devicectl list devices`). The app's bundle identifier is `com.andrewvoirol.GemmaEdgeGallery`.

## Backend Auto-Detection Logic

The app automatically selects the correct backend based on model variant and platform.

### ModelRegistry.lookup()

Matches models by filename to determine capabilities:

```swift
// ModelRegistry maps filenames to known model metadata
let metadata = ModelRegistry.lookup(filename: "gemma-4-E2B-it.litertlm")
// Returns: name, backendCapability, supportsMTP, etc.
```

### PlatformSupport.currentPlatform

Detects the current execution environment:

```swift
// Uses compile-time checks:
#if targetEnvironment(simulator)
    return .simulator
#elseif os(iOS)
    return .iOSDevice
#elseif os(macOS)
    return .macOS
#endif
```

### BackendCapability Enum

```swift
enum BackendCapability {
    case gpuOnly      // Web/mobile variants — no CPU subgraph
    case cpuOnly      // Forced CPU (e.g., simulator)
    case gpuAndCpu    // Standard variants — both backends available
    case unknown      // Unrecognized model
}
```

### InstrumentedEngine.initializeWithFallback()

Probes the primary backend, falls back on failure:

```
1. Determine primary backend from model metadata + platform
2. Try primary backend (e.g., GPU)
3. If primary fails → try fallback backend (e.g., CPU)
4. If fallback fails → report error with both failure reasons
```

> [!TIP]
> The fallback mechanism provides resilience — if GPU initialization fails for any reason, it automatically falls back to CPU (XNNPACK). In practice, standard models load successfully on GPU on both macOS and iOS devices.

## Key Constraints

### Standard Models (Desktop Metal Shaders)
- ✅ macOS GPU: Desktop Metal shaders work on Apple Silicon Macs
- ✅ iOS Device GPU: Desktop Metal shaders load successfully on A-series chips (verified iPhone 16 Pro Max, ~2.33s init)
- ✅ All platforms CPU: XNNPACK subgraph always available
- ❌ Simulator GPU: Metal shader translation is unreliable

### Web/Mobile Models (Mobile Metal Shaders)
- ✅ iOS Device GPU: Mobile Metal shaders designed for A-series chips
- ❌ CPU: No XNNPACK subgraph compiled in — GPU-only
- ❌ Simulator: No CPU fallback, GPU translation unreliable
- ⚠️ macOS GPU: Untested — mobile shaders may not match desktop Metal

### Gemma 3n (INT4 Quantized, Mobile Metal)
- ✅ iOS Device GPU: Mobile Metal shaders, INT4 quantization
- ❌ CPU: No CPU subgraph
- This is the iOS Gallery's production model choice
- Requires HuggingFace authentication (gated model from `google/`)

### Simulator
- Metal shader translation is unreliable for all model variants
- CPU (XNNPACK) is the only safe path
- Only standard models have a CPU subgraph
- **Recommendation**: Use standard models on simulator, web/mobile models on physical devices

### Verified Decode Speeds (iPhone 16 Pro Max)
- Gemma 3n GPU: 24.0 tok/s
- Web GPU (gemma-4-E2B-it-web): 43.5 tok/s
- Standard CPU (gemma-4-E2B-it): 24.3 tok/s

## iOS-Specific Configuration

### `#filePath` Caveat

> [!WARNING]
> `#filePath` does **not** resolve correctly on physical iOS devices — it returns a compile-time source path, not the on-device path. Use `Bundle.main.bundleURL` or `FileManager.default.urls(for: .documentDirectory, ...)` instead.

### Required Info.plist Keys

To enable model file access via Files app and `devicectl`:

```xml
<key>UIFileSharingEnabled</key>
<true/>
<key>LSSupportsOpeningDocumentsInPlace</key>
<true/>
<key>UISupportsDocumentBrowser</key>
<true/>
```

These keys expose the app's `Documents/` directory in the iOS Files app and allow `devicectl device copy to` to push files into the container.
