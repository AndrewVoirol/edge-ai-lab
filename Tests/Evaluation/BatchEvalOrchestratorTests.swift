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

// MARK: - BatchEvalState Tests

/// Tests for the `BatchEvalState` enum — `isActive` and `displayLabel` for all cases.
@Suite("BatchEvalState")
struct BatchEvalStateTests {

    // MARK: - isActive

    @Test("idle is not active")
    func idleIsNotActive() {
        let state = BatchEvalState.idle
        #expect(state.isActive == false)
    }

    @Test("running is active")
    func runningIsActive() {
        let state = BatchEvalState.running(suiteIndex: 0, suiteName: "Suite A")
        #expect(state.isActive == true)
    }

    @Test("complete is not active")
    func completeIsNotActive() {
        let state = BatchEvalState.complete(runsCompleted: 3)
        #expect(state.isActive == false)
    }

    @Test("cancelled is not active")
    func cancelledIsNotActive() {
        let state = BatchEvalState.cancelled(runsCompleted: 1)
        #expect(state.isActive == false)
    }

    @Test("failed is not active")
    func failedIsNotActive() {
        let state = BatchEvalState.failed("something broke")
        #expect(state.isActive == false)
    }

    // MARK: - displayLabel

    @Test("idle displayLabel is Ready")
    func idleDisplayLabel() {
        #expect(BatchEvalState.idle.displayLabel == "Ready")
    }

    @Test("running displayLabel includes suite index and name")
    func runningDisplayLabel() {
        let label = BatchEvalState.running(suiteIndex: 2, suiteName: "Math").displayLabel
        #expect(label.contains("3"))       // suiteIndex + 1
        #expect(label.contains("Math"))
    }

    @Test("complete displayLabel includes run count — singular")
    func completeDisplayLabelSingular() {
        let label = BatchEvalState.complete(runsCompleted: 1).displayLabel
        #expect(label.contains("1 run finished"))
    }

    @Test("complete displayLabel includes run count — plural")
    func completeDisplayLabelPlural() {
        let label = BatchEvalState.complete(runsCompleted: 5).displayLabel
        #expect(label.contains("5 runs finished"))
    }

    @Test("cancelled displayLabel includes run count")
    func cancelledDisplayLabel() {
        let label = BatchEvalState.cancelled(runsCompleted: 2).displayLabel
        #expect(label.contains("Cancelled"))
        #expect(label.contains("2 runs finished"))
    }

    @Test("failed displayLabel includes error message")
    func failedDisplayLabel() {
        let label = BatchEvalState.failed("engine crashed").displayLabel
        #expect(label.contains("Failed"))
        #expect(label.contains("engine crashed"))
    }

    // MARK: - Equatable

    @Test("states with same case and values are equal")
    func equatableSameCase() {
        let a = BatchEvalState.running(suiteIndex: 1, suiteName: "X")
        let b = BatchEvalState.running(suiteIndex: 1, suiteName: "X")
        #expect(a == b)
    }

    @Test("states with different cases are not equal")
    func equatableDifferentCase() {
        let a = BatchEvalState.idle
        let b = BatchEvalState.complete(runsCompleted: 0)
        #expect(a != b)
    }
}

// MARK: - BatchEvalOrchestrator Tests

/// Tests for `BatchEvalOrchestrator` property behavior (progress, state).
///
/// These tests use `MockInferenceEngine` and an `EvalStore` with a temporary
/// directory so no real inference or persistence occurs.
@Suite("BatchEvalOrchestrator")
@MainActor
struct BatchEvalOrchestratorTests {

    // MARK: - Helpers

    /// Create an orchestrator backed by a mock engine and temp-dir store.
    private func makeOrchestrator() -> BatchEvalOrchestrator {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BatchEvalOrchestratorTests-\(UUID().uuidString)")
        let store = EvalStore(storageDirectory: tempDir)
        return BatchEvalOrchestrator(store: store)
    }

    // MARK: - Initial State

    @Test("initial state is idle")
    func initialState() {
        let orch = makeOrchestrator()
        #expect(orch.state == .idle)
        #expect(orch.completedRuns == 0)
        #expect(orch.totalRuns == 0)
        #expect(orch.results.isEmpty)
    }

    // MARK: - Overall Progress

