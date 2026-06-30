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

/// Tests for `EvalRunner` state transitions, progress tracking, and error handling.
///
/// Uses `MockInstrumentedEngine` and a temporary `EvalStore` for isolation.
final class EvalRunnerTests: XCTestCase {

    private var mockEngine: MockInstrumentedEngine!
    private var evalStore: EvalStore!
    private var tempDir: URL!
    private var evalRunner: EvalRunner!

    @MainActor
    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("EvalRunnerTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        mockEngine = MockInstrumentedEngine()
        evalStore = EvalStore(storageDirectory: tempDir)
        evalRunner = EvalRunner(engine: mockEngine, store: evalStore)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - Initial State

    @MainActor
    func testInitialState() {
        XCTAssertEqual(evalRunner.state, .idle)
        XCTAssertNil(evalRunner.currentRun)
    }

    // MARK: - Reset

    @MainActor
    func testResetClearsState() {
        // Manually set some state to verify reset clears it
        evalRunner.currentModelIndex = 2
        evalRunner.currentPromptIndex = 5
        evalRunner.totalModels = 3
        evalRunner.totalPrompts = 10
        evalRunner.progressDescription = "Running..."

        evalRunner.reset()

        XCTAssertEqual(evalRunner.state, .idle)
        XCTAssertNil(evalRunner.currentRun)
        XCTAssertEqual(evalRunner.currentModelIndex, 0)
        XCTAssertEqual(evalRunner.currentPromptIndex, 0)
        XCTAssertEqual(evalRunner.totalModels, 0)
        XCTAssertEqual(evalRunner.totalPrompts, 0)
        XCTAssertEqual(evalRunner.progressDescription, "")
    }

    // MARK: - Run Validation

    @MainActor
    func testRunWithNoModelsThrows() async {
        let suite = EvalSuite(
            name: "Empty Models Test",
            description: "",
            category: .general,
            prompts: [EvalPrompt(prompt: "Test", expectedBehavior: .nonEmpty)]
        )
        let flags = RuntimeFlags(
            enableBenchmark: true,
            enableSpeculativeDecoding: nil,
            enableConversationConstrainedDecoding: false,
            visualTokenBudget: nil
        )

        do {
            _ = try await evalRunner.run(suite: suite, models: [], flags: flags, cacheDir: "/tmp")
            XCTFail("Expected EvalRunnerError.noModels to be thrown")
        } catch let error as EvalRunnerError {
            if case .noModels = error {
                // Expected
            } else {
                XCTFail("Expected .noModels, got: \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // MARK: - Cancel

    @MainActor
    func testCancelWhenIdle() {
        XCTAssertEqual(evalRunner.state, .idle)
        evalRunner.cancel()
        XCTAssertEqual(evalRunner.state, .idle)
    }

    // MARK: - Progress

    @MainActor
    func testOverallProgress_initial() {
        XCTAssertEqual(evalRunner.overallProgress, 0)
    }

    // MARK: - State Display Labels

    @MainActor
    func testStateDisplayLabels() {
        let states: [EvalRunnerState] = [
            .idle,
            .preparing,
            .running(modelIndex: 0, promptIndex: 0),
            .scoring,
            .complete,
            .failed("Test error"),
        ]

        for state in states {
            XCTAssertFalse(state.displayLabel.isEmpty, "\(state) should have a non-empty displayLabel")
        }
    }

    // MARK: - State isActive

    @MainActor
    func testStateIsActive() {
        // Active states
        XCTAssertTrue(EvalRunnerState.preparing.isActive)
        XCTAssertTrue(EvalRunnerState.running(modelIndex: 0, promptIndex: 0).isActive)
        XCTAssertTrue(EvalRunnerState.scoring.isActive)

        // Inactive states
        XCTAssertFalse(EvalRunnerState.idle.isActive)
        XCTAssertFalse(EvalRunnerState.complete.isActive)
        XCTAssertFalse(EvalRunnerState.failed("error").isActive)
    }

    // MARK: - Error Descriptions

    @MainActor
    func testEvalRunnerErrorDescriptions() {
        let errors: [EvalRunnerError] = [
            .noModels,
            .cancelled,
            .promptTimeout(UUID()),
            .engineInitFailed("GPU not available"),
        ]

        for error in errors {
            XCTAssertNotNil(error.errorDescription, "\(error) should have a non-nil errorDescription")
            XCTAssertFalse(error.errorDescription!.isEmpty, "\(error) should have a non-empty errorDescription")
        }
    }
}
