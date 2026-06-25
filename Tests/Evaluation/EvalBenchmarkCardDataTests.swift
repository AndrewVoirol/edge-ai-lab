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

@Suite("EvalBenchmarkCardData")
struct EvalBenchmarkCardDataTests {

    // MARK: - Helpers

    private func makePromptResult(passed: Bool, decodeSpeed: Double? = nil) -> PromptEvalResult {
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

    private func makeModelResult(
        modelName: String = "Test Model",
        avgDecodeSpeed: Double = 42.5,
        avgTTFT: Double = 0.87
    ) -> ModelEvalResult {
        let prompts = [
            makePromptResult(passed: true, decodeSpeed: avgDecodeSpeed),
            makePromptResult(passed: false, decodeSpeed: avgDecodeSpeed),
        ]
        return ModelEvalResult(
            modelName: modelName,
            modelFile: "test.litertlm",
            avgDecodeSpeed: avgDecodeSpeed,
            avgTTFT: avgTTFT,
            p95Latency: 25.0,
            totalTokensGenerated: 200,
            totalDuration: 10.0,
            promptResults: prompts
        )
    }

    private func makeEvalRun(
        suiteName: String = "Test Suite",
        category: EvalCategory = .math,
        modelResults: [ModelEvalResult] = []
    ) -> EvalRun {
        EvalRun(
            suiteId: UUID(),
            suiteName: suiteName,
            suiteCategory: category,
            startedAt: Date(timeIntervalSince1970: 1_000_000),
            platform: "macOS",
            deviceName: "Test Mac",
            modelResults: modelResults
        )
    }

    // MARK: - from(_:) Tests

    @Test("Transfers suiteName from EvalRun")
    func suiteName() {
        let run = makeEvalRun(suiteName: "Math Accuracy")
        let data = EvalBenchmarkCardData.from(run)
        #expect(data.suiteName == "Math Accuracy")
    }

    @Test("Transfers category from EvalRun")
    func category() {
        let run = makeEvalRun(category: .reasoning)
        let data = EvalBenchmarkCardData.from(run)
        #expect(data.category == .reasoning)
    }

    @Test("Transfers platform from EvalRun")
    func platform() {
        let run = makeEvalRun()
        let data = EvalBenchmarkCardData.from(run)
        #expect(data.platform == "macOS")
    }

    @Test("Transfers deviceName from EvalRun")
    func deviceName() {
        let run = makeEvalRun()
        let data = EvalBenchmarkCardData.from(run)
        #expect(data.deviceName == "Test Mac")
    }

    @Test("Transfers startedAt as date")
    func date() {
        let run = makeEvalRun()
        let data = EvalBenchmarkCardData.from(run)
        #expect(data.date == run.startedAt)
    }

    @Test("Creates model summaries from modelResults")
    func modelSummaries() {
        let model1 = makeModelResult(modelName: "Gemma E2B", avgDecodeSpeed: 42.5, avgTTFT: 0.87)
        let model2 = makeModelResult(modelName: "Gemma E4B", avgDecodeSpeed: 28.1, avgTTFT: 1.23)
        let run = makeEvalRun(modelResults: [model1, model2])
        let data = EvalBenchmarkCardData.from(run)
        #expect(data.modelSummaries.count == 2)
        #expect(data.modelSummaries[0].modelName == "Gemma E2B")
        #expect(data.modelSummaries[1].modelName == "Gemma E4B")
    }

    @Test("Handles empty modelResults")
    func emptyResults() {
        let run = makeEvalRun(modelResults: [])
        let data = EvalBenchmarkCardData.from(run)
        #expect(data.modelSummaries.isEmpty)
        #expect(data.overallPassRate == 0.0)
    }

    @Test("ModelSummary has unique identifiers")
    func uniqueIds() {
        let model = makeModelResult()
        let run = makeEvalRun(modelResults: [model, makeModelResult(modelName: "Other")])
        let data = EvalBenchmarkCardData.from(run)
        let ids = data.modelSummaries.map(\.id)
        #expect(Set(ids).count == 2)
    }

    @Test("Model summary captures avgDecodeSpeed and avgTTFT")
    func summaryMetrics() {
        let model = makeModelResult(avgDecodeSpeed: 42.5, avgTTFT: 0.87)
        let run = makeEvalRun(modelResults: [model])
        let data = EvalBenchmarkCardData.from(run)
        #expect(data.modelSummaries[0].avgDecodeSpeed == 42.5)
        #expect(data.modelSummaries[0].avgTTFT == 0.87)
    }
}
