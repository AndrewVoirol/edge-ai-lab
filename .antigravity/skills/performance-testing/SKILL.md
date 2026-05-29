---
name: Performance Testing Framework
description: Guidelines for running performance tests, capturing metrics, and managing the JSON metrics store.
---

# Performance Testing Framework

## 1. Test Architecture

Two test layers separated by Xcode Test Plans:

- **UnitTests.xctestplan**: Mock-based tests for instrumentation plumbing. No model dependency. Fast.
- **PerformanceTests.xctestplan**: Real model tests with `measure(metrics:)` blocks. Requires ~2GB model file.

Both layers live in the same test targets (`GemmaEdgeGallery_iOSTests` / `GemmaEdgeGallery_macOSTests`). Test files use `#if os(iOS)` / `#elseif os(macOS)` for platform-specific imports.

## 2. InstrumentedEngine Protocol

All inference interaction goes through `InstrumentedEngineProtocol`:

- **Unit tests** inject `MockInstrumentedEngine` — returns configurable `BenchmarkInfo` values without loading a real model.
- **Performance tests** inject real `InstrumentedEngine` — wraps LiteRTLM and produces actual benchmark data.

Never call LiteRTLM APIs directly from test code. Always go through the protocol.

## 3. JSON Metrics Store

- **Location**: `metrics/history.json` in the project root.
- **Append-only**: Each test run adds an entry. Never overwrite or truncate.
- **Schema** includes: timestamp, model name, platform, device, all `BenchmarkInfo` fields, `ExperimentalFlags` state.
- The agent queries this file for trend analysis and regression detection.

## 4. Running Tests

- **Unit tests**: Use XcodeBuildMCP `test` tool with the `UnitTests` test plan.
- **Performance tests**: Use XcodeBuildMCP `test` tool with the `PerformanceTests` test plan. Requires a model file at a known path.
- **Parse results**: Use XcodeBuildMCP `getTestResults` with the xcresult bundle path.
- **Do NOT** use Fastlane for test execution. Fastlane is for build/distribution only.

## 5. Baseline Methodology

- **NO** hard CI/CD failures on performance regressions.
- Measure first, derive baselines from first principles, enforce thresholds only after understanding model capabilities.
- Alerts are soft: agent-generated reports from JSON metrics store trends.

## 6. XCTMetrics (Phase 2)

Performance tests use `measure(metrics:)` with:

- `XCTMemoryMetric()` — peak memory (critical for 2–8GB models)
- `XCTCPUMetric()` — CPU usage (anomaly detector for GPU fallback)
- `XCTOSSignpostMetric()` — validates `os_signpost` interval durations

## 7. os_signpost Categories

- **Subsystem**: `com.andrewvoirol.GemmaEdgeGallery.performance`
- **Categories**: `model-load`, `inference`, `first-token`
- Signposts wrap: engine initialization, message streaming, first token event.
