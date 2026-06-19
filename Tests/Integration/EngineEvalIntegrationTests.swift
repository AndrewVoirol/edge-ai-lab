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

// MARK: - Engine ↔ Eval Integration Tests

/// Validates the integration seam between the inference engine and evaluation runner.
///
/// These tests exercise `EvalRunner` with `MockInstrumentedEngine` to verify that:
/// - Normal engine responses flow through scoring correctly
/// - Engine errors (init failures, mid-stream errors) are handled gracefully
/// - Empty engine responses produce correct edge-case scoring
/// - Multiple prompts run sequentially through the same engine instance
///
/// ## Pattern
/// Uses Swift Testing (`@Suite`/`@Test`) per project conventions.
/// Each test creates its own `MockInstrumentedEngine`, a temporary `EvalStore`,
/// and an `EvalRunner` wired together. Since `EvalRunner` is `@MainActor`,
/// all test bodies run on MainActor.
@Suite("Engine ↔ Eval Integration")
struct EngineEvalIntegrationTests {

    // MARK: - Helpers

    /// Default flags for eval — benchmarks enabled, no speculative decoding.
    private static let defaultFlags = ExperimentalFlagsState(
        enableBenchmark: true,
        enableSpeculativeDecoding: nil,
        enableConversationConstrainedDecoding: false,
        visualTokenBudget: nil
    )

    /// Creates a minimal `ModelMetadata` suitable for integration tests.
    /// Uses the Gemma 4 E2B standard model shape with all multimodal support disabled.
    private static func testMetadata(
        name: String = "Test Model",
        modelFile: String = "test-model.litertlm",
        supportsImage: Bool = false,
        supportsAudio: Bool = false
    ) -> ModelMetadata {
        ModelMetadata(
            name: name,
            modelId: "test/test-model",
            modelFile: modelFile,
            description: "Test model for integration tests",
            sizeInBytes: 1_000_000,
            minDeviceMemoryGB: 4,
            contextWindowSize: 4_096,
            architectureType: "Test",
            recommendedFor: "Integration testing",
            supportsImage: supportsImage,
            supportsAudio: supportsAudio,
            capabilities: [],
            defaultConfig: ModelDefaultConfig(
                topK: 1,
                topP: 1.0,
                temperature: 1.0,
                maxContextLength: 4_096,
                maxTokens: 256,
                accelerators: "cpu",
                visionAccelerator: nil
            ),
            platformSupport: PlatformSupport(
                macOS: .cpuOnly,
                iOSDevice: .cpuOnly,
                iOSSimulator: .cpuOnly
            )
        )
    }

    /// Creates a single-model entry list for eval runner.
    private static func singleModelEntry(
        metadata: ModelMetadata? = nil
    ) -> [EvalModelEntry] {
        let md = metadata ?? testMetadata()
        return [EvalModelEntry(metadata: md, modelPath: "/tmp/test-model.litertlm")]
    }

    /// Creates a temporary `EvalStore` backed by a unique temp directory.
    /// The directory is cleaned up automatically when the process exits.
    @MainActor
    private static func makeTempStore() -> EvalStore {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("EngineEvalIntegrationTests-\(UUID().uuidString)")
        return EvalStore(storageDirectory: tempDir)
    }

    // MARK: - 1. Happy Path: Normal Responses → Correct Scoring

