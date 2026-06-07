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

---

## Feature Expansion & Testing Overhaul (June 3, 2026 — Session 2)

**Objective:** Comprehensive modernization following the Stack Audit. Focused on multimodal input, UI completion, testing infrastructure expansion, and automation hardening.

### Changes Made

**Multimodal Input Support:**
- Added `sendMessageStream(_:imageData:audioData:)` to `InstrumentedEngineProtocol` with full os_signpost instrumentation
- Image input via `PhotosPicker` (iOS) and photo library (macOS)
- Audio input via file importer for `.wav`/`.mp3`/`.aac` files
- Visual attachment strip with image thumbnail preview and remove buttons
- Capability badges in header: 📷 image, 🎵 audio, 🐰 MTP icons
- Attachments auto-clear after each generation

**UI Polish (Stack Audit Completion):**
- Seed stepper in Sampler Configuration section (reproducible generation)
- System Message TextEditor with clear button and examples
- Both take effect on next model load (documented with warnings)

**Testing Infrastructure (49 → 107 tests):**
- `ModelRegistryTests` (12 tests) — exhaustive registry validation
- `ConversationViewModelSamplerTests` (9 tests) — seed/systemMessage/preset coverage
- `DownloadManagerTests` (10 tests) — state management and auth flow
- `GalleryModelDiscoveryTests` (9 tests) — file scanning and lookup matching
- `MockInstrumentedEngine` updated with multimodal tracking (imageData/audioData)
- `UnitTests.xctestplan` expanded from 9 → 13 test classes

**Automation Expansion:**
- `automation/flows/multimodal_flow.json` — UI flow for image+text inference
- `automation/flows/settings_flow.json` — UI flow for all settings verification
- `IntegrationTests.xctestplan` — functional tests requiring a model
- `automation/ci_test_runner.sh` — full test pyramid orchestrator (Unit → Integration → Performance)

### Key Decisions
- Stay on `.branch("main")` for SDK — v0.13.0 decision from Stack Audit session continued
- Focus on E2B/E4B/12B models — 26B MoE and 31B Dense deferred
- Tool calling deferred to next session — need observability layer first
- Device testing required — simulators insufficient per user direction

### Competitive Context
- Gallery macOS app at v1.0.14/v1.0.15 with MCP support, Agent Skills, Thinking Mode
- New "Google AI Edge Eloquent" macOS app for voice dictation (Gemma 4 12B)
- MediaPipe LLM Inference API deprecated on Android & iOS — LiteRT-LM is replacement

---

## Session 3 — Tool Calling, Thinking Mode, Multi-turn Chat & UI Overhaul (June 3, 2026)

**Objective:** Implement the four major feature pillars identified in the Stack Audit: on-device function calling with observability, thinking mode with streaming parser, multi-turn conversation state management, and a complete conversation UI overhaul with chat bubbles.

### Phase 1 — Tool Calling with Observability

**6 Built-in Tools** (all side-effect-free, offline-capable):

| Tool | Function Name | Description |
|------|--------------|-------------|
| CalculatorTool | `calculate` | NSExpression-based safe math evaluation |
| DateTimeTool | `get_current_datetime` | Current date/time with optional IANA timezone |
| DeviceInfoTool | `get_device_info` | Device model, OS, processor, memory, thermal state |
| UnitConverterTool | `convert_units` | Foundation Measurement API for temp/distance/weight/data |
| TextAnalyzerTool | `analyze_text` | Word/char/sentence counts, reading time, language detection |
| SystemHealthTool | `get_system_health` | **Killer differentiator** — model introspects its own hardware |

**Architecture:**
- `ToolRegistry` enum with `defaultTools: [Tool]` and `createToolManager() -> ToolManager`
- `ToolCallEvent` struct (Identifiable, Sendable) for observability: name, args, result, duration, success
- All tools return JSON strings via shared `jsonString(from:)` helper
- SystemHealthTool: thermal emoji indicators, memory pressure classification, battery (iOS), disk space

### Phase 2 — Thinking Mode

**ThinkingParser** — streaming-aware parser for `<think>`/`<|think|>` delimiter tags:
- Two-state machine (normal/thinking) with buffer-based approach
- `drainBuffer(isFinal:)` core loop: scans for tags, emits segments, flips state
- `findSafeEmitBoundary()`: retains trailing `maxTagLength - 1` chars for partial tag handling
- `finalize()` flushes buffer as literal text (incomplete tags → regular content)
- Convenience `ThinkingParser.parse(_:)` static method for non-streaming use cases

### Phase 3 — Multi-turn Chat Data Model

**ChatMessage** — Identifiable message model:
- `Role` enum: `.user`, `.assistant`, `.system`, `.toolResult`
- `Attachment` enum: `.image(Data)`, `.audio(Data)` with convenience predicates
- `BenchmarkSnapshot` — frozen copy of `BenchmarkInfo` at message completion time
- Factory methods: `.user(_:imageData:audioData:)`, `.assistant()`, `.system(_:)`

