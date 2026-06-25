// Copyright 2026 Andrew Voirol. Apache-2.0
// Copyright 2026 Andrew Voirol
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

import Testing
import Foundation
#if os(iOS)
@testable import EdgeAILab_iOS
#elseif os(macOS)
@testable import EdgeAILab_macOS
#endif

/// Comprehensive tests for EvalResult computed properties that are at the edges
/// of existing coverage. Targets formattedXxx, display labels, and edge-case
/// aggregations across EvalRun, ModelEvalResult, and PromptEvalResult.
@Suite("EvalResult — Display & Edge Cases")
struct EvalResultDisplayTests {

    // MARK: - Helpers

    private func makePromptResult(
        passed: Bool,
        decodeSpeed: Double? = nil,
        ttft: Double? = nil,
        score: EvalScore = .pass,
        toolCallEvents: [ToolCallEvent] = [],
        response: String = "Test response"
    ) -> PromptEvalResult {
        PromptEvalResult(
            promptId: UUID(),
            promptText: "test prompt",
            response: response,
            passed: passed,
            score: passed ? .pass : score,
            decodeSpeed: decodeSpeed,
            ttft: ttft,
            toolCallEvents: toolCallEvents,
            duration: 1.0
        )
    }

    private func makeModelResult(
        modelName: String = "Test",
        avgDecodeSpeed: Double = 42.0,
        avgTTFT: Double = 0.5,
        totalDuration: TimeInterval = 93.0,
        promptResults: [PromptEvalResult] = []
    ) -> ModelEvalResult {
        ModelEvalResult(
            modelName: modelName,
            modelFile: "test.litertlm",
            avgDecodeSpeed: avgDecodeSpeed,
            avgTTFT: avgTTFT,
            p95Latency: 25.0,
            totalTokensGenerated: 100,
            totalDuration: totalDuration,
            promptResults: promptResults
        )
    }

    private func makeRun(
        modelResults: [ModelEvalResult] = [],
        completedAt: Date? = nil
    ) -> EvalRun {
        EvalRun(
            suiteId: UUID(),
            suiteName: "Test",
            startedAt: Date(timeIntervalSince1970: 1000),
            completedAt: completedAt,
            platform: "macOS",
            deviceName: "Test",
            modelResults: modelResults
        )
    }

    // MARK: - PromptEvalResult

    @Suite("PromptEvalResult computed properties")
    struct PromptResultTests {
        @Test("formattedDecodeSpeed with value")
        func formattedDecodeSpeedValue() {
            let result = PromptEvalResult(
                promptId: UUID(),
                promptText: "test",
                response: "test",
                passed: true,
                score: .pass,
                decodeSpeed: 42.5,
                ttft: nil,
                duration: 1.0
            )
            #expect(result.formattedDecodeSpeed == "42.5 tok/s")
        }

        @Test("formattedDecodeSpeed without value")
        func formattedDecodeSpeedNil() {
            let result = PromptEvalResult(
                promptId: UUID(),
                promptText: "test",
                response: "test",
                passed: true,
                score: .pass,
                decodeSpeed: nil,
                ttft: nil,
                duration: 1.0
            )
            #expect(result.formattedDecodeSpeed == "N/A")
        }

        @Test("formattedTTFT with value")
        func formattedTTFTValue() {
            let result = PromptEvalResult(
                promptId: UUID(),
                promptText: "test",
                response: "test",
                passed: true,
                score: .pass,
                decodeSpeed: nil,
                ttft: 0.87,
                duration: 1.0
            )
            #expect(result.formattedTTFT == "0.87s")
        }

        @Test("formattedTTFT without value")
        func formattedTTFTNil() {
            let result = PromptEvalResult(
                promptId: UUID(),
                promptText: "test",
                response: "test",
                passed: true,
                score: .pass,
                decodeSpeed: nil,
                ttft: nil,
                duration: 1.0
            )
            #expect(result.formattedTTFT == "N/A")
        }

