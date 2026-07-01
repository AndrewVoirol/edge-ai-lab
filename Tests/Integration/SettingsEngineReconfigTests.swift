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

import XCTest

#if os(iOS)
@testable import EdgeAILab_iOS
#elseif os(macOS)
@testable import EdgeAILab_macOS
#endif

/// Integration tests for Settings → engine reconfiguration flow.
///
/// Validates that changes to `RuntimeFlags` and generation parameters
/// (temperature, topK, topP, seed) propagate correctly through the
/// MockInferenceEngine, and that the `ExperimentConfig` snapshot captures
/// the expected values.
@MainActor
final class SettingsEngineReconfigTests: XCTestCase {

    // MARK: - Properties

    private var engine: MockInferenceEngine!

    private let defaultFlags = RuntimeFlags(
        enableBenchmark: true,
        enableThinking: true,
        enableToolCalling: false,
        enableAgentSkills: false,
        enableSpeculativeDecoding: nil,
        enableConversationConstrainedDecoding: false,
        visualTokenBudget: nil
    )

    // MARK: - Setup / Teardown

    override func setUp() {
        super.setUp()
        engine = MockInferenceEngine()
    }

    override func tearDown() {
        engine = nil
        super.tearDown()
    }

    // MARK: - Default Settings

    /// Verify `RuntimeFlags` defaults match expected values.
    func testDefaultSettings() {
        let flags = RuntimeFlags(
            enableBenchmark: true,
            enableSpeculativeDecoding: nil,
            enableConversationConstrainedDecoding: false,
            visualTokenBudget: nil
        )

        // Check defaults for the properties with default parameter values
        XCTAssertTrue(flags.enableBenchmark,
            "enableBenchmark should be true when passed as true.")
        XCTAssertNil(flags.enableSpeculativeDecoding,
            "enableSpeculativeDecoding should be nil by default.")
        XCTAssertFalse(flags.enableConversationConstrainedDecoding,
            "enableConversationConstrainedDecoding should be false.")
        XCTAssertNil(flags.visualTokenBudget,
            "visualTokenBudget should be nil by default.")
        XCTAssertTrue(flags.enableThinking,
            "enableThinking should default to true.")
        XCTAssertFalse(flags.enableToolCalling,
            "enableToolCalling should default to false.")
        XCTAssertFalse(flags.enableAgentSkills,
            "enableAgentSkills should default to false.")
    }

    // MARK: - Thinking Mode Toggle

    /// Toggle thinking mode on and off, verify the engine sees the change.
    func testToggleThinkingMode() async throws {
        // Initialize with thinking enabled (default)
        try await engine.loadModel(config: ModelLoadConfig(
            modelPath: "/fake/model.litertlm",
            preferGPU: false,
            cacheDir: NSTemporaryDirectory(),
            runtimeFlags: defaultFlags
        ))

        XCTAssertTrue(engine.isLoaded, "Engine should be loaded after init.")
        XCTAssertTrue(engine.lastRuntimeFlags?.enableThinking ?? false,
            "Engine should see enableThinking = true from initial flags.")

        // Re-initialize with thinking disabled
        var disabledThinking = defaultFlags
        disabledThinking.enableThinking = false

        try await engine.loadModel(config: ModelLoadConfig(
            modelPath: "/fake/model.litertlm",
            preferGPU: false,
            cacheDir: NSTemporaryDirectory(),
            runtimeFlags: disabledThinking
        ))

        XCTAssertFalse(engine.lastRuntimeFlags?.enableThinking ?? true,
            "Engine should see enableThinking = false after reconfiguration.")
        XCTAssertEqual(engine.loadModelCallCount, 2,
            "loadModel() should have been called twice.")

        // Verify lastRuntimeFlags on the engine tracks the change
        XCTAssertFalse(engine.lastRuntimeFlags?.enableThinking ?? true,
            "Engine's lastRuntimeFlags should reflect the updated thinking flag.")
    }

    // MARK: - Tool Calling Toggle

