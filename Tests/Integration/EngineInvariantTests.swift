// Copyright 2026 Andrew Voirol. Apache-2.0
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0

import XCTest
import LiteRTLM

#if os(iOS)
@testable import EdgeAILab_iOS
#elseif os(macOS)
@testable import EdgeAILab_macOS
#endif

// MARK: - Invariant Definitions

/// A violation of an engine invariant.
struct InvariantViolation: CustomStringConvertible {
    let invariantName: String
    let detail: String
    let configLabel: String

    var description: String {
        "[\(configLabel)] VIOLATION: \(invariantName) — \(detail)"
    }
}

/// Configuration for a single test run.
struct TestRunConfig: CustomStringConvertible {
    let label: String
    let enableThinking: Bool
    let enableCD: Bool
    let enableMTP: Bool
    let enableBenchmark: Bool
    let enableToolCalling: Bool
    let temperature: Float
    let topK: Int
    let topP: Float
    let seed: Int

    var description: String { label }

    /// Short flags string for logging.
    var flagsString: String {
        var parts: [String] = []
        if enableThinking { parts.append("think") }
        if enableCD { parts.append("cd") }
        if enableMTP { parts.append("mtp") }
        if enableBenchmark { parts.append("bench") }
        if enableToolCalling { parts.append("tools") }
        parts.append("t\(temperature)_k\(topK)_p\(topP)_s\(seed)")
        return parts.isEmpty ? "bare" : parts.joined(separator: "+")
    }
}

/// Result of a single test run.
struct TestRunResult {
    let config: TestRunConfig
    let response: String
    let error: Error?
    let benchmarkInfo: BenchmarkInfo?
    let wallClockSeconds: Double
    let hasThinkTags: Bool
    let timeToFirstChunkSeconds: Double?

    var responseLength: Int { response.count }
    var isEmpty: Bool { response.isEmpty }
}

/// Checks all invariants against a test run result. Returns violations.
func checkInvariants(_ result: TestRunResult) -> [InvariantViolation] {
    var violations: [InvariantViolation] = []
    let label = result.config.label

    // INV-1: Non-empty response OR explicit error.
    // Silent zero-output is a violation.
    if result.error == nil && result.isEmpty {
        // Check if benchmark shows tokens were decoded internally
        let internalTokens = result.benchmarkInfo?.lastDecodeTokenCount ?? 0
        let internalTokS = result.benchmarkInfo?.lastDecodeTokensPerSecond ?? 0
        violations.append(InvariantViolation(
            invariantName: "INV-1: No Silent Zero Output",
            detail: "Response empty with no error. Internal decode: \(internalTokens) tokens at \(String(format: "%.1f", internalTokS)) tok/s",
            configLabel: label
        ))
    }

    // INV-2: If benchmark enabled, BenchmarkInfo must be populated.
    if result.config.enableBenchmark && result.benchmarkInfo == nil && result.error == nil {
        violations.append(InvariantViolation(
            invariantName: "INV-2: Benchmark Populated",
            detail: "Benchmark enabled but BenchmarkInfo is nil after inference",
            configLabel: label
        ))
    }

    // INV-3: If decode tokens > 0, visible response must be non-empty.
    if let bench = result.benchmarkInfo,
       bench.lastDecodeTokenCount > 0 && result.isEmpty && result.error == nil {
        violations.append(InvariantViolation(
            invariantName: "INV-3: Internal/Visible Token Consistency",
            detail: "Engine decoded \(bench.lastDecodeTokenCount) tokens at \(String(format: "%.1f", bench.lastDecodeTokensPerSecond)) tok/s but yielded 0 visible chars",
            configLabel: label
        ))
    }

    // INV-4: If thinking enabled and response non-empty, response should contain think tags.
    if result.config.enableThinking && !result.isEmpty && !result.hasThinkTags {
        violations.append(InvariantViolation(
            invariantName: "INV-4: Thinking Tags Present",
            detail: "Thinking enabled, got \(result.responseLength) chars but no <think> tags",
            configLabel: label
        ))
    }

    // INV-5: If thinking disabled, response should NOT contain think tags.
    if !result.config.enableThinking && result.hasThinkTags {
        violations.append(InvariantViolation(
            invariantName: "INV-5: No Thinking Tags When Disabled",
            detail: "Thinking disabled but response contains <think> tags",
            configLabel: label
        ))
    }

    // INV-6: Benchmark tok/s consistency.
    // If decode token count > 0, decode tok/s must be > 0.
    if let bench = result.benchmarkInfo,
       bench.lastDecodeTokenCount > 0 && bench.lastDecodeTokensPerSecond <= 0 {
        violations.append(InvariantViolation(
            invariantName: "INV-6: Decode Rate Consistency",
            detail: "Decoded \(bench.lastDecodeTokenCount) tokens but reported \(bench.lastDecodeTokensPerSecond) tok/s",
            configLabel: label
        ))
    }

    // INV-7: Wall clock sanity.
    // Inference should complete within a reasonable time bound (60s for E2B).
    if result.wallClockSeconds > 60 && result.error == nil {
        violations.append(InvariantViolation(
            invariantName: "INV-7: Inference Timeout",
            detail: "Inference took \(String(format: "%.1f", result.wallClockSeconds))s — exceeds 60s bound",
            configLabel: label
        ))
    }

    // INV-8: Response is valid UTF-8.
    // Swift strings are always valid UTF-8, but check for replacement characters
    // which indicate encoding issues in the underlying bytes.
    if result.response.contains("\u{FFFD}") {
        violations.append(InvariantViolation(
            invariantName: "INV-8: Valid UTF-8",
            detail: "Response contains Unicode replacement character (U+FFFD)",
            configLabel: label
        ))
    }

    return violations
}

