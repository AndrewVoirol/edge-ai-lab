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

/// Isolated reproduction tests for hypotheses from the permutation matrix.
///
/// Each test runs in its own invocation — ONE model load, ONE inference,
/// fresh process state. This eliminates memory pressure and prior-state
/// contamination as confounds.
///
/// ## Scientific Method
/// - Each test has a HYPOTHESIS, CONTROL, and EXPECTED OUTCOME documented.
/// - Results are logged with `[REPRO]` tags for machine parsing.
/// - No assertions on behavior — we OBSERVE and RECORD, then interpret.
final class IsolatedReproductionTests: XCTestCase {

    private static let standardPrompt = "What is 15 * 23? Show your work."

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

    private func findModel(_ filename: String) throws -> String {
        let url = modelsDirectory.appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("Model \(filename) not found")
        }
        return url.path
    }

    /// Single model load → inference → capture, with full instrumentation.
    private func runSingleInference(
        label: String,
        enableBenchmark: Bool = false,
        enableThinking: Bool = false,
        enableMTP: Bool = false,
        enableConstrainedDecoding: Bool = false,
        enableToolCalling: Bool = false
    ) async throws -> (response: String, benchmarkInfo: BenchmarkInfo?, wallClock: Double) {
        let modelPath = try findModel("gemma-4-E2B-it.litertlm")
        let start = CFAbsoluteTimeGetCurrent()

        let engine = InstrumentedEngine()
        let cacheDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("Repro-\(label)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

        let flags = ExperimentalFlagsState(
            enableBenchmark: enableBenchmark,
            enableSpeculativeDecoding: enableMTP,
            enableConversationConstrainedDecoding: enableConstrainedDecoding,
            visualTokenBudget: nil
        )

        let systemMessage: String? = enableThinking
            ? "<|think|>\nYou are a helpful assistant."
            : "You are a helpful assistant."

        let sampler = try SamplerConfig(topK: 1, topP: 1.0, temperature: 1.0, seed: 42)

        print("[REPRO] [\(label)] Initializing engine...")
        try await engine.initialize(
            modelPath: modelPath,
            useGPU: true,
            cacheDir: cacheDir.path,
            flags: flags,
            samplerConfig: sampler,
            systemMessage: systemMessage
        )
        let initElapsed = CFAbsoluteTimeGetCurrent() - start
        print("[REPRO] [\(label)] Engine ready in \(String(format: "%.2f", initElapsed))s")

        print("[REPRO] [\(label)] Running inference...")
        var response = ""
        for try await chunk in engine.sendMessageStream(
            Self.standardPrompt,
            enableThinking: enableThinking
        ) {
            response += chunk
        }
        let bench = engine.lastBenchmarkInfo
        let totalElapsed = CFAbsoluteTimeGetCurrent() - start

        await engine.shutdown()
        try? FileManager.default.removeItem(at: cacheDir)

        let hasThinkTags = response.contains("<think>")
        let tps = bench?.lastDecodeTokensPerSecond
        print("[REPRO] [\(label)] COMPLETE")
        print("[REPRO] [\(label)]   response_length=\(response.count)")
        print("[REPRO] [\(label)]   has_think_tags=\(hasThinkTags)")
        print("[REPRO] [\(label)]   decode_tok_s=\(tps.map { String(format: "%.1f", $0) } ?? "n/a")")
        print("[REPRO] [\(label)]   wall_clock=\(String(format: "%.2f", totalElapsed))s")
        print("[REPRO] [\(label)]   response_preview=\(String(response.prefix(150)))")

        return (response, bench, totalElapsed)
    }

    // MARK: - H1: bench+mtp crash reproduction

    /// HYPOTHESIS: Combining enableBenchmark + enableMTP crashes the engine.
    /// OBSERVED IN: P18 of permutation matrix (after 17 prior model loads).
    /// CONFOUND: Could be memory exhaustion from sequential loads, not setting interaction.
    /// TEST: Single fresh load with bench+mtp, no prior state.
    /// CONTROL: testH1_Control_BenchOnly and testH1_Control_MTPOnly
    func testH1_BenchPlusMTP_Isolated() async throws {
        print("[REPRO] === H1: bench+mtp crash reproduction (ISOLATED) ===")
        let (response, bench, wall) = try await runSingleInference(
            label: "H1_bench_mtp",
            enableBenchmark: true,
            enableMTP: true
        )
        print("[REPRO] [H1_bench_mtp] VERDICT: \(response.isEmpty ? "EMPTY RESPONSE" : "GOT RESPONSE") | bench=\(bench != nil ? "populated" : "nil") | wall=\(String(format: "%.1f", wall))s")
        // NO assertion — we observe and record
    }

    /// CONTROL for H1: Benchmark alone (known working from P16).
    func testH1_Control_BenchOnly() async throws {
        print("[REPRO] === H1 CONTROL: bench only ===")
        let (response, bench, _) = try await runSingleInference(
            label: "H1_ctrl_bench",
            enableBenchmark: true
        )
        print("[REPRO] [H1_ctrl_bench] VERDICT: len=\(response.count) | bench=\(bench != nil ? "populated" : "nil")")
    }

    /// CONTROL for H1: MTP alone (known working from P2).
    func testH1_Control_MTPOnly() async throws {
        print("[REPRO] === H1 CONTROL: mtp only ===")
        let (response, _, _) = try await runSingleInference(
            label: "H1_ctrl_mtp",
            enableMTP: true
        )
        print("[REPRO] [H1_ctrl_mtp] VERDICT: len=\(response.count)")
    }

    // MARK: - H2: think+cd zero-response reproduction

    /// HYPOTHESIS: Combining enableThinking + enableConstrainedDecoding produces zero-length response.
    /// OBSERVED IN: P9 and P13 of permutation matrix.
    /// CONFOUND: Could be prior conversation state from P0-P8.
    /// TEST: Single fresh load with think+cd.
    /// CONTROL: testH2_Control_ThinkOnly and testH2_Control_CDOnly
    func testH2_ThinkPlusCD_Isolated() async throws {
        print("[REPRO] === H2: think+cd zero-response reproduction (ISOLATED) ===")
        let (response, _, _) = try await runSingleInference(
            label: "H2_think_cd",
            enableThinking: true,
            enableConstrainedDecoding: true
        )
        print("[REPRO] [H2_think_cd] VERDICT: len=\(response.count) | \(response.isEmpty ? "⚠️ ZERO-LENGTH CONFIRMED" : "✅ Got response")")
    }

    /// CONTROL for H2: Thinking alone (known working from P8).
    func testH2_Control_ThinkOnly() async throws {
        print("[REPRO] === H2 CONTROL: think only ===")
        let (response, _, _) = try await runSingleInference(
            label: "H2_ctrl_think",
            enableThinking: true
        )
        print("[REPRO] [H2_ctrl_think] VERDICT: len=\(response.count)")
    }

    /// CONTROL for H2: Constrained Decoding alone (known working from P1).
    func testH2_Control_CDOnly() async throws {
        print("[REPRO] === H2 CONTROL: cd only ===")
        let (response, _, _) = try await runSingleInference(
            label: "H2_ctrl_cd",
            enableConstrainedDecoding: true
        )
        print("[REPRO] [H2_ctrl_cd] VERDICT: len=\(response.count)")
    }

    // MARK: - H3: CD truncation measurement

    /// HYPOTHESIS: Constrained decoding reduces output by ~67% vs baseline.
    /// TEST: Run bare and cd back-to-back (2 loads), compare lengths.
    /// NOTE: Both use deterministic sampler, so any length difference is from CD.
    func testH3_CDTruncation_Measurement() async throws {
        print("[REPRO] === H3: CD truncation measurement ===")
        let (bareResponse, _, _) = try await runSingleInference(
            label: "H3_bare",
            enableConstrainedDecoding: false
        )
        let (cdResponse, _, _) = try await runSingleInference(
            label: "H3_cd",
            enableConstrainedDecoding: true
        )
        let reduction = bareResponse.count > 0
            ? Double(bareResponse.count - cdResponse.count) / Double(bareResponse.count) * 100
            : 0
        print("[REPRO] [H3_truncation] bare_len=\(bareResponse.count) | cd_len=\(cdResponse.count) | reduction=\(String(format: "%.1f", reduction))%")
    }

    // MARK: - H4: think+mtp+cd rescue effect

    /// HYPOTHESIS: MTP "rescues" think+cd from zero-response (observed P11 vs P9).
    /// TEST: Run think+mtp+cd in isolation to verify MTP prevents the zero-response.
    func testH4_ThinkMTPCD_RescueEffect() async throws {
        print("[REPRO] === H4: Does MTP rescue think+cd? ===")
        let (response, _, _) = try await runSingleInference(
            label: "H4_think_mtp_cd",
            enableThinking: true,
            enableMTP: true,
            enableConstrainedDecoding: true
        )
        print("[REPRO] [H4_think_mtp_cd] VERDICT: len=\(response.count) | \(response.isEmpty ? "⚠️ ZERO — MTP does NOT rescue" : "✅ MTP rescued — got response")")
    }

    // MARK: - H5: App code path vs test code path

    /// HYPOTHESIS: The crash/zero-response behaviors differ between
    /// direct InstrumentedEngine.initialize() and LiteRTEngineAdapter (app path).
    /// TEST: Run bench+mtp through LiteRTEngineAdapter — same as real app.
    func testH5_BenchMTP_ViaAdapter() async throws {
        print("[REPRO] === H5: bench+mtp via LiteRTEngineAdapter (app code path) ===")
        let modelPath = try findModel("gemma-4-E2B-it.litertlm")
        let start = CFAbsoluteTimeGetCurrent()

        let flags = RuntimeFlags(
            enableBenchmark: true,
            enableThinking: false,
            enableToolCalling: false,
            enableAgentSkills: false,
            enableSpeculativeDecoding: true,
            enableConversationConstrainedDecoding: false
        )

        let adapter = LiteRTEngineAdapter()
        let config = ModelLoadConfig(
            modelPath: modelPath,
            preferGPU: true,
            systemMessage: "You are a helpful assistant.",
            generationConfig: GenerationConfig.default,
            runtimeFlags: flags
        )

        print("[REPRO] [H5] Loading via adapter...")
        try await adapter.loadModel(config: config)
        let initElapsed = CFAbsoluteTimeGetCurrent() - start
        print("[REPRO] [H5] Adapter ready in \(String(format: "%.2f", initElapsed))s")

        var response = ""
        print("[REPRO] [H5] Running inference via adapter...")
        for try await event in adapter.generateStream(prompt: Self.standardPrompt, config: GenerationConfig.default) {
            if case .text(let chunk) = event {
                response += chunk
            }
        }
        let totalElapsed = CFAbsoluteTimeGetCurrent() - start
        let metrics = adapter.lastInferenceMetrics

        print("[REPRO] [H5] COMPLETE")
        print("[REPRO] [H5]   response_length=\(response.count)")
        print("[REPRO] [H5]   wall_clock=\(String(format: "%.2f", totalElapsed))s")
        print("[REPRO] [H5]   response_preview=\(String(response.prefix(150)))")

        await adapter.shutdown()

        print("[REPRO] [H5] VERDICT: \(response.isEmpty ? "⚠️ EMPTY" : "✅ GOT RESPONSE (\(response.count) chars)")")
    }
}