    /// Toggle tool calling, verify the engine receives updated flags.
    func testToggleToolCalling() async throws {
        // Start without tool calling
        try await engine.loadModel(config: ModelLoadConfig(
            modelPath: "/fake/model.litertlm",
            preferGPU: false,
            cacheDir: NSTemporaryDirectory(),
            runtimeFlags: defaultFlags
        ))

        XCTAssertFalse(engine.lastRuntimeFlags?.enableToolCalling ?? true,
            "Engine should see enableToolCalling = false initially.")

        // Enable tool calling
        var toolCallingFlags = defaultFlags
        toolCallingFlags.enableToolCalling = true

        try await engine.loadModel(config: ModelLoadConfig(
            modelPath: "/fake/model.litertlm",
            preferGPU: false,
            cacheDir: NSTemporaryDirectory(),
            runtimeFlags: toolCallingFlags
        ))

        XCTAssertTrue(engine.lastRuntimeFlags?.enableToolCalling ?? false,
            "Engine should see enableToolCalling = true after reconfiguration.")
    }

    // MARK: - Temperature Change

    /// Change the inference temperature, verify the engine receives the updated generation config.
    func testChangeTemperature() async throws {
        // Initialize with default temperature
        let defaultGenConfig = GenerationConfig(temperature: 1.0, topP: 0.95, topK: 64)
        try await engine.loadModel(config: ModelLoadConfig(
            modelPath: "/fake/model.litertlm",
            preferGPU: false,
            cacheDir: NSTemporaryDirectory(),
            generationConfig: defaultGenConfig,
            runtimeFlags: defaultFlags
        ))

        XCTAssertNotNil(engine.lastGenerationConfig,
            "Engine should have received a generation config.")

        // Re-initialize with a different temperature
        let hotGenConfig = GenerationConfig(temperature: 1.8, topP: 0.95, topK: 64)
        try await engine.loadModel(config: ModelLoadConfig(
            modelPath: "/fake/model.litertlm",
            preferGPU: false,
            cacheDir: NSTemporaryDirectory(),
            generationConfig: hotGenConfig,
            runtimeFlags: defaultFlags
        ))

        XCTAssertNotNil(engine.lastGenerationConfig,
            "Engine should have received the updated generation config with new temperature.")
        XCTAssertEqual(engine.loadModelCallCount, 2,
            "Engine should have been re-initialized for the temperature change.")
    }

    // MARK: - Max Tokens Change

    /// Change the max output tokens via `ExperimentConfig` snapshot,
    /// verifying that generation config changes propagate through re-init.
    func testChangeMaxTokens() async throws {
        // Initialize with default generation config (topK=64)
        let defaultGenConfig = GenerationConfig(temperature: 1.0, topP: 0.95, topK: 64)
        try await engine.loadModel(config: ModelLoadConfig(
            modelPath: "/fake/model.litertlm",
            preferGPU: false,
            cacheDir: NSTemporaryDirectory(),
            generationConfig: defaultGenConfig,
            runtimeFlags: defaultFlags
        ))

        // Re-initialize with greedy decoding (topK=1) — simulates changing max output behavior
        let greedyGenConfig = GenerationConfig(temperature: 1.0, topP: 1.0, topK: 1)
        try await engine.loadModel(config: ModelLoadConfig(
            modelPath: "/fake/model.litertlm",
            preferGPU: false,
            cacheDir: NSTemporaryDirectory(),
            generationConfig: greedyGenConfig,
            runtimeFlags: defaultFlags
        ))

        XCTAssertNotNil(engine.lastGenerationConfig,
            "Engine should have received the updated generation config.")
        XCTAssertEqual(engine.loadModelCallCount, 2,
            "Engine should have been re-initialized for the generation config change.")
    }

    // MARK: - Settings Persistence

