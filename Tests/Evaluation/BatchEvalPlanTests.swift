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

// MARK: - Helpers

/// Creates a minimal EvalSuite with the specified number of prompts.
private func makeSuiteForPlan(name: String = "Test Suite", promptCount: Int = 5) -> EvalSuite {
    let prompts = (0..<promptCount).map { i in
        EvalPrompt(
            prompt: "Prompt \(i)",
            expectedBehavior: .containsText("test")
        )
    }
    return EvalSuite(
        name: name,
        description: "Test suite",
        category: .general,
        prompts: prompts
    )
}

/// Creates a minimal EvalModelEntry.
private func makeModelEntryForPlan(name: String = "Test Model") -> EvalModelEntry {
    let profile = ModelCapabilityProfile(
        id: "\(name).litertlm",
        displayName: name,
        repoId: nil,
        runtimeType: .litertlm,
        supportsVision: nil, supportsAudio: nil, supportsThinking: nil,
        supportsToolCalling: nil, supportsMTP: nil, supportsConstrainedDecoding: nil,
        architecture: nil, contextWindow: nil, fileSizeBytes: nil,
        estimatedMemoryGB: nil, totalParameters: nil, parameterLabel: nil,
        confidence: .low, source: .huggingFaceInferred, lastUpdated: Date(),
        repoSha: nil, license: nil, licenseLink: nil, baseModelId: nil,
        downloads: nil, likes: nil, downloadsAllTime: nil,
        supportedLanguages: [], tags: [],
        defaultConfig: ModelDefaultConfig(
            topK: 64,
            topP: 0.95,
            temperature: 1.0,
            maxContextLength: 32_000,
            maxTokens: 4_000,
            accelerators: "gpu,cpu",
            visionAccelerator: nil
        ),
        platformSupport: PlatformSupport(
            macOS: .gpuAndCpu,
            iOSDevice: .gpuAndCpu,
            iOSSimulator: .cpuOnly
        ),
        modelDescription: nil, recommendedFor: nil,
        modelFile: "\(name).litertlm",
        modelId: "test-org/\(name)-it-litert-lm"
    )
    return EvalModelEntry(profile: profile, modelPath: "/tmp/\(name).litertlm")
}

// MARK: - BatchEvalPlan Computed Property Tests

@Suite("BatchEvalPlan — Computed Properties")
struct BatchEvalPlanComputedTests {

    @Test("totalSuites returns suite count")
    func totalSuites() {
        let plan = BatchEvalPlan(
            suites: [makeSuiteForPlan(name: "A"), makeSuiteForPlan(name: "B")],
            models: [makeModelEntryForPlan()]
        )
        #expect(plan.totalSuites == 2)
    }

    @Test("totalModels returns model count")
    func totalModels() {
        let plan = BatchEvalPlan(
            suites: [makeSuiteForPlan()],
            models: [makeModelEntryForPlan(name: "A"), makeModelEntryForPlan(name: "B"), makeModelEntryForPlan(name: "C")]
        )
        #expect(plan.totalModels == 3)
    }

    @Test("totalRuns is suites × models")
    func totalRuns() {
        let plan = BatchEvalPlan(
            suites: [makeSuiteForPlan(), makeSuiteForPlan()],
            models: [makeModelEntryForPlan(), makeModelEntryForPlan(), makeModelEntryForPlan()]
        )
        #expect(plan.totalRuns == 6)
    }

    @Test("totalPrompts counts all prompts × models")
    func totalPrompts() {
        let plan = BatchEvalPlan(
            suites: [makeSuiteForPlan(promptCount: 5), makeSuiteForPlan(promptCount: 5)],
            models: [makeModelEntryForPlan(), makeModelEntryForPlan(), makeModelEntryForPlan()]
        )
        #expect(plan.totalPrompts == 30)
    }

    @Test("estimatedDurationSeconds uses 30s per prompt")
    func estimatedDuration() {
        let plan = BatchEvalPlan(
            suites: [makeSuiteForPlan(promptCount: 2)],
            models: [makeModelEntryForPlan()]
        )
        #expect(plan.estimatedDurationSeconds == 60.0)
    }

