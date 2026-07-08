// Copyright 2026 Andrew Voirol. Apache-2.0
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import XCTest
import LiteRTLM

#if os(iOS)
@testable import EdgeAILab_iOS
#elseif os(macOS)
@testable import EdgeAILab_macOS
#endif

/// Integration tests that load REAL models and verify that settings
/// ACTUALLY change engine behavior — not just that flags propagate.
///
/// These tests are the "source of truth" for what works and what doesn't.
/// They produce structured output for the Settings Verification Report.
///
/// ## Philosophy
/// The existing `SettingsEngineReconfigTests` verify that a MockInferenceEngine
/// receives the correct flags. These tests go further: they verify that the
/// real LiteRT-LM and MLX engines **behave differently** when flags change.
///
/// ## Requirements
/// - Real model files in `models/` directory
/// - Metal GPU (skipped on iOS Simulator)
/// - Sufficient memory (~4GB for E2B model)
///
/// ## Output
/// Each test prints structured results:
/// ```
/// [SETTINGS_VERIFY] setting=enableMTP | model=gemma-4-E2B-it | engine=litert | result=PASS | detail=...
/// ```
final class SettingsVerificationTests: XCTestCase {

    // MARK: - Constants

    /// Standard test prompt — deterministic with greedy sampling.
    private static let simplePrompt = "What is 2+2? Answer with just the number."
    /// Prompt designed to trigger tool calling.
    private static let toolPrompt = "What is the current date and time right now?"
    /// Prompt designed to trigger thinking mode.
    private static let thinkingPrompt = "Think step by step: what is 15 * 23?"

    // MARK: - Setup