        @Test("hadToolCalls false when empty")
        func noToolCalls() {
            let result = PromptEvalResult(
                promptId: UUID(),
                promptText: "test",
                response: "test",
                passed: true,
                score: .pass,
                duration: 1.0
            )
            #expect(result.hadToolCalls == false)
        }

        @Test("hadToolCalls true with events")
        func withToolCalls() {
            let event = ToolCallEvent(
                toolName: "search",
                arguments: "{}",
                result: "ok",
                durationMs: 100,
                timestamp: Date(),
                succeeded: true
            )
            let result = PromptEvalResult(
                promptId: UUID(),
                promptText: "test",
                response: "test",
                passed: true,
                score: .pass,
                toolCallEvents: [event],
                duration: 1.0
            )
            #expect(result.hadToolCalls == true)
            #expect(result.toolNamesUsed == ["search"])
        }

        @Test("truncatedResponse short stays unchanged")
        func shortResponse() {
            let result = PromptEvalResult(
                promptId: UUID(),
                promptText: "test",
                response: "Short response",
                passed: true,
                score: .pass,
                duration: 1.0
            )
            #expect(result.truncatedResponse == "Short response")
        }

        @Test("truncatedResponse long gets truncated")
        func longResponse() {
            let longText = String(repeating: "a", count: 200)
            let result = PromptEvalResult(
                promptId: UUID(),
                promptText: "test",
                response: longText,
                passed: true,
                score: .pass,
                duration: 1.0
            )
            #expect(result.truncatedResponse.hasSuffix("..."))
            #expect(result.truncatedResponse.count == 120)
        }
    }

    // MARK: - ModelEvalResult

    @Suite("ModelEvalResult formatted strings")
    struct ModelResultTests {
        @Test("formattedDecodeSpeed formats correctly")
        func formattedDecodeSpeed() {
            let model = ModelEvalResult(
                modelName: "Test",
                modelFile: "test.litertlm",
                avgDecodeSpeed: 42.5,
                avgTTFT: 0.5,
                p95Latency: 25.0,
                totalTokensGenerated: 100,
                totalDuration: 10.0,
                promptResults: []
            )
            #expect(model.formattedDecodeSpeed == "42.5 tok/s")
        }

        @Test("formattedTTFT formats correctly")
        func formattedTTFT() {
            let model = ModelEvalResult(
                modelName: "Test",
                modelFile: "test.litertlm",
                avgDecodeSpeed: 42.0,
                avgTTFT: 0.87,
                p95Latency: 25.0,
                totalTokensGenerated: 100,
                totalDuration: 10.0,
                promptResults: []
            )
            #expect(model.formattedTTFT == "0.87s")
        }

        @Test("formattedDuration with minutes")
        func formattedDuration() {
            let model = ModelEvalResult(
                modelName: "Test",
                modelFile: "test.litertlm",
                avgDecodeSpeed: 42.0,
                avgTTFT: 0.5,
                p95Latency: 25.0,
                totalTokensGenerated: 100,
                totalDuration: 93.0,
                promptResults: []
            )
            #expect(model.formattedDuration == "1m 33s")
        }

        @Test("formattedDuration seconds only")
        func formattedDurationSeconds() {
            let model = ModelEvalResult(
                modelName: "Test",
                modelFile: "test.litertlm",
                avgDecodeSpeed: 42.0,
                avgTTFT: 0.5,
                p95Latency: 25.0,
                totalTokensGenerated: 100,
                totalDuration: 45.0,
                promptResults: []
            )
            #expect(model.formattedDuration == "45s")
        }

        @Test("passRatePercent formats correctly")
        func passRatePercent() {
            let prompts = [
                PromptEvalResult(promptId: UUID(), promptText: "t", response: "r", passed: true, score: .pass, duration: 1),
                PromptEvalResult(promptId: UUID(), promptText: "t", response: "r", passed: false, score: .fail(reason: "x"), duration: 1),
                PromptEvalResult(promptId: UUID(), promptText: "t", response: "r", passed: true, score: .pass, duration: 1),
            ]
            let model = ModelEvalResult(
                modelName: "Test",
                modelFile: "test.litertlm",
                avgDecodeSpeed: 42.0,
                avgTTFT: 0.5,
                p95Latency: 25.0,
                totalTokensGenerated: 100,
                totalDuration: 10.0,
                promptResults: prompts
            )
            #expect(model.passRatePercent == "66%")
        }