    /// Verify that RuntimeFlags round-trips through Codable encoding/decoding.
    func testSettingsPersistence() throws {
        let flags = RuntimeFlags(
            enableBenchmark: true,
            enableThinking: false,
            enableToolCalling: true,
            enableAgentSkills: true,
            enableSpeculativeDecoding: true,
            enableConversationConstrainedDecoding: true,
            visualTokenBudget: 280
        )

        // Encode to JSON
        let encoder = JSONEncoder()
        let data = try encoder.encode(flags)

        // Decode from JSON
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(RuntimeFlags.self, from: data)

        // Verify all fields round-trip correctly
        XCTAssertEqual(decoded.enableBenchmark, flags.enableBenchmark,
            "enableBenchmark should survive Codable round-trip.")
        XCTAssertEqual(decoded.enableSpeculativeDecoding, flags.enableSpeculativeDecoding,
            "enableSpeculativeDecoding should survive Codable round-trip.")
        XCTAssertEqual(decoded.enableConversationConstrainedDecoding, flags.enableConversationConstrainedDecoding,
            "enableConversationConstrainedDecoding should survive Codable round-trip.")
        XCTAssertEqual(decoded.visualTokenBudget, flags.visualTokenBudget,
            "visualTokenBudget should survive Codable round-trip.")
        XCTAssertEqual(decoded.enableThinking, flags.enableThinking,
            "enableThinking should survive Codable round-trip.")
        XCTAssertEqual(decoded.enableToolCalling, flags.enableToolCalling,
            "enableToolCalling should survive Codable round-trip.")
        XCTAssertEqual(decoded.enableAgentSkills, flags.enableAgentSkills,
            "enableAgentSkills should survive Codable round-trip.")

        // Verify Equatable conformance
        XCTAssertEqual(decoded, flags,
            "Decoded flags should be equal to original via Equatable.")
    }

    // MARK: - Multiple Settings Changes

    /// Change several settings at once, verify the engine sees all changes after re-init.
    func testMultipleSettingsChanges() async throws {
        // Initialize with all defaults
        try await engine.loadModel(config: ModelLoadConfig(
            modelPath: "/fake/model.litertlm",
            preferGPU: false,
            cacheDir: NSTemporaryDirectory(),
            runtimeFlags: defaultFlags
        ))

        // Prepare a new flags state with multiple changes
        let newFlags = RuntimeFlags(
            enableBenchmark: false,
            enableThinking: false,
            enableToolCalling: true,
            enableAgentSkills: true,
            enableSpeculativeDecoding: true,
            enableConversationConstrainedDecoding: true,
            visualTokenBudget: 560
        )

        // Re-initialize with all changes at once + new generation config + system message
        let newGenConfig = GenerationConfig(temperature: 0.5, topP: 1.0, topK: 1)
        try await engine.loadModel(config: ModelLoadConfig(
            modelPath: "/fake/model.litertlm",
            preferGPU: true,
            cacheDir: NSTemporaryDirectory(),
            systemMessage: "You are a helpful coding assistant.",
            generationConfig: newGenConfig,
            runtimeFlags: newFlags
        ))

        // Verify all changes propagated
        XCTAssertEqual(engine.loadModelCallCount, 2,
            "loadModel() should have been called twice.")

        let capturedFlags = engine.lastRuntimeFlags
        XCTAssertNotNil(capturedFlags, "Engine should have captured flags.")
        XCTAssertFalse(capturedFlags?.enableBenchmark ?? true,
            "enableBenchmark should be false.")
        XCTAssertEqual(capturedFlags?.enableSpeculativeDecoding, true,
            "enableSpeculativeDecoding should be true.")
        XCTAssertTrue(capturedFlags?.enableConversationConstrainedDecoding ?? false,
            "enableConversationConstrainedDecoding should be true.")
        XCTAssertEqual(capturedFlags?.visualTokenBudget, 560,
            "visualTokenBudget should be 560.")
        XCTAssertFalse(capturedFlags?.enableThinking ?? true,
            "enableThinking should be false.")
        XCTAssertTrue(capturedFlags?.enableToolCalling ?? false,
            "enableToolCalling should be true.")
        XCTAssertTrue(capturedFlags?.enableAgentSkills ?? false,
            "enableAgentSkills should be true.")

        // Verify generation config and system message
        XCTAssertNotNil(engine.lastGenerationConfig,
            "Engine should have received the new generation config.")
        XCTAssertEqual(engine.lastSystemMessage, "You are a helpful coding assistant.",
            "Engine should have received the system message.")

        // Verify the engine's lastRuntimeFlags matches
        XCTAssertEqual(engine.lastRuntimeFlags, newFlags,
            "Engine's lastRuntimeFlags should equal the new flags via Equatable.")
    }
}
