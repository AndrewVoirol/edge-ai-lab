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

import Foundation
import XCTest

#if os(iOS)
@testable import EdgeAILab_iOS
#elseif os(macOS)
@testable import EdgeAILab_macOS
#endif

/// Tests for all types defined in `EvalResult.swift`:
/// `EvalScore`, `PromptEvalResult`, `ModelEvalResult`, `EvalRun`, and `EvalRunIndexEntry`.
final class EvalResultTests: XCTestCase {

    // MARK: - Helpers

    /// Creates a minimal `PromptEvalResult` with the given score and passed flag.
    private func makePromptResult(
        score: EvalScore,
        passed: Bool,
        decodeSpeed: Double? = nil,
        ttft: Double? = nil,
        toolCallEvents: [ToolCallEvent] = [],
        response: String = "Test response",
        duration: TimeInterval = 1.0
    ) -> PromptEvalResult {
        PromptEvalResult(
            promptId: UUID(),
            promptText: "Test prompt",
            response: response,
            passed: passed,
            score: score,
            decodeSpeed: decodeSpeed,
            ttft: ttft,
            toolCallEvents: toolCallEvents,
            duration: duration
        )
    }

    /// Creates a `ToolCallEvent` with the given tool name.
    private func makeToolCallEvent(
        toolName: String = "calculate",
        succeeded: Bool = true
    ) -> ToolCallEvent {
        ToolCallEvent(
            toolName: toolName,
            arguments: "{\"x\": 1}",
            result: "{\"value\": 2}",
            durationMs: 42.0,
            timestamp: Date(),
            succeeded: succeeded
        )
    }

    /// Creates a `ModelEvalResult` with the given prompt results.
    private func makeModelResult(
        promptResults: [PromptEvalResult],
        passRate: Double? = nil,
        totalDuration: TimeInterval = 60.0
    ) -> ModelEvalResult {
        ModelEvalResult(
            modelName: "Gemma Test",
            modelFile: "gemma-test.bin",
            avgDecodeSpeed: 45.3,
            avgTTFT: 0.87,
            p95Latency: 12.5,
            totalTokensGenerated: 1024,
            totalDuration: totalDuration,
            promptResults: promptResults,
            passRate: passRate
        )
    }

    // MARK: - EvalScore · Display Labels

    func testEvalScoreDisplayLabels() {
        XCTAssertEqual(EvalScore.pass.displayLabel, "Pass")
        XCTAssertEqual(EvalScore.fail(reason: "wrong").displayLabel, "Fail")
        XCTAssertEqual(EvalScore.timeout.displayLabel, "Timeout")
        XCTAssertEqual(EvalScore.error("oops").displayLabel, "Error")
        XCTAssertEqual(EvalScore.manualReviewNeeded.displayLabel, "Needs Review")
    }

    // MARK: - EvalScore · Symbol Names

    func testEvalScoreSymbolNames() {
        XCTAssertEqual(EvalScore.pass.symbolName, "checkmark.circle.fill")
        XCTAssertEqual(EvalScore.fail(reason: "x").symbolName, "xmark.circle.fill")
        XCTAssertEqual(EvalScore.timeout.symbolName, "clock.badge.exclamationmark")
        XCTAssertEqual(EvalScore.error("e").symbolName, "exclamationmark.triangle.fill")
        XCTAssertEqual(EvalScore.manualReviewNeeded.symbolName, "eye.circle")
    }

    // MARK: - EvalScore · isPass / isFailure

    func testEvalScoreIsPass() {
        XCTAssertTrue(EvalScore.pass.isPass)
        XCTAssertFalse(EvalScore.fail(reason: "bad").isPass)
        XCTAssertFalse(EvalScore.timeout.isPass)
        XCTAssertFalse(EvalScore.error("err").isPass)
        XCTAssertFalse(EvalScore.manualReviewNeeded.isPass)
    }