        @Test("passCount and failCount")
        func passFail() {
            let prompts = [
                PromptEvalResult(promptId: UUID(), promptText: "t", response: "r", passed: true, score: .pass, duration: 1),
                PromptEvalResult(promptId: UUID(), promptText: "t", response: "r", passed: false, score: .fail(reason: "x"), duration: 1),
            ]
            let model = ModelEvalResult(
                modelName: "Test",
                modelFile: "test.litertlm",
                avgDecodeSpeed: 42.0,
                avgTTFT: 0.5,
                p95Latency: 25.0,
                totalTokensGenerated: 100,
                totalDuration: 10.0,
                promptResults: prompts
            )
            #expect(model.passCount == 1)
            #expect(model.failCount == 1)
        }

        @Test("timeoutCount counts timeout scores")
        func timeoutCount() {
            let prompts = [
                PromptEvalResult(promptId: UUID(), promptText: "t", response: "r", passed: false, score: .timeout, duration: 1),
                PromptEvalResult(promptId: UUID(), promptText: "t", response: "r", passed: false, score: .fail(reason: "x"), duration: 1),
            ]
            let model = ModelEvalResult(
                modelName: "Test",
                modelFile: "test.litertlm",
                avgDecodeSpeed: 42.0,
                avgTTFT: 0.5,
                p95Latency: 25.0,
                totalTokensGenerated: 100,
                totalDuration: 10.0,
                promptResults: prompts
            )
            #expect(model.timeoutCount == 1)
        }

        @Test("errorCount counts error scores")
        func errorCount() {
            let prompts = [
                PromptEvalResult(promptId: UUID(), promptText: "t", response: "r", passed: false, score: .error("crash"), duration: 1),
            ]
            let model = ModelEvalResult(
                modelName: "Test",
                modelFile: "test.litertlm",
                avgDecodeSpeed: 42.0,
                avgTTFT: 0.5,
                p95Latency: 25.0,
                totalTokensGenerated: 100,
                totalDuration: 10.0,
                promptResults: prompts
            )
            #expect(model.errorCount == 1)
        }
    }

    // MARK: - EvalRun

    @Suite("EvalRun display properties")
    struct EvalRunTests {
        @Test("displaySummary with multiple models")
        func displaySummary() {
            let model1 = ModelEvalResult(
                modelName: "A", modelFile: "a.litertlm",
                avgDecodeSpeed: 42.0, avgTTFT: 0.5, p95Latency: 25.0,
                totalTokensGenerated: 100, totalDuration: 10.0,
                promptResults: [
                    PromptEvalResult(promptId: UUID(), promptText: "t", response: "r", passed: true, score: .pass, duration: 1),
                ]
            )
            let run = EvalRun(
                suiteId: UUID(),
                suiteName: "Test",
                platform: "macOS",
                deviceName: "Test",
                modelResults: [model1]
            )
            let summary = run.displaySummary
            #expect(summary.contains("1 model"))
            #expect(summary.contains("100%"))
        }

        @Test("overallPassRate with no models is 0")
        func overallPassRateEmpty() {
            let run = EvalRun(
                suiteId: UUID(),
                suiteName: "Test",
                platform: "macOS",
                deviceName: "Test",
                modelResults: []
            )
            #expect(run.overallPassRate == 0.0)
        }

        @Test("currentPlatform is macOS in test env")
        func currentPlatform() {
            #if os(macOS)
            #expect(EvalRun.currentPlatform == "macOS")
            #elseif os(iOS)
            #expect(EvalRun.currentPlatform == "iOS")
            #endif
        }

        @Test("currentDeviceName is not empty")
        func currentDeviceName() {
            #expect(!EvalRun.currentDeviceName.isEmpty)
        }
    }
}
