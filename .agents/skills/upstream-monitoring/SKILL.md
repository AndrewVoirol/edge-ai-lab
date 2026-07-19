---
name: upstream-monitoring
description: Track upstream dependency PRs, merge velocity, and ecosystem changes for mlx-swift-lm and related repos. Activate when checking PR status, planning SDK updates, or investigating upstream gaps.
---

# Upstream Dependency Monitoring

## Tracked Dependencies

| Dependency | Repo | Our Pin Location | Current Pin |
|---|---|---|---|
| mlx-swift-lm | ml-explore/mlx-swift-lm | `Project.swift` L28 | `.revision("d2424294a6c3")` |
| mlx-swift | ml-explore/mlx-swift | Resolved transitively via mlx-swift-lm | — |

## Active Tracked PRs

| PR | Title | Status | Impact |
|---|---|---|---|
| #392 | Gemma 4: native audio (USM-Conformer encoder) | 🟡 OPEN | Fixes MLX audio 0% on E2B/E4B |
| #391 | Video input for base Gemma 4 | 🟡 OPEN | Enables video evals |
| #400 | Gemma4Unified (12B): audio+video in processor | 🟡 OPEN | Audio for 12B models |
| #434 | Tool-schema $defs hoisting | 🟡 OPEN | Complex tool schemas |
| #426 | Prompt-lookup speculative decoding | 🟡 OPEN | Draft-model-free speedup |

## Merge Velocity Baseline (measured July 2026)

| Metric | Value |
|---|---|
| Repo median time-to-merge | 4.2 days |
| Mean time-to-merge | 8.9 days |
| 75th percentile | 12.3 days |
| 90th percentile | 21.3 days |
| fdagostino average | 3.9 days (2 PRs: 1.0d, 6.8d) |

## Quick Status Check

```bash
# Check all tracked PRs
for PR in 392 391 400 434 426; do
  curl -s "https://api.github.com/repos/ml-explore/mlx-swift-lm/pulls/$PR" | \
    python3 -c "import json,sys; d=json.load(sys.stdin); print(f'PR #{d[\"number\"]}: {\"MERGED \" + d[\"merged_at\"][:10] if d.get(\"merged_at\") else d[\"state\"].upper()} — {d[\"title\"][:60]}')"
done
```

## When a PR Merges — Update Checklist

1. Get the merge commit SHA: `curl -s "https://api.github.com/repos/ml-explore/mlx-swift-lm/pulls/<NUM>" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('merge_commit_sha','?'))"`
2. Update `Project.swift`: change `.revision("d2424294a6c3")` → `.revision("<new-sha>")`
3. Run `tuist generate`
4. Build both platforms:
   - `xcodebuild build -workspace EdgeAILab.xcworkspace -scheme "Edge AI Lab" -destination "platform=macOS"`
   - `xcodebuild build -workspace EdgeAILab.xcworkspace -scheme EdgeAILab_iOS -destination "platform=iOS Simulator,name=iPhone 16 Pro Max"`
5. Run test plan
6. Run relevant eval suites (audio evals if #392, vision evals if #405, etc.)
7. Commit with: `deps: update mlx-swift-lm to <sha> (adds <feature>)`

## Key Ecosystem Contacts

| Person | GitHub | Role | Key Repos/PRs |
|---|---|---|---|
| davidkoski | @davidkoski | ml-explore maintainer | mlx-swift-lm reviewer, swift-format tag |
| fdagostino | @fdagostino | Contributor | PRs #390 (merged), #391, #392, #400, #413 (merged), #426 |
| Prince Canuma | @Blaizzy | Community | mlx-vlm (Python VLM), mlx-audio (Python TTS/STT), mlx-audio-swift (Swift TTS/STT) |
| VincentGourbin | @VincentGourbin | Community | gemma-4-swift-mlx (standalone reference implementation) |
| CharlieTLe | @CharlieTLe | Contributor | CI, swift-format, FoundationModels |
| GoodOlClint | @GoodOlClint | Contributor | E-series fixes, MTP, KV cache, pooling |

## mlx-swift Issues Affecting Edge AI Lab

| Issue | Title | Severity | Impact |
|---|---|---|---|
| #424 | conv1d wrong results on iOS GPU (output > 32768 frames) | 🔴 HIGH | Audio encoder uses conv1d — could corrupt results for clips > ~8s on iOS |
| #420 | quantizedMM upcasts to float32 silently | 🟡 MEDIUM | May explain 4-bit performance anomalies |
| #441 | Bump vendored mlx-core for batched RoPE fix | 🟡 MEDIUM | Performance improvement |

## Ecosystem Map

```
ml-explore (Apple official)
├── mlx          — Core Metal GPU framework (C++)
├── mlx-swift    — Swift bindings (our transitive dependency)
├── mlx-swift-lm — LLM/VLM runtime (OUR DIRECT DEPENDENCY)
├── mlx-lm       — Python LLM inference (model conversion tool)
└── mlx-examples — Python examples (Whisper, StableDiffusion)

Blaizzy (Prince Canuma, community)
├── mlx-vlm         — Python VLM inference (Gemma 4 audio works here since Apr 2026)
├── mlx-audio       — Python TTS/STT/STS (standalone, NOT Gemma audio)
├── mlx-audio-swift — Swift TTS/STT/STS SDK (standalone SPM, NOT Gemma audio)
└── mlx-video       — Python video generation (NOT understanding)

VincentGourbin (community)
└── gemma-4-swift-mlx — Standalone Swift Gemma 4 (text+vision+audio+video, reference only)
```