**ConversationState** — collection wrapper:
- `messages: [ChatMessage]` with `append`, `clear`, `count`, `isEmpty`
- `updateLastAssistantMessage(content:thinkingContent:toolCalls:isStreaming:benchmarkInfo:)`
- `isAssistantStreaming` computed property for UI binding

### Phase 4 — Conversation UI Overhaul

**ChatBubbleView** component:
- Role-based styling: user (right/blue), assistant (left/gray), system (yellow), tool result (orange)
- Collapsible thinking section with pulsing brain icon (`DisclosureGroup`)
- Inline tool call chips with expandable details (arguments + result + timing)
- Multimodal attachment previews (image thumbnails, audio waveform badge)
- Per-message benchmark mini-badge (tok/s, TTFT, token count)
- Cross-platform image handling (`#if os(iOS)` / `#elseif os(macOS)`)

**ContentView** updates:
- Chat bubble list replaces raw text dump (`LazyVStack` + `ScrollViewReader`)
- Auto-scroll to latest message on new messages and during streaming
- "New Chat" button with conversation reset
- Enter-to-send (`.onSubmit` on TextField)
- Thinking mode pulsing indicator in action bar
- Tool calling & thinking mode capability badges in header

**InferenceSettingsView** updates:
- "Thinking Mode" section with enable toggle and description
- "Tool Calling" section with enable toggle and tool list display
- Tool list shows all 6 tools with names and descriptions

**ConversationViewModel** rewrite:
- `ConversationState` replaces single `responseText` (backward-compatible via computed property)
- ThinkingParser integration in streaming loop
- `newConversation()` method clears chat + resets engine conversation
- Tool call event collection and per-message benchmark snapshots

### Phase 5 — Testing

**35 new tests (107 → 142 total):**
- `ToolCallingTests` (16 tests): Calculator, DateTime, UnitConverter, TextAnalyzer, ToolRegistry, ToolCallEvent
- `ThinkingParserTests` (11 tests): streaming parsing, tag variants, split tags, multiple blocks, reset, HTML pass-through
- `ChatMessageTests` (8 tests): message creation, ConversationState, streaming state
- `UnitTests.xctestplan` updated with all new test classes

### Key Decisions
- Tools are side-effect-free and offline-only — no network calls, no file writes
- SystemHealthTool is the differentiator: on-device model reasons about its own hardware
- ThinkingParser handles both `<think>` and `<|think|>` tag variants
- `enableThinking` and `enableToolCalling` are `var` properties (not init params) for binary/struct compatibility
- Conversation UI uses `LazyVStack` for performance with long conversations

---

## Session 10 — Edge AI Lab Identity: 3-Column Layout, Dark Forest, HF Browser (June 7, 2026)

**Objective:** Transform from "chat app with benchmarks" to "Edge AI research instrument." The chat is secondary — it's how you *exercise* the model, not the point.

### Changes Made

**Dark Forest Design System:** Complete palette replacement in `DesignSystem.swift`. All system colors replaced with `AppColors` tokens. Deep charcoals, muted greens, cream text, warm amber accents. New `ForestGlassModifier`, `AppShadow` tokens.

**Streaming Polish:** `LoadingShimmerView` (shimmer skeleton before TTFT), `BlinkingCursor` during streaming, fixed thinking chevron rotation (was 0:0 no-op), removed dead `MessageChunk` struct.

**3-Column NavigationSplitView (macOS):** Sidebar (models/benchmarks/conversations) → Detail (model info/dashboard/comparison) → Chat. iOS uses 3-tab TabView. `appliedSharedModifiers()` wrapper avoids `@Bindable` ViewModifier conformance issues.

**HuggingFace Model Browser:** Full API client (`HFModelBrowser.swift`). List by org, model detail, format detection (LiteRT-LM vs MLX), auth via HFTokenStorage, caching.

**Benchmark Comparison:** `BenchmarkComparisonView.swift` with animated performance bars and `PerformanceTier` color coding.

### Key Lessons

1. `ViewModifier` + `@Bindable` = compiler error → use `@ViewBuilder` wrapping method instead
2. Full test suite takes 15+ min (integration tests load models) → always use `-only-testing`
3. `test_macos` MCP tool runs ALL tests → use raw xcodebuild with `-only-testing` for agent feedback
4. `linkd.autoShortcut` errors (167+) are harmless macOS IPC noise → ignore completely
5. grep `**` regex is invalid → use `TEST SUCCEEDED` without asterisks
6. `MCPClientTests` was missing from `UnitTests.xctestplan` → fixed

### Verification: 85/85 unit tests pass, BUILD SUCCEEDED, zero system color leaks.