    func testEvalScoreIsFailure() {
        XCTAssertFalse(EvalScore.pass.isFailure)
        XCTAssertTrue(EvalScore.fail(reason: "bad").isFailure)
        XCTAssertTrue(EvalScore.timeout.isFailure)
        XCTAssertTrue(EvalScore.error("err").isFailure)
        // manualReviewNeeded is NOT a failure
        XCTAssertFalse(EvalScore.manualReviewNeeded.isFailure)
    }

    // MARK: - EvalScore · Reason

    func testEvalScoreReasonForFail() {
        let score = EvalScore.fail(reason: "Keyword missing")
        XCTAssertEqual(score.reason, "Keyword missing")
    }

    func testEvalScoreReasonForError() {
        let score = EvalScore.error("Engine crashed")
        XCTAssertEqual(score.reason, "Engine crashed")
    }

    func testEvalScoreReasonForTimeout() {
        XCTAssertEqual(EvalScore.timeout.reason, "Inference timed out")
    }

    func testEvalScoreReasonNilForPass() {
        XCTAssertNil(EvalScore.pass.reason)
    }

    func testEvalScoreReasonNilForManualReview() {
        XCTAssertNil(EvalScore.manualReviewNeeded.reason)
    }

    // MARK: - EvalScore · Codable Round-Trip

    func testEvalScoreCodableRoundTrip() throws {
        let scores: [EvalScore] = [
            .pass,
            .fail(reason: "Missing keyword"),
            .timeout,
            .error("OOM"),
            .manualReviewNeeded,
        ]
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for original in scores {
            let data = try encoder.encode(original)
            let decoded = try decoder.decode(EvalScore.self, from: data)
            // Verify round-trip preserves display label and reason
            XCTAssertEqual(decoded.displayLabel, original.displayLabel)
            XCTAssertEqual(decoded.reason, original.reason)
            XCTAssertEqual(decoded.isPass, original.isPass)
            XCTAssertEqual(decoded.isFailure, original.isFailure)
        }
    }

    // MARK: - EvalScore · Fail with Empty Reason

    func testEvalScoreFailWithEmptyReason() {
        let score = EvalScore.fail(reason: "")
        XCTAssertTrue(score.isFailure)
        XCTAssertEqual(score.reason, "")
        XCTAssertEqual(score.displayLabel, "Fail")
    }

    // MARK: - PromptEvalResult · Basic Properties

    func testPromptEvalResultBasicProperties() {
        let promptId = UUID()
        let result = PromptEvalResult(
            promptId: promptId,
            promptText: "What is 2+2?",
            response: "4",
            passed: true,
            score: .pass,
            decodeSpeed: 50.0,
            ttft: 0.5,
            duration: 1.5
        )

        XCTAssertEqual(result.promptId, promptId)
        XCTAssertEqual(result.promptText, "What is 2+2?")
        XCTAssertEqual(result.response, "4")
        XCTAssertTrue(result.passed)
        XCTAssertTrue(result.score.isPass)
        XCTAssertEqual(result.decodeSpeed, 50.0)
        XCTAssertEqual(result.ttft, 0.5)
        XCTAssertEqual(result.duration, 1.5)
    }

    // MARK: - PromptEvalResult · Tool Calls

    func testPromptEvalResultHadToolCallsWhenEmpty() {
        let result = makePromptResult(score: .pass, passed: true)
        XCTAssertFalse(result.hadToolCalls)
        XCTAssertTrue(result.toolNamesUsed.isEmpty)
    }

    func testPromptEvalResultHadToolCallsWithEvents() {
        let events = [
            makeToolCallEvent(toolName: "calculate"),
            makeToolCallEvent(toolName: "search"),
        ]
        let result = makePromptResult(score: .pass, passed: true, toolCallEvents: events)
        XCTAssertTrue(result.hadToolCalls)
        XCTAssertEqual(result.toolNamesUsed, ["calculate", "search"])
    }

    // MARK: - PromptEvalResult · Formatted Speed & TTFT

    func testPromptEvalResultFormattedDecodeSpeedWithValue() {
        let result = makePromptResult(score: .pass, passed: true, decodeSpeed: 43.12)
        XCTAssertEqual(result.formattedDecodeSpeed, "43.1 tok/s")
    }

