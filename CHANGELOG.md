# Changelog

All notable changes to Edge AI Lab will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.0] - 2026-06-08

### Added

- **Layout** — 3-column `NavigationSplitView` layout (macOS) with Sidebar → Lab → Chat panes.
- **Multi-model support** — Gemma 4 E2B (Standard / Web), E4B (Standard / Web), and 12B Dense.
- **On-device inference** via LiteRT-LM with Metal GPU acceleration.
- **Smart GPU → CPU fallback** with detailed diagnostics when Metal is unavailable or fails.
- **6 built-in tools** — Calculator, DateTime, DeviceInfo, UnitConverter, TextAnalyzer, SystemHealth — for structured tool-calling workflows.
- **Agent Skills [Beta]** — Wikipedia and Maps skills (network-dependent, behind feature flag).
- **Thinking mode** with streaming `<think>` block parser and collapsible UI disclosure.
- **Multimodal input** — image attachments via `PhotosPicker` and audio file attachments (`.wav`, `.mp3`, `.aac`).
- **Deep benchmarking** — per-token latency, P95, time-to-first-token (TTFT), memory delta, and thermal-state tracking.
- **Performance dashboard** with historical metrics rendered via Swift Charts.
- **MCP server support** (macOS) via stdio-based JSON-RPC for external tool integration.
- **HuggingFace model browser** with organization listing and format detection.
- **Conversation persistence** with auto-save, fork, rename, export (JSON), and delete.
- **Dark Forest design system** with a curated color palette and centralized design tokens.
- **Developer automation harness** for benchmark matrix runs across models and backends.
- **282 unit tests** + UI test suite covering core inference, tool-calling, and navigation flows.

### Architecture

- MVVM with `@Observable` and full Swift 6 concurrency (`Sendable`, `actor` isolation).
- Protocol-based dependency injection (`InstrumentedEngineProtocol`) for testability.
- Centralized design tokens in `DesignSystem.swift` — no hardcoded colors or spacing.
- `os.Logger` + `os_signpost` instrumentation throughout for profiling and diagnostics.

### Known Limitations

- LiteRT-LM SDK is tracked on `branch("main")` — tagged releases currently have SPM packaging issues.
- App Sandbox is disabled (required for model file access and MCP subprocess spawning).
- iOS support is present in the codebase but is not the primary shipping target for v1.0.
- E4B and 12B benchmarks may not have formal numbers at launch.

[Unreleased]: https://github.com/AndrewVoirol/edge-ai-lab/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/AndrewVoirol/edge-ai-lab/releases/tag/v1.0.0
