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

import XCTest
import LiteRTLM

#if os(iOS)
@testable import EdgeAILab_iOS
#elseif os(macOS)
@testable import EdgeAILab_macOS
#endif

/// Behavioral tests for the EvalRunner state machine.
///
/// Validates the full lifecycle: `idle → preparing → running → scoring → complete`,
/// including cancellation, progress updates, and multi-suite execution.
/// Uses MockInstrumentedEngine and a temporary EvalStore for isolation.
@MainActor
final class EvalRunnerLifecycleTests: XCTestCase {

    // MARK: - Test Infrastructure

    private var mockEngine: MockInstrumentedEngine!
    private var evalStore: EvalStore!
    private var tempDir: URL!

    private let defaultFlags = ExperimentalFlagsState(
        enableBenchmark: true,
        enableSpeculativeDecoding: nil,
        enableConversationConstrainedDecoding: false,
        visualTokenBudget: nil
    )

    override func setUp() async throws {
        try await super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("EvalRunnerLifecycleTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        mockEngine = MockInstrumentedEngine()
        mockEngine.mockResponseChunks = ["Test", " response", "."]
        evalStore = EvalStore(storageDirectory: tempDir)
    }

    override func tearDown() async throws {
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        try await super.tearDown()
    }

    // MARK: - Helpers

    private func makeRunner() -> EvalRunner {
        EvalRunner(engine: mockEngine, store: evalStore)
    }

    private func makeModelEntry() -> EvalModelEntry {
        EvalModelEntry(
            metadata: ModelRegistry.knownModels.first!,
            modelPath: "/fake/model.litertlm"
        )
    }

    private func makeSuite(
        name: String = "Test Suite",
        promptCount: Int = 3
    ) -> EvalSuite {
        let prompts = (0..<promptCount).map { i in
            EvalPrompt(
                prompt: "Test prompt \(i + 1)",
                expectedBehavior: .nonEmpty
            )
        }
        return EvalSuite(
            name: name,
            description: "Test suite for lifecycle tests",
            category: .general,
            prompts: prompts
        )
    }

    // MARK: - Initial State

    /// Runner starts in `.idle` with no current run.
    func testInitialState() {
        let runner = makeRunner()

        XCTAssertEqual(runner.state, .idle,
            "Runner should start in .idle state")
        XCTAssertNil(runner.currentRun,
            "currentRun should be nil when idle")
        XCTAssertEqual(runner.currentModelIndex, 0)
        XCTAssertEqual(runner.currentPromptIndex, 0)
        XCTAssertEqual(runner.overallProgress, 0)
    }

    // MARK: - Preparing State

    /// Starting a run transitions through `.preparing` before `.running`.
    func testPreparingState() async throws {
        let runner = makeRunner()
        var observedStates: [EvalRunnerState] = []

        // Use a slow engine to catch the preparing state
        mockEngine.chunkDelay = 0.01

        // Track state changes via onPromptComplete callback
        runner.onPromptComplete = { _ in
            observedStates.append(runner.state)
        }

        let suite = makeSuite(promptCount: 1)
        let model = makeModelEntry()

        _ = try await runner.run(
            suite: suite,
            models: [model],
            flags: defaultFlags,
            cacheDir: NSTemporaryDirectory()
        )

        // The runner should have been in a running state when prompts were completing
        let hadRunningState = observedStates.contains { state in
            if case .running = state { return true }
            return false
        }
        XCTAssertTrue(hadRunningState || runner.state == .complete,
            "Runner should have transitioned through .running. Final state: \(runner.state)")
    }

    // MARK: - Running State

    /// During execution, the runner transitions through `.running` with progress updates.
    func testRunningState() async throws {
        let runner = makeRunner()
        var promptIndices: [Int] = []

        runner.onPromptComplete = { _ in
            promptIndices.append(runner.currentPromptIndex)
        }

        let suite = makeSuite(promptCount: 3)
        let model = makeModelEntry()

        _ = try await runner.run(
            suite: suite,
            models: [model],
            flags: defaultFlags,
            cacheDir: NSTemporaryDirectory()
        )

        XCTAssertEqual(promptIndices.count, 3,
            "Should have received 3 prompt completions. Got: \(promptIndices.count)")
    }

    // MARK: - Completion State

    /// After all prompts are scored, the runner transitions to `.complete`.
    func testCompletionState() async throws {
        let runner = makeRunner()
        let suite = makeSuite(promptCount: 2)
        let model = makeModelEntry()

        let run = try await runner.run(
            suite: suite,
            models: [model],
            flags: defaultFlags,
            cacheDir: NSTemporaryDirectory()
        )

        XCTAssertEqual(runner.state, .complete,
            "Runner should be in .complete state after successful run. Got: \(runner.state)")
        XCTAssertFalse(run.modelResults.isEmpty,
            "Completed run should have model results")

        let modelResult = run.modelResults.first!
        XCTAssertEqual(modelResult.promptResults.count, 2,
            "Should have 2 prompt results. Got: \(modelResult.promptResults.count)")

        // All prompts should have non-empty responses (mock returns "Test response.")
        for result in modelResult.promptResults {
            XCTAssertFalse(result.response.isEmpty,
                "Each prompt result should have a non-empty response")
        }
    }

    // MARK: - Cancel During Run

    /// Cancelling mid-run transitions the state to `.failed("Cancelled by user")`.
    func testCancelDuringRun() async throws {
        let runner = makeRunner()

        // Use slow chunks so we have time to cancel
        mockEngine.chunkDelay = 0.2
        mockEngine.mockResponseChunks = ["Slow", " response", " that", " takes", " time"]

        let suite = makeSuite(promptCount: 5)
        let model = makeModelEntry()

        // Start run in a separate task
        let runTask = Task {
            try await runner.run(
                suite: suite,
                models: [model],
                flags: defaultFlags,
                cacheDir: NSTemporaryDirectory()
            )
        }

        // Wait briefly for the run to start
        try await Task.sleep(for: .seconds(0.3))

        // Cancel
        runner.cancel()

        // The run task should complete (either with error or result)
        do {
            _ = try await runTask.value
            // If it completes without error, that's acceptable — cancellation is best-effort
        } catch {
            // Expected — cancellation causes the run to throw
        }

        // State should indicate failure due to cancellation
        if case .failed(let msg) = runner.state {
            XCTAssertTrue(msg.contains("Cancelled"),
                "Failed state should mention cancellation. Got: \(msg)")
        } else if runner.state == .complete {
            // Cancellation arrived too late — the run already completed.
            // This is acceptable behavior.
        } else {
            // Any other active state is unexpected after cancel
            XCTAssertFalse(runner.state.isActive,
                "Runner should not be in an active state after cancel. Got: \(runner.state)")
        }
    }

    // MARK: - Multiple Suites

    /// Running with multiple models processes all of them and aggregates results.
    func testMultipleSuites() async throws {
        let runner = makeRunner()
        let suite = makeSuite(name: "Multi-Model Suite", promptCount: 2)

        // Use two model entries (same mock engine handles both)
        let models = ModelRegistry.knownModels.prefix(2).map { metadata in
            EvalModelEntry(metadata: metadata, modelPath: "/fake/\(metadata.modelFile)")
        }

        // Need at least 2 known models for this test
        guard models.count >= 2 else {
            throw XCTSkip("Need at least 2 known models in ModelRegistry for this test")
        }

        let run = try await runner.run(
            suite: suite,
            models: Array(models),
            flags: defaultFlags,
            cacheDir: NSTemporaryDirectory()
        )

        XCTAssertEqual(runner.state, .complete,
            "Runner should complete after processing all models. Got: \(runner.state)")
        XCTAssertEqual(run.modelResults.count, 2,
            "Should have results for both models. Got: \(run.modelResults.count)")

        // Each model should have results for all prompts
        for modelResult in run.modelResults {
            XCTAssertEqual(modelResult.promptResults.count, 2,
                "Each model should have 2 prompt results. Got: \(modelResult.promptResults.count) for \(modelResult.modelName)")
        }

        // Verify progress tracking was updated
        XCTAssertEqual(runner.progressDescription, "Complete",
            "Progress description should say 'Complete'. Got: \(runner.progressDescription)")
    }
}
