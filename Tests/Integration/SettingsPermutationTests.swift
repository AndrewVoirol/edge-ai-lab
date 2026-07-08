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

// MARK: - Permutation Result

/// Structured result from a single permutation test run.
/// Captures everything observable about one settings configuration.
struct PermutationResult: Codable {
    /// Unique permutation ID (e.g., "P0", "P1", ... "P63").
    let permutationId: String

    /// Human-readable label for the combination.
    let label: String

    /// The model filename used.
    let model: String

    /// The runtime engine used.
    let engine: String

    /// Individual flag values for this permutation.
    let enableBenchmark: Bool
    let enableThinking: Bool
    let enableToolCalling: Bool
    let enableMTP: Bool
    let enableConstrainedDecoding: Bool

    /// Outcome
    let succeeded: Bool
    let errorMessage: String?

    /// Raw response
    let responseLength: Int
    let responsePreview: String

    /// Observable behaviors
    let containsThinkTags: Bool
    let containsToolCall: Bool

    /// Metrics (nil if benchmarking was off or inference failed)
    let decodeTokPerSec: Double?
    let prefillTokPerSec: Double?
    let ttftSeconds: Double?
    let decodeTokenCount: Int?
    let prefillTokenCount: Int?
    let initTimeSeconds: Double?

    /// Timing
    let wallClockSeconds: Double
}

// MARK: - SettingsPermutationTests

/// Combinatorial settings permutation test runner.
///
/// Enumerates EVERY combination of boolean settings (2^5 = 32 permutations
/// per model) and runs real inference for each. Captures full instrumentation
/// data and outputs structured JSON results.
///
/// ## Why This Exists
/// Individual setting tests tell you "does MTP work in isolation?" but NOT
/// "does MTP break when tool calling + thinking are also enabled?" Only
/// combinatorial testing surfaces interaction bugs.
///
/// ## What It Captures Per Permutation
/// - Did inference succeed or crash?
/// - Response content (length, preview, think tags, tool calls)
/// - Full benchmark metrics (tok/s, TTFT, token counts, init time)
/// - Wall clock time
///
/// ## Output Format
/// Results are printed as JSON arrays for machine-parseable analysis.
/// Each line tagged `[PERM_RESULT]` contains one `PermutationResult` as JSON.
/// At the end, `[PERM_SUMMARY]` contains the full matrix.
final class SettingsPermutationTests: XCTestCase {

    // MARK: - Constants

    /// Standard prompt for all permutation runs.
    /// Short enough for fast runs, complex enough to trigger thinking/tools if enabled.
    private static let standardPrompt = "What is 15 * 23? Show your work."

    /// Secondary prompt to test conversation continuity.
    private static let followUpPrompt = "Now add 100 to that result."

    // MARK: - Setup