    func testPromptEvalResultFormattedDecodeSpeedNil() {
        let result = makePromptResult(score: .pass, passed: true, decodeSpeed: nil)
        XCTAssertEqual(result.formattedDecodeSpeed, "N/A")
    }

    func testPromptEvalResultFormattedTTFTWithValue() {
        let result = makePromptResult(score: .pass, passed: true, ttft: 0.873)
        XCTAssertEqual(result.formattedTTFT, "0.87s")
    }

    func testPromptEvalResultFormattedTTFTNil() {
        let result = makePromptResult(score: .pass, passed: true, ttft: nil)
        XCTAssertEqual(result.formattedTTFT, "N/A")
    }

    // MARK: - PromptEvalResult · Truncated Response

    func testTruncatedResponseShortString() {
        let shortResponse = "Hello, world!"
        let result = makePromptResult(score: .pass, passed: true, response: shortResponse)
        XCTAssertEqual(result.truncatedResponse, shortResponse)
    }

    func testTruncatedResponseExactly120Characters() {
        let exact120 = String(repeating: "A", count: 120)
        let result = makePromptResult(score: .pass, passed: true, response: exact120)
        XCTAssertEqual(result.truncatedResponse, exact120)
    }

    func testTruncatedResponseOver120Characters() {
        let long = String(repeating: "B", count: 200)
        let result = makePromptResult(score: .pass, passed: true, response: long)
        XCTAssertEqual(result.truncatedResponse.count, 120)
        XCTAssertTrue(result.truncatedResponse.hasSuffix("..."))
        // First 117 chars should be "B"s
        let prefix = String(result.truncatedResponse.prefix(117))
        XCTAssertEqual(prefix, String(repeating: "B", count: 117))
    }

    func testTruncatedResponseEmptyString() {
        let result = makePromptResult(score: .pass, passed: true, response: "")
        XCTAssertEqual(result.truncatedResponse, "")
    }

    // MARK: - ModelEvalResult · Auto-Computed Pass Rate

    func testModelEvalResultAutoComputedPassRate() {
        let prompts = [
            makePromptResult(score: .pass, passed: true),
            makePromptResult(score: .pass, passed: true),
            makePromptResult(score: .fail(reason: "wrong"), passed: false),
        ]
        let model = makeModelResult(promptResults: prompts)
        // 2 out of 3 passed
        XCTAssertEqual(model.passRate, 2.0 / 3.0, accuracy: 0.001)
    }

    func testModelEvalResultExplicitPassRate() {
        let prompts = [
            makePromptResult(score: .pass, passed: true),
            makePromptResult(score: .fail(reason: "x"), passed: false),
        ]
        let model = makeModelResult(promptResults: prompts, passRate: 0.99)
        // Explicit rate overrides auto-computation
        XCTAssertEqual(model.passRate, 0.99, accuracy: 0.001)
    }

    func testModelEvalResultPassRateWithEmptyPrompts() {
        let model = makeModelResult(promptResults: [])
        XCTAssertEqual(model.passRate, 0)
    }

    // MARK: - ModelEvalResult · Counts

    func testModelEvalResultCounts() {
        let prompts = [
            makePromptResult(score: .pass, passed: true),
            makePromptResult(score: .pass, passed: true),
            makePromptResult(score: .fail(reason: "wrong"), passed: false),
            makePromptResult(score: .timeout, passed: false),
            makePromptResult(score: .error("OOM"), passed: false),
            makePromptResult(score: .manualReviewNeeded, passed: false),
        ]
        let model = makeModelResult(promptResults: prompts)

        XCTAssertEqual(model.passCount, 2)
        XCTAssertEqual(model.failCount, 4)  // total - passCount = 6 - 2 = 4
        XCTAssertEqual(model.timeoutCount, 1)
        XCTAssertEqual(model.errorCount, 1)
    }

