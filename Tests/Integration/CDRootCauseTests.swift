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

/// Root cause investigation tests for CD and think+cd observations.
///
/// Each test isolates a SINGLE variable to determine causation.
/// All tests use clean engine instances — one model load per test.
final class CDRootCauseTests: XCTestCase {

    private static let prompt = "What is 15 * 23? Show your work."

    override func setUpWithError() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Requires real Metal GPU")
        #endif
    }

    private var modelsDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("models")
    }

    private func makeEngine(
        label: String,
        enableThinking: Bool = false,
        enableCD: Bool = false,
        enableMTP: Bool = false,
        enableBenchmark: Bool = true,
        systemMessage: String? = nil,
        tools: [Tool]? = nil
    ) async throws -> (InstrumentedEngine, String) {
        let modelURL = modelsDirectory.appendingPathComponent("gemma-4-E2B-it.litertlm")
        guard FileManager.default.fileExists(atPath: modelURL.path) else {
            throw XCTSkip("Model not found")
        }

        let engine = InstrumentedEngine()
        let cacheDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CDRoot-\(label)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

        let flags = ExperimentalFlagsState(
            enableBenchmark: enableBenchmark,
            enableSpeculativeDecoding: enableMTP,
            enableConversationConstrainedDecoding: enableCD,
            visualTokenBudget: nil,
            enableThinking: enableThinking
        )

        // Determine system message
        let sysMsg: String?
        if let explicit = systemMessage {
            sysMsg = explicit
        } else if enableThinking {
            sysMsg = "<|think|>\nYou are a helpful assistant."
        } else {
            sysMsg = "You are a helpful assistant."
        }

        let sampler = try SamplerConfig(topK: 1, topP: 1.0, temperature: 1.0, seed: 42)

        try await engine.initialize(
            modelPath: modelURL.path,
            useGPU: true,
            cacheDir: cacheDir.path,
            flags: flags,
            samplerConfig: sampler,
            systemMessage: sysMsg,
            tools: tools
        )

        return (engine, cacheDir.path)
    }

    private func runInference(
        engine: InstrumentedEngine,
        enableThinking: Bool = false,
        cacheDir: String
    ) async throws -> (response: String, benchmarkInfo: BenchmarkInfo?) {
        var response = ""
        for try await chunk in engine.sendMessageStream(
            Self.prompt,
            enableThinking: enableThinking
        ) {
            response += chunk
        }
        let bench = engine.lastBenchmarkInfo
        await engine.shutdown()
        try? FileManager.default.removeItem(atPath: cacheDir)
        return (response, bench)
    }

    // MARK: - Q1: Is think+cd=0 caused by system message or per-message flag?

    /// TEST: thinking system message + CD, but enableThinking=FALSE on the message.
    /// If output is zero → system message `<|think|>` conflicts with CD.
    /// If output is non-zero → per-message enableThinking flag is the trigger.
    func testQ1a_ThinkSystemMsg_CD_NoPerMsgThink() async throws {
        print("[CD_ROOT] === Q1a: think system msg + CD, but enableThinking=false per-message ===")
        let (engine, cacheDir) = try await makeEngine(
            label: "Q1a",
            enableThinking: false,
            enableCD: true,
            systemMessage: "<|think|>\nYou are a helpful assistant."  // think in system msg
        )

        // Send message WITHOUT enableThinking
        let (response, bench) = try await runInference(engine: engine, enableThinking: false, cacheDir: cacheDir)

        print("[CD_ROOT] [Q1a] response_length=\(response.count)")
        print("[CD_ROOT] [Q1a] tok/s=\(bench?.lastDecodeTokensPerSecond ?? -1)")
        print("[CD_ROOT] [Q1a] preview=\(String(response.prefix(200)))")
        print("[CD_ROOT] [Q1a] VERDICT: \(response.isEmpty ? "ZERO — system msg <|think|> conflicts with CD" : "NON-ZERO — system msg alone doesn't conflict")")
    }

    /// TEST: NO thinking system message + CD, but enableThinking=TRUE on the message.
    /// If output is zero → per-message enableThinking conflicts with CD.
    /// If output is non-zero → the system message is the trigger.
    func testQ1b_NoThinkSystemMsg_CD_WithPerMsgThink() async throws {
        print("[CD_ROOT] === Q1b: plain system msg + CD, but enableThinking=true per-message ===")
        let (engine, cacheDir) = try await makeEngine(
            label: "Q1b",
            enableThinking: false,  // no think in system msg
            enableCD: true,
            systemMessage: "You are a helpful assistant."  // no <|think|>
        )

        // Send message WITH enableThinking
        let (response, bench) = try await runInference(engine: engine, enableThinking: true, cacheDir: cacheDir)

        print("[CD_ROOT] [Q1b] response_length=\(response.count)")
        print("[CD_ROOT] [Q1b] tok/s=\(bench?.lastDecodeTokensPerSecond ?? -1)")
        print("[CD_ROOT] [Q1b] preview=\(String(response.prefix(200)))")
        print("[CD_ROOT] [Q1b] VERDICT: \(response.isEmpty ? "ZERO — per-message enableThinking conflicts with CD" : "NON-ZERO — per-message flag alone doesn't conflict")")
    }

    /// TEST: BOTH thinking system message AND per-message enableThinking + CD.
    /// This is the original failing combo. Included as control.
    func testQ1c_BothThink_CD() async throws {
        print("[CD_ROOT] === Q1c: both think system msg + per-msg think + CD (ORIGINAL FAIL) ===")
        let (engine, cacheDir) = try await makeEngine(
            label: "Q1c",
            enableThinking: true,  // <|think|> in system msg
            enableCD: true
        )

        let (response, bench) = try await runInference(engine: engine, enableThinking: true, cacheDir: cacheDir)

        print("[CD_ROOT] [Q1c] response_length=\(response.count)")
        print("[CD_ROOT] [Q1c] tok/s=\(bench?.lastDecodeTokensPerSecond ?? -1)")
        print("[CD_ROOT] [Q1c] VERDICT: \(response.isEmpty ? "ZERO — confirmed" : "NON-ZERO — different from permutation matrix?")")
    }

    // MARK: - Q2: Does CD behave differently with tools registered?
    // NOTE: The LiteRT-LM Tool protocol requires @ToolParam property wrappers
    // and struct conformance — can't be created inline. Requires dedicated
    // test tool structs. Deferred to a follow-up test that can use the
    // existing AppTool wrappers from the app's ToolRegistry.
    // For now, Q1 and Q3 answer the most critical questions.

    // MARK: - Q3: CD truncation — full content comparison

    /// TEST: Capture full bare vs CD responses to see exactly where CD truncates.
    func testQ3_FullContentComparison() async throws {
        print("[CD_ROOT] === Q3: Full content comparison — bare vs CD ===")

        // Bare response
        let (bareEngine, bareCacheDir) = try await makeEngine(label: "Q3_bare", enableCD: false)
        let (bareResponse, bareBench) = try await runInference(engine: bareEngine, cacheDir: bareCacheDir)

        // CD response
        let (cdEngine, cdCacheDir) = try await makeEngine(label: "Q3_cd", enableCD: true)
        let (cdResponse, cdBench) = try await runInference(engine: cdEngine, cacheDir: cdCacheDir)

        print("[CD_ROOT] [Q3] === BARE RESPONSE (\(bareResponse.count) chars) ===")
        print(bareResponse)
        print("[CD_ROOT] [Q3] === CD RESPONSE (\(cdResponse.count) chars) ===")
        print(cdResponse)
        print("[CD_ROOT] [Q3] === COMPARISON ===")

        // Check if CD response is a prefix of bare response
        let isPrefix = bareResponse.hasPrefix(cdResponse)
        print("[CD_ROOT] [Q3] CD is prefix of bare: \(isPrefix)")
        print("[CD_ROOT] [Q3] bare tok/s=\(bareBench?.lastDecodeTokensPerSecond ?? -1)")
        print("[CD_ROOT] [Q3] cd tok/s=\(cdBench?.lastDecodeTokensPerSecond ?? -1)")
        print("[CD_ROOT] [Q3] bare tokens=\(bareBench?.lastDecodeTokenCount ?? -1)")
        print("[CD_ROOT] [Q3] cd tokens=\(cdBench?.lastDecodeTokenCount ?? -1)")

        if isPrefix {
            print("[CD_ROOT] [Q3] VERDICT: CD truncates at token \(cdBench?.lastDecodeTokenCount ?? -1) — same content, earlier EOS")
        } else {
            // Find first divergence point
            let minLen = min(bareResponse.count, cdResponse.count)
            var divergeAt = minLen
            for i in 0..<minLen {
                let bIdx = bareResponse.index(bareResponse.startIndex, offsetBy: i)
                let cIdx = cdResponse.index(cdResponse.startIndex, offsetBy: i)
                if bareResponse[bIdx] != cdResponse[cIdx] {
                    divergeAt = i
                    break
                }
            }
            print("[CD_ROOT] [Q3] VERDICT: Responses diverge at char \(divergeAt)")
            if divergeAt > 0 {
                let start = max(0, divergeAt - 20)
                let bareSnippet = String(bareResponse[bareResponse.index(bareResponse.startIndex, offsetBy: start)..<bareResponse.index(bareResponse.startIndex, offsetBy: min(divergeAt + 20, bareResponse.count))])
                let cdSnippet = String(cdResponse[cdResponse.index(cdResponse.startIndex, offsetBy: start)..<cdResponse.index(cdResponse.startIndex, offsetBy: min(divergeAt + 20, cdResponse.count))])
                print("[CD_ROOT] [Q3] bare around diverge: ...\(bareSnippet)...")
                print("[CD_ROOT] [Q3] cd around diverge: ...\(cdSnippet)...")
            }
        }
    }
}
