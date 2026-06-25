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

// MARK: - Test Helpers

/// Creates a minimal PromptEvalResult for testing.
private func makePromptResult(
    passed: Bool,
    decodeSpeed: Double? = nil
) -> PromptEvalResult {
    PromptEvalResult(
        promptId: UUID(),
        promptText: "test prompt",
        response: "test response",
        passed: passed,
        score: passed ? .pass : .fail(reason: "test"),
        decodeSpeed: decodeSpeed,
        ttft: nil,
        duration: 1.0
    )
}

/// Creates a ModelEvalResult with the given prompt results.
private func makeModelResult(
    modelName: String = "Test Model",
    prompts: [PromptEvalResult]
) -> ModelEvalResult {
    let avgSpeed = prompts.compactMap(\.decodeSpeed).isEmpty ? 0.0 :
        prompts.compactMap(\.decodeSpeed).reduce(0, +) / Double(prompts.compactMap(\.decodeSpeed).count)
    return ModelEvalResult(
        modelName: modelName,
        modelFile: "test.litertlm",
        avgDecodeSpeed: avgSpeed,
        avgTTFT: 0.5,
        p95Latency: 25.0,
        totalTokensGenerated: 100,
        totalDuration: 10.0,
        promptResults: prompts
    )
}

// MARK: - Tests

@Suite("EvalComparisonLogic — Expanded")
struct EvalComparisonLogicExpandedTests {

    // MARK: - ResultFilter

    @Suite("ResultFilter enum")
    struct ResultFilterTests {
        @Test("All cases are present")
        func allCases() {
            let cases = EvalComparisonLogic.ResultFilter.allCases
            #expect(cases.count == 3)
            #expect(cases.contains(.all))
            #expect(cases.contains(.passed))
            #expect(cases.contains(.failed))
        }

        @Test("Raw values match display labels")
        func rawValues() {
            #expect(EvalComparisonLogic.ResultFilter.all.rawValue == "All")
            #expect(EvalComparisonLogic.ResultFilter.passed.rawValue == "Passed")
            #expect(EvalComparisonLogic.ResultFilter.failed.rawValue == "Failed")
        }

        @Test("Identifiable uses rawValue")
        func identifiable() {
            let filter = EvalComparisonLogic.ResultFilter.passed
            #expect(filter.id == "Passed")
        }
    }

    // MARK: - filteredPromptResults

    @Suite("filteredPromptResults")
    struct FilteredPromptResultsTests {
        @Test("Returns empty for nil model")
        func nilModel() {
            let result = EvalComparisonLogic.filteredPromptResults(from: nil, filter: .all)
            #expect(result.isEmpty)
        }

        @Test("All filter returns all prompts")
        func allFilter() {
            let model = makeModelResult(prompts: [
                makePromptResult(passed: true),
                makePromptResult(passed: false),
                makePromptResult(passed: true),
            ])
            let result = EvalComparisonLogic.filteredPromptResults(from: model, filter: .all)
            #expect(result.count == 3)
        }

        @Test("Passed filter returns only passed")
        func passedFilter() {
            let model = makeModelResult(prompts: [
                makePromptResult(passed: true),
                makePromptResult(passed: false),
                makePromptResult(passed: true),
            ])
            let result = EvalComparisonLogic.filteredPromptResults(from: model, filter: .passed)
            #expect(result.count == 2)
        }

        @Test("Failed filter returns only failed")
        func failedFilter() {
            let model = makeModelResult(prompts: [
                makePromptResult(passed: true),
                makePromptResult(passed: false),
            ])
            let result = EvalComparisonLogic.filteredPromptResults(from: model, filter: .failed)
            #expect(result.count == 1)
        }

        @Test("Empty prompts returns empty for all filters")
        func emptyPrompts() {
            let model = makeModelResult(prompts: [])
            #expect(EvalComparisonLogic.filteredPromptResults(from: model, filter: .all).isEmpty)
            #expect(EvalComparisonLogic.filteredPromptResults(from: model, filter: .passed).isEmpty)
            #expect(EvalComparisonLogic.filteredPromptResults(from: model, filter: .failed).isEmpty)
        }
    }

    // MARK: - countForFilter

    @Suite("countForFilter")
    struct CountForFilterTests {
        @Test("Returns 0 for nil model")
        func nilModel() {
            #expect(EvalComparisonLogic.countForFilter(.all, in: nil) == 0)
            #expect(EvalComparisonLogic.countForFilter(.passed, in: nil) == 0)
            #expect(EvalComparisonLogic.countForFilter(.failed, in: nil) == 0)
        }