    func testModelEvalResultCountsAllPassing() {
        let prompts = [
            makePromptResult(score: .pass, passed: true),
            makePromptResult(score: .pass, passed: true),
        ]
        let model = makeModelResult(promptResults: prompts)

        XCTAssertEqual(model.passCount, 2)
        XCTAssertEqual(model.failCount, 0)
        XCTAssertEqual(model.timeoutCount, 0)
        XCTAssertEqual(model.errorCount, 0)
    }

    // MARK: - ModelEvalResult · Formatted Strings

    func testModelEvalResultPassRatePercent() {
        let prompts = [
            makePromptResult(score: .pass, passed: true),
            makePromptResult(score: .fail(reason: "x"), passed: false),
        ]
        let model = makeModelResult(promptResults: prompts)
        XCTAssertEqual(model.passRatePercent, "50%")
    }

    func testModelEvalResultFormattedDecodeSpeed() {
        let model = makeModelResult(promptResults: [])
        XCTAssertEqual(model.formattedDecodeSpeed, "45.3 tok/s")
    }

    func testModelEvalResultFormattedTTFT() {
        let model = makeModelResult(promptResults: [])
        XCTAssertEqual(model.formattedTTFT, "0.87s")
    }

    func testModelEvalResultFormattedDurationSeconds() {
        let model = makeModelResult(promptResults: [], totalDuration: 45)
        XCTAssertEqual(model.formattedDuration, "45s")
    }

    func testModelEvalResultFormattedDurationMinutesAndSeconds() {
        let model = makeModelResult(promptResults: [], totalDuration: 123)
        XCTAssertEqual(model.formattedDuration, "2m 3s")
    }

    func testModelEvalResultDisplaySummary() {
        let prompts = [
            makePromptResult(score: .pass, passed: true),
            makePromptResult(score: .pass, passed: true),
            makePromptResult(score: .fail(reason: "x"), passed: false),
        ]
        // passRate auto-computed: 2/3 ≈ 0.666 → 66%
        let model = makeModelResult(promptResults: prompts)
        XCTAssertEqual(model.displaySummary, "66% pass · 45.3 tok/s · 0.87s TTFT")
    }

    // MARK: - EvalRun · Basic Init & Computed Properties

    func testEvalRunInProgressDefaults() {
        let suiteId = UUID()
        let run = EvalRun(suiteId: suiteId, suiteName: "Quality Suite")

        XCTAssertEqual(run.suiteId, suiteId)
        XCTAssertEqual(run.suiteName, "Quality Suite")
        XCTAssertFalse(run.isComplete)
        XCTAssertNil(run.duration)
        XCTAssertEqual(run.formattedDuration, "In progress…")
        XCTAssertEqual(run.modelCount, 0)
        XCTAssertTrue(run.modelResults.isEmpty)
    }

    func testEvalRunCompletedDuration() {
        let start = Date(timeIntervalSince1970: 1000)
        let end = Date(timeIntervalSince1970: 1154)  // 154 seconds = 2m 34s

        let run = EvalRun(
            suiteId: UUID(),
            suiteName: "Test",
            startedAt: start,
            completedAt: end,
            platform: "macOS",
            deviceName: "Mac"
        )

        XCTAssertTrue(run.isComplete)
        XCTAssertEqual(run.duration!, 154, accuracy: 0.001)
        XCTAssertEqual(run.formattedDuration, "2m 34s")
    }

    func testEvalRunFormattedDurationSecondsOnly() {
        let start = Date(timeIntervalSince1970: 0)
        let end = Date(timeIntervalSince1970: 45)

        let run = EvalRun(
            suiteId: UUID(),
            suiteName: "Test",
            startedAt: start,
            completedAt: end,
            platform: "macOS",
            deviceName: "Mac"
        )

        XCTAssertEqual(run.formattedDuration, "45s")
    }

    // MARK: - EvalRun · Overall Pass Rate

    func testEvalRunOverallPassRateEmpty() {
        let run = EvalRun(suiteId: UUID(), suiteName: "Empty")
        XCTAssertEqual(run.overallPassRate, 0)
    }

