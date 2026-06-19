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

// MARK: - EvalStoreLogicTests

/// Pure-logic tests for types in `EvalStore.swift`, `EvalResult.swift`, and
/// `EvalResultPersistence.swift`. Focuses on computed properties, aggregation
/// formulas, and Codable round-trips that the existing XCTest suites don't
/// exercise (e.g., EvalStoreError, EvalExportRecord, multi-model pass rate
/// edge cases, EvalRunIndexEntry Codable fidelity).
@Suite("EvalStore Logic")
struct EvalStoreLogicTests {

    // MARK: - Helpers

    private static func makePromptResult(
        passed: Bool,
        score: EvalScore = .pass,
        decodeSpeed: Double? = nil,
        ttft: Double? = nil,
        response: String = "Test response",
        duration: TimeInterval = 1.0,
        toolCallEvents: [ToolCallEvent] = []
    ) -> PromptEvalResult {
        PromptEvalResult(
            promptId: UUID(),
            promptText: "Test prompt",
            response: response,
            passed: passed,
            score: passed ? .pass : score,
            decodeSpeed: decodeSpeed,
            ttft: ttft,
            toolCallEvents: toolCallEvents,
            duration: duration
        )
    }

    private static func makeModelResult(
        promptResults: [PromptEvalResult],
        passRate: Double? = nil,
        avgDecodeSpeed: Double = 45.0,
        avgTTFT: Double = 0.8,
        totalDuration: TimeInterval = 60.0
    ) -> ModelEvalResult {
        ModelEvalResult(
            modelName: "Test Model",
            modelFile: "test.bin",
            avgDecodeSpeed: avgDecodeSpeed,
            avgTTFT: avgTTFT,
            p95Latency: 15.0,
            totalTokensGenerated: 1024,
            totalDuration: totalDuration,
            promptResults: promptResults,
            passRate: passRate
        )
    }

    private static func makeRun(
        suiteName: String = "Test Suite",
        modelResults: [ModelEvalResult] = [],
        startedAt: Date = Date(timeIntervalSince1970: 1000),
        completedAt: Date? = nil
    ) -> EvalRun {
        EvalRun(
            suiteId: UUID(),
            suiteName: suiteName,
            startedAt: startedAt,
            completedAt: completedAt,
            platform: "macOS",
            deviceName: "Test Mac",
            modelResults: modelResults
        )
    }

    // MARK: - EvalStoreError Descriptions

    @Suite("EvalStoreError LocalizedError")
    struct StoreErrorDescriptions {

        @Test("saveFailed includes underlying error message")
        func saveFailedMessage() {
            let underlying = NSError(
                domain: "Test",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "disk full"]
            )
            let error = EvalStoreError.saveFailed(underlying)
            #expect(error.errorDescription?.contains("disk full") == true)
        }

