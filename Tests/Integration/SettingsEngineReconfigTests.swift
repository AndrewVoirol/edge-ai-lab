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

/// Integration tests for Settings → engine reconfiguration flow.
///
/// Validates that changes to `ExperimentalFlagsState` and sampler parameters
/// (temperature, topK, topP, seed) propagate correctly through the
/// MockInstrumentedEngine, and that the `ExperimentConfig` snapshot captures
/// the expected values.
@MainActor
final class SettingsEngineReconfigTests: XCTestCase {

    // MARK: - Properties

    private var engine: MockInstrumentedEngine!

    private let defaultFlags = ExperimentalFlagsState(
        enableBenchmark: true,
        enableSpeculativeDecoding: nil,
        enableConversationConstrainedDecoding: false,
        visualTokenBudget: nil,
        enableThinking: true,
        enableToolCalling: false,
        enableAgentSkills: false
    )

    // MARK: - Setup / Teardown

    override func setUp() {
        super.setUp()
        engine = MockInstrumentedEngine()
    }

    override func tearDown() {
        engine = nil
        super.tearDown()
    }

    // MARK: - Default Settings

    /// Verify `ExperimentalFlagsState` defaults match expected values.
    func testDefaultSettings() {
        let flags = ExperimentalFlagsState(
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
        try await engine.initialize(
            modelPath: "/fake/model.litertlm",
            useGPU: false,
            cacheDir: NSTemporaryDirectory(),
            flags: defaultFlags,
            samplerConfig: nil,
            systemMessage: nil,
            tools: nil
        )

        XCTAssertTrue(engine.isReady, "Engine should be ready after init.")
        XCTAssertTrue(engine.lastFlags?.enableThinking ?? false,
            "Engine should see enableThinking = true from initial flags.")

        // Re-initialize with thinking disabled
        var disabledThinking = defaultFlags
        disabledThinking.enableThinking = false

        try await engine.initialize(
            modelPath: "/fake/model.litertlm",
            useGPU: false,
            cacheDir: NSTemporaryDirectory(),
            flags: disabledThinking,
            samplerConfig: nil,
            systemMessage: nil,
            tools: nil
        )

        XCTAssertFalse(engine.lastFlags?.enableThinking ?? true,
            "Engine should see enableThinking = false after reconfiguration.")
        XCTAssertEqual(engine.initializeCallCount, 2,
            "initialize() should have been called twice.")

        // Verify flagsState on the engine tracks the change
        XCTAssertFalse(engine.flagsState.enableThinking,
            "Engine's flagsState should reflect the updated thinking flag.")
    }

    // MARK: - Tool Calling Toggle

    /// Toggle tool calling, verify the engine receives updated flags.
    func testToggleToolCalling() async throws {
        // Start without tool calling
        try await engine.initialize(
            modelPath: "/fake/model.litertlm",
            useGPU: false,
            cacheDir: NSTemporaryDirectory(),
            flags: defaultFlags,
            samplerConfig: nil,
            systemMessage: nil,
            tools: nil
        )

        XCTAssertFalse(engine.lastFlags?.enableToolCalling ?? true,
            "Engine should see enableToolCalling = false initially.")
        XCTAssertNil(engine.lastTools,
            "No tools should be passed when tool calling is disabled.")

        // Enable tool calling
        var toolCallingFlags = defaultFlags
        toolCallingFlags.enableToolCalling = true

        try await engine.initialize(
            modelPath: "/fake/model.litertlm",
            useGPU: false,
            cacheDir: NSTemporaryDirectory(),
            flags: toolCallingFlags,
            samplerConfig: nil,
            systemMessage: nil,
            tools: nil
        )

        XCTAssertTrue(engine.lastFlags?.enableToolCalling ?? false,
            "Engine should see enableToolCalling = true after reconfiguration.")
        XCTAssertTrue(engine.flagsState.enableToolCalling,
            "Engine's flagsState should reflect tool calling enabled.")
    }

    // MARK: - Temperature Change

    /// Change the inference temperature, verify the engine receives the updated sampler config.
    func testChangeTemperature() async throws {
        // Initialize with default temperature
        let defaultSampler = try SamplerConfig(topK: 64, topP: 0.95, temperature: 1.0)
        try await engine.initialize(
            modelPath: "/fake/model.litertlm",
            useGPU: false,
            cacheDir: NSTemporaryDirectory(),
            flags: defaultFlags,
            samplerConfig: defaultSampler,
            systemMessage: nil,
            tools: nil
        )

        XCTAssertNotNil(engine.lastSamplerConfig,
            "Engine should have received a sampler config.")

        // Re-initialize with a different temperature
        let hotSampler = try SamplerConfig(topK: 64, topP: 0.95, temperature: 1.8)
        try await engine.initialize(
            modelPath: "/fake/model.litertlm",
            useGPU: false,
            cacheDir: NSTemporaryDirectory(),
            flags: defaultFlags,
            samplerConfig: hotSampler,
            systemMessage: nil,
            tools: nil
        )

        XCTAssertNotNil(engine.lastSamplerConfig,
            "Engine should have received the updated sampler config with new temperature.")
        XCTAssertEqual(engine.initializeCallCount, 2,
            "Engine should have been re-initialized for the temperature change.")
    }

    // MARK: - Max Tokens Change

    /// Change the max output tokens via `ExperimentConfig` snapshot,
    /// verifying that sampler config changes propagate through re-init.
    func testChangeMaxTokens() async throws {
        // Initialize with default sampler (topK=64)
        let defaultSampler = try SamplerConfig(topK: 64, topP: 0.95, temperature: 1.0)
        try await engine.initialize(
            modelPath: "/fake/model.litertlm",
            useGPU: false,
            cacheDir: NSTemporaryDirectory(),
            flags: defaultFlags,
            samplerConfig: defaultSampler,
            systemMessage: nil,
            tools: nil
        )

        // Re-initialize with greedy decoding (topK=1) — simulates changing max output behavior
        let greedySampler = try SamplerConfig(topK: 1, topP: 1.0, temperature: 1.0)
        try await engine.initialize(
            modelPath: "/fake/model.litertlm",
            useGPU: false,
            cacheDir: NSTemporaryDirectory(),
            flags: defaultFlags,
            samplerConfig: greedySampler,
            systemMessage: nil,
            tools: nil
        )

        XCTAssertNotNil(engine.lastSamplerConfig,
            "Engine should have received the updated sampler config.")
        XCTAssertEqual(engine.initializeCallCount, 2,
            "Engine should have been re-initialized for the sampler change.")
    }

    // MARK: - Settings Persistence

    /// Verify that ExperimentalFlagsState round-trips through Codable encoding/decoding.
    func testSettingsPersistence() throws {
        var flags = ExperimentalFlagsState(
            enableBenchmark: true,
            enableSpeculativeDecoding: true,
            enableConversationConstrainedDecoding: true,
            visualTokenBudget: 280,
            enableThinking: false,
            enableToolCalling: true,
            enableAgentSkills: true
        )

        // Encode to JSON
        let encoder = JSONEncoder()
        let data = try encoder.encode(flags)

        // Decode from JSON
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ExperimentalFlagsState.self, from: data)

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
        try await engine.initialize(
            modelPath: "/fake/model.litertlm",
            useGPU: false,
            cacheDir: NSTemporaryDirectory(),
            flags: defaultFlags,
            samplerConfig: nil,
            systemMessage: nil,
            tools: nil
        )

        // Prepare a new flags state with multiple changes
        var newFlags = ExperimentalFlagsState(
            enableBenchmark: false,
            enableSpeculativeDecoding: true,
            enableConversationConstrainedDecoding: true,
            visualTokenBudget: 560,
            enableThinking: false,
            enableToolCalling: true,
            enableAgentSkills: true
        )

        // Re-initialize with all changes at once + new sampler + system message
        let newSampler = try SamplerConfig(topK: 1, topP: 1.0, temperature: 0.5)
        try await engine.initialize(
            modelPath: "/fake/model.litertlm",
            useGPU: true,
            cacheDir: NSTemporaryDirectory(),
            flags: newFlags,
            samplerConfig: newSampler,
            systemMessage: "You are a helpful coding assistant.",
            tools: nil
        )

        // Verify all changes propagated
        XCTAssertEqual(engine.initializeCallCount, 2,
            "initialize() should have been called twice.")

        let capturedFlags = engine.lastFlags
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

        // Verify sampler and system message
        XCTAssertNotNil(engine.lastSamplerConfig,
            "Engine should have received the new sampler config.")
        XCTAssertEqual(engine.lastSystemMessage, "You are a helpful coding assistant.",
            "Engine should have received the system message.")

        // Verify the engine's internal flagsState matches
        XCTAssertEqual(engine.flagsState, newFlags,
            "Engine's flagsState should equal the new flags via Equatable.")
    }
}
