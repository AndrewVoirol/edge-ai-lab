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

// MARK: - LiteRTEngineAdapter Tests

/// Tests for the `LiteRTEngineAdapter` — the bridge between `InstrumentedEngine`
/// and the runtime-agnostic `InferenceEngine` protocol.
///
/// These tests verify:
/// - Adapter conforms to `InferenceEngine`
/// - Initial state (not loaded, nil modelInfo)
/// - Runtime type is `.litertlm`
/// - `GenerationConfig` → `SamplerConfig` mapping
/// - Stream returns error when engine not ready
///
/// **Note:** These tests do NOT load a real model. Testing actual inference
/// requires integration tests with a `.litertlm` model file on disk.
@Suite("LiteRTEngineAdapter")
struct LiteRTEngineAdapterTests {

    // MARK: - Protocol Conformance

    @Suite("Protocol conformance")
    struct ConformanceTests {

        @Test("adapter conforms to InferenceEngine")
        func conformsToProtocol() {
            let adapter = LiteRTEngineAdapter()
            let engine: any InferenceEngine = adapter
            #expect(engine.runtimeType == .litertlm)
        }

        @Test("adapter is AnyObject (reference type)")
        func isReferenceType() {
            let adapter = LiteRTEngineAdapter()
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
            let adapter = LiteRTEngineAdapter()
            #expect(adapter.isLoaded == false)
        }

        @Test("model info is nil before loading")
        func nilModelInfo() {
            let adapter = LiteRTEngineAdapter()
            #expect(adapter.modelInfo == nil)
        }

        @Test("runtime type is litertlm")
        func runtimeType() {
            let adapter = LiteRTEngineAdapter()
            #expect(adapter.runtimeType == .litertlm)
        }
    }

    // MARK: - SamplerConfig Mapping

    @Suite("SamplerConfig mapping")
    struct SamplerConfigMappingTests {

        @Test("maps default GenerationConfig to valid SamplerConfig")
        func defaultMapping() throws {
            let genConfig = GenerationConfig.default
            let samplerConfig = try LiteRTEngineAdapter.makeSamplerConfig(from: genConfig)
            // SamplerConfig is from LiteRTLM SDK — verify it was created successfully
            // (the throwing init validates parameter ranges)
            _ = samplerConfig // If we got here, the mapping succeeded
        }

        @Test("maps custom GenerationConfig values")
        func customMapping() throws {
            let genConfig = GenerationConfig(
                maxTokens: 1024,
                temperature: 1.5,
                topP: 0.95,
                topK: 50
            )
            let samplerConfig = try LiteRTEngineAdapter.makeSamplerConfig(from: genConfig)
            _ = samplerConfig // Mapping succeeded with custom values
        }

        @Test("diffusion parameters are silently ignored in mapping")
        func diffusionIgnored() throws {
            let genConfig = GenerationConfig(
                diffusionSteps: 32,
                diffusionSchedule: "cosine"
            )
            // Should succeed — diffusion params don't affect SamplerConfig creation
            let samplerConfig = try LiteRTEngineAdapter.makeSamplerConfig(from: genConfig)
            _ = samplerConfig
        }
    }

    // MARK: - Stream Behavior Without Model

    @Suite("Stream without loaded model")
    struct StreamWithoutModelTests {

        @Test("generateStream returns error when not loaded")
        func streamErrorWhenNotLoaded() async {
            let adapter = LiteRTEngineAdapter()
            var receivedError: Error?

            do {
                for try await _ in adapter.generateStream(
                    prompt: "Hello",
                    config: .default
                ) {
                    // Should not receive any tokens
                    Issue.record("Received token from unloaded engine")
                }
            } catch {
                receivedError = error
            }

            #expect(receivedError != nil)
        }

        @Test("generateBatch throws when not loaded")
        func batchErrorWhenNotLoaded() async throws {
            let adapter = LiteRTEngineAdapter()
            await #expect(throws: Error.self) {
                try await adapter.generateBatch(prompt: "Hello", config: .default)
            }
        }
    }

    // MARK: - Factory Integration

    @Suite("Factory integration")
    struct FactoryIntegrationTests {

        @Test("factory creates LiteRTEngineAdapter for litertlm")
        func factoryCreatesAdapter() throws {
            let engine = try EngineFactory.createEngine(for: .litertlm as RuntimeType)
            #expect(engine is LiteRTEngineAdapter)
        }

        @Test("adapter from factory has correct initial state")
        func factoryAdapterState() throws {
            let engine = try EngineFactory.createEngine(for: .litertlm as RuntimeType)
            #expect(engine.isLoaded == false)
            #expect(engine.modelInfo == nil)
            #expect(engine.runtimeType == .litertlm)
        }
    }
}
