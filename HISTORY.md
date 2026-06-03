# GemmaEdgeGallery — Investigation History

Archived institutional knowledge from the Gemma 3n bring-up and Gallery parity investigation (May 2026).

---

## Decode Gap Investigation

**Problem:** Initial benchmarks showed a ~25% decode speed gap between our LiteRT-LM SDK integration and the official AI Edge Gallery iOS app for Gemma 3n E2B.

**Root Cause:** Methodology difference in prefill measurement.
- The Gallery app uses **synthetic tokens** (via the SDK's `benchmark()` function with `initializeForBenchmark()`) for prefill measurement.
- Our initial tests used **natural language prompts** that LiteRT-LM tokenizes into ~256 tokens.
- This difference inflated the apparent gap. When using the SDK's native benchmark mode with synthetic tokens, the decode speeds aligned.

**Resolution:** Adopted SDK benchmark mode (`benchmark()` function) for apples-to-apples comparison. Natural language prompts are still used in the Gallery Parity benchmark for real-world decode measurement.

---

## resetConversation Race Condition

**Problem:** Memory leaked when calling `resetConversation()` between benchmark runs.

**Root Cause:** The `Task` captured a strong reference to the `Conversation` object, preventing `deinit`. The old conversation was replaced but never deallocated because the async Task's closure retained it.

**Resolution:** Ensured proper weak/unowned references in async contexts. The benchmark engine now correctly releases conversation resources between runs.

---

## BenchmarkInfo Is Per-Session, Not Per-Engine

**Discovery:** The SDK's `BenchmarkInfo` is scoped to the current *session* (conversation), not the engine lifetime.
- On the **first turn** of a new session, `BenchmarkInfo` returns `nil`.
- Starting from **turn 2**, `BenchmarkInfo` is populated with metrics.
- This means every benchmark run needs a throwaway "warmup" inference on turn 1 before the real benchmark on turn 2.

**Workaround:** The Gallery Parity benchmark performs a warmup inference (sending "Hi") before each real benchmark prompt to prime the BenchmarkInfo subsystem.

---

## Metal Sampler Dylib — Git LFS Pointer

**Discovery:** The Metal sampler `.dylib` bundled with some LiteRT-LM model packages may be a Git LFS pointer file rather than the actual binary.

**Impact:** None for our use case. We use **greedy sampling** (topK=1) which does not invoke the Metal sampler dylib. The dylib is only needed for non-greedy sampling strategies (topK > 1 with GPU-accelerated sampling).

---

## Final Parity Results

For the complete benchmark comparison, see [gallery_parity_results.md](metrics/gallery_parity_results.md).

### Gemma 3n E2B HW — GPU (iPhone 16 Pro Max)

| Metric | Gallery v1.0.6 | GemmaEdgeGallery | Delta |
|--------|---------------|-------------------|-------|
| Decode | 25.57 tok/s   | 25.71 tok/s       | **+0.5%** ✅ |

Parity achieved — our SDK integration matches the official Gallery app within measurement noise.

### Gemma 4 E2B — GPU (iPhone 16 Pro Max)

| Metric | Gallery v1.0.6 | GemmaEdgeGallery | Delta |
|--------|---------------|-------------------|-------|
| Decode | 41.65 tok/s   | 43.09 tok/s       | **+3.5%** ✅ |

---

## Stack Audit — June 3, 2026

**Objective:** Full stack audit to catch up with LiteRT-LM SDK development velocity and recent model releases.

### Changes Made
1. **SDK updated** to latest `main` HEAD (`aeefa9b`, v0.13.0-dev) — no breaking API changes
2. **Gemma 4 12B Dense Multimodal** added to `ModelRegistry` (released June 3, 2026)
   - 6.5GB, 256K context window, native text + image + audio
   - Allowed on both macOS and iOS (test, don't assume OOM)
   - Added to automation benchmark matrix as configs 9 and 10
3. **`SamplerConfig.seed`** integrated for reproducible generation
4. **`ConversationConfig.systemMessage`** integrated for model persona/instructions
5. **Protocol extension pattern** used for backward-compatible API evolution
6. **Test hardening**: UnitTests.xctestplan expanded from 3 → 9 test classes (~49 tests)
7. **PerformanceTests.xctestplan** expanded to include SmartFallbackIntegrationTests

### SDK API Discovery
The SDK at `aeefa9b` includes significant new capabilities:
- `Tool` protocol + `@ToolParam` property wrapper — native function calling
- `ToolManager` — auto-handles tool call loop (up to 25 iterations)
- `Content.imageData/imageFile/audioData/audioFile` — multimodal input types
- `Capabilities` class — query model capabilities before loading
- `EngineConfig.maxNumTokens` — KV-cache size control
- `Conversation.cancel()` — cancel ongoing inference
- `Conversation.renderMessageIntoString()` — debug rendering
- `ExperimentalFlags.convertCamelToSnakeCaseInToolDescription` — tool name format

### Key Decision
- SDK tracked on `.branch("main")` — v0.12.0 tag has SPM packaging issues (Issue #2407), v0.13.0 not yet released

---

## Models Removed in Phase 2 Cleanup

The following models and registry entries were removed during the Gemma 3n cleanup, then **partially restored** during the Stack Audit:
- `gemma3nE2B` — Gemma 3n E2B INT4 variant (3.39 GB) — **removed, not re-added**
- `gemma3nE2BHW` — Gemma 3n E2B hardware-optimized variant (2.83 GB) — **removed, not re-added**
- `gemma4E4BStandard` — Gemma 4 E4B standard build (3.66 GB) — **restored to ModelRegistry**
- `gemma4E4BWeb` — Gemma 4 E4B web/mobile variant (2.97 GB) — **restored to ModelRegistry**
- `gemma4_12B` — Gemma 4 12B Dense Multimodal (6.50 GB) — **NEW, added in Stack Audit**

The project now supports 5 models: E2B Standard, E2B Web, E4B Standard, E4B Web, and 12B Dense.