    func testEvalRunOverallPassRateMultipleModels() {
        let model1 = makeModelResult(
            promptResults: [
                makePromptResult(score: .pass, passed: true),
                makePromptResult(score: .pass, passed: true),
            ]
        )
        // model1.passRate = 1.0

        let model2 = makeModelResult(
            promptResults: [
                makePromptResult(score: .pass, passed: true),
                makePromptResult(score: .fail(reason: "x"), passed: false),
            ]
        )
        // model2.passRate = 0.5

        let run = EvalRun(
            suiteId: UUID(),
            suiteName: "Mixed",
            modelResults: [model1, model2]
        )

        // Overall = (1.0 + 0.5) / 2 = 0.75
        XCTAssertEqual(run.overallPassRate, 0.75, accuracy: 0.001)
    }

    // MARK: - EvalRun · Display Summary

    func testEvalRunDisplaySummarySingleModel() {
        let model = makeModelResult(
            promptResults: [makePromptResult(score: .pass, passed: true)]
        )

        let run = EvalRun(
            suiteId: UUID(),
            suiteName: "Test",
            modelResults: [model]
        )

        XCTAssertEqual(run.displaySummary, "1 model · 100% pass rate")
    }

    func testEvalRunDisplaySummaryMultipleModels() {
        let model1 = makeModelResult(
            promptResults: [makePromptResult(score: .pass, passed: true)]
        )
        let model2 = makeModelResult(
            promptResults: [makePromptResult(score: .pass, passed: true)]
        )

        let run = EvalRun(
            suiteId: UUID(),
            suiteName: "Test",
            modelResults: [model1, model2]
        )

        XCTAssertEqual(run.displaySummary, "2 models · 100% pass rate")
    }

    // MARK: - EvalRun · Platform Detection

    func testEvalRunCurrentPlatform() {
        let platform = EvalRun.currentPlatform
        #if os(iOS)
        XCTAssertEqual(platform, "iOS")
        #elseif os(macOS)
        XCTAssertEqual(platform, "macOS")
        #endif
    }

    func testEvalRunCurrentDeviceName() {
        let name = EvalRun.currentDeviceName
        XCTAssertFalse(name.isEmpty)
    }

    // MARK: - EvalRun · Codable Round-Trip