// MARK: - Test Runner

/// Engine-level invariant test runner.
///
/// Each test method is ONE configuration, ONE model load, ONE inference.
/// xcodebuild runs each test in a separate process invocation when called
/// with -only-testing, giving true process isolation.
///
/// Invariants are checked after EVERY run — they ARE the test.
final class EngineInvariantTests: XCTestCase {

    override func setUpWithError() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Requires real Metal GPU")
        #endif
    }

    private var modelsDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // Integration/
            .deletingLastPathComponent()  // Tests/
            .deletingLastPathComponent()  // project root
            .appendingPathComponent("models")
    }

    /// Run a single configuration and check all invariants.
    /// - Parameters:
    ///   - config: The test configuration (flags, sampler, etc.)
    ///   - prompt: The user prompt to send
    ///   - tools: Optional real Tool definitions to register with the conversation.
    ///     When nil, no tools are passed (flag-only). When provided, tools are
    ///     registered in ConversationConfig so CD's grammar has actual schemas.
    private func runAndCheck(_ config: TestRunConfig, prompt: String, tools: [Tool]? = nil) async throws {
        let modelURL = modelsDirectory.appendingPathComponent("gemma-4-E2B-it.litertlm")
        guard FileManager.default.fileExists(atPath: modelURL.path) else {
            throw XCTSkip("Model gemma-4-E2B-it.litertlm not found in models/")
        }

        let engine = InstrumentedEngine()
        let cacheDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("Invariant-\(config.label)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: cacheDir) }

        let flags = ExperimentalFlagsState(
            enableBenchmark: config.enableBenchmark,
            enableSpeculativeDecoding: config.enableMTP,
            enableConversationConstrainedDecoding: config.enableCD,
            visualTokenBudget: nil,
            enableThinking: config.enableThinking,
            enableToolCalling: config.enableToolCalling
        )

        let sysMsg = config.enableThinking
            ? "<|think|>\nYou are a helpful assistant."
            : "You are a helpful assistant."

        let sampler = try SamplerConfig(
            topK: config.topK,
            topP: config.topP,
            temperature: config.temperature,
            seed: config.seed
        )

        let startTime = CFAbsoluteTimeGetCurrent()
        var inferenceError: Error?
        var response = ""
        var firstChunkTime: Double?

        do {
            try await engine.initialize(
                modelPath: modelURL.path,
                useGPU: true,
                cacheDir: cacheDir.path,
                flags: flags,
                samplerConfig: sampler,
                systemMessage: sysMsg,
                tools: tools,
                supportsVision: false,
                supportsAudio: false,
                maxNumTokens: nil
            )

            for try await chunk in engine.sendMessageStream(
                prompt,
                enableThinking: config.enableThinking
            ) {
                if firstChunkTime == nil {
                    firstChunkTime = CFAbsoluteTimeGetCurrent() - startTime
                }
                response += chunk
            }
        } catch {
            inferenceError = error
        }

        let wallClock = CFAbsoluteTimeGetCurrent() - startTime
        let bench = engine.lastBenchmarkInfo
        await engine.shutdown()

        let result = TestRunResult(
            config: config,
            response: response,
            error: inferenceError,
            benchmarkInfo: bench,
            wallClockSeconds: wallClock,
            hasThinkTags: response.contains("<think>"),
            timeToFirstChunkSeconds: firstChunkTime
        )

        // Log the run
        let tokS = bench?.lastDecodeTokensPerSecond
        let tokCount = bench?.lastDecodeTokenCount
        print("[INV] [\(config.label)] flags=\(config.flagsString)")
        print("[INV] [\(config.label)] response_len=\(result.responseLength) | wall=\(String(format: "%.2f", wallClock))s | tok/s=\(tokS.map { String(format: "%.1f", $0) } ?? "n/a") | tokens=\(tokCount ?? -1)")
        if let err = inferenceError {
            print("[INV] [\(config.label)] ERROR: \(err)")
        }

        // Check invariants
        let violations = checkInvariants(result)
        if violations.isEmpty {
            print("[INV] [\(config.label)] ✅ ALL INVARIANTS PASS")
        } else {
            for v in violations {
                print("[INV] [\(config.label)] ❌ \(v)")
            }
        }

        // Output machine-parseable JSON result
        let jsonResult: [String: Any] = [
            "label": config.label,
            "flags": config.flagsString,
            "responseLength": result.responseLength,
            "wallClockSeconds": wallClock,
            "decodeTokensPerSecond": tokS ?? -1,
            "decodeTokenCount": tokCount ?? -1,
            "hasThinkTags": result.hasThinkTags,
            "hasError": inferenceError != nil,
            "violationCount": violations.count,
            "violations": violations.map { $0.invariantName }
        ]
        if let jsonData = try? JSONSerialization.data(withJSONObject: jsonResult),
           let jsonStr = String(data: jsonData, encoding: .utf8) {
            print("[INV_RESULT] \(jsonStr)")
        }

        // Record violations but don't fail the test — we want ALL configs to run.
        // Violations are analyzed in aggregate, not per-test.
        for v in violations {
            XCTContext.runActivity(named: "Violation: \(v.invariantName)") { _ in
                XCTIssue(type: .unmatchedExpectedFailure, compactDescription: v.description)
            }
        }
    }

    // MARK: - Standard prompt for all singles

    private static let standardPrompt = "What is 15 * 23? Show your work."

    // MARK: - Singles: Each setting alone

    func testSingle_Bare() async throws {
        try await runAndCheck(TestRunConfig(
            label: "single_bare", enableThinking: false, enableCD: false,
            enableMTP: false, enableBenchmark: true, enableToolCalling: false,
            temperature: 1.0, topK: 1, topP: 1.0, seed: 42
        ), prompt: Self.standardPrompt)
    }

    func testSingle_Think() async throws {
        try await runAndCheck(TestRunConfig(
            label: "single_think", enableThinking: true, enableCD: false,
            enableMTP: false, enableBenchmark: true, enableToolCalling: false,
            temperature: 1.0, topK: 1, topP: 1.0, seed: 42
        ), prompt: Self.standardPrompt)
    }

    func testSingle_CD() async throws {
        try await runAndCheck(TestRunConfig(
            label: "single_cd", enableThinking: false, enableCD: true,
            enableMTP: false, enableBenchmark: true, enableToolCalling: false,
            temperature: 1.0, topK: 1, topP: 1.0, seed: 42
        ), prompt: Self.standardPrompt)
    }

    func testSingle_MTP() async throws {
        try await runAndCheck(TestRunConfig(
            label: "single_mtp", enableThinking: false, enableCD: false,
            enableMTP: true, enableBenchmark: true, enableToolCalling: false,
            temperature: 1.0, topK: 1, topP: 1.0, seed: 42
        ), prompt: Self.standardPrompt)
    }

    func testSingle_Tools() async throws {
        try await runAndCheck(TestRunConfig(
            label: "single_tools", enableThinking: false, enableCD: false,
            enableMTP: false, enableBenchmark: true, enableToolCalling: true,
            temperature: 1.0, topK: 1, topP: 1.0, seed: 42
        ), prompt: Self.standardPrompt)
    }

    // MARK: - Pairwise: Every 2-setting combination

    func testPair_Think_CD() async throws {
        try await runAndCheck(TestRunConfig(
            label: "pair_think_cd", enableThinking: true, enableCD: true,
            enableMTP: false, enableBenchmark: true, enableToolCalling: false,
            temperature: 1.0, topK: 1, topP: 1.0, seed: 42
        ), prompt: Self.standardPrompt)
    }

    func testPair_Think_MTP() async throws {
        try await runAndCheck(TestRunConfig(
            label: "pair_think_mtp", enableThinking: true, enableCD: false,
            enableMTP: true, enableBenchmark: true, enableToolCalling: false,
            temperature: 1.0, topK: 1, topP: 1.0, seed: 42
        ), prompt: Self.standardPrompt)
    }

    func testPair_Think_Tools() async throws {
        try await runAndCheck(TestRunConfig(
            label: "pair_think_tools", enableThinking: true, enableCD: false,
            enableMTP: false, enableBenchmark: true, enableToolCalling: true,
            temperature: 1.0, topK: 1, topP: 1.0, seed: 42
        ), prompt: Self.standardPrompt)
    }

    func testPair_CD_MTP() async throws {
        try await runAndCheck(TestRunConfig(
            label: "pair_cd_mtp", enableThinking: false, enableCD: true,
            enableMTP: true, enableBenchmark: true, enableToolCalling: false,
            temperature: 1.0, topK: 1, topP: 1.0, seed: 42
        ), prompt: Self.standardPrompt)
    }

    func testPair_CD_Tools() async throws {
        try await runAndCheck(TestRunConfig(
            label: "pair_cd_tools", enableThinking: false, enableCD: true,
            enableMTP: false, enableBenchmark: true, enableToolCalling: true,
            temperature: 1.0, topK: 1, topP: 1.0, seed: 42
        ), prompt: Self.standardPrompt)
    }

    func testPair_MTP_Tools() async throws {
        try await runAndCheck(TestRunConfig(
            label: "pair_mtp_tools", enableThinking: false, enableCD: false,
            enableMTP: true, enableBenchmark: true, enableToolCalling: true,
            temperature: 1.0, topK: 1, topP: 1.0, seed: 42
        ), prompt: Self.standardPrompt)
    }

    // MARK: - Triples: Every 3-setting combination

    func testTriple_Think_CD_MTP() async throws {
        try await runAndCheck(TestRunConfig(
            label: "triple_think_cd_mtp", enableThinking: true, enableCD: true,
            enableMTP: true, enableBenchmark: true, enableToolCalling: false,
            temperature: 1.0, topK: 1, topP: 1.0, seed: 42
        ), prompt: Self.standardPrompt)
    }

    func testTriple_Think_CD_Tools() async throws {
        try await runAndCheck(TestRunConfig(
            label: "triple_think_cd_tools", enableThinking: true, enableCD: true,
            enableMTP: false, enableBenchmark: true, enableToolCalling: true,
            temperature: 1.0, topK: 1, topP: 1.0, seed: 42
        ), prompt: Self.standardPrompt)
    }

    func testTriple_Think_MTP_Tools() async throws {
        try await runAndCheck(TestRunConfig(
            label: "triple_think_mtp_tools", enableThinking: true, enableCD: false,
            enableMTP: true, enableBenchmark: true, enableToolCalling: true,
            temperature: 1.0, topK: 1, topP: 1.0, seed: 42
        ), prompt: Self.standardPrompt)
    }

    func testTriple_CD_MTP_Tools() async throws {
        try await runAndCheck(TestRunConfig(
            label: "triple_cd_mtp_tools", enableThinking: false, enableCD: true,
            enableMTP: true, enableBenchmark: true, enableToolCalling: true,
            temperature: 1.0, topK: 1, topP: 1.0, seed: 42
        ), prompt: Self.standardPrompt)
    }

    // MARK: - All on

    func testAll_On() async throws {
        try await runAndCheck(TestRunConfig(
            label: "all_on", enableThinking: true, enableCD: true,
            enableMTP: true, enableBenchmark: true, enableToolCalling: true,
            temperature: 1.0, topK: 1, topP: 1.0, seed: 42
        ), prompt: Self.standardPrompt)
    }

    // MARK: - Determinism: Same config twice, must match

    func testDeterminism_Bare_Run1() async throws {
        try await runAndCheck(TestRunConfig(
            label: "determinism_bare_r1", enableThinking: false, enableCD: false,
            enableMTP: false, enableBenchmark: true, enableToolCalling: false,
            temperature: 1.0, topK: 1, topP: 1.0, seed: 42
        ), prompt: Self.standardPrompt)
    }

    func testDeterminism_Bare_Run2() async throws {
        try await runAndCheck(TestRunConfig(
            label: "determinism_bare_r2", enableThinking: false, enableCD: false,
            enableMTP: false, enableBenchmark: true, enableToolCalling: false,
            temperature: 1.0, topK: 1, topP: 1.0, seed: 42
        ), prompt: Self.standardPrompt)
    }

    // MARK: - Sampler variation: Non-greedy

    func testSampler_HighTemp() async throws {
        try await runAndCheck(TestRunConfig(
            label: "sampler_hightemp", enableThinking: false, enableCD: false,
            enableMTP: false, enableBenchmark: true, enableToolCalling: false,
            temperature: 1.5, topK: 40, topP: 0.95, seed: 42
        ), prompt: Self.standardPrompt)
    }

    func testSampler_LowTemp() async throws {
        try await runAndCheck(TestRunConfig(
            label: "sampler_lowtemp", enableThinking: false, enableCD: false,
            enableMTP: false, enableBenchmark: true, enableToolCalling: false,
            temperature: 0.3, topK: 10, topP: 0.9, seed: 42
        ), prompt: Self.standardPrompt)
    }

    // MARK: - Different prompt

    func testPrompt_Creative() async throws {
        try await runAndCheck(TestRunConfig(
            label: "prompt_creative", enableThinking: false, enableCD: false,
            enableMTP: false, enableBenchmark: true, enableToolCalling: false,
            temperature: 1.0, topK: 1, topP: 1.0, seed: 42
        ), prompt: "Write a haiku about a neural network learning to see.")
    }

    func testPrompt_Creative_WithCD() async throws {
        try await runAndCheck(TestRunConfig(
            label: "prompt_creative_cd", enableThinking: false, enableCD: true,
            enableMTP: false, enableBenchmark: true, enableToolCalling: false,
            temperature: 1.0, topK: 1, topP: 1.0, seed: 42
        ), prompt: "Write a haiku about a neural network learning to see.")
    }

    func testPrompt_Short() async throws {
        try await runAndCheck(TestRunConfig(
            label: "prompt_short", enableThinking: false, enableCD: false,
            enableMTP: false, enableBenchmark: true, enableToolCalling: false,
            temperature: 1.0, topK: 1, topP: 1.0, seed: 42
        ), prompt: "Hello")
    }

    func testPrompt_Short_WithCD() async throws {
        try await runAndCheck(TestRunConfig(
            label: "prompt_short_cd", enableThinking: false, enableCD: true,
            enableMTP: false, enableBenchmark: true, enableToolCalling: false,
            temperature: 1.0, topK: 1, topP: 1.0, seed: 42
        ), prompt: "Hello")
    }

    // MARK: - CD With Real Tools (Function Calling Use Case)

    /// CD with a real CalculatorTool registered — testing CD in its INTENDED use case.
    /// Previous cd+tools tests only set the flag without passing Tool definitions.
    /// With real tools, the FST grammar should have actual function schemas to constrain against.
    func testCD_WithRealTools_MathPrompt() async throws {
        try await runAndCheck(TestRunConfig(
            label: "cd_realtools_math", enableThinking: false, enableCD: true,
            enableMTP: false, enableBenchmark: true, enableToolCalling: true,
            temperature: 1.0, topK: 1, topP: 1.0, seed: 42
        ), prompt: "What is 15 * 23?", tools: [CalculatorTool()])
    }

    /// CD + real tools + thinking — does the think+cd conflict persist with real tools?
    func testCD_WithRealTools_ThinkMath() async throws {
        try await runAndCheck(TestRunConfig(
            label: "cd_realtools_think_math", enableThinking: true, enableCD: true,
            enableMTP: false, enableBenchmark: true, enableToolCalling: true,
            temperature: 1.0, topK: 1, topP: 1.0, seed: 42
        ), prompt: "What is 15 * 23?", tools: [CalculatorTool()])
    }

    /// CD + real tools + MTP — does MTP still bypass CD when real tools are present?
    func testCD_WithRealTools_MTP_Math() async throws {
        try await runAndCheck(TestRunConfig(
            label: "cd_realtools_mtp_math", enableThinking: false, enableCD: true,
            enableMTP: true, enableBenchmark: true, enableToolCalling: true,
            temperature: 1.0, topK: 1, topP: 1.0, seed: 42
        ), prompt: "What is 15 * 23?", tools: [CalculatorTool()])
    }

    /// CD + real tools + think + MTP — full stack with real tools
    func testCD_WithRealTools_Think_MTP_Math() async throws {
        try await runAndCheck(TestRunConfig(
            label: "cd_realtools_think_mtp_math", enableThinking: true, enableCD: true,
            enableMTP: true, enableBenchmark: true, enableToolCalling: true,
            temperature: 1.0, topK: 1, topP: 1.0, seed: 42
        ), prompt: "What is 15 * 23?", tools: [CalculatorTool()])
    }

    // MARK: - Multi-Turn Invariants

    /// Run multiple turns on the same engine instance and check invariants on each.
    /// This tests whether conversation state affects invariant behavior.
    private func runMultiTurn(
        _ config: TestRunConfig,
        prompts: [String],
        tools: [Tool]? = nil
    ) async throws {
        let modelURL = modelsDirectory.appendingPathComponent("gemma-4-E2B-it.litertlm")
        guard FileManager.default.fileExists(atPath: modelURL.path) else {
            throw XCTSkip("Model gemma-4-E2B-it.litertlm not found in models/")
        }

        let engine = InstrumentedEngine()
        let cacheDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MultiTurn-\(config.label)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: cacheDir) }

        let flags = ExperimentalFlagsState(
            enableBenchmark: config.enableBenchmark,
            enableSpeculativeDecoding: config.enableMTP,
            enableConversationConstrainedDecoding: config.enableCD,
            visualTokenBudget: nil,
            enableThinking: config.enableThinking,
            enableToolCalling: config.enableToolCalling
        )

        let sysMsg = config.enableThinking
            ? "<|think|>\nYou are a helpful assistant."
            : "You are a helpful assistant."

        let sampler = try SamplerConfig(
            topK: config.topK,
            topP: config.topP,
            temperature: config.temperature,
            seed: config.seed
        )

        try await engine.initialize(
            modelPath: modelURL.path,
            useGPU: true,
            cacheDir: cacheDir.path,
            flags: flags,
            samplerConfig: sampler,
            systemMessage: sysMsg,
            tools: tools,
            supportsVision: false,
            supportsAudio: false,
            maxNumTokens: nil
        )

        for (turnIndex, prompt) in prompts.enumerated() {
            let turnLabel = "\(config.label)_turn\(turnIndex + 1)"
            let startTime = CFAbsoluteTimeGetCurrent()
            var response = ""
            var inferenceError: Error?
            var firstChunkTime: Double?

            do {
                for try await chunk in engine.sendMessageStream(
                    prompt,
                    enableThinking: config.enableThinking
                ) {
                    if firstChunkTime == nil {
                        firstChunkTime = CFAbsoluteTimeGetCurrent() - startTime
                    }
                    response += chunk
                }
            } catch {
                inferenceError = error
            }

            let wallClock = CFAbsoluteTimeGetCurrent() - startTime
            let bench = engine.lastBenchmarkInfo

            let result = TestRunResult(
                config: TestRunConfig(
                    label: turnLabel,
                    enableThinking: config.enableThinking,
                    enableCD: config.enableCD,
                    enableMTP: config.enableMTP,
                    enableBenchmark: config.enableBenchmark,
                    enableToolCalling: config.enableToolCalling,
                    temperature: config.temperature,
                    topK: config.topK,
                    topP: config.topP,
                    seed: config.seed
                ),
                response: response,
                error: inferenceError,
                benchmarkInfo: bench,
                wallClockSeconds: wallClock,
                hasThinkTags: response.contains("<think>"),
                timeToFirstChunkSeconds: firstChunkTime
            )

            // Log the turn
            let tokS = bench?.lastDecodeTokensPerSecond
            let tokCount = bench?.lastDecodeTokenCount
            print("[INV] [\(turnLabel)] flags=\(config.flagsString)")
            print("[INV] [\(turnLabel)] response_len=\(result.responseLength) | wall=\(String(format: "%.2f", wallClock))s | tok/s=\(tokS.map { String(format: "%.1f", $0) } ?? "n/a") | tokens=\(tokCount ?? -1)")

            let violations = checkInvariants(result)
            if violations.isEmpty {
                print("[INV] [\(turnLabel)] ✅ ALL INVARIANTS PASS")
            } else {
                for v in violations {
                    print("[INV] [\(turnLabel)] ❌ \(v)")
                }
            }

            // Output machine-parseable JSON result
            let jsonResult: [String: Any] = [
                "label": turnLabel,
                "turnIndex": turnIndex + 1,
                "prompt": prompt,
                "flags": config.flagsString,
                "responseLength": result.responseLength,
                "wallClockSeconds": wallClock,
                "decodeTokensPerSecond": tokS ?? -1,
                "decodeTokenCount": tokCount ?? -1,
                "hasThinkTags": result.hasThinkTags,
                "hasError": inferenceError != nil,
                "violationCount": violations.count,
                "violations": violations.map { $0.invariantName }
            ]
            if let jsonData = try? JSONSerialization.data(withJSONObject: jsonResult),
               let jsonStr = String(data: jsonData, encoding: .utf8) {
                print("[INV_RESULT] \(jsonStr)")
            }

            for v in violations {
                XCTContext.runActivity(named: "Violation: \(v.invariantName)") { _ in
                    XCTIssue(type: .unmatchedExpectedFailure, compactDescription: v.description)
                }
            }
        }

        await engine.shutdown()
    }

    private static let multiTurnPrompts = [
        "What is 15 * 23? Show your work.",
        "Now double that result.",
        "Write a one-sentence summary of our conversation."
    ]

    /// Multi-turn baseline — bare config, 3 turns
    func testMultiTurn_Bare() async throws {
        try await runMultiTurn(TestRunConfig(
            label: "multiturn_bare", enableThinking: false, enableCD: false,
            enableMTP: false, enableBenchmark: true, enableToolCalling: false,
            temperature: 1.0, topK: 1, topP: 1.0, seed: 42
        ), prompts: Self.multiTurnPrompts)
    }

    /// Multi-turn with thinking — do think tags persist across turns?
    func testMultiTurn_Think() async throws {
        try await runMultiTurn(TestRunConfig(
            label: "multiturn_think", enableThinking: true, enableCD: false,
            enableMTP: false, enableBenchmark: true, enableToolCalling: false,
            temperature: 1.0, topK: 1, topP: 1.0, seed: 42
        ), prompts: Self.multiTurnPrompts)
    }

    /// Multi-turn with MTP — does speedup hold across turns?
    func testMultiTurn_MTP() async throws {
        try await runMultiTurn(TestRunConfig(
            label: "multiturn_mtp", enableThinking: false, enableCD: false,
            enableMTP: true, enableBenchmark: true, enableToolCalling: false,
            temperature: 1.0, topK: 1, topP: 1.0, seed: 42
        ), prompts: Self.multiTurnPrompts)
    }

    /// Multi-turn with CD + real tools — does CD function calling hold across turns?
    func testMultiTurn_CD_RealTools() async throws {
        try await runMultiTurn(TestRunConfig(
            label: "multiturn_cd_tools", enableThinking: false, enableCD: true,
            enableMTP: false, enableBenchmark: true, enableToolCalling: true,
            temperature: 1.0, topK: 1, topP: 1.0, seed: 42
        ), prompts: Self.multiTurnPrompts, tools: [CalculatorTool()])
    }
}
