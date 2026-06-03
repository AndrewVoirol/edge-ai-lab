---
name: benchmark-comparison
description: Generates cross-dimensional benchmark comparison tables from metrics/history.json and known Gallery/HuggingFace baselines. Use when summarizing benchmark results or creating session walkthroughs.
---

# Benchmark Comparison Skill

Automates the generation of cross-dimensional comparison tables for benchmark analysis.

## When to Use

- After running `GalleryParityBenchmarkTests` or any performance test suite
- When creating or updating walkthrough artifacts
- When comparing results across sessions
- When the user asks "how do we compare to Gallery/HuggingFace"

## How to Use

### 1. Generate a Comparison Report

Run the comparison script to produce a markdown table:

```bash
./.antigravity/skills/benchmark-comparison/scripts/generate-comparison.sh
```

This reads `metrics/history.json` and produces a markdown comparison table on stdout.

### 2. Manual Comparison Template

If `metrics/history.json` doesn't have enough data, use these known baselines:

#### Gallery Baselines (iPhone 16 Pro Max, v1.0.6, 2026-05-31)

| Model | Accel | Prefill (tok/s) | Decode (tok/s) | TTFT (s) | Init (ms) |
|---|---|---|---|---|---|
| Gemma-4-E2B-it | GPU+MTP | 360.35 | 41.65 | 0.74 | 9192 |
| Gemma-3n-E2B-it | GPU+MTP | 392.86 | 25.57 | 0.70 | 8194 |
| Gemma-4-E2B-it | CPU | 0.00 | 0.00 | 0.00 | 0.00 |

#### HuggingFace Baselines (litert-community model cards)

| Model | Device | Prefill (tok/s) | Decode (tok/s) | Config |
|---|---|---|---|---|
| Gemma-4-E2B-it | iPhone 17 Pro | ~2,878 | ~56 | 1024 prefill, GPU |
| Gemma-4-E2B-it | MacBook M4 | ~7,835 | ~160 | 1024 prefill, GPU |

#### Our App Baselines (Session 3b, macOS, 256 tokens)

| Model | Backend | Decode (tok/s) | TTFT (s) | Init (ms) |
|---|---|---|---|---|
| Gemma 4 E2B Standard | GPU | 103.2 | 0.25 | 1119 |
| Gemma 4 E2B Mobile GPU | GPU | 94.1 | 0.42 | 1433 |
| Gemma 3n E2B HW | GPU | 66.8 | 0.57 | 1559 |
| Gemma 4 E2B Standard | CPU | 28.7 | 1.65 | 1766 |

### 3. Cross-Dimensional Table Format

When producing comparison tables, use this format:

```markdown
| Source | Platform | Model | Prefill (tok/s) | Decode (tok/s) | TTFT (s) | Config |
|---|---|---|---|---|---|---|
| HuggingFace | iPhone 17 Pro | Gemma 4 E2B | ~2,878 | ~56 | — | 1024 tok |
| Gallery | iPhone 16 Pro Max | Gemma 4 E2B | 360 | 41.7 | 0.74 | 256 tok, MTP, topK=1 |
| Our App | iPhone 16 Pro Max | Gemma 4 E2B | 115.8 | 44.9 | 1.08 | ~10 tok, no MTP, topK=64 |
| Our App | macOS | Gemma 4 E2B | — | 103.2 | 0.25 | 256 tok, no MTP |
```

## Key Comparison Notes

> [!WARNING]
> **These numbers are NOT directly comparable without matching methodology:**
> - HuggingFace uses 1024 prefill tokens; Gallery uses 256; our short tests use ~10
> - Gallery uses `topK: 1` (greedy); our app uses `topK: 64` (sampling). Use `seed: 42` for reproducibility.
> - Gallery enables MTP by default; our tests run both with and without
> - Prefill speed scales with token count (GPU parallelism saturation)
> - **12B model** (configs 9-10 in automation matrix) requires ≥16GB RAM — not all devices can run it

## Trend Tracking

To compare across sessions, filter `metrics/history.json` by `sessionId`:

```bash
# Show all benchmark entries for a specific session
jq '[.[] | select(.sessionId | contains("SESSION_ID_PREFIX"))]' metrics/history.json

# Show decode speed trends for a specific model label
jq '[.[] | .benchmarks[] | select(.label | contains("Standard/GPU")) | {session: .label, decode: .decodeSpeed}]' metrics/history.json
```