    @Test("Engine returns matching text → EvalRunner scores as pass")
    @MainActor
    func testHappyPathContainsTextPass() async throws {
        let engine = MockInstrumentedEngine.happyPath()
        // "Hello, world!" contains "world"
        engine.mockResponseChunks = ["The answer is ", "4", "."]

        let store = Self.makeTempStore()
        let runner = EvalRunner(engine: engine, store: store)

        let suite = EvalSuite(
            name: "Math Test",
            description: "Basic math check",
            category: .math,
            prompts: [
                EvalPrompt(
                    prompt: "What is 2+2?",
                    expectedBehavior: .containsText("4"),
                    timeoutSeconds: 10
                )
            ]
        )

        let run = try await runner.run(
            suite: suite,
            models: Self.singleModelEntry(),
            flags: Self.defaultFlags,
            cacheDir: "/tmp/cache"
        )

        #expect(run.modelResults.count == 1, "Should have exactly 1 model result")
        let modelResult = run.modelResults[0]
        #expect(modelResult.promptResults.count == 1, "Should have exactly 1 prompt result")

        let promptResult = modelResult.promptResults[0]
        #expect(promptResult.passed, "Prompt should pass when response contains '4'")
        #expect(promptResult.score == .pass, "Score should be .pass")
        #expect(promptResult.response == "The answer is 4.",
                "Response should be the concatenation of all chunks")
    }

    @Test("Engine returns nonEmpty response → EvalRunner scores as pass")
    @MainActor
    func testHappyPathNonEmptyPass() async throws {
        let engine = MockInstrumentedEngine.happyPath()
        engine.mockResponseChunks = ["Some", " response"]

        let store = Self.makeTempStore()
        let runner = EvalRunner(engine: engine, store: store)

        let suite = EvalSuite(
            name: "NonEmpty Test",
            description: "Checks non-empty responses",
            category: .general,
            prompts: [
                EvalPrompt(
                    prompt: "Say something",
                    expectedBehavior: .nonEmpty,
                    timeoutSeconds: 10
                )
            ]
        )

        let run = try await runner.run(
            suite: suite,
            models: Self.singleModelEntry(),
            flags: Self.defaultFlags,
            cacheDir: "/tmp/cache"
        )

        let promptResult = run.modelResults[0].promptResults[0]
        #expect(promptResult.passed, "Non-empty response should pass .nonEmpty check")
        #expect(promptResult.score == .pass)
    }

    @Test("Engine returns text not matching expectation → EvalRunner scores as fail")
    @MainActor
    func testContainsTextFail() async throws {
        let engine = MockInstrumentedEngine.happyPath()
        engine.mockResponseChunks = ["I don't know the answer"]

        let store = Self.makeTempStore()
        let runner = EvalRunner(engine: engine, store: store)

        let suite = EvalSuite(
            name: "Mismatch Test",
            description: "Expected text not present",
            category: .general,
            prompts: [
                EvalPrompt(
                    prompt: "What is 2+2?",
                    expectedBehavior: .containsText("42"),
                    timeoutSeconds: 10
                )
            ]
        )

        let run = try await runner.run(
            suite: suite,
            models: Self.singleModelEntry(),
            flags: Self.defaultFlags,
            cacheDir: "/tmp/cache"
        )

        let promptResult = run.modelResults[0].promptResults[0]
        #expect(!promptResult.passed, "Should fail when expected text is not in response")
        #expect(promptResult.score.isFailure, "Score should be a failure variant")
    }

    // MARK: - 2. Engine Error → Graceful Handling

    @Test("Engine init failure → model gets failed result without crashing")
    @MainActor
    func testEngineInitFailureHandledGracefully() async throws {
        let engine = MockInstrumentedEngine.failingEngine()

        let store = Self.makeTempStore()
        let runner = EvalRunner(engine: engine, store: store)

        let suite = EvalSuite(
            name: "Init Failure Suite",
            description: "Engine fails to initialize",
            category: .general,
            prompts: [
                EvalPrompt(
                    prompt: "Hello?",
                    expectedBehavior: .nonEmpty,
                    timeoutSeconds: 10
                )
            ]
        )

        // EvalRunner catches model-level errors and creates a failed ModelEvalResult
        // rather than propagating the throw. The run itself should complete.
        let run = try await runner.run(
            suite: suite,
            models: Self.singleModelEntry(),
            flags: Self.defaultFlags,
            cacheDir: "/tmp/cache"
        )

        #expect(run.modelResults.count == 1, "Should still produce a model result")
        let modelResult = run.modelResults[0]
        // A failed init produces empty promptResults and 0 pass rate
        #expect(modelResult.promptResults.isEmpty,
                "Failed init should yield no prompt results")
        #expect(modelResult.passRate == 0.0, "Pass rate should be 0 for failed model")
    }

    @Test("Engine mid-stream error → prompt gets error score, run continues")
    @MainActor
    func testMidStreamErrorHandledGracefully() async throws {
        let engine = MockInstrumentedEngine()
        engine.mockResponseChunks = ["chunk1", "chunk2", "chunk3", "chunk4"]
        engine.errorAtChunkIndex = 2  // Error after emitting chunks 0 and 1

        let store = Self.makeTempStore()
        let runner = EvalRunner(engine: engine, store: store)

        let suite = EvalSuite(
            name: "Mid-Stream Error Suite",
            description: "Engine errors mid-stream",
            category: .general,
            prompts: [
                EvalPrompt(
                    prompt: "Tell me a story",
                    expectedBehavior: .nonEmpty,
                    timeoutSeconds: 10
                )
            ]
        )

        let run = try await runner.run(
            suite: suite,
            models: Self.singleModelEntry(),
            flags: Self.defaultFlags,
            cacheDir: "/tmp/cache"
        )

        let promptResult = run.modelResults[0].promptResults[0]
        #expect(!promptResult.passed,
                "Mid-stream error should result in a non-passing prompt")
        #expect(promptResult.score.isFailure,
                "Score should indicate failure (error variant)")
    }

    @Test("Engine inference error → prompt scored as error, not crash")
    @MainActor
    func testInferenceErrorProducesErrorScore() async throws {
        let engine = MockInstrumentedEngine()
        engine.inferenceError = NSError(
            domain: "TestDomain",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "Simulated inference failure"]
        )

        let store = Self.makeTempStore()
        let runner = EvalRunner(engine: engine, store: store)

        let suite = EvalSuite(
            name: "Inference Error Suite",
            description: "Engine throws on inference",
            category: .general,
            prompts: [
                EvalPrompt(
                    prompt: "This will fail",
                    expectedBehavior: .nonEmpty,
                    timeoutSeconds: 10
                )
            ]
        )

        let run = try await runner.run(
            suite: suite,
            models: Self.singleModelEntry(),
            flags: Self.defaultFlags,
            cacheDir: "/tmp/cache"
        )

        let promptResult = run.modelResults[0].promptResults[0]
        #expect(!promptResult.passed, "Inference error should not pass")

        // The score should be .error(...)
        if case .error(let message) = promptResult.score {
            #expect(!message.isEmpty, "Error message should not be empty")
        } else {
            Issue.record("Expected .error score but got \(promptResult.score)")
        }
    }

    // MARK: - 3. Empty Response → Edge Case Scoring

    @Test("Engine returns empty chunks → nonEmpty check fails correctly")
    @MainActor
    func testEmptyResponseFailsNonEmptyCheck() async throws {
        let engine = MockInstrumentedEngine()
        engine.mockResponseChunks = []  // No chunks at all

        let store = Self.makeTempStore()
        let runner = EvalRunner(engine: engine, store: store)

        let suite = EvalSuite(
            name: "Empty Response Suite",
            description: "Engine returns nothing",
            category: .general,
            prompts: [
                EvalPrompt(
                    prompt: "Say something",
                    expectedBehavior: .nonEmpty,
                    timeoutSeconds: 10
                )
            ]
        )

        let run = try await runner.run(
            suite: suite,
            models: Self.singleModelEntry(),
            flags: Self.defaultFlags,
            cacheDir: "/tmp/cache"
        )

        let promptResult = run.modelResults[0].promptResults[0]
        #expect(!promptResult.passed,
                "Empty response should fail .nonEmpty check")
        #expect(promptResult.response.isEmpty,
                "Response should be empty string when no chunks emitted")
    }

    @Test("Engine returns whitespace-only chunks → containsText fails")
    @MainActor
    func testWhitespaceOnlyResponseFailsContainsText() async throws {
        let engine = MockInstrumentedEngine()
        engine.mockResponseChunks = ["  ", "\n", "\t"]

        let store = Self.makeTempStore()
        let runner = EvalRunner(engine: engine, store: store)

        let suite = EvalSuite(
            name: "Whitespace Suite",
            description: "Engine returns only whitespace",
            category: .general,
            prompts: [
                EvalPrompt(
                    prompt: "What is 2+2?",
                    expectedBehavior: .containsText("4"),
                    timeoutSeconds: 10
                )
            ]
        )

        let run = try await runner.run(
            suite: suite,
            models: Self.singleModelEntry(),
            flags: Self.defaultFlags,
            cacheDir: "/tmp/cache"
        )

        let promptResult = run.modelResults[0].promptResults[0]
        #expect(!promptResult.passed,
                "Whitespace-only response should not contain expected text")
    }

    // MARK: - 4. Multiple Prompts → Sequential Execution

    @Test("Multiple prompts run sequentially through same engine instance")
    @MainActor
    func testMultiplePromptsRunSequentially() async throws {
        let engine = MockInstrumentedEngine.happyPath()
        // Same chunks for each prompt — "Hello, world!" satisfies .nonEmpty
        engine.mockResponseChunks = ["Hello", ", ", "world", "!"]

        let store = Self.makeTempStore()
        let runner = EvalRunner(engine: engine, store: store)

        let prompts = [
            EvalPrompt(
                prompt: "First prompt",
                expectedBehavior: .nonEmpty,
                timeoutSeconds: 10
            ),
            EvalPrompt(
                prompt: "Second prompt",
                expectedBehavior: .nonEmpty,
                timeoutSeconds: 10
            ),
            EvalPrompt(
                prompt: "Third prompt",
                expectedBehavior: .nonEmpty,
                timeoutSeconds: 10
            ),
        ]

        let suite = EvalSuite(
            name: "Multi-Prompt Suite",
            description: "Three prompts against one model",
            category: .general,
            prompts: prompts
        )

        let run = try await runner.run(
            suite: suite,
            models: Self.singleModelEntry(),
            flags: Self.defaultFlags,
            cacheDir: "/tmp/cache"
        )

        let modelResult = run.modelResults[0]
        #expect(modelResult.promptResults.count == 3,
                "Should have results for all 3 prompts")

        // All should pass since "Hello, world!" is non-empty
        for (index, result) in modelResult.promptResults.enumerated() {
            #expect(result.passed,
                    "Prompt \(index + 1) should pass .nonEmpty check")
        }

        // Verify the engine received all 3 prompts
        #expect(engine.sendMessageCallCount == 3,
                "Engine should have been called 3 times")

        // Verify conversation was reset between prompts (N-1 resets for N prompts)
        #expect(engine.resetConversationCallCount == 2,
                "Engine should reset conversation between prompts (2 resets for 3 prompts)")
    }

    @Test("Multiple prompts with mixed pass/fail produce correct aggregate passRate")
    @MainActor
    func testMixedPassFailAggregation() async throws {
        let engine = MockInstrumentedEngine()
        // Response contains "hello" but not "42"
        engine.mockResponseChunks = ["hello", " world"]

        let store = Self.makeTempStore()
        let runner = EvalRunner(engine: engine, store: store)

        let prompts = [
            EvalPrompt(
                prompt: "Say hello",
                expectedBehavior: .containsText("hello"),
                timeoutSeconds: 10
            ),
            EvalPrompt(
                prompt: "What is the meaning of life?",
                expectedBehavior: .containsText("42"),
                timeoutSeconds: 10
            ),
            EvalPrompt(
                prompt: "Say anything",
                expectedBehavior: .nonEmpty,
                timeoutSeconds: 10
            ),
        ]

        let suite = EvalSuite(
            name: "Mixed Results Suite",
            description: "Some pass, some fail",
            category: .general,
            prompts: prompts
        )

        let run = try await runner.run(
            suite: suite,
            models: Self.singleModelEntry(),
            flags: Self.defaultFlags,
            cacheDir: "/tmp/cache"
        )

        let modelResult = run.modelResults[0]
        #expect(modelResult.promptResults.count == 3)

        // First prompt: "hello world" contains "hello" → pass
        #expect(modelResult.promptResults[0].passed, "Should pass .containsText('hello')")

        // Second prompt: "hello world" does NOT contain "42" → fail
        #expect(!modelResult.promptResults[1].passed, "Should fail .containsText('42')")

        // Third prompt: "hello world" is non-empty → pass
        #expect(modelResult.promptResults[2].passed, "Should pass .nonEmpty")

        // Pass rate: 2/3
        let expectedPassRate = 2.0 / 3.0
        #expect(abs(modelResult.passRate - expectedPassRate) < 0.01,
                "Pass rate should be ~66.7% (2/3)")
    }

    // MARK: - 5. Runner State Machine

    @Test("EvalRunner state reaches .complete after successful run")
    @MainActor
    func testRunnerStateCompletesAfterRun() async throws {
        let engine = MockInstrumentedEngine.happyPath()
        let store = Self.makeTempStore()
        let runner = EvalRunner(engine: engine, store: store)

        let suite = EvalSuite(
            name: "State Test",
            description: "Verify runner state",
            category: .general,
            prompts: [
                EvalPrompt(
                    prompt: "Hello",
                    expectedBehavior: .nonEmpty,
                    timeoutSeconds: 10
                )
            ]
        )

        _ = try await runner.run(
            suite: suite,
            models: Self.singleModelEntry(),
            flags: Self.defaultFlags,
            cacheDir: "/tmp/cache"
        )

        #expect(runner.state == .complete,
                "Runner state should be .complete after successful run")
    }

    @Test("EvalRunner rejects empty model list with noModels error")
    @MainActor
    func testEmptyModelListThrowsNoModels() async throws {
        let engine = MockInstrumentedEngine.happyPath()
        let store = Self.makeTempStore()
        let runner = EvalRunner(engine: engine, store: store)

        let suite = EvalSuite(
            name: "No Models Suite",
            description: "Should fail with no models",
            category: .general,
            prompts: [
                EvalPrompt(
                    prompt: "Hello",
                    expectedBehavior: .nonEmpty,
                    timeoutSeconds: 10
                )
            ]
        )

        await #expect(throws: EvalRunnerError.self) {
            try await runner.run(
                suite: suite,
                models: [],
                flags: Self.defaultFlags,
                cacheDir: "/tmp/cache"
            )
        }
    }

    // MARK: - 6. Engine Shutdown Lifecycle

    @Test("EvalRunner shuts down engine after evaluation completes")
    @MainActor
    func testEngineShutdownAfterEval() async throws {
        let engine = MockInstrumentedEngine.happyPath()
        let store = Self.makeTempStore()
        let runner = EvalRunner(engine: engine, store: store)

        let suite = EvalSuite(
            name: "Shutdown Test",
            description: "Verify engine shutdown",
            category: .general,
            prompts: [
                EvalPrompt(
                    prompt: "Hello",
                    expectedBehavior: .nonEmpty,
                    timeoutSeconds: 10
                )
            ]
        )

        _ = try await runner.run(
            suite: suite,
            models: Self.singleModelEntry(),
            flags: Self.defaultFlags,
            cacheDir: "/tmp/cache"
        )

        // Engine should be shut down after eval: once before model init + once after eval
        #expect(engine.shutdownCallCount >= 2,
                "Engine should be shut down at least twice (before model init + after eval)")
        #expect(!engine.isReady,
                "Engine should not be ready after eval shutdown")
    }

    // MARK: - 7. Regex Expected Behavior

    @Test("Engine response matching regex → scores as pass")
    @MainActor
    func testRegexMatchPass() async throws {
        let engine = MockInstrumentedEngine()
        engine.mockResponseChunks = ["The result is 42 units"]

        let store = Self.makeTempStore()
        let runner = EvalRunner(engine: engine, store: store)

        let suite = EvalSuite(
            name: "Regex Suite",
            description: "Regex pattern matching",
            category: .general,
            prompts: [
                EvalPrompt(
                    prompt: "Give me a number",
                    expectedBehavior: .matchesRegex("\\d+"),
                    timeoutSeconds: 10
                )
            ]
        )

        let run = try await runner.run(
            suite: suite,
            models: Self.singleModelEntry(),
            flags: Self.defaultFlags,
            cacheDir: "/tmp/cache"
        )

        let promptResult = run.modelResults[0].promptResults[0]
        #expect(promptResult.passed, "Response containing digits should match \\d+ regex")
    }

    // MARK: - 8. Run Persistence

    @Test("Completed eval run is persisted to EvalStore")
    @MainActor
    func testRunPersistedToStore() async throws {
        let engine = MockInstrumentedEngine.happyPath()
        let store = Self.makeTempStore()
        let runner = EvalRunner(engine: engine, store: store)

        let suite = EvalSuite(
            name: "Persistence Test",
            description: "Verify run is saved",
            category: .general,
            prompts: [
                EvalPrompt(
                    prompt: "Hello",
                    expectedBehavior: .nonEmpty,
                    timeoutSeconds: 10
                )
            ]
        )

        let run = try await runner.run(
            suite: suite,
            models: Self.singleModelEntry(),
            flags: Self.defaultFlags,
            cacheDir: "/tmp/cache"
        )

        // Verify the run was persisted
        let indexEntries = store.list()
        #expect(indexEntries.count == 1,
                "Store should contain exactly 1 run after eval")
        #expect(indexEntries[0].id == run.id,
                "Persisted run ID should match returned run ID")

        // Verify it can be loaded back
        let loadedRun = try store.load(id: run.id)
        #expect(loadedRun.suiteName == "Persistence Test",
                "Loaded run should have correct suite name")
        #expect(loadedRun.modelResults.count == 1,
                "Loaded run should have 1 model result")
    }
}