        @Test("Counts match filtered results")
        func countsMatch() {
            let model = makeModelResult(prompts: [
                makePromptResult(passed: true),
                makePromptResult(passed: false),
                makePromptResult(passed: true),
                makePromptResult(passed: false),
                makePromptResult(passed: true),
            ])
            #expect(EvalComparisonLogic.countForFilter(.all, in: model) == 5)
            #expect(EvalComparisonLogic.countForFilter(.passed, in: model) == 3)
            #expect(EvalComparisonLogic.countForFilter(.failed, in: model) == 2)
        }
    }

    // MARK: - activeModelResult

    @Suite("activeModelResult")
    struct ActiveModelResultTests {
        @Test("Returns model at valid index")
        func validIndex() {
            let models = [
                makeModelResult(modelName: "A", prompts: []),
                makeModelResult(modelName: "B", prompts: []),
            ]
            let result = EvalComparisonLogic.activeModelResult(at: 1, from: models)
            #expect(result?.modelName == "B")
        }

        @Test("Returns nil for out-of-bounds index")
        func outOfBounds() {
            let models = [makeModelResult(prompts: [])]
            #expect(EvalComparisonLogic.activeModelResult(at: 5, from: models) == nil)
        }

        @Test("Returns nil for empty array")
        func emptyArray() {
            #expect(EvalComparisonLogic.activeModelResult(at: 0, from: []) == nil)
        }
    }

    // MARK: - passRateLabel

    @Suite("passRateLabel")
    struct PassRateLabelTests {
        @Test("Formats 1.0 as 100%")
        func fullPass() {
            #expect(EvalComparisonLogic.passRateLabel(1.0) == "100%")
        }

        @Test("Formats 0.0 as 0%")
        func zeroPass() {
            #expect(EvalComparisonLogic.passRateLabel(0.0) == "0%")
        }

        @Test("Formats 0.875 as 88%")
        func partialPass() {
            #expect(EvalComparisonLogic.passRateLabel(0.875) == "88%")
        }

        @Test("Formats 0.333 as 33%")
        func thirdPass() {
            #expect(EvalComparisonLogic.passRateLabel(0.333) == "33%")
        }
    }

    // MARK: - speedLabel

    @Suite("speedLabel")
    struct SpeedLabelTests {
        @Test("Formats speed with one decimal")
        func oneDecimal() {
            #expect(EvalComparisonLogic.speedLabel(42.5) == "42.5 tok/s")
        }

        @Test("Formats zero speed")
        func zero() {
            #expect(EvalComparisonLogic.speedLabel(0.0) == "0.0 tok/s")
        }

        @Test("Formats large speed")
        func large() {
            #expect(EvalComparisonLogic.speedLabel(113.1) == "113.1 tok/s")
        }
    }

    // MARK: - ttftLabel

    @Suite("ttftLabel")
    struct TTFTLabelTests {
        @Test("Formats TTFT with two decimals")
        func twoDecimals() {
            #expect(EvalComparisonLogic.ttftLabel(0.87) == "0.87s")
        }

        @Test("Formats zero TTFT")
        func zero() {
            #expect(EvalComparisonLogic.ttftLabel(0.0) == "0.00s")
        }
    }

    // MARK: - exportFilename

    @Suite("exportFilename")
    struct ExportFilenameTests {
        @Test("Generates sanitized filename")
        func sanitized() {
            let id = UUID(uuidString: "12345678-ABCD-1234-ABCD-123456789ABC")!
            let name = EvalComparisonLogic.exportFilename(suiteName: "Math Accuracy", id: id)
            #expect(name == "eval_Math_Accuracy_12345678.json")
        }

        @Test("Handles no spaces")
        func noSpaces() {
            let id = UUID(uuidString: "ABCDEF12-3456-7890-ABCD-EF1234567890")!
            let name = EvalComparisonLogic.exportFilename(suiteName: "CodeGen", id: id)
            #expect(name == "eval_CodeGen_ABCDEF12.json")
        }
    }

    // MARK: - modelCountLabel

    @Suite("modelCountLabel")
    struct ModelCountLabelTests {
        @Test("Singular for 1")
        func singular() {
            #expect(EvalComparisonLogic.modelCountLabel(1) == "1 model")
        }

        @Test("Plural for 0")
        func zero() {
            #expect(EvalComparisonLogic.modelCountLabel(0) == "0 models")
        }

        @Test("Plural for many")
        func many() {
            #expect(EvalComparisonLogic.modelCountLabel(5) == "5 models")
        }
    }
}