    func testEvalRunCodableRoundTrip() throws {
        let promptResults = [
            makePromptResult(score: .pass, passed: true, decodeSpeed: 50.0, ttft: 0.5),
            makePromptResult(score: .fail(reason: "Missing keyword"), passed: false, decodeSpeed: 40.0, ttft: 0.7),
            makePromptResult(score: .timeout, passed: false),
            makePromptResult(score: .error("OOM"), passed: false),
            makePromptResult(score: .manualReviewNeeded, passed: false),
        ]

        let toolEvents = [makeToolCallEvent(toolName: "get_weather")]
        let promptWithTools = makePromptResult(
            score: .pass,
            passed: true,
            decodeSpeed: 55.0,
            ttft: 0.3,
            toolCallEvents: toolEvents
        )

        let model = ModelEvalResult(
            modelName: "Gemma 4 E2B",
            modelFile: "gemma-4-E2B-it.bin",
            avgDecodeSpeed: 45.3,
            avgTTFT: 0.87,
            p95Latency: 12.5,
            totalTokensGenerated: 2048,
            totalDuration: 120.0,
            promptResults: promptResults + [promptWithTools],
            toolCallAccuracy: 0.95,
            peakMemoryDeltaMB: 512.0,
            thermalTransitions: 2
        )

        let start = Date(timeIntervalSince1970: 1000)
        let end = Date(timeIntervalSince1970: 1120)

        let original = EvalRun(
            suiteId: UUID(),
            suiteName: "Full Codable Test Suite",
            startedAt: start,
            completedAt: end,
            platform: "macOS",
            deviceName: "MacBook Pro (M4 Max)",
            modelResults: [model]
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(EvalRun.self, from: data)

        // Verify top-level properties
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.suiteId, original.suiteId)
        XCTAssertEqual(decoded.suiteName, original.suiteName)
        XCTAssertEqual(decoded.platform, original.platform)
        XCTAssertEqual(decoded.deviceName, original.deviceName)
        XCTAssertTrue(decoded.isComplete)
        XCTAssertEqual(decoded.modelCount, 1)

        // Verify model result
        let decodedModel = decoded.modelResults[0]
        XCTAssertEqual(decodedModel.modelName, "Gemma 4 E2B")
        XCTAssertEqual(decodedModel.modelFile, "gemma-4-E2B-it.bin")
        XCTAssertEqual(decodedModel.avgDecodeSpeed, 45.3, accuracy: 0.01)
        XCTAssertEqual(decodedModel.promptResults.count, 6)
        XCTAssertEqual(decodedModel.thermalTransitions, 2)
        XCTAssertEqual(decodedModel.peakMemoryDeltaMB, 512.0)
        XCTAssertEqual(decodedModel.toolCallAccuracy, 0.95)

        // Verify score round-trips
        XCTAssertTrue(decodedModel.promptResults[0].score.isPass)
        XCTAssertEqual(decodedModel.promptResults[1].score.reason, "Missing keyword")
        XCTAssertEqual(decodedModel.promptResults[2].score.displayLabel, "Timeout")
        XCTAssertEqual(decodedModel.promptResults[3].score.reason, "OOM")
        XCTAssertFalse(decodedModel.promptResults[4].score.isPass)
        XCTAssertFalse(decodedModel.promptResults[4].score.isFailure)

        // Verify tool call event round-trip
        let decodedToolPrompt = decodedModel.promptResults[5]
        XCTAssertTrue(decodedToolPrompt.hadToolCalls)
        XCTAssertEqual(decodedToolPrompt.toolNamesUsed, ["get_weather"])
    }

    // MARK: - EvalRunIndexEntry

    func testEvalRunIndexEntryFromCompleteRun() {
        let start = Date(timeIntervalSince1970: 5000)
        let end = Date(timeIntervalSince1970: 5200)

        let model = makeModelResult(
            promptResults: [
                makePromptResult(score: .pass, passed: true),
                makePromptResult(score: .pass, passed: true),
                makePromptResult(score: .fail(reason: "x"), passed: false),
            ]
        )

        let run = EvalRun(
            suiteId: UUID(),
            suiteName: "Index Test",
            startedAt: start,
            completedAt: end,
            platform: "iOS",
            deviceName: "iPhone 16 Pro",
            modelResults: [model]
        )

        let entry = EvalRunIndexEntry(from: run)

        XCTAssertEqual(entry.id, run.id)
        XCTAssertEqual(entry.suiteName, "Index Test")
        XCTAssertEqual(entry.modelCount, 1)
        XCTAssertEqual(entry.overallPassRate, run.overallPassRate, accuracy: 0.001)
        XCTAssertEqual(entry.platform, "iOS")
        XCTAssertEqual(entry.deviceName, "iPhone 16 Pro")
        XCTAssertTrue(entry.isComplete)
    }

    func testEvalRunIndexEntryFromInProgressRun() {
        let run = EvalRun(
            suiteId: UUID(),
            suiteName: "In Progress",
            completedAt: nil,
            platform: "macOS",
            deviceName: "Mac"
        )

        let entry = EvalRunIndexEntry(from: run)
        XCTAssertFalse(entry.isComplete)
        XCTAssertNil(entry.completedAt)
        XCTAssertEqual(entry.modelCount, 0)
        XCTAssertEqual(entry.overallPassRate, 0)
    }

    // MARK: - EvalRunIndexEntry · Codable Round-Trip