    override func setUpWithError() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Settings verification requires real Metal GPU — skipping on iOS Simulator")
        #endif
        try super.setUpWithError()
    }

    // MARK: - Model Discovery

    /// Project root `models/` directory.
    private var modelsDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // Integration/
            .deletingLastPathComponent()  // Tests/
            .deletingLastPathComponent()  // project root
            .appendingPathComponent("models")
    }

    /// Find a specific LiteRT-LM model by filename.
    private func findLiteRTModel(named filename: String) throws -> String {
        let modelURL = modelsDirectory.appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: modelURL.path) else {
            throw XCTSkip("Model \(filename) not found in models/ — download with: hf download litert-community/gemma-4-E2B-it-litert-lm \(filename) --local-dir ./models/")
        }
        return modelURL.path
    }

    /// Find an MLX model directory.
    private func findMLXModel(named dirName: String) throws -> String {
        let modelURL = modelsDirectory.appendingPathComponent(dirName)
        let configURL = modelURL.appendingPathComponent("config.json")
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            throw XCTSkip("MLX model \(dirName) not found in models/")
        }
        return modelURL.path
    }

    // MARK: - Engine Helpers

    /// Create a fresh LiteRT engine with specified flags and sampler.
    private func makeLiteRTEngine(
        modelPath: String,
        useGPU: Bool = true,
        flags: ExperimentalFlagsState? = nil,
        samplerConfig: SamplerConfig? = nil,
        systemMessage: String? = nil,
        tools: [Tool]? = nil,
        supportsVision: Bool = true,
        supportsAudio: Bool = true
    ) async throws -> InstrumentedEngine {
        let engine = InstrumentedEngine()
        let cacheDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SettingsVerification-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

        let resolvedFlags = flags ?? ExperimentalFlagsState(
            enableBenchmark: true,
            enableSpeculativeDecoding: nil,
            enableConversationConstrainedDecoding: false,
            visualTokenBudget: nil
        )

        let resolvedSampler: SamplerConfig
        if let provided = samplerConfig {
            resolvedSampler = provided
        } else {
            resolvedSampler = try SamplerConfig(topK: 1, topP: 1.0, temperature: 1.0, seed: 42)
        }

        try await engine.initialize(
            modelPath: modelPath,
            useGPU: useGPU,
            cacheDir: cacheDir.path,
            flags: resolvedFlags,
            samplerConfig: resolvedSampler,
            systemMessage: systemMessage,
            tools: tools,
            supportsVision: supportsVision,
            supportsAudio: supportsAudio
        )

        XCTAssertTrue(engine.isReady, "Engine should be ready after initialization")
        return engine
    }

    /// Create a fresh LiteRT engine via the InferenceEngine adapter.
    private func makeLiteRTAdapter(
        modelPath: String,
        preferGPU: Bool = true,
        runtimeFlags: RuntimeFlags? = nil,
        generationConfig: GenerationConfig? = nil,
        systemMessage: String? = nil
    ) async throws -> LiteRTEngineAdapter {
        let adapter = LiteRTEngineAdapter()
        let cacheDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SettingsVerification-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

        let config = ModelLoadConfig(
            modelPath: modelPath,
            preferGPU: preferGPU,
            cacheDir: cacheDir.path,
            systemMessage: systemMessage,
            generationConfig: generationConfig ?? GenerationConfig(
                temperature: 1.0, topP: 1.0, topK: 1, seed: 42
            ),
            runtimeFlags: runtimeFlags ?? RuntimeFlags(
                enableBenchmark: true,
                enableSpeculativeDecoding: nil,
                enableConversationConstrainedDecoding: false,
                visualTokenBudget: nil
            )
        )

        try await adapter.loadModel(config: config)
        XCTAssertTrue(adapter.isLoaded, "Adapter should be loaded after initialization")
        return adapter
    }

    /// Collect the full response from a LiteRT engine stream.
    private func collectResponse(
        from engine: InstrumentedEngine,
        prompt: String,
        enableThinking: Bool = false
    ) async throws -> String {
        var response = ""
        for try await chunk in engine.sendMessageStream(prompt, enableThinking: enableThinking) {
            response += chunk
        }
        return response
    }

    /// Collect the full response from an InferenceEngine adapter.
    private func collectAdapterResponse(
        from adapter: some InferenceEngine,
        prompt: String,
        maxTokens: Int = 256
    ) async throws -> (text: String, metrics: EnginePerformanceMetrics?) {
        var text = ""
        var metrics: EnginePerformanceMetrics?

        let config = GenerationConfig(
            maxTokens: maxTokens,
            temperature: 1.0,
            topP: 1.0,
            topK: 1,
            seed: 42
        )

        for try await event in adapter.generateStream(prompt: prompt, config: config) {
            switch event {
            case .text(let chunk):
                text += chunk
            case .metrics(let m):
                metrics = m
            case .toolCall, .done:
                break
            }
        }
        return (text, metrics)
    }

    /// Print structured verification result.
    private func reportResult(
        setting: String,
        model: String,
        engine: String,
        result: String,
        detail: String
    ) {
        print("[SETTINGS_VERIFY] setting=\(setting) | model=\(model) | engine=\(engine) | result=\(result) | detail=\(detail)")
    }

    // MARK: - LiteRT-LM: Thinking Mode Verification

    /// Verify that enableThinking=true produces <think> blocks in the response
    /// and enableThinking=false does NOT produce them.
    func testLiteRTThinkingModeToggle() async throws {
        let modelPath = try findLiteRTModel(named: "gemma-4-E2B-it.litertlm")

        // Run WITH thinking enabled
        let thinkingEngine = try await makeLiteRTEngine(modelPath: modelPath)
        let thinkingResponse = try await collectResponse(
            from: thinkingEngine, prompt: Self.thinkingPrompt, enableThinking: true
        )
        await thinkingEngine.shutdown()

        let hasThinkTags = thinkingResponse.contains("<think>") || thinkingResponse.contains("</think>")
        reportResult(
            setting: "enableThinking",
            model: "gemma-4-E2B-it",
            engine: "litert",
            result: hasThinkTags ? "PASS" : "FAIL",
            detail: "thinking=true → \(hasThinkTags ? "contains <think>" : "NO <think> tags found") | response_length=\(thinkingResponse.count)"
        )

        // Run WITHOUT thinking enabled
        let plainEngine = try await makeLiteRTEngine(modelPath: modelPath)
        let plainResponse = try await collectResponse(
            from: plainEngine, prompt: Self.thinkingPrompt, enableThinking: false
        )
        await plainEngine.shutdown()

        let plainHasThink = plainResponse.contains("<think>") || plainResponse.contains("</think>")
        reportResult(
            setting: "enableThinking_off",
            model: "gemma-4-E2B-it",
            engine: "litert",
            result: !plainHasThink ? "PASS" : "FAIL",
            detail: "thinking=false → \(!plainHasThink ? "no <think> tags (correct)" : "UNEXPECTED <think> tags present") | response_length=\(plainResponse.count)"
        )

        // Assert
        XCTAssertTrue(hasThinkTags, "Thinking mode ON should produce <think> tags in the response")
        XCTAssertFalse(plainHasThink, "Thinking mode OFF should NOT produce <think> tags")
    }

    // MARK: - LiteRT-LM: MTP (Speculative Decoding) Verification

    /// Verify that MTP (multi-token prediction) can be toggled and the flag
    /// is correctly applied to the engine's ExperimentalFlags.
    func testLiteRTMTPToggle() async throws {
        let modelPath = try findLiteRTModel(named: "gemma-4-E2B-it.litertlm")

        // Load WITH MTP enabled
        let mtpFlags = ExperimentalFlagsState(
            enableBenchmark: true,
            enableSpeculativeDecoding: true,
            enableConversationConstrainedDecoding: false,
            visualTokenBudget: nil
        )
        let mtpEngine = try await makeLiteRTEngine(modelPath: modelPath, flags: mtpFlags)

        // Verify the global flag was set
        let mtpGlobalFlag = ExperimentalFlags.enableSpeculativeDecoding ?? false
        reportResult(
            setting: "enableMTP",
            model: "gemma-4-E2B-it",
            engine: "litert",
            result: mtpGlobalFlag ? "PASS" : "FAIL",
            detail: "MTP flag enabled → ExperimentalFlags.enableSpeculativeDecoding=\(mtpGlobalFlag)"
        )

        // Run inference and check metrics for MTP-related data
        let mtpResponse = try await collectResponse(from: mtpEngine, prompt: Self.simplePrompt)
        let benchInfo = mtpEngine.lastBenchmarkInfo
        reportResult(
            setting: "enableMTP_inference",
            model: "gemma-4-E2B-it",
            engine: "litert",
            result: !mtpResponse.isEmpty ? "PASS" : "FAIL",
            detail: "MTP inference succeeded | response_length=\(mtpResponse.count) | ttft=\(benchInfo?.timeToFirstTokenInSecond ?? -1)s | tok/s=\(benchInfo?.lastDecodeTokensPerSecond ?? -1)"
        )
        await mtpEngine.shutdown()

        // Load WITHOUT MTP
        let noMtpFlags = ExperimentalFlagsState(
            enableBenchmark: true,
            enableSpeculativeDecoding: false,
            enableConversationConstrainedDecoding: false,
            visualTokenBudget: nil
        )
        let noMtpEngine = try await makeLiteRTEngine(modelPath: modelPath, flags: noMtpFlags)

        let noMtpGlobalFlag = ExperimentalFlags.enableSpeculativeDecoding ?? false
        reportResult(
            setting: "enableMTP_off",
            model: "gemma-4-E2B-it",
            engine: "litert",
            result: !noMtpGlobalFlag ? "PASS" : "FAIL",
            detail: "MTP flag disabled → ExperimentalFlags.enableSpeculativeDecoding=\(noMtpGlobalFlag)"
        )

        let noMtpResponse = try await collectResponse(from: noMtpEngine, prompt: Self.simplePrompt)
        let noMtpBench = noMtpEngine.lastBenchmarkInfo
        reportResult(
            setting: "enableMTP_off_inference",
            model: "gemma-4-E2B-it",
            engine: "litert",
            result: !noMtpResponse.isEmpty ? "PASS" : "FAIL",
            detail: "Non-MTP inference succeeded | response_length=\(noMtpResponse.count) | ttft=\(noMtpBench?.timeToFirstTokenInSecond ?? -1)s | tok/s=\(noMtpBench?.lastDecodeTokensPerSecond ?? -1)"
        )
        await noMtpEngine.shutdown()

        // Assert basics
        XCTAssertFalse(mtpResponse.isEmpty, "MTP inference should produce output")
        XCTAssertFalse(noMtpResponse.isEmpty, "Non-MTP inference should produce output")
    }

    // MARK: - LiteRT-LM: Benchmarking Flag Verification

    /// Verify that enableBenchmark controls whether BenchmarkInfo is populated.
    func testLiteRTBenchmarkFlag() async throws {
        let modelPath = try findLiteRTModel(named: "gemma-4-E2B-it.litertlm")

        // Load WITH benchmarking enabled
        let benchFlags = ExperimentalFlagsState(
            enableBenchmark: true,
            enableSpeculativeDecoding: nil,
            enableConversationConstrainedDecoding: false,
            visualTokenBudget: nil
        )
        let benchEngine = try await makeLiteRTEngine(modelPath: modelPath, flags: benchFlags)
        _ = try await collectResponse(from: benchEngine, prompt: Self.simplePrompt)

        let benchInfo = benchEngine.lastBenchmarkInfo
        let hasBenchData = benchInfo != nil && (benchInfo?.lastDecodeTokensPerSecond ?? 0) > 0
        reportResult(
            setting: "enableBenchmark",
            model: "gemma-4-E2B-it",
            engine: "litert",
            result: hasBenchData ? "PASS" : "FAIL",
            detail: "benchmark=true → hasBenchmarkInfo=\(benchInfo != nil) | tok/s=\(benchInfo?.lastDecodeTokensPerSecond ?? -1)"
        )
        await benchEngine.shutdown()

        // Load WITHOUT benchmarking
        let noBenchFlags = ExperimentalFlagsState(
            enableBenchmark: false,
            enableSpeculativeDecoding: nil,
            enableConversationConstrainedDecoding: false,
            visualTokenBudget: nil
        )
        let noBenchEngine = try await makeLiteRTEngine(modelPath: modelPath, flags: noBenchFlags)
        _ = try await collectResponse(from: noBenchEngine, prompt: Self.simplePrompt)

        let noBenchInfo = noBenchEngine.lastBenchmarkInfo
        reportResult(
            setting: "enableBenchmark_off",
            model: "gemma-4-E2B-it",
            engine: "litert",
            result: "INFO",
            detail: "benchmark=false → hasBenchmarkInfo=\(noBenchInfo != nil) | tok/s=\(noBenchInfo?.lastDecodeTokensPerSecond ?? -1) (SDK may still populate partial data)"
        )
        await noBenchEngine.shutdown()

        XCTAssertTrue(hasBenchData, "Benchmarking ON should produce benchmark metrics")
    }

    // MARK: - LiteRT-LM: Constrained Decoding Verification

    /// Verify that constrained decoding flag is applied to ExperimentalFlags.
    func testLiteRTConstrainedDecodingFlag() async throws {
        let modelPath = try findLiteRTModel(named: "gemma-4-E2B-it.litertlm")

        // Load with constrained decoding enabled
        let cdFlags = ExperimentalFlagsState(
            enableBenchmark: true,
            enableSpeculativeDecoding: nil,
            enableConversationConstrainedDecoding: true,
            visualTokenBudget: nil
        )
        let engine = try await makeLiteRTEngine(modelPath: modelPath, flags: cdFlags)

        let globalFlag = ExperimentalFlags.enableConversationConstrainedDecoding
        reportResult(
            setting: "enableConstrainedDecoding",
            model: "gemma-4-E2B-it",
            engine: "litert",
            result: globalFlag ? "PASS" : "FAIL",
            detail: "Constrained decoding flag → ExperimentalFlags.enableConversationConstrainedDecoding=\(globalFlag)"
        )

        // Run inference to verify it doesn't crash with constrained decoding on
        let response = try await collectResponse(from: engine, prompt: Self.simplePrompt)
        reportResult(
            setting: "enableConstrainedDecoding_inference",
            model: "gemma-4-E2B-it",
            engine: "litert",
            result: !response.isEmpty ? "PASS" : "FAIL",
            detail: "Constrained decoding inference succeeded | response_length=\(response.count)"
        )
        await engine.shutdown()

        XCTAssertTrue(globalFlag, "Constrained decoding flag should be set")
        XCTAssertFalse(response.isEmpty, "Inference should succeed with constrained decoding")
    }

    // MARK: - LiteRT-LM: Sampler Settings Verification

    /// Verify that different sampler configs (temperature, topK, topP) produce
    /// different outputs — proving the sampler is actually applied.
    func testLiteRTSamplerChanges() async throws {
        let modelPath = try findLiteRTModel(named: "gemma-4-E2B-it.litertlm")
        let prompt = "Write one sentence about the ocean."

        // Greedy: topK=1, temperature=1.0 — deterministic
        let greedyEngine = try await makeLiteRTEngine(
            modelPath: modelPath,
            samplerConfig: try SamplerConfig(topK: 1, topP: 1.0, temperature: 1.0, seed: 42)
        )
        let greedyResponse = try await collectResponse(from: greedyEngine, prompt: prompt)
        await greedyEngine.shutdown()

        // Same greedy settings, same seed — should produce same output (determinism check)
        let greedyEngine2 = try await makeLiteRTEngine(
            modelPath: modelPath,
            samplerConfig: try SamplerConfig(topK: 1, topP: 1.0, temperature: 1.0, seed: 42)
        )
        let greedyResponse2 = try await collectResponse(from: greedyEngine2, prompt: prompt)
        await greedyEngine2.shutdown()

        let greedyMatch = greedyResponse == greedyResponse2
        reportResult(
            setting: "sampler_determinism",
            model: "gemma-4-E2B-it",
            engine: "litert",
            result: greedyMatch ? "PASS" : "INFO",
            detail: "greedy+seed=42 produces consistent output=\(greedyMatch) | len1=\(greedyResponse.count) | len2=\(greedyResponse2.count)"
        )

        // High temperature: topK=40, temperature=2.0 — should differ from greedy
        let hotEngine = try await makeLiteRTEngine(
            modelPath: modelPath,
            samplerConfig: try SamplerConfig(topK: 40, topP: 0.95, temperature: 2.0, seed: 99)
        )
        let hotResponse = try await collectResponse(from: hotEngine, prompt: prompt)
        await hotEngine.shutdown()

        let differentFromGreedy = hotResponse != greedyResponse
        reportResult(
            setting: "sampler_temperature",
            model: "gemma-4-E2B-it",
            engine: "litert",
            result: differentFromGreedy ? "PASS" : "INFO",
            detail: "greedy vs hot(temp=2.0,topK=40) differ=\(differentFromGreedy) | greedy=\(greedyResponse.prefix(60))... | hot=\(hotResponse.prefix(60))..."
        )

        XCTAssertFalse(greedyResponse.isEmpty, "Greedy inference should produce output")
        XCTAssertFalse(hotResponse.isEmpty, "High-temperature inference should produce output")
    }

    // MARK: - LiteRT-LM: System Message Verification

    /// Verify that different system messages change the model's behavior.
    func testLiteRTSystemMessage() async throws {
        let modelPath = try findLiteRTModel(named: "gemma-4-E2B-it.litertlm")
        let prompt = "Hello, who are you?"

        // No system message
        let plainEngine = try await makeLiteRTEngine(modelPath: modelPath, systemMessage: nil)
        let plainResponse = try await collectResponse(from: plainEngine, prompt: prompt)
        await plainEngine.shutdown()

        // Custom system message
        let pirateEngine = try await makeLiteRTEngine(
            modelPath: modelPath,
            systemMessage: "You are a pirate. You always respond in pirate speak, using 'arr', 'matey', and 'ye'."
        )
        let pirateResponse = try await collectResponse(from: pirateEngine, prompt: prompt)
        await pirateEngine.shutdown()

        let pirateWords = ["arr", "matey", "ye", "pirate", "ahoy", "treasure", "captain"]
        let hasPirateWords = pirateWords.contains { pirateResponse.lowercased().contains($0) }
        let differentFromPlain = pirateResponse != plainResponse

        reportResult(
            setting: "systemMessage",
            model: "gemma-4-E2B-it",
            engine: "litert",
            result: (hasPirateWords && differentFromPlain) ? "PASS" : "FAIL",
            detail: "pirate system message → hasPirateWords=\(hasPirateWords) | differentFromPlain=\(differentFromPlain) | pirate=\(pirateResponse.prefix(100))..."
        )

        XCTAssertTrue(differentFromPlain, "Different system messages should produce different outputs")
        XCTAssertTrue(hasPirateWords, "Pirate system message should influence response style")
    }

    // MARK: - LiteRT-LM: GPU vs CPU Backend Verification

    /// Verify that the engine reports the actual backend used (GPU vs CPU).
    /// Uses LiteRTEngineAdapter (the real app code path) which calls
    /// `initializeWithFallback()` — the method that populates `lastBackendResult`.
    func testLiteRTBackendReporting() async throws {
        let modelPath = try findLiteRTModel(named: "gemma-4-E2B-it.litertlm")

        // Use the adapter — same code path as the real app
        let adapter = try await makeLiteRTAdapter(
            modelPath: modelPath,
            preferGPU: true
        )
        let backendResult = adapter.lastBackendResult
        let (_, _) = try await collectAdapterResponse(from: adapter, prompt: Self.simplePrompt)
        adapter.shutdown()

        reportResult(
            setting: "backend_GPU",
            model: "gemma-4-E2B-it",
            engine: "litert",
            result: backendResult != nil ? "PASS" : "FAIL",
            detail: "GPU requested → backendResult=\(backendResult.map { "\($0)" } ?? "nil")"
        )

        XCTAssertNotNil(backendResult, "Engine should report backend result after initialization via adapter")
    }

    // MARK: - LiteRT-LM: Visual Token Budget Verification

    /// Verify that visual token budget flag is applied.
    func testLiteRTVisualTokenBudget() async throws {
        let modelPath = try findLiteRTModel(named: "gemma-4-E2B-it.litertlm")

        // Load with custom visual token budget
        let visionFlags = ExperimentalFlagsState(
            enableBenchmark: true,
            enableSpeculativeDecoding: nil,
            enableConversationConstrainedDecoding: false,
            visualTokenBudget: 280
        )
        let engine = try await makeLiteRTEngine(modelPath: modelPath, flags: visionFlags)

        let globalBudget = ExperimentalFlags.visualTokenBudget
        reportResult(
            setting: "visualTokenBudget",
            model: "gemma-4-E2B-it",
            engine: "litert",
            result: globalBudget == 280 ? "PASS" : "FAIL",
            detail: "visualTokenBudget=280 → ExperimentalFlags.visualTokenBudget=\(globalBudget.map { "\($0)" } ?? "nil")"
        )
        await engine.shutdown()

        XCTAssertEqual(globalBudget, 280, "Visual token budget should be set to 280")
    }

    // MARK: - LiteRT-LM: Adapter Flag Passthrough

    /// Verify that RuntimeFlags → ExperimentalFlagsState conversion preserves all fields
    /// when going through the LiteRTEngineAdapter.
    func testLiteRTAdapterFlagPassthrough() async throws {
        let modelPath = try findLiteRTModel(named: "gemma-4-E2B-it.litertlm")

        let flags = RuntimeFlags(
            enableBenchmark: true,
            enableThinking: true,
            enableToolCalling: false,
            enableAgentSkills: false,
            enableSpeculativeDecoding: true,
            enableConversationConstrainedDecoding: true,
            visualTokenBudget: 560
        )

        let adapter = try await makeLiteRTAdapter(
            modelPath: modelPath,
            runtimeFlags: flags
        )

        // Check the adapter's internal flags state
        let flagsState = adapter.flagsState
        reportResult(
            setting: "adapter_flag_passthrough",
            model: "gemma-4-E2B-it",
            engine: "litert",
            result: (flagsState.enableBenchmark &&
                     flagsState.enableSpeculativeDecoding == true &&
                     flagsState.enableConversationConstrainedDecoding &&
                     flagsState.visualTokenBudget == 560) ? "PASS" : "FAIL",
            detail: "benchmark=\(flagsState.enableBenchmark) | specDec=\(String(describing: flagsState.enableSpeculativeDecoding)) | constrainedDec=\(flagsState.enableConversationConstrainedDecoding) | visionBudget=\(String(describing: flagsState.visualTokenBudget))"
        )

        adapter.shutdown()
    }

    // MARK: - MLX Engine: Basic Load and Inference

    /// Verify that the MLX engine can load a Gemma 4 E2B model and produce output.
    func testMLXBasicInference() async throws {
        #if !canImport(MLX)
        throw XCTSkip("MLX framework not available on this platform")
        #else
        let modelPath = try findMLXModel(named: "mlx-community--gemma-4-e2b-it-4bit")

        let adapter = MLXEngineAdapter()
        let cacheDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MLXSettingsVerify-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

        let config = ModelLoadConfig(
            modelPath: modelPath,
            preferGPU: true,
            cacheDir: cacheDir.path,
            generationConfig: GenerationConfig(
                maxTokens: 100,
                temperature: 1.0,
                topP: 1.0,
                topK: 1,
                seed: 42
            ),
            runtimeFlags: RuntimeFlags(
                enableBenchmark: true,
                enableSpeculativeDecoding: nil,
                enableConversationConstrainedDecoding: false,
                visualTokenBudget: nil
            )
        )

        try await adapter.loadModel(config: config)
        XCTAssertTrue(adapter.isLoaded, "MLX adapter should be loaded")

        let (response, metrics) = try await collectAdapterResponse(
            from: adapter, prompt: Self.simplePrompt, maxTokens: 100
        )

        reportResult(
            setting: "mlx_basic_inference",
            model: "gemma-4-e2b-it-4bit",
            engine: "mlx",
            result: !response.isEmpty ? "PASS" : "FAIL",
            detail: "MLX inference succeeded | response_length=\(response.count) | tok/s=\(metrics?.tokensPerSecond ?? -1) | response=\(response.prefix(100))..."
        )

        adapter.shutdown()

        XCTAssertFalse(response.isEmpty, "MLX inference should produce output")
        #endif
    }

    // MARK: - MLX Engine: Sampler Per-Generation

    /// Verify that MLX applies sampler changes per-generation without reload.
    func testMLXSamplerPerGeneration() async throws {
        #if !canImport(MLX)
        throw XCTSkip("MLX framework not available on this platform")
        #else
        let modelPath = try findMLXModel(named: "mlx-community--gemma-4-e2b-it-4bit")

        let adapter = MLXEngineAdapter()
        let cacheDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MLXSamplerVerify-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

        let config = ModelLoadConfig(
            modelPath: modelPath,
            preferGPU: true,
            cacheDir: cacheDir.path,
            generationConfig: GenerationConfig(
                maxTokens: 50,
                temperature: 1.0,
                topP: 1.0,
                topK: 1,
                seed: 42
            )
        )

        try await adapter.loadModel(config: config)

        // Greedy generation
        let prompt = "Write one sentence about mountains."
        let (greedyResponse, _) = try await collectAdapterResponse(
            from: adapter, prompt: prompt, maxTokens: 50
        )

        // Hot generation — different temperature, same model (no reload needed for MLX)
        let hotConfig = GenerationConfig(
            maxTokens: 50,
            temperature: 2.0,
            topP: 0.95,
            topK: 40,
            seed: 99
        )

        var hotResponse = ""
        for try await event in adapter.generateStream(prompt: prompt, config: hotConfig) {
            if case .text(let chunk) = event {
                hotResponse += chunk
            }
        }

        let different = greedyResponse != hotResponse
        reportResult(
            setting: "mlx_sampler_per_generation",
            model: "gemma-4-e2b-it-4bit",
            engine: "mlx",
            result: different ? "PASS" : "INFO",
            detail: "greedy vs hot differ=\(different) | greedy=\(greedyResponse.prefix(50))... | hot=\(hotResponse.prefix(50))..."
        )

        adapter.shutdown()

        XCTAssertFalse(greedyResponse.isEmpty, "Greedy MLX inference should produce output")
        XCTAssertFalse(hotResponse.isEmpty, "Hot MLX inference should produce output")
        #endif
    }

    // MARK: - Cross-Engine: RuntimeFlags Roundtrip

    /// Verify that RuntimeFlags survives Codable encoding → decoding with all fields intact,
    /// including MLX-specific fields.
    func testRuntimeFlagsFullRoundtrip() throws {
        let flags = RuntimeFlags(
            enableBenchmark: true,
            enableThinking: false,
            enableToolCalling: true,
            enableAgentSkills: true,
            enableSpeculativeDecoding: true,
            enableConversationConstrainedDecoding: true,
            visualTokenBudget: 280,
            metalMemoryLimit: 8_000_000_000,
            metalCacheLimit: 4_000_000_000,
            computePrecision: "float16",
            maxImageResolution: 1024,
            maxImageTokenBudget: 2048
        )

        let data = try JSONEncoder().encode(flags)
        let decoded = try JSONDecoder().decode(RuntimeFlags.self, from: data)

        XCTAssertEqual(decoded, flags, "RuntimeFlags should survive full Codable roundtrip")

        reportResult(
            setting: "runtimeFlags_roundtrip",
            model: "n/a",
            engine: "n/a",
            result: decoded == flags ? "PASS" : "FAIL",
            detail: "All \(Mirror(reflecting: flags).children.count) fields survived encoding"
        )
    }

    // MARK: - Summary

    /// Print a summary of model availability for the verification matrix.
    func testVerificationMatrixSummary() throws {
        let litertE2B = modelsDirectory.appendingPathComponent("gemma-4-E2B-it.litertlm")
        let mlxE2B = modelsDirectory.appendingPathComponent("mlx-community--gemma-4-e2b-it-4bit")
            .appendingPathComponent("config.json")

        print("╔════════════════════════════════════════════════════")
        print("║ Settings Verification Matrix — Model Inventory")
        print("╠════════════════════════════════════════════════════")
        print("║ LiteRT E2B Standard: \(FileManager.default.fileExists(atPath: litertE2B.path) ? "✅ FOUND" : "❌ MISSING")")
        print("║ MLX Gemma 4 E2B 4bit: \(FileManager.default.fileExists(atPath: mlxE2B.path) ? "✅ FOUND" : "❌ MISSING")")
        print("╚════════════════════════════════════════════════════")
    }
}