    override func setUpWithError() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Permutation tests require real Metal GPU — skipping on iOS Simulator")
        #endif
        try super.setUpWithError()
    }

    // MARK: - Model Discovery

    private var modelsDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // Integration/
            .deletingLastPathComponent()  // Tests/
            .deletingLastPathComponent()  // project root
            .appendingPathComponent("models")
    }

    private func findLiteRTModel(named filename: String) throws -> String {
        let modelURL = modelsDirectory.appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: modelURL.path) else {
            throw XCTSkip("Model \(filename) not found")
        }
        return modelURL.path
    }

    // MARK: - Permutation Generation

    /// All boolean setting combinations.
    /// 5 boolean flags → 2^5 = 32 permutations.
    ///
    /// Flags:
    /// - enableBenchmark
    /// - enableThinking
    /// - enableToolCalling (note: enableAgentSkills is a sub-flag of toolCalling, tested separately)
    /// - enableMTP (enableSpeculativeDecoding)
    /// - enableConstrainedDecoding
    private struct SettingsCombination {
        let enableBenchmark: Bool
        let enableThinking: Bool
        let enableToolCalling: Bool
        let enableMTP: Bool
        let enableConstrainedDecoding: Bool

        var label: String {
            var parts: [String] = []
            if enableBenchmark { parts.append("bench") }
            if enableThinking { parts.append("think") }
            if enableToolCalling { parts.append("tools") }
            if enableMTP { parts.append("mtp") }
            if enableConstrainedDecoding { parts.append("cd") }
            return parts.isEmpty ? "bare" : parts.joined(separator: "+")
        }

        func toRuntimeFlags() -> RuntimeFlags {
            RuntimeFlags(
                enableBenchmark: enableBenchmark,
                enableThinking: enableThinking,
                enableToolCalling: enableToolCalling,
                enableAgentSkills: false, // tested as a toolCalling sub-flag
                enableSpeculativeDecoding: enableMTP,
                enableConversationConstrainedDecoding: enableConstrainedDecoding,
                visualTokenBudget: nil
            )
        }

        func toExperimentalFlags() -> ExperimentalFlagsState {
            ExperimentalFlagsState(
                enableBenchmark: enableBenchmark,
                enableSpeculativeDecoding: enableMTP,
                enableConversationConstrainedDecoding: enableConstrainedDecoding,
                visualTokenBudget: nil
            )
        }
    }

    private static func allCombinations() -> [SettingsCombination] {
        var combos: [SettingsCombination] = []
        for bench in [false, true] {
            for think in [false, true] {
                for tools in [false, true] {
                    for mtp in [false, true] {
                        for cd in [false, true] {
                            combos.append(SettingsCombination(
                                enableBenchmark: bench,
                                enableThinking: think,
                                enableToolCalling: tools,
                                enableMTP: mtp,
                                enableConstrainedDecoding: cd
                            ))
                        }
                    }
                }
            }
        }
        return combos
    }

    // MARK: - Single Permutation Runner

    /// Run a single permutation: load model, run inference, capture everything.
    private func runPermutation(
        id: String,
        combo: SettingsCombination,
        modelPath: String,
        modelName: String,
        engineName: String
    ) async -> PermutationResult {
        let startTime = CFAbsoluteTimeGetCurrent()

        // Build system message — include thinking trigger if thinking is enabled
        let systemMessage: String? = combo.enableThinking
            ? "<|think|>\nYou are a helpful assistant."
            : "You are a helpful assistant."

        do {
            let engine = InstrumentedEngine()
            let cacheDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("Permutation-\(id)-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

            let flags = combo.toExperimentalFlags()
            let sampler = try SamplerConfig(topK: 1, topP: 1.0, temperature: 1.0, seed: 42)

            try await engine.initialize(
                modelPath: modelPath,
                useGPU: true,
                cacheDir: cacheDir.path,
                flags: flags,
                samplerConfig: sampler,
                systemMessage: systemMessage,
                tools: nil,
                supportsVision: true,
                supportsAudio: true
            )

            guard engine.isReady else {
                let elapsed = CFAbsoluteTimeGetCurrent() - startTime
                await engine.shutdown()
                return PermutationResult(
                    permutationId: id, label: combo.label, model: modelName,
                    engine: engineName,
                    enableBenchmark: combo.enableBenchmark,
                    enableThinking: combo.enableThinking,
                    enableToolCalling: combo.enableToolCalling,
                    enableMTP: combo.enableMTP,
                    enableConstrainedDecoding: combo.enableConstrainedDecoding,
                    succeeded: false, errorMessage: "Engine not ready after init",
                    responseLength: 0, responsePreview: "",
                    containsThinkTags: false, containsToolCall: false,
                    decodeTokPerSec: nil, prefillTokPerSec: nil,
                    ttftSeconds: nil, decodeTokenCount: nil,
                    prefillTokenCount: nil, initTimeSeconds: nil,
                    wallClockSeconds: elapsed
                )
            }

            // Run inference
            var response = ""
            for try await chunk in engine.sendMessageStream(
                Self.standardPrompt,
                enableThinking: combo.enableThinking
            ) {
                response += chunk
            }

            // Capture metrics
            let bench = engine.lastBenchmarkInfo
            let inferenceMetrics = engine.lastInferenceMetrics
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime

            await engine.shutdown()

            // Clean up cache
            try? FileManager.default.removeItem(at: cacheDir)

            let containsThink = response.contains("<think>") || response.contains("</think>")
            let containsToolCall = response.contains("\"function_call\"") ||
                                   response.contains("\"tool_calls\"") ||
                                   response.contains("\"name\":") && response.contains("\"arguments\":")

            return PermutationResult(
                permutationId: id, label: combo.label, model: modelName,
                engine: engineName,
                enableBenchmark: combo.enableBenchmark,
                enableThinking: combo.enableThinking,
                enableToolCalling: combo.enableToolCalling,
                enableMTP: combo.enableMTP,
                enableConstrainedDecoding: combo.enableConstrainedDecoding,
                succeeded: true, errorMessage: nil,
                responseLength: response.count,
                responsePreview: String(response.prefix(200)),
                containsThinkTags: containsThink,
                containsToolCall: containsToolCall,
                decodeTokPerSec: bench?.lastDecodeTokensPerSecond,
                prefillTokPerSec: bench?.lastPrefillTokensPerSecond,
                ttftSeconds: bench?.timeToFirstTokenInSecond,
                decodeTokenCount: bench?.lastDecodeTokenCount,
                prefillTokenCount: bench?.lastPrefillTokenCount,
                initTimeSeconds: bench?.initTimeInSecond,
                wallClockSeconds: elapsed
            )

        } catch {
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            return PermutationResult(
                permutationId: id, label: combo.label, model: modelName,
                engine: engineName,
                enableBenchmark: combo.enableBenchmark,
                enableThinking: combo.enableThinking,
                enableToolCalling: combo.enableToolCalling,
                enableMTP: combo.enableMTP,
                enableConstrainedDecoding: combo.enableConstrainedDecoding,
                succeeded: false, errorMessage: error.localizedDescription,
                responseLength: 0, responsePreview: "",
                containsThinkTags: false, containsToolCall: false,
                decodeTokPerSec: nil, prefillTokPerSec: nil,
                ttftSeconds: nil, decodeTokenCount: nil,
                prefillTokenCount: nil, initTimeSeconds: nil,
                wallClockSeconds: elapsed
            )
        }
    }

    // MARK: - Anomaly Detection

    /// Analyze results for anomalies — combinations that behave unexpectedly.
    private func detectAnomalies(results: [PermutationResult]) -> [String] {
        var anomalies: [String] = []

        for r in results {
            // Anomaly: inference failed
            if !r.succeeded {
                anomalies.append("❌ \(r.permutationId) [\(r.label)]: FAILED — \(r.errorMessage ?? "unknown")")
            }

            // Anomaly: thinking enabled but no think tags
            if r.enableThinking && r.succeeded && !r.containsThinkTags && r.responseLength > 10 {
                anomalies.append("⚠️ \(r.permutationId) [\(r.label)]: thinking=ON but NO <think> tags in \(r.responseLength) char response")
            }

            // Anomaly: thinking disabled but think tags present
            if !r.enableThinking && r.succeeded && r.containsThinkTags {
                anomalies.append("⚠️ \(r.permutationId) [\(r.label)]: thinking=OFF but <think> tags PRESENT")
            }

            // Anomaly: benchmark enabled but no metrics
            if r.enableBenchmark && r.succeeded && r.decodeTokPerSec == nil {
                anomalies.append("⚠️ \(r.permutationId) [\(r.label)]: benchmark=ON but no decode tok/s captured")
            }

            // Anomaly: empty or very short response (< 5 chars) for a math prompt
            if r.succeeded && r.responseLength < 5 {
                anomalies.append("⚠️ \(r.permutationId) [\(r.label)]: suspiciously short response (\(r.responseLength) chars)")
            }

            // Anomaly: extremely slow (> 30s wall clock for a simple prompt)
            if r.succeeded && r.wallClockSeconds > 30 {
                anomalies.append("🐌 \(r.permutationId) [\(r.label)]: very slow — \(String(format: "%.1f", r.wallClockSeconds))s wall clock")
            }

            // Anomaly: decode speed drops below 5 tok/s when benchmarking is on
            if r.enableBenchmark && r.succeeded, let tps = r.decodeTokPerSec, tps < 5.0 {
                anomalies.append("🐌 \(r.permutationId) [\(r.label)]: very low decode speed — \(String(format: "%.1f", tps)) tok/s")
            }
        }

        // Cross-permutation anomalies: compare results that differ by exactly one flag
        let succeeded = results.filter { $0.succeeded }
        for i in 0..<succeeded.count {
            for j in (i+1)..<succeeded.count {
                let a = succeeded[i]
                let b = succeeded[j]

                // Find pairs where only MTP differs
                if a.enableBenchmark == b.enableBenchmark &&
                   a.enableThinking == b.enableThinking &&
                   a.enableToolCalling == b.enableToolCalling &&
                   a.enableConstrainedDecoding == b.enableConstrainedDecoding &&
                   a.enableMTP != b.enableMTP {
                    // Compare speeds if both have benchmark data
                    if let aTps = a.decodeTokPerSec, let bTps = b.decodeTokPerSec {
                        let mtpOn = a.enableMTP ? a : b
                        let mtpOff = a.enableMTP ? b : a
                        let mtpOnTps = a.enableMTP ? aTps : bTps
                        let mtpOffTps = a.enableMTP ? bTps : aTps
                        let ratio = mtpOnTps / max(mtpOffTps, 0.001)
                        if ratio < 0.5 || ratio > 2.0 {
                            anomalies.append("📊 MTP speed delta: [\(mtpOn.label)] \(String(format: "%.1f", mtpOnTps)) tok/s vs [\(mtpOff.label)] \(String(format: "%.1f", mtpOffTps)) tok/s (ratio=\(String(format: "%.2f", ratio))x)")
                        }
                    }
                }
            }
        }

        return anomalies
    }

    // MARK: - Full Permutation Matrix Test

    /// Run ALL 32 permutations of boolean settings against the LiteRT E2B Standard model.
    ///
    /// This is the master test. It loads the model 32 times, runs inference each time,
    /// and captures full instrumentation. Expected runtime: ~3-5 minutes.
    func testLiteRTFullPermutationMatrix() async throws {
        let modelPath = try findLiteRTModel(named: "gemma-4-E2B-it.litertlm")
        let combos = Self.allCombinations()
        var results: [PermutationResult] = []

        let totalStart = CFAbsoluteTimeGetCurrent()

        print("╔════════════════════════════════════════════════════════════════")
        print("║ Settings Permutation Matrix — gemma-4-E2B-it (LiteRT)")
        print("║ \(combos.count) permutations × 1 model × full instrumentation")
        print("╠════════════════════════════════════════════════════════════════")

        for (index, combo) in combos.enumerated() {
            let id = "P\(index)"
            print("║ [\(id)] Running: \(combo.label) (\(index+1)/\(combos.count))...")

            let result = await runPermutation(
                id: id,
                combo: combo,
                modelPath: modelPath,
                modelName: "gemma-4-E2B-it",
                engineName: "litert"
            )

            results.append(result)

            // Emit structured result line
            if let jsonData = try? JSONEncoder().encode(result),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                print("[PERM_RESULT] \(jsonString)")
            }

            let status = result.succeeded ? "✅" : "❌"
            let speed = result.decodeTokPerSec.map { String(format: "%.1f tok/s", $0) } ?? "n/a"
            let think = result.containsThinkTags ? "🧠" : "  "
            print("║   \(status) \(think) len=\(result.responseLength) | \(speed) | \(String(format: "%.1f", result.wallClockSeconds))s")
        }

        let totalElapsed = CFAbsoluteTimeGetCurrent() - totalStart
        let passCount = results.filter { $0.succeeded }.count
        let failCount = results.filter { !$0.succeeded }.count

        print("╠════════════════════════════════════════════════════════════════")
        print("║ SUMMARY: \(passCount)/\(combos.count) passed, \(failCount) failed")
        print("║ Total time: \(String(format: "%.1f", totalElapsed))s")
        print("╠════════════════════════════════════════════════════════════════")

        // Anomaly detection
        let anomalies = detectAnomalies(results: results)
        if anomalies.isEmpty {
            print("║ No anomalies detected.")
        } else {
            print("║ ANOMALIES DETECTED (\(anomalies.count)):")
            for anomaly in anomalies {
                print("║   \(anomaly)")
            }
        }
        print("╚════════════════════════════════════════════════════════════════")

        // Write full results to disk as JSON
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let fullJson = try? encoder.encode(results) {
            let outputURL = modelsDirectory
                .deletingLastPathComponent() // project root
                .appendingPathComponent("metrics")
                .appendingPathComponent("permutation_results_litert_e2b.json")
            try? FileManager.default.createDirectory(
                at: outputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? fullJson.write(to: outputURL)
            print("[PERM_OUTPUT] Results written to: \(outputURL.path)")
        }

        // Assert no failures
        XCTAssertEqual(failCount, 0,
            "\(failCount) permutation(s) failed: \(results.filter { !$0.succeeded }.map { "\($0.permutationId)[\($0.label)]: \($0.errorMessage ?? "?")" }.joined(separator: ", "))")
    }

    // MARK: - Conversation Continuity Test

    /// Test that settings persist correctly across a two-turn conversation.
    /// For each critical combination, send two messages and verify the second
    /// response is consistent with the settings.
    func testConversationContinuityAcrossSettings() async throws {
        let modelPath = try findLiteRTModel(named: "gemma-4-E2B-it.litertlm")

        // Test a subset of critical combos for conversation continuity
        let criticalCombos: [(SettingsCombination, String)] = [
            (SettingsCombination(enableBenchmark: true, enableThinking: true,
                                enableToolCalling: false, enableMTP: false,
                                enableConstrainedDecoding: false), "think_only"),
            (SettingsCombination(enableBenchmark: true, enableThinking: true,
                                enableToolCalling: false, enableMTP: true,
                                enableConstrainedDecoding: false), "think+mtp"),
            (SettingsCombination(enableBenchmark: true, enableThinking: false,
                                enableToolCalling: false, enableMTP: true,
                                enableConstrainedDecoding: true), "mtp+cd"),
            (SettingsCombination(enableBenchmark: true, enableThinking: true,
                                enableToolCalling: false, enableMTP: true,
                                enableConstrainedDecoding: true), "all_on"),
        ]

        print("╔════════════════════════════════════════════════════════════════")
        print("║ Conversation Continuity Test — Two-Turn Consistency")
        print("╠════════════════════════════════════════════════════════════════")

        for (combo, name) in criticalCombos {
            let systemMessage: String? = combo.enableThinking
                ? "<|think|>\nYou are a helpful assistant."
                : "You are a helpful assistant."

            do {
                let engine = InstrumentedEngine()
                let cacheDir = FileManager.default.temporaryDirectory
                    .appendingPathComponent("Continuity-\(name)-\(UUID().uuidString)")
                try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

                try await engine.initialize(
                    modelPath: modelPath,
                    useGPU: true,
                    cacheDir: cacheDir.path,
                    flags: combo.toExperimentalFlags(),
                    samplerConfig: try SamplerConfig(topK: 1, topP: 1.0, temperature: 1.0, seed: 42),
                    systemMessage: systemMessage
                )

                // Turn 1
                var turn1 = ""
                for try await chunk in engine.sendMessageStream(
                    Self.standardPrompt,
                    enableThinking: combo.enableThinking
                ) {
                    turn1 += chunk
                }
                let bench1 = engine.lastBenchmarkInfo

                // Turn 2 — follow up
                var turn2 = ""
                for try await chunk in engine.sendMessageStream(
                    Self.followUpPrompt,
                    enableThinking: combo.enableThinking
                ) {
                    turn2 += chunk
                }
                let bench2 = engine.lastBenchmarkInfo

                await engine.shutdown()
                try? FileManager.default.removeItem(at: cacheDir)

                let t1Think = turn1.contains("<think>")
                let t2Think = turn2.contains("<think>")
                let thinkConsistent = (combo.enableThinking && t1Think && t2Think) ||
                                     (!combo.enableThinking && !t1Think && !t2Think)

                print("║ [\(name)]")
                print("║   Turn 1: len=\(turn1.count) think=\(t1Think) tok/s=\(bench1?.lastDecodeTokensPerSecond ?? -1)")
                print("║   Turn 2: len=\(turn2.count) think=\(t2Think) tok/s=\(bench2?.lastDecodeTokensPerSecond ?? -1)")
                print("║   Thinking consistent: \(thinkConsistent ? "✅" : "⚠️ INCONSISTENT")")

                if !thinkConsistent {
                    print("║   ⚠️ ANOMALY: Thinking behavior changed between turns!")
                }
            } catch {
                print("║ [\(name)] ❌ FAILED: \(error.localizedDescription)")
            }
        }

        print("╚════════════════════════════════════════════════════════════════")
    }
}