    func testEvalRunIndexEntryCodableRoundTrip() throws {
        let run = EvalRun(
            suiteId: UUID(),
            suiteName: "Codable Entry Test",
            startedAt: Date(timeIntervalSince1970: 100),
            completedAt: Date(timeIntervalSince1970: 200),
            platform: "macOS",
            deviceName: "Mac Studio"
        )

        let original = EvalRunIndexEntry(from: run)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(EvalRunIndexEntry.self, from: data)

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.suiteName, original.suiteName)
        XCTAssertEqual(decoded.modelCount, original.modelCount)
        XCTAssertEqual(decoded.overallPassRate, original.overallPassRate, accuracy: 0.001)
        XCTAssertEqual(decoded.platform, original.platform)
        XCTAssertEqual(decoded.deviceName, original.deviceName)
        XCTAssertEqual(decoded.isComplete, original.isComplete)
    }

    // MARK: - ToolCallEvent · Properties

    func testToolCallEventProperties() {
        let now = Date()
        let event = ToolCallEvent(
            toolName: "search",
            arguments: "{\"query\": \"test\"}",
            result: "{\"found\": true}",
            durationMs: 150.5,
            timestamp: now,
            succeeded: true
        )

        XCTAssertEqual(event.toolName, "search")
        XCTAssertEqual(event.arguments, "{\"query\": \"test\"}")
        XCTAssertEqual(event.result, "{\"found\": true}")
        XCTAssertEqual(event.durationMs, 150.5)
        XCTAssertTrue(event.succeeded)
    }

    func testToolCallEventFailedCall() {
        let event = ToolCallEvent(
            toolName: "dangerous_op",
            arguments: "{}",
            result: "{\"error\": \"denied\"}",
            durationMs: 5.0,
            timestamp: Date(),
            succeeded: false
        )

        XCTAssertFalse(event.succeeded)
        XCTAssertEqual(event.toolName, "dangerous_op")
    }

    // MARK: - ModelEvalResult · Thermal & Memory

    func testModelEvalResultResourceMetrics() {
        let model = ModelEvalResult(
            modelName: "Test Model",
            modelFile: "test.bin",
            avgDecodeSpeed: 30.0,
            avgTTFT: 1.2,
            p95Latency: 20.0,
            totalTokensGenerated: 512,
            totalDuration: 90.0,
            promptResults: [],
            peakMemoryDeltaMB: 256.5,
            thermalTransitions: 3
        )

        XCTAssertEqual(model.peakMemoryDeltaMB, 256.5)
        XCTAssertEqual(model.thermalTransitions, 3)
    }

    func testModelEvalResultNilResourceMetrics() {
        let model = ModelEvalResult(
            modelName: "Test Model",
            modelFile: "test.bin",
            avgDecodeSpeed: 30.0,
            avgTTFT: 1.2,
            p95Latency: 20.0,
            totalTokensGenerated: 512,
            totalDuration: 90.0,
            promptResults: []
        )

        XCTAssertNil(model.peakMemoryDeltaMB)
        XCTAssertNil(model.toolCallAccuracy)
        XCTAssertEqual(model.thermalTransitions, 0)
    }

    // MARK: - PromptEvalResult · Identifiable

    func testPromptEvalResultIdentifiable() {
        let id = UUID()
        let result = PromptEvalResult(
            id: id,
            promptId: UUID(),
            promptText: "test",
            response: "resp",
            passed: true,
            score: .pass
        )
        XCTAssertEqual(result.id, id)
    }

    // MARK: - ModelEvalResult · Identifiable

    func testModelEvalResultIdentifiable() {
        let id = UUID()
        let model = ModelEvalResult(
            id: id,
            modelName: "M",
            modelFile: "m.bin",
            avgDecodeSpeed: 1,
            avgTTFT: 1,
            p95Latency: 1,
            totalTokensGenerated: 1,
            totalDuration: 1,
            promptResults: []
        )
        XCTAssertEqual(model.id, id)
    }

    // MARK: - EvalRun · Identifiable

    func testEvalRunIdentifiable() {
        let id = UUID()
        let run = EvalRun(
            id: id,
            suiteId: UUID(),
            suiteName: "Test"
        )
        XCTAssertEqual(run.id, id)
    }
}
