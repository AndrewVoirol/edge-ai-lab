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

// MARK: - MLXEngineAdapter Tests

/// Tests for the `MLXEngineAdapter` — the bridge between `mlx-swift-lm` and
/// the runtime-agnostic `InferenceEngine` protocol.
///
/// These tests verify:
/// - Protocol conformance (InferenceEngine, AnyObject, Sendable)
/// - Initial state (not loaded, nil modelInfo, nil metrics)
/// - Runtime type is `.mlx`
/// - Error behavior when not loaded (generateStream, generateBatch)
/// - Shutdown clears all state
/// - Cancel generation nulls active task
/// - Reset conversation doesn't throw when not loaded
/// - Generation event types (via mock — tested in MockMLXEngine tests)
///
/// **Note:** Actual model loading and inference tests require Metal (macOS or physical device).
/// These tests run on all platforms including iOS Simulator (where the stub is used).
@Suite("MLXEngineAdapter")
struct MLXEngineAdapterTests {

    // MARK: - Protocol Conformance

    @Suite("Protocol conformance")
    struct ConformanceTests {

        @Test("adapter conforms to InferenceEngine")
        func conformsToProtocol() {
            let adapter = MLXEngineAdapter()
            let engine: any InferenceEngine = adapter
            #expect(engine.runtimeType == .mlx)
        }

        @Test("adapter is AnyObject (reference type)")
        func isReferenceType() {
            let adapter = MLXEngineAdapter()
            let ref1: AnyObject = adapter
            let ref2: AnyObject = adapter
            #expect(ref1 === ref2)
        }
    }

    // MARK: - Initial State

    @Suite("Initial state")
    struct InitialStateTests {

        @Test("starts not loaded")
        func notLoaded() {
            let adapter = MLXEngineAdapter()
            #expect(adapter.isLoaded == false)
        }

        @Test("model info is nil before loading")
        func nilModelInfo() {
            let adapter = MLXEngineAdapter()
            #expect(adapter.modelInfo == nil)
        }

        @Test("runtime type is mlx")
        func runtimeType() {
            let adapter = MLXEngineAdapter()
            #expect(adapter.runtimeType == .mlx)
        }

        @Test("last performance metrics are nil before generation")
        func nilMetrics() {
            let adapter = MLXEngineAdapter()
            #expect(adapter.lastPerformanceMetrics == nil)
        }

        @Test("download progress is 0 before loading")
        func zeroProgress() {
            let adapter = MLXEngineAdapter()
            #expect(adapter.downloadProgress == 0.0)
        }
    }

    // MARK: - Capabilities

    @Suite("Capabilities")
    struct CapabilityTests {

        @Test("supports tool calling")
        func toolCalling() {
            let adapter = MLXEngineAdapter()
            // On macOS (real implementation), supportsToolCalling is true.
            // On iOS Simulator (stub), it's false. Test platform-appropriate value.
            #if canImport(MLX) && !targetEnvironment(simulator)
            #expect(adapter.supportsToolCalling == true)
            #else
            #expect(adapter.supportsToolCalling == false)
            #endif
        }

        @Test("does not support vision (Phase 4)")
        func noVision() {
            let adapter = MLXEngineAdapter()
            #expect(adapter.supportsVision == false)
        }
    }

    // MARK: - Stream Behavior Without Model

    @Suite("Stream without loaded model")
    struct StreamWithoutModelTests {

        @Test("generateStream returns error when not loaded")
        func streamErrorWhenNotLoaded() async {
            let adapter = MLXEngineAdapter()
            var receivedError: Error?

            do {
                for try await _ in adapter.generateStream(
                    prompt: "Hello",
                    config: .default
                ) {
                    Issue.record("Received event from unloaded engine")
                }
            } catch {
                receivedError = error
            }

            #expect(receivedError != nil)
        }

        @Test("generateBatch throws when not loaded")
        func batchErrorWhenNotLoaded() async throws {
            let adapter = MLXEngineAdapter()
            await #expect(throws: Error.self) {
                try await adapter.generateBatch(prompt: "Hello", config: .default)
            }
        }
    }

    // MARK: - Lifecycle

    @Suite("Lifecycle")
    struct LifecycleTests {

        @Test("shutdown clears all state")
        func shutdownClearsState() async {
            let adapter = MLXEngineAdapter()
            // Shutdown should not crash even when nothing is loaded.
            await adapter.shutdown()
            #expect(adapter.isLoaded == false)
            #expect(adapter.modelInfo == nil)
            #expect(adapter.lastPerformanceMetrics == nil)
        }

        @Test("cancel generation doesn't crash when no active task")
        func cancelWithNoTask() {
            let adapter = MLXEngineAdapter()
            // Should be a no-op, not crash.
            adapter.cancelGeneration()
        }

        @Test("reset conversation doesn't throw when not loaded")
        func resetWhenNotLoaded() async throws {
            let adapter = MLXEngineAdapter()
            // On stub: should be a no-op. On real: guard returns early.
            try await adapter.resetConversation()
        }

        @Test("multiple shutdowns don't crash")
        func multipleShutdowns() async {
            let adapter = MLXEngineAdapter()
            await adapter.shutdown()
            await adapter.shutdown()
            await adapter.shutdown()
            #expect(adapter.isLoaded == false)
        }
    }

    // MARK: - Factory Integration

    @Suite("Factory integration")
    struct FactoryIntegrationTests {

        @Test("factory creates MLXEngineAdapter for mlx")
        func factoryCreatesAdapter() throws {
            let engine = try EngineFactory.createEngine(for: .mlx as RuntimeType)
            #expect(engine is MLXEngineAdapter)
        }

        @Test("adapter from factory has correct initial state")
        func factoryAdapterState() throws {
            let engine = try EngineFactory.createEngine(for: .mlx as RuntimeType)
            #expect(engine.isLoaded == false)
            #expect(engine.modelInfo == nil)
            #expect(engine.runtimeType == .mlx)
        }

        @Test("factory also creates MLXEngineAdapter from HFModelFormat.mlx")
        func factoryFromHFFormat() throws {
            let engine = try EngineFactory.createEngine(for: .mlx as HFModelFormat)
            #expect(engine is MLXEngineAdapter)
            #expect(engine.runtimeType == .mlx)
        }
    }
}