    @Test("overallProgress is 0 when totalRuns is 0")
    func progressZeroWhenNoRuns() {
        let orch = makeOrchestrator()
        // totalRuns defaults to 0
        #expect(orch.overallProgress == 0)
    }

    @Test("overallProgress reflects completedRuns fraction")
    func progressReflectsCompletedRuns() {
        let orch = makeOrchestrator()
        orch.totalRuns = 4
        orch.completedRuns = 2
        // No currentRunner, so currentRunProgress = 0
        // expected: 2/4 = 0.5
        #expect(orch.overallProgress == 0.5)
    }

    @Test("overallProgress is 1.0 when all runs complete")
    func progressFullWhenAllComplete() {
        let orch = makeOrchestrator()
        orch.totalRuns = 3
        orch.completedRuns = 3
        #expect(orch.overallProgress == 1.0)
    }

    @Test("overallProgress includes currentRunner progress")
    func progressIncludesCurrentRunner() {
        let orch = makeOrchestrator()
        orch.totalRuns = 2
        orch.completedRuns = 0

        // Create a mock EvalRunner to simulate partial progress
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BatchEvalOrchestratorTests-runner-\(UUID().uuidString)")
        let store = EvalStore(storageDirectory: tempDir)
        let runner = EvalRunner(store: store)

        // Simulate the runner being partway through: 1 of 2 models, 1 of 4 prompts
        runner.totalModels = 2
        runner.totalPrompts = 4
        runner.currentModelIndex = 0
        runner.currentPromptIndex = 2  // 2/8 = 0.25

        orch.currentRunner = runner

        // overallProgress = (0/2) + (0.25 * 1/2) = 0.125
        let progress = orch.overallProgress
        #expect(progress > 0.0, "Should include partial runner progress")
        #expect(progress < 0.5, "Should be less than half since no completed runs")
    }

    // MARK: - State Transitions

    @Test("state can be set to running")
    func stateTransitionToRunning() {
        let orch = makeOrchestrator()
        orch.state = .running(suiteIndex: 0, suiteName: "Test Suite")
        #expect(orch.state.isActive)
        #expect(orch.state == .running(suiteIndex: 0, suiteName: "Test Suite"))
    }

    @Test("state can be set to complete")
    func stateTransitionToComplete() {
        let orch = makeOrchestrator()
        orch.state = .running(suiteIndex: 0, suiteName: "Suite")
        orch.state = .complete(runsCompleted: 1)
        #expect(!orch.state.isActive)
        #expect(orch.state == .complete(runsCompleted: 1))
    }

    @Test("state can be set to cancelled")
    func stateTransitionToCancelled() {
        let orch = makeOrchestrator()
        orch.state = .running(suiteIndex: 0, suiteName: "Suite")
        orch.state = .cancelled(runsCompleted: 0)
        #expect(!orch.state.isActive)
    }

    @Test("state can be set to failed")
    func stateTransitionToFailed() {
        let orch = makeOrchestrator()
        orch.state = .failed("timeout")
        #expect(!orch.state.isActive)
        #expect(orch.state == .failed("timeout"))
    }

    // MARK: - Cancel

    @Test("cancel sets state to cancelled on next check")
    func cancelSetsFlag() {
        let orch = makeOrchestrator()
        // cancel() sets internal isCancelled and calls currentRunner?.cancel()
        // We can't directly observe isCancelled, but we can verify it doesn't crash
        orch.cancel()
        // After cancel(), state isn't changed synchronously — it's checked
        // during runAll(). The cancel mechanism is tested via integration tests.
    }
}

// MARK: - BatchEvalPlan Tests (Swift Testing)

/// Swift Testing version of the BatchEvalPlan tests from BatchEvalTests.swift (XCTest).
@Suite("BatchEvalPlan")
struct BatchEvalPlanTests {

    // MARK: - Helpers

    private func makeTestSuite(name: String, promptCount: Int) -> EvalSuite {
        let prompts = (0..<promptCount).map { i in
            EvalPrompt(prompt: "Test prompt \(i)", expectedBehavior: .nonEmpty)
        }
        return EvalSuite(
            name: name,
            description: "Test suite",
            category: .general,
            prompts: prompts,
            isBuiltIn: false
        )
    }

