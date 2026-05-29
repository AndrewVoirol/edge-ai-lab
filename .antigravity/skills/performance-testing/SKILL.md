---
name: performance-testing
description: "Guidelines for running performance tests, capturing metrics, and managing the JSON metrics store for trend tracking. Activate when working with tests, benchmarks, or performance analysis."
---

# Performance Testing Framework

## Test Architecture: Two Layers

Tests are organized into two test plans for selective execution:

| Test Plan | Purpose | Model Required | Speed | Files |
|---|---|---|---|---|
| **UnitTests** | Logic validation with mocks | ❌ No | Fast (seconds) | `GemmaEdgeGalleryTests.swift`, `MockInstrumentedEngine.swift` |
| **PerformanceTests** | Real inference benchmarking | ✅ Yes | Slow (minutes) | `PerformanceTests.swift` |

### InstrumentedEngineProtocol
All tests use the `InstrumentedEngineProtocol` abstraction:
- **Unit tests** inject `MockInstrumentedEngine` — fast, deterministic, no model needed
- **Performance tests** use `InstrumentedEngine` — real LiteRT-LM inference with signposts

> [!IMPORTANT]
> **Never call LiteRTLM APIs directly from test code.** Always go through `InstrumentedEngineProtocol`.

## Running Tests

### Unit Tests (fast, no model)
```
MCP Server: xcodebuild-mcp
Tool: simulator test
Args: scheme=GemmaEdgeGallery_iOS, workspace=GemmaEdgeGallery.xcworkspace, testPlan=UnitTests
```

### Performance Tests (requires model in models/)
```
MCP Server: xcodebuild-mcp
Tool: simulator test  
Args: scheme=GemmaEdgeGallery_iOS, workspace=GemmaEdgeGallery.xcworkspace, testPlan=PerformanceTests
```

> [!WARNING]
> Performance tests require a `.litertlm` model file in the `models/` directory. If no model is present, performance tests will be skipped. Run `.antigravity/skills/performance-testing/scripts/provision-model.sh` to check model availability.

## Metrics Store

Test results are automatically captured to `metrics/history.json` by a PostToolUse hook after every test execution via XcodeBuildMCP.

### Schema
Each entry in `metrics/history.json`:
```json
{
  "timestamp": "2026-05-29T20:00:00Z",
  "testPlan": "PerformanceTests",
  "results": [
    {
      "suite": "PerformanceTests",
      "test": "testInferenceLatency",
      "status": "passed",
      "durationMs": 1234
    }
  ],
  "flags": {
    "enableBenchmark": true,
    "enableSpeculativeDecoding": null,
    "enableConversationConstrainedDecoding": false
  },
  "model": "gemma-4-E2B-it-web.litertlm",
  "device": "iPhone 16 Pro Simulator"
}
```

### Purpose
The metrics store enables trend tracking across:
- Model changes (drop in different models, compare performance)
- Feature additions/removals (impact on latency/memory)
- Flag configurations (speculative decoding impact)
- Device variations (simulator vs device)

## os_signpost Categories

The `InstrumentedEngine` emits signposts under subsystem `com.andrewvoirol.GemmaEdgeGallery.performance`:

| Category | Signpost | What It Measures |
|---|---|---|
| `model-load` | `ModelLoad` | Time from engine init to model ready |
| `inference` | `Inference` | Full inference duration (prompt to completion) |
| `first-token` | `FirstToken` | Time to first token (TTFT) |

## Baseline Methodology
- No hard CI/CD failures on regressions
- Metrics are append-only for trend analysis
- Agents query `metrics/history.json` to detect regressions
- Human review for significant regressions
