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

// MARK: - EvalComparisonLogic Tests

@Suite("EvalComparisonLogic")
struct EvalComparisonLogicTests {

    // MARK: - Test Helpers

    /// Create a minimal `PromptEvalResult` with an optional decode speed.
    private static func makePromptResult(decodeSpeed: Double? = nil) -> PromptEvalResult {
        PromptEvalResult(
            promptId: UUID(),
            promptText: "test prompt",
            response: "test response",
            passed: true,
            score: .pass,
            decodeSpeed: decodeSpeed,
            duration: 1.0
        )
    }

    /// Create a minimal `ModelEvalResult` with the given prompt results.
    private static func makeModelResult(promptResults: [PromptEvalResult]) -> ModelEvalResult {
        ModelEvalResult(
            modelName: "TestModel",
            modelFile: "test.bin",
            avgDecodeSpeed: 0,
            avgTTFT: 0,
            p95Latency: 0,
            totalTokensGenerated: 0,
            totalDuration: 0,
            promptResults: promptResults
        )
    }

    // MARK: - averageDecodeSpeed

    @Suite("averageDecodeSpeed")
    struct AverageDecodeSpeedTests {

        @Test("Returns nil for empty model results array")
        func emptyArray() {
            #expect(EvalComparisonLogic.averageDecodeSpeed(from: []) == nil)
        }

        @Test("Returns nil when all decode speeds are nil")
        func allNilSpeeds() {
            let prompt1 = makePromptResult(decodeSpeed: nil)
            let prompt2 = makePromptResult(decodeSpeed: nil)
            let model = makeModelResult(promptResults: [prompt1, prompt2])
            #expect(EvalComparisonLogic.averageDecodeSpeed(from: [model]) == nil)
        }

        @Test("Single model with single speed returns that speed")
        func singleSpeed() {
            let prompt = makePromptResult(decodeSpeed: 42.0)
            let model = makeModelResult(promptResults: [prompt])
            let result = EvalComparisonLogic.averageDecodeSpeed(from: [model])
            #expect(result == 42.0)
        }

        @Test("Single model with multiple speeds returns arithmetic mean")
        func multipleSpeedsOneModel() {
            let p1 = makePromptResult(decodeSpeed: 20.0)
            let p2 = makePromptResult(decodeSpeed: 40.0)
            let model = makeModelResult(promptResults: [p1, p2])
            let result = EvalComparisonLogic.averageDecodeSpeed(from: [model])
            #expect(result == 30.0)
        }

        @Test("Multiple models aggregates speeds across all prompt results")
        func multipleModels() {
            let m1 = makeModelResult(promptResults: [
                makePromptResult(decodeSpeed: 10.0),
                makePromptResult(decodeSpeed: 20.0),
            ])
            let m2 = makeModelResult(promptResults: [
                makePromptResult(decodeSpeed: 30.0),
            ])
            // Mean of [10, 20, 30] = 20
            let result = EvalComparisonLogic.averageDecodeSpeed(from: [m1, m2])
            #expect(result == 20.0)
        }

        @Test("Nil speeds are excluded from the average")
        func mixedNilAndValues() {
            let m = makeModelResult(promptResults: [
                makePromptResult(decodeSpeed: nil),
                makePromptResult(decodeSpeed: 50.0),
                makePromptResult(decodeSpeed: 30.0),
                makePromptResult(decodeSpeed: nil),
            ])
            // Mean of [50, 30] = 40
            let result = EvalComparisonLogic.averageDecodeSpeed(from: [m])
            #expect(result == 40.0)
        }
    }

    // MARK: - formatDuration

    @Suite("formatDuration")
    struct FormatDurationTests {

        @Test("Zero seconds shows 0s")
        func zeroSeconds() {
            #expect(EvalComparisonLogic.formatDuration(0) == "0s")
        }

        @Test("30 seconds shows seconds only")
        func thirtySeconds() {
            #expect(EvalComparisonLogic.formatDuration(30) == "30s")
        }

        @Test("59 seconds shows seconds only")
        func fiftyNineSeconds() {
            #expect(EvalComparisonLogic.formatDuration(59) == "59s")
        }

        @Test("61 seconds shows 1m 1s")
        func sixtyOneSeconds() {
            #expect(EvalComparisonLogic.formatDuration(61) == "1m 1s")
        }

        @Test("60 seconds shows 1m 0s")
        func exactlyOneMinute() {
            #expect(EvalComparisonLogic.formatDuration(60) == "1m 0s")
        }

        @Test("3600 seconds shows 60m 0s")
        func oneHour() {
            #expect(EvalComparisonLogic.formatDuration(3600) == "60m 0s")
        }

        @Test("Negative value uses Int truncation toward zero")
        func negativeValue() {
            // Int(-5) / 60 == 0, Int(-5) % 60 == -5 → "0m -5s" won't happen
            // because mins == 0 so it falls through to "\(secs)s" → "-5s"
            let result = EvalComparisonLogic.formatDuration(-5)
            #expect(result == "-5s")
        }

        @Test("Fractional seconds are truncated via Int conversion")
        func fractionalSeconds() {
            // Int(90.7) == 90 → 1m 30s
            #expect(EvalComparisonLogic.formatDuration(90.7) == "1m 30s")
        }
    }

    // MARK: - totalPromptCount

    @Suite("totalPromptCount")
    struct TotalPromptCountTests {

        @Test("Returns zero for empty model results array")
        func emptyArray() {
            #expect(EvalComparisonLogic.totalPromptCount(from: []) == 0)
        }

        @Test("Single model returns its prompt count")
        func singleModel() {
            let model = makeModelResult(promptResults: [
                makePromptResult(),
                makePromptResult(),
                makePromptResult(),
            ])
            #expect(EvalComparisonLogic.totalPromptCount(from: [model]) == 3)
        }

        @Test("Multiple models sums all prompt counts")
        func multipleModels() {
            let m1 = makeModelResult(promptResults: [
                makePromptResult(),
                makePromptResult(),
            ])
            let m2 = makeModelResult(promptResults: [
                makePromptResult(),
            ])
            let m3 = makeModelResult(promptResults: [
                makePromptResult(),
                makePromptResult(),
                makePromptResult(),
                makePromptResult(),
            ])
            #expect(EvalComparisonLogic.totalPromptCount(from: [m1, m2, m3]) == 7)
        }

        @Test("Model with zero prompts contributes zero")
        func modelWithNoPrompts() {
            let m1 = makeModelResult(promptResults: [makePromptResult()])
            let m2 = makeModelResult(promptResults: [])
            #expect(EvalComparisonLogic.totalPromptCount(from: [m1, m2]) == 1)
        }
    }
}