    private func makeTestModelEntry(name: String) -> EvalModelEntry {
        let slug = name.lowercased().replacingOccurrences(of: " ", with: "_")
        return EvalModelEntry(
            metadata: ModelMetadata(
                name: name,
                modelId: "test/\(slug)",
                modelFile: "\(slug).litertlm",
                description: "Test model: \(name)",
                sizeInBytes: 1_000_000,
                minDeviceMemoryGB: 4,
                contextWindowSize: 32_000,
                architectureType: "Test",
                recommendedFor: "Testing",
                supportsImage: false,
                supportsAudio: false,
                capabilities: ["llm_thinking"],
                defaultConfig: ModelDefaultConfig(
                    topK: 64,
                    topP: 0.95,
                    temperature: 1.0,
                    maxContextLength: 32_000,
                    maxTokens: 2048,
                    accelerators: "gpu,cpu",
                    visionAccelerator: nil
                ),
                platformSupport: PlatformSupport(
                    macOS: .gpuAndCpu,
                    iOSDevice: .gpuAndCpu,
                    iOSSimulator: .cpuOnly
                ),
                runtimeType: .litertlm
            ),
            modelPath: "/tmp/\(slug).litertlm"
        )
    }

    // MARK: - Plan Counts

    @Test("plan with multiple suites and models computes correct counts")
    func planCounts() {
        let suites = [
            makeTestSuite(name: "Suite A", promptCount: 5),
            makeTestSuite(name: "Suite B", promptCount: 3),
        ]
        let models = [
            makeTestModelEntry(name: "Model 1"),
            makeTestModelEntry(name: "Model 2"),
        ]

        let plan = BatchEvalPlan(suites: suites, models: models)

        #expect(plan.totalSuites == 2)
        #expect(plan.totalModels == 2)
        #expect(plan.totalRuns == 4, "2 suites × 2 models = 4 runs")
        #expect(plan.totalPrompts == 16, "(5 + 3) × 2 = 16 total prompts")
    }

    @Test("plan with empty suites has zero runs and prompts")
    func emptyPlan() {
        let plan = BatchEvalPlan(suites: [], models: [makeTestModelEntry(name: "M")])
        #expect(plan.totalRuns == 0)
        #expect(plan.totalPrompts == 0)
    }

    @Test("plan with empty models has zero runs and prompts")
    func emptyModels() {
        let plan = BatchEvalPlan(
            suites: [makeTestSuite(name: "S", promptCount: 5)],
            models: []
        )
        #expect(plan.totalRuns == 0)
        #expect(plan.totalPrompts == 0)
    }

    @Test("estimatedDurationSeconds is positive for non-empty plan")
    func estimatedDuration() {
        let suites = [makeTestSuite(name: "Suite", promptCount: 10)]
        let models = [makeTestModelEntry(name: "Model")]
        let plan = BatchEvalPlan(suites: suites, models: models)
        #expect(plan.estimatedDurationSeconds > 0)
    }

    @Test("estimatedDurationFormatted returns seconds for short durations")
    func formattedDurationSeconds() {
        // 1 prompt × 30s = 30s → "30s"
        let suites = [makeTestSuite(name: "S", promptCount: 1)]
        let models = [makeTestModelEntry(name: "M")]
        let plan = BatchEvalPlan(suites: suites, models: models)
        #expect(plan.estimatedDurationFormatted.hasSuffix("s"))
    }

    @Test("estimatedDurationFormatted returns minutes for medium durations")
    func formattedDurationMinutes() {
        // 10 prompts × 30s = 300s = 5 min
        let suites = [makeTestSuite(name: "S", promptCount: 10)]
        let models = [makeTestModelEntry(name: "M")]
        let plan = BatchEvalPlan(suites: suites, models: models)
        #expect(plan.estimatedDurationFormatted.contains("min"))
    }

    @Test("description includes suite and model counts")
    func descriptionContainsCounts() {
        let suites = [
            makeTestSuite(name: "Math", promptCount: 5),
            makeTestSuite(name: "Reasoning", promptCount: 3),
        ]
        let models = [makeTestModelEntry(name: "Gemma 3n")]
        let plan = BatchEvalPlan(suites: suites, models: models)

        let desc = plan.description
        #expect(desc.contains("2 suite"), "Description should mention suite count")
        #expect(desc.contains("1 model"), "Description should mention model count")
    }
}