        @Test("loadFailed includes underlying error message")
        func loadFailedMessage() {
            let underlying = NSError(
                domain: "Test",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "corrupted JSON"]
            )
            let error = EvalStoreError.loadFailed(underlying)
            #expect(error.errorDescription?.contains("corrupted JSON") == true)
        }

        @Test("deleteFailed includes underlying error message")
        func deleteFailedMessage() {
            let underlying = NSError(
                domain: "Test",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "permission denied"]
            )
            let error = EvalStoreError.deleteFailed(underlying)
            #expect(error.errorDescription?.contains("permission denied") == true)
        }

        @Test("notFound includes UUID in description")
        func notFoundMessage() {
            let id = UUID()
            let error = EvalStoreError.notFound(id)
            #expect(error.errorDescription?.contains(id.uuidString) == true)
        }

        @Test("exportFailed includes reason string")
        func exportFailedMessage() {
            let error = EvalStoreError.exportFailed("UTF-8 encoding failed")
            #expect(error.errorDescription?.contains("UTF-8 encoding failed") == true)
        }
    }

    // MARK: - EvalRun Aggregation Edge Cases

    @Suite("EvalRun aggregation")
    struct RunAggregation {

        @Test("overallPassRate uses actual counts not averaged rates")
        func overallPassRateUsesActualCounts() {
            // Model 1: 1/1 pass (100%), Model 2: 1/3 pass (33%)
            // Naive average: (100+33)/2 = 66.5%
            // Correct (actual counts): 2/4 = 50%
            let model1 = makeModelResult(
                promptResults: [makePromptResult(passed: true)]
            )
            let model2 = makeModelResult(
                promptResults: [
                    makePromptResult(passed: true),
                    makePromptResult(passed: false, score: .fail(reason: "x")),
                    makePromptResult(passed: false, score: .fail(reason: "y")),
                ]
            )
            let run = makeRun(modelResults: [model1, model2])

            // 2 passed out of 4 total
            #expect(run.overallPassRate == 0.5)
        }

        @Test("overallPassRate zero for models with zero prompts")
        func overallPassRateZeroForEmptyModels() {
            let emptyModel = makeModelResult(promptResults: [])
            let run = makeRun(modelResults: [emptyModel])
            #expect(run.overallPassRate == 0)
        }

        @Test("overallPassRate 1.0 when all prompts pass")
        func overallPassRateAllPass() {
            let model = makeModelResult(
                promptResults: [
                    makePromptResult(passed: true),
                    makePromptResult(passed: true),
                    makePromptResult(passed: true),
                ]
            )
            let run = makeRun(modelResults: [model])
            #expect(run.overallPassRate == 1.0)
        }

        @Test("displaySummary singular model word")
        func displaySummarySingular() {
            let model = makeModelResult(
                promptResults: [makePromptResult(passed: true)]
            )
            let run = makeRun(modelResults: [model])
            #expect(run.displaySummary.contains("1 model"))
            #expect(!run.displaySummary.contains("models"))
        }

        @Test("displaySummary plural models word")
        func displaySummaryPlural() {
            let model1 = makeModelResult(promptResults: [])
            let model2 = makeModelResult(promptResults: [])
            let run = makeRun(modelResults: [model1, model2])
            #expect(run.displaySummary.contains("2 models"))
        }

        @Test("modelCount reflects actual number of model results")
        func modelCountAccurate() {
            let models = (0..<5).map { _ in makeModelResult(promptResults: []) }
            let run = makeRun(modelResults: models)
            #expect(run.modelCount == 5)
        }
    }

    // MARK: - EvalRun Duration Formatting

    @Suite("EvalRun duration formatting")
    struct RunDurationFormatting {

        @Test("In-progress run shows 'In progress…'")
        func inProgressDuration() {
            let run = makeRun(completedAt: nil)
            #expect(run.formattedDuration == "In progress…")
            #expect(run.duration == nil)
            #expect(!run.isComplete)
        }

        @Test("Seconds-only duration format")
        func secondsOnly() {
            let run = makeRun(
                startedAt: Date(timeIntervalSince1970: 0),
                completedAt: Date(timeIntervalSince1970: 42)
            )
            #expect(run.formattedDuration == "42s")
        }

        @Test("Minutes and seconds duration format")
        func minutesAndSeconds() {
            let run = makeRun(
                startedAt: Date(timeIntervalSince1970: 0),
                completedAt: Date(timeIntervalSince1970: 185)
            )
            #expect(run.formattedDuration == "3m 5s")
        }

        @Test("Zero second duration")
        func zeroDuration() {
            let t = Date(timeIntervalSince1970: 500)
            let run = makeRun(startedAt: t, completedAt: t)
            #expect(run.formattedDuration == "0s")
        }
    }

    // MARK: - ModelEvalResult Computed Counts

    @Suite("ModelEvalResult computed counts")
    struct ModelResultCounts {

        @Test("timeoutCount counts only timeout scores")
        func timeoutCountAccuracy() {
            let prompts = [
                makePromptResult(passed: false, score: .timeout),
                makePromptResult(passed: false, score: .timeout),
                makePromptResult(passed: false, score: .fail(reason: "x")),
                makePromptResult(passed: true),
            ]
            let model = makeModelResult(promptResults: prompts)
            #expect(model.timeoutCount == 2)
        }

        @Test("errorCount counts only error scores")
        func errorCountAccuracy() {
            let prompts = [
                makePromptResult(passed: false, score: .error("OOM")),
                makePromptResult(passed: false, score: .error("crash")),
                makePromptResult(passed: false, score: .error("timeout")),
                makePromptResult(passed: false, score: .fail(reason: "wrong")),
            ]
            let model = makeModelResult(promptResults: prompts)
            #expect(model.errorCount == 3)
        }

        @Test("failCount is total minus passCount")
        func failCountDerivation() {
            let prompts = [
                makePromptResult(passed: true),
                makePromptResult(passed: false, score: .fail(reason: "a")),
                makePromptResult(passed: false, score: .timeout),
                makePromptResult(passed: false, score: .error("b")),
                makePromptResult(passed: false, score: .manualReviewNeeded),
            ]
            let model = makeModelResult(promptResults: prompts)
            #expect(model.passCount == 1)
            #expect(model.failCount == 4)  // 5 - 1
        }

        @Test("Auto-computed passRate for all-failing prompts")
        func allFailing() {
            let prompts = [
                makePromptResult(passed: false, score: .fail(reason: "a")),
                makePromptResult(passed: false, score: .fail(reason: "b")),
            ]
            let model = makeModelResult(promptResults: prompts)
            #expect(model.passRate == 0)
        }

        @Test("passRatePercent rounds to integer")
        func passRatePercentRounding() {
            // 1 pass out of 3 = 33.33...% → "33%"
            let prompts = [
                makePromptResult(passed: true),
                makePromptResult(passed: false, score: .fail(reason: "a")),
                makePromptResult(passed: false, score: .fail(reason: "b")),
            ]
            let model = makeModelResult(promptResults: prompts)
            #expect(model.passRatePercent == "33%")
        }
    }

    // MARK: - ModelEvalResult Formatted Strings

    @Suite("ModelEvalResult formatted strings")
    struct ModelResultFormatted {

        @Test("formattedDecodeSpeed uses one decimal place")
        func decodeSpeedFormat() {
            let model = makeModelResult(promptResults: [], avgDecodeSpeed: 123.456)
            #expect(model.formattedDecodeSpeed == "123.5 tok/s")
        }

        @Test("formattedTTFT uses two decimal places")
        func ttftFormat() {
            let model = makeModelResult(promptResults: [], avgTTFT: 1.234)
            #expect(model.formattedTTFT == "1.23s")
        }

        @Test("formattedDuration seconds only for under a minute")
        func durationSecondsOnly() {
            let model = makeModelResult(promptResults: [], totalDuration: 55)
            #expect(model.formattedDuration == "55s")
        }

        @Test("formattedDuration minutes and seconds for 60+")
        func durationMinutesSeconds() {
            let model = makeModelResult(promptResults: [], totalDuration: 90)
            #expect(model.formattedDuration == "1m 30s")
        }
    }

    // MARK: - PromptEvalResult Edge Cases

    @Suite("PromptEvalResult edge cases")
    struct PromptResultEdgeCases {

        @Test("truncatedResponse at exactly 121 characters")
        func truncateAt121() {
            let response = String(repeating: "X", count: 121)
            let result = makePromptResult(passed: true, response: response)
            #expect(result.truncatedResponse.count == 120)
            #expect(result.truncatedResponse.hasSuffix("..."))
        }

        @Test("formattedDecodeSpeed nil returns N/A")
        func decodeSpeedNil() {
            let result = makePromptResult(passed: true, decodeSpeed: nil)
            #expect(result.formattedDecodeSpeed == "N/A")
        }

        @Test("formattedTTFT nil returns N/A")
        func ttftNil() {
            let result = makePromptResult(passed: true, ttft: nil)
            #expect(result.formattedTTFT == "N/A")
        }

        @Test("toolNamesUsed collects all tool names in order")
        func toolNamesOrdered() {
            let events = [
                ToolCallEvent(
                    toolName: "search",
                    arguments: "{}",
                    result: "{}",
                    durationMs: 10,
                    timestamp: Date(),
                    succeeded: true
                ),
                ToolCallEvent(
                    toolName: "calculate",
                    arguments: "{}",
                    result: "{}",
                    durationMs: 20,
                    timestamp: Date(),
                    succeeded: true
                ),
            ]
            let result = makePromptResult(
                passed: true,
                toolCallEvents: events
            )
            #expect(result.toolNamesUsed == ["search", "calculate"])
            #expect(result.hadToolCalls)
        }
    }

    // MARK: - EvalScore Edge Cases

    @Suite("EvalScore edge cases")
    struct ScoreEdgeCases {

        @Test("manualReviewNeeded is neither pass nor failure")
        func manualReviewNeither() {
            let score = EvalScore.manualReviewNeeded
            #expect(!score.isPass)
            #expect(!score.isFailure)
            #expect(score.reason == nil)
        }

        @Test("EvalScore Equatable", arguments: [
            (EvalScore.pass, EvalScore.pass, true),
            (EvalScore.timeout, EvalScore.timeout, true),
            (EvalScore.manualReviewNeeded, EvalScore.manualReviewNeeded, true),
            (EvalScore.fail(reason: "a"), EvalScore.fail(reason: "a"), true),
            (EvalScore.fail(reason: "a"), EvalScore.fail(reason: "b"), false),
            (EvalScore.error("x"), EvalScore.error("x"), true),
            (EvalScore.error("x"), EvalScore.error("y"), false),
            (EvalScore.pass, EvalScore.timeout, false),
        ])
        func equatable(lhs: EvalScore, rhs: EvalScore, expected: Bool) {
            #expect((lhs == rhs) == expected)
        }
    }

    // MARK: - EvalRunIndexEntry from Run

    @Suite("EvalRunIndexEntry construction")
    struct IndexEntryConstruction {

        @Test("Index entry copies all fields from run")
        func fieldsCopied() {
            let model = makeModelResult(
                promptResults: [
                    makePromptResult(passed: true),
                    makePromptResult(passed: false, score: .fail(reason: "x")),
                ]
            )
            let start = Date(timeIntervalSince1970: 5000)
            let end = Date(timeIntervalSince1970: 5300)
            let run = EvalRun(
                suiteId: UUID(),
                suiteName: "Entry Test",
                startedAt: start,
                completedAt: end,
                platform: "iOS",
                deviceName: "iPhone 16 Pro",
                modelResults: [model]
            )
            let entry = EvalRunIndexEntry(from: run)

            #expect(entry.id == run.id)
            #expect(entry.suiteName == "Entry Test")
            #expect(entry.modelCount == 1)
            #expect(entry.platform == "iOS")
            #expect(entry.deviceName == "iPhone 16 Pro")
            #expect(entry.isComplete)
            // overallPassRate: 1 pass / 2 total = 0.5
            #expect(entry.overallPassRate == run.overallPassRate)
        }

        @Test("Index entry for in-progress run")
        func inProgress() {
            let run = makeRun(completedAt: nil)
            let entry = EvalRunIndexEntry(from: run)
            #expect(!entry.isComplete)
            #expect(entry.completedAt == nil)
        }

        @Test("Index entry Codable round-trip preserves all fields")
        func codableRoundTrip() throws {
            let run = EvalRun(
                suiteId: UUID(),
                suiteName: "Codable Entry",
                startedAt: Date(timeIntervalSince1970: 100),
                completedAt: Date(timeIntervalSince1970: 200),
                platform: "macOS",
                deviceName: "Mac Studio",
                modelResults: [
                    makeModelResult(
                        promptResults: [makePromptResult(passed: true)]
                    ),
                ]
            )
            let original = EvalRunIndexEntry(from: run)

            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            let data = try encoder.encode(original)
            let decoded = try decoder.decode(EvalRunIndexEntry.self, from: data)

            #expect(decoded.id == original.id)
            #expect(decoded.suiteName == original.suiteName)
            #expect(decoded.modelCount == original.modelCount)
            #expect(decoded.platform == original.platform)
            #expect(decoded.deviceName == original.deviceName)
            #expect(decoded.isComplete == original.isComplete)
            // Compare overallPassRate with tolerance
            let diff = abs(decoded.overallPassRate - original.overallPassRate)
            #expect(diff < 0.001)
        }
    }

    // MARK: - EvalExportError Descriptions

    @Suite("EvalExportError LocalizedError")
    struct ExportErrorDescriptions {

        @Test("saveFailed includes underlying error")
        func saveFailed() {
            let underlying = NSError(
                domain: "Test",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "no space"]
            )
            let error = EvalExportError.saveFailed(underlying)
            #expect(error.errorDescription?.contains("no space") == true)
        }

        @Test("loadFailed includes underlying error")
        func loadFailed() {
            let underlying = NSError(
                domain: "Test",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "bad format"]
            )
            let error = EvalExportError.loadFailed(underlying)
            #expect(error.errorDescription?.contains("bad format") == true)
        }

        @Test("deleteFailed includes underlying error")
        func deleteFailed() {
            let underlying = NSError(
                domain: "Test",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "locked file"]
            )
            let error = EvalExportError.deleteFailed(underlying)
            #expect(error.errorDescription?.contains("locked file") == true)
        }
    }

    // MARK: - EvalExportRecord Construction

    @Suite("EvalExportRecord from EvalRun")
    struct ExportRecordConstruction {

        @Test("Export record captures run metadata")
        func capturesMetadata() {
            let model = makeModelResult(
                promptResults: [
                    makePromptResult(passed: true, decodeSpeed: 50.0, ttft: 0.3),
                    makePromptResult(passed: false, score: .fail(reason: "wrong")),
                ]
            )
            let run = EvalRun(
                suiteId: UUID(),
                suiteName: "Export Test",
                suiteCategory: .math,
                startedAt: Date(timeIntervalSince1970: 1000),
                completedAt: Date(timeIntervalSince1970: 1200),
                platform: "macOS",
                deviceName: "MacBook Pro",
                modelResults: [model]
            )

            let record = EvalExportRecord(from: run)

            #expect(record.exportVersion == "1.0")
            #expect(record.runId == run.id)
            #expect(record.suiteName == "Export Test")
            #expect(record.suiteCategory == "math")
            #expect(record.platform == "macOS")
            #expect(record.deviceName == "MacBook Pro")
            #expect(record.modelCount == 1)
            #expect(record.totalPrompts == 2)
            #expect(record.models.count == 1)
            // overallPassRate: 1/2 = 0.5
            let diff = abs(record.overallPassRate - 0.5)
            #expect(diff < 0.001)
        }

        @Test("Export record Codable round-trip")
        func codableRoundTrip() throws {
            let model = makeModelResult(
                promptResults: [makePromptResult(passed: true)]
            )
            let run = makeRun(
                suiteName: "Round Trip",
                modelResults: [model],
                completedAt: Date(timeIntervalSince1970: 1100)
            )

            let record = EvalExportRecord(from: run)

            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            let data = try encoder.encode(record)
            let decoded = try decoder.decode(EvalExportRecord.self, from: data)

            #expect(decoded.exportVersion == "1.0")
            #expect(decoded.runId == record.runId)
            #expect(decoded.suiteName == "Round Trip")
            #expect(decoded.models.count == 1)
            #expect(decoded.models.first?.prompts.count == 1)
            #expect(decoded.models.first?.prompts.first?.passed == true)
        }
    }

    // MARK: - ExportPromptScore Truncation

    @Suite("ExportPromptScore response truncation")
    struct ExportPromptTruncation {

        @Test("Response under 500 chars preserved in full")
        func shortResponsePreserved() {
            let prompt = makePromptResult(passed: true, response: "Short answer")
            let exported = ExportPromptScore(from: prompt)
            #expect(exported.response == "Short answer")
        }

        @Test("Response over 500 chars truncated with ellipsis")
        func longResponseTruncated() {
            let longResponse = String(repeating: "A", count: 600)
            let prompt = makePromptResult(passed: true, response: longResponse)
            let exported = ExportPromptScore(from: prompt)
            #expect(exported.response.count == 500)
            #expect(exported.response.hasSuffix("..."))
        }

        @Test("Export preserves score metadata")
        func scoreMetadata() {
            let prompt = PromptEvalResult(
                promptId: UUID(),
                promptText: "What is 2+2?",
                response: "4",
                passed: true,
                score: .pass,
                decodeSpeed: 55.0,
                ttft: 0.4,
                duration: 2.0
            )
            let exported = ExportPromptScore(from: prompt)
            #expect(exported.scoreLabel == "Pass")
            #expect(exported.scoreReason == nil)
            #expect(exported.decodeSpeed == 55.0)
            #expect(exported.ttft == 0.4)
            #expect(exported.duration == 2.0)
            #expect(exported.passed)
        }

        @Test("Export captures failure reason")
        func failureReason() {
            let prompt = PromptEvalResult(
                promptId: UUID(),
                promptText: "Solve this",
                response: "Wrong",
                passed: false,
                score: .fail(reason: "Expected 42"),
                duration: 3.0
            )
            let exported = ExportPromptScore(from: prompt)
            #expect(exported.scoreLabel == "Fail")
            #expect(exported.scoreReason == "Expected 42")
            #expect(!exported.passed)
        }
    }
}
