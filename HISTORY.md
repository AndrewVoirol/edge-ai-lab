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

## Models Removed in Phase 2 Cleanup

The following models and registry entries were removed during the Gemma 3n cleanup:
- `gemma3nE2B` — Gemma 3n E2B INT4 variant (3.39 GB)
- `gemma3nE2BHW` — Gemma 3n E2B hardware-optimized variant (2.83 GB)
- `gemma4E4BStandard` — Gemma 4 E4B standard build (3.66 GB)
- `gemma4E4BWeb` — Gemma 4 E4B web/mobile variant (2.97 GB)

The project now focuses exclusively on **Gemma 4 E2B** (Standard and Web variants).