    @Test("estimatedDurationFormatted shows seconds for short durations")
    func formatSeconds() {
        let plan = BatchEvalPlan(
            suites: [makeSuiteForPlan(promptCount: 1)],
            models: [makeModelEntryForPlan()]
        )
        #expect(plan.estimatedDurationFormatted == "30s")
    }

    @Test("estimatedDurationFormatted shows minutes for medium durations")
    func formatMinutes() {
        let plan = BatchEvalPlan(
            suites: [makeSuiteForPlan(promptCount: 4)],
            models: [makeModelEntryForPlan()]
        )
        #expect(plan.estimatedDurationFormatted == "2 min")
    }

    @Test("estimatedDurationFormatted shows hours for long durations")
    func formatHours() {
        let plan = BatchEvalPlan(
            suites: [makeSuiteForPlan(promptCount: 60)],
            models: [makeModelEntryForPlan(), makeModelEntryForPlan()]
        )
        #expect(plan.estimatedDurationFormatted == "1h 0m")
    }

    @Test("description combines all elements")
    func descriptionContent() {
        let plan = BatchEvalPlan(
            suites: [makeSuiteForPlan(promptCount: 3)],
            models: [makeModelEntryForPlan(), makeModelEntryForPlan()]
        )
        let desc = plan.description
        #expect(desc.contains("1 suite"))
        #expect(desc.contains("2 models"))
        #expect(desc.contains("6 prompts"))
    }

    @Test("description uses singular for single suite and model")
    func singularDescription() {
        let plan = BatchEvalPlan(
            suites: [makeSuiteForPlan()],
            models: [makeModelEntryForPlan()]
        )
        #expect(plan.description.contains("1 suite"))
        #expect(plan.description.contains("1 model"))
    }

    @Test("Empty plan has zero totals")
    func emptyPlan() {
        let plan = BatchEvalPlan(suites: [], models: [])
        #expect(plan.totalSuites == 0)
        #expect(plan.totalModels == 0)
        #expect(plan.totalRuns == 0)
        #expect(plan.totalPrompts == 0)
        #expect(plan.estimatedDurationSeconds == 0.0)
        #expect(plan.estimatedDurationFormatted == "0s")
    }
}

// MARK: - BatchEvalState Display Tests

@Suite("BatchEvalState — Display & Equatable")
struct BatchEvalStateDisplayTests {

    @Test("idle is not active and shows Ready")
    func idle() {
        #expect(BatchEvalState.idle.isActive == false)
        #expect(BatchEvalState.idle.displayLabel == "Ready")
    }

    @Test("running is active and shows suite info")
    func running() {
        let state = BatchEvalState.running(suiteIndex: 2, suiteName: "Math")
        #expect(state.isActive == true)
        let label = state.displayLabel
        #expect(label.contains("3"))
        #expect(label.contains("Math"))
    }

    @Test("complete is not active, singular label")
    func completeSingular() {
        let state = BatchEvalState.complete(runsCompleted: 1)
        #expect(state.isActive == false)
        #expect(state.displayLabel.contains("1 run finished"))
    }

    @Test("complete plural label")
    func completePlural() {
        #expect(BatchEvalState.complete(runsCompleted: 5).displayLabel.contains("5 runs finished"))
    }

    @Test("cancelled includes count")
    func cancelled() {
        let state = BatchEvalState.cancelled(runsCompleted: 2)
        #expect(state.isActive == false)
        let label = state.displayLabel
        #expect(label.contains("Cancelled"))
        #expect(label.contains("2 runs finished"))
    }

    @Test("failed includes error message")
    func failed() {
        let state = BatchEvalState.failed("Out of memory")
        #expect(state.isActive == false)
        #expect(state.displayLabel.contains("Out of memory"))
    }

    @Test("Equatable works correctly")
    func equatable() {
        #expect(BatchEvalState.idle == BatchEvalState.idle)
        #expect(BatchEvalState.idle != BatchEvalState.complete(runsCompleted: 0))
        let a = BatchEvalState.running(suiteIndex: 1, suiteName: "Test")
        let b = BatchEvalState.running(suiteIndex: 1, suiteName: "Test")
        #expect(a == b)
    }
}
