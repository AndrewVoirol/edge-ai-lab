// Copyright 2026 Andrew Voirol. Apache-2.0
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0

import XCTest

#if os(iOS)
@testable import EdgeAILab_iOS
#elseif os(macOS)
@testable import EdgeAILab_macOS
#endif

/// MLX Engine invariant tests.
///
/// Tests the MLX inference engine with the real Gemma 4 E2B MLX model.
/// MLX does NOT support CD, MTP, or ExperimentalFlags — those are LiteRT-only.
/// What MLX DOES support: thinking (via chat template), sampler settings,
/// VLM detection, and metrics reporting.
///
/// Each test is one configuration, one model load, one (or more) inferences.
final class MLXInvariantTests: XCTestCase {

    override func setUpWithError() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("MLX requires real Metal GPU — skipping on simulator")
        #endif
    }

    private var modelsDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // Integration/
            .deletingLastPathComponent()  // Tests/
            .deletingLastPathComponent()  // project root
            .appendingPathComponent("models")
    }

    private var mlxModelPath: String {
        modelsDirectory.appendingPathComponent("mlx-community--gemma-4-E2B-it-4bit").path
    }

    private func skipIfModelMissing() throws {
        guard FileManager.default.fileExists(atPath: mlxModelPath) else {
            throw XCTSkip("MLX model mlx-community--gemma-4-E2B-it-4bit not found in models/")
        }
    }

    // MARK: - MLX Invariant Checks

    /// MLX-specific invariant checks (subset of the full invariant list).
    /// MLX doesn't have BenchmarkInfo, so we skip INV-2, INV-3, INV-6.
    private func checkMLXInvariants(
        response: String,
        error: Error?,
        wallClockSeconds: Double,
        metrics: EnginePerformanceMetrics?,
        thinkingEnabled: Bool,
        label: String
    ) -> [InvariantViolation] {
        var violations: [InvariantViolation] = []

        // INV-1: Non-empty response OR explicit error.
        if error == nil && response.isEmpty {
            violations.append(InvariantViolation(
                invariantName: "INV-1: No Silent Zero Output",
                detail: "Response empty with no error",
                configLabel: label
            ))
        }

        // INV-4: If thinking enabled and response non-empty, should contain think tags.
        // Check ALL supported thinking formats:
        // - `<think>` / `<|think|>`: LiteRT format
        // - `<|channel>thought`: MLX Gemma 4 channel-based format
        let hasThinkTags = response.contains("<think>")
            || response.contains("<|think|>")
            || response.contains("<|channel>thought")
        if thinkingEnabled && !response.isEmpty && !hasThinkTags {
            violations.append(InvariantViolation(
                invariantName: "INV-4: Thinking Tags Present",
                detail: "Thinking enabled, got \(response.count) chars but no <think> tags",
                configLabel: label
            ))
        }

        // INV-5: If thinking disabled, response should NOT contain think tags.
        if !thinkingEnabled && hasThinkTags {
            violations.append(InvariantViolation(
                invariantName: "INV-5: No Thinking Tags When Disabled",
                detail: "Thinking disabled but response contains <think> tags",
                configLabel: label
            ))
        }

        // INV-7: Wall clock sanity (120s for MLX — slower than LiteRT for first load).
        if wallClockSeconds > 120 && error == nil {
            violations.append(InvariantViolation(
                invariantName: "INV-7: Inference Timeout",
                detail: "Inference took \(String(format: "%.1f", wallClockSeconds))s — exceeds 120s bound",
                configLabel: label
            ))
        }

        // INV-8: Valid UTF-8.
        if response.contains("\u{FFFD}") {
            violations.append(InvariantViolation(
                invariantName: "INV-8: Valid UTF-8",
                detail: "Response contains Unicode replacement character (U+FFFD)",
                configLabel: label
            ))
        }

        // MLX-INV-1: Metrics populated.
        if error == nil && !response.isEmpty && metrics == nil {
            violations.append(InvariantViolation(
                invariantName: "MLX-INV-1: Metrics Populated",
                detail: "Successful inference but EnginePerformanceMetrics is nil",
                configLabel: label
            ))
        }

        // MLX-INV-2: If metrics populated, tok/s must be > 0.
        if let metrics = metrics, metrics.tokensPerSecond <= 0 && !response.isEmpty {
            violations.append(InvariantViolation(
                invariantName: "MLX-INV-2: Positive Decode Rate",
                detail: "Metrics report \(metrics.tokensPerSecond) tok/s for non-empty response",
                configLabel: label
            ))
        }

        return violations
    }

    /// Run inference on the MLX engine and return results.
    private func runMLXInference(
        prompt: String,
        thinkingEnabled: Bool,
        temperature: Float = 0.6,
        topK: Int = 40,
        topP: Float = 0.9,
        seed: Int = 0,
        label: String
    ) async throws -> (response: String, metrics: EnginePerformanceMetrics?, wallClockSeconds: Double, error: Error?) {
        try skipIfModelMissing()

        let engine = MLXEngineAdapter()

        let flags = RuntimeFlags(
            enableThinking: thinkingEnabled,
            enableToolCalling: false,
            enableAgentSkills: false
        )

        let genConfig = GenerationConfig(
            maxTokens: 512,
            temperature: Double(temperature),
            topP: Double(topP),
            topK: topK,
            seed: seed > 0 ? UInt64(seed) : nil
        )

        // MLX thinking is activated via additionalContext: ["enable_thinking": true]
        // in RuntimeFlags → loadModel, NOT via system message prefix.
        // The Jinja template injects <|think|> when enable_thinking is set.
        let sysMsg = "You are a helpful assistant."

        let loadConfig = ModelLoadConfig(
            modelPath: mlxModelPath,
            preferGPU: true,
            systemMessage: sysMsg,
            runtimeFlags: flags
        )

        let startTime = CFAbsoluteTimeGetCurrent()
        var response = ""
        var inferenceError: Error?

        do {
            try await engine.loadModel(config: loadConfig)
            XCTAssertTrue(engine.isLoaded, "MLX engine should be loaded after loadModel")

            let stream = engine.generateStream(prompt: prompt, config: genConfig)
            for try await event in stream {
                switch event {
                case .text(let text):
                    response += text
                case .metrics, .done, .toolCall:
                    break
                }
            }
        } catch {
            inferenceError = error
        }

        let wallClock = CFAbsoluteTimeGetCurrent() - startTime
        let metrics = engine.lastPerformanceMetrics

        // Log results
        let hasThinkTags = response.contains("<think>")
            || response.contains("<|think|>")
            || response.contains("<|channel>thought")
        let tokS = metrics?.tokensPerSecond ?? 0
        let tokenCount = metrics?.tokenCount ?? 0
        print("[MLX-INV] [\(label)] response_len=\(response.count) | wall=\(String(format: "%.2f", wallClock))s | tok/s=\(String(format: "%.1f", tokS)) | tokens=\(tokenCount) | think_tags=\(hasThinkTags)")
        // Dump first 200 chars for diagnostic inspection
        print("[MLX-INV] [\(label)] RAW_OUTPUT_HEAD: \(String(response.prefix(200)))")

        return (response, metrics, wallClock, inferenceError)
    }

    /// Run and check invariants, failing the test on any violation.
    private func runAndCheck(
        prompt: String,
        thinkingEnabled: Bool,
        temperature: Float = 0.6,
        topK: Int = 40,
        topP: Float = 0.9,
        seed: Int = 0,
        label: String
    ) async throws {
        let result = try await runMLXInference(
            prompt: prompt,
            thinkingEnabled: thinkingEnabled,
            temperature: temperature,
            topK: topK,
            topP: topP,
            seed: seed,
            label: label
        )

        let violations = checkMLXInvariants(
            response: result.response,
            error: result.error,
            wallClockSeconds: result.wallClockSeconds,
            metrics: result.metrics,
            thinkingEnabled: thinkingEnabled,
            label: label
        )

        if violations.isEmpty {
            print("[MLX-INV] [\(label)] ✅ ALL INVARIANTS PASS")
        } else {
            for v in violations {
                print("[MLX-INV] [\(label)] ❌ \(v)")
            }
            XCTFail("MLX invariant violations: \(violations.map(\.description).joined(separator: "; "))")
        }
    }

    // MARK: - Test Methods

    /// Basic MLX inference — no thinking, default sampler.
    func testMLX_Bare() async throws {
        try await runAndCheck(
            prompt: "What is 2 + 2? Answer briefly.",
            thinkingEnabled: false,
            label: "mlx_bare"
        )
    }

    /// MLX with thinking enabled — should produce <think> tags.
    func testMLX_Think() async throws {
        try await runAndCheck(
            prompt: "What is 15 * 23? Show your work.",
            thinkingEnabled: true,
            label: "mlx_think"
        )
    }

    /// MLX with thinking disabled — should NOT produce <think> tags.
    func testMLX_Think_Disabled() async throws {
        try await runAndCheck(
            prompt: "What is 15 * 23?",
            thinkingEnabled: false,
            label: "mlx_think_disabled"
        )
    }

    /// MLX sampler settings — verify different temperature produces output.
    func testMLX_SamplerLowTemp() async throws {
        try await runAndCheck(
            prompt: "Name one color.",
            thinkingEnabled: false,
            temperature: 0.1,
            topK: 1,
            topP: 1.0,
            label: "mlx_sampler_low_temp"
        )
    }

    /// MLX determinism — same seed should produce same output (if supported).
    func testMLX_Determinism() async throws {
        try skipIfModelMissing()

        let result1 = try await runMLXInference(
            prompt: "Name one fruit.",
            thinkingEnabled: false,
            temperature: 0.1,
            topK: 1,
            seed: 42,
            label: "mlx_determinism_run1"
        )

        let result2 = try await runMLXInference(
            prompt: "Name one fruit.",
            thinkingEnabled: false,
            temperature: 0.1,
            topK: 1,
            seed: 42,
            label: "mlx_determinism_run2"
        )

        // Check basic invariants on both
        XCTAssertNil(result1.error, "Run 1 should not error")
        XCTAssertNil(result2.error, "Run 2 should not error")
        XCTAssertFalse(result1.response.isEmpty, "Run 1 should produce output")
        XCTAssertFalse(result2.response.isEmpty, "Run 2 should produce output")

        // Log whether outputs match — MLX may or may not support deterministic seeding
        if result1.response == result2.response {
            print("[MLX-INV] [mlx_determinism] ✅ DETERMINISTIC: outputs match")
        } else {
            print("[MLX-INV] [mlx_determinism] ⚠️ NON-DETERMINISTIC: outputs differ")
            print("[MLX-INV] [mlx_determinism] Run 1: \(result1.response.prefix(100))...")
            print("[MLX-INV] [mlx_determinism] Run 2: \(result2.response.prefix(100))...")
            // NOT a failure — just an observation. MLX seeding behavior is unknown.
        }
    }

    /// MLX metrics — verify EnginePerformanceMetrics is populated.
    func testMLX_Metrics() async throws {
        try skipIfModelMissing()

        let result = try await runMLXInference(
            prompt: "Say hello.",
            thinkingEnabled: false,
            label: "mlx_metrics"
        )

        XCTAssertNil(result.error, "Should not error")
        XCTAssertFalse(result.response.isEmpty, "Should produce output")

        // Metrics checks
        let metrics = result.metrics
        XCTAssertNotNil(metrics, "EnginePerformanceMetrics should be populated after inference")
        if let metrics = metrics {
            XCTAssertGreaterThan(metrics.tokensPerSecond, 0, "tok/s should be positive")
            print("[MLX-INV] [mlx_metrics] tok/s=\(String(format: "%.1f", metrics.tokensPerSecond)) tokenCount=\(metrics.tokenCount ?? -1) promptTok/s=\(String(format: "%.1f", metrics.promptTokensPerSecond ?? 0))")
        }
    }

    /// MLX multi-turn — 3-turn conversation maintains state.
    func testMLX_MultiTurn() async throws {
        try skipIfModelMissing()

        let engine = MLXEngineAdapter()

        let flags = RuntimeFlags(
            enableThinking: false,
            enableToolCalling: false,
            enableAgentSkills: false
        )

        let loadConfig = ModelLoadConfig(
            modelPath: mlxModelPath,
            preferGPU: true,
            systemMessage: "You are a helpful assistant.",
            runtimeFlags: flags
        )

        try await engine.loadModel(config: loadConfig)
        XCTAssertTrue(engine.isLoaded)

        let genConfig = GenerationConfig(
            maxTokens: 256,
            temperature: 0.6,
            topP: 0.9,
            topK: 40
        )

        let prompts = [
            "What is 15 * 23? Answer briefly.",
            "Now double that result.",
            "Write a one-sentence summary of our conversation."
        ]

        for (i, prompt) in prompts.enumerated() {
            let turnLabel = "mlx_multiturn_turn\(i + 1)"
            let startTime = CFAbsoluteTimeGetCurrent()
            var response = ""

            let stream = engine.generateStream(prompt: prompt, config: genConfig)
            for try await event in stream {
                if case .text(let text) = event {
                    response += text
                }
            }

            let wallClock = CFAbsoluteTimeGetCurrent() - startTime
            let metrics = engine.lastPerformanceMetrics
            let tokS = metrics?.tokensPerSecond ?? 0

            print("[MLX-INV] [\(turnLabel)] response_len=\(response.count) | wall=\(String(format: "%.2f", wallClock))s | tok/s=\(String(format: "%.1f", tokS))")

            XCTAssertFalse(response.isEmpty, "Turn \(i + 1) should produce output")

            let violations = checkMLXInvariants(
                response: response,
                error: nil,
                wallClockSeconds: wallClock,
                metrics: metrics,
                thinkingEnabled: false,
                label: turnLabel
            )
            if !violations.isEmpty {
                XCTFail("Turn \(i + 1) violations: \(violations.map(\.description).joined(separator: "; "))")
            } else {
                print("[MLX-INV] [\(turnLabel)] ✅ ALL INVARIANTS PASS")
            }
        }
    }
}
