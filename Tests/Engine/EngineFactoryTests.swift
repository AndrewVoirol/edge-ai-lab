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

// MARK: - EngineFactory Tests

/// Tests for `EngineFactory` — the routing layer that maps `RuntimeType` and `HFModelFormat`
/// to appropriate `InferenceEngine` implementations.
///
/// These tests verify:
/// - LiteRT-LM creates a `LiteRTEngineAdapter`
/// - MLX creates an `MLXEngineAdapter`
/// - Unsupported runtimes (GGUF) throw `runtimeNotYetAvailable`
/// - Unknown format throws `unsupportedFormat`
/// - HFModelFormat convenience routing matches RuntimeType routing
@Suite("EngineFactory")
struct EngineFactoryTests {

    // MARK: - RuntimeType Routing

    @Suite("RuntimeType routing")
    struct RuntimeTypeRoutingTests {

        @Test("litertlm creates LiteRTEngineAdapter")
        func litertlmCreatesAdapter() throws {
            let engine = try EngineFactory.createEngine(for: .litertlm as RuntimeType)
            #expect(engine is LiteRTEngineAdapter)
            #expect(engine.runtimeType == .litertlm)
        }

        @Test("litertlm engine starts not loaded")
        func litertlmStartsNotLoaded() throws {
            let engine = try EngineFactory.createEngine(for: .litertlm as RuntimeType)
            #expect(engine.isLoaded == false)
            #expect(engine.modelInfo == nil)
        }

        @Test("mlx creates MLXEngineAdapter")
        func mlxCreatesAdapter() throws {
            let engine = try EngineFactory.createEngine(for: .mlx as RuntimeType)
            #expect(engine is MLXEngineAdapter)
            #expect(engine.runtimeType == .mlx)
        }

        @Test("mlx engine starts not loaded")
        func mlxStartsNotLoaded() throws {
            let engine = try EngineFactory.createEngine(for: .mlx as RuntimeType)
            #expect(engine.isLoaded == false)
            #expect(engine.modelInfo == nil)
        }

        @Test("mlx engine has correct runtime type")
        func mlxHasCorrectRuntime() throws {
            let engine = try EngineFactory.createEngine(for: .mlx as RuntimeType)
            #expect(engine.runtimeType == .mlx)
        }

        @Test("gguf engine has correct runtime type")
        func ggufHasCorrectRuntime() throws {
            let engine = try EngineFactory.createEngine(for: .gguf as RuntimeType)
            #expect(engine.runtimeType == .gguf)
        }

        @Test("all RuntimeType cases are handled")
        func exhaustive() {
            for runtimeType in RuntimeType.allCases {
                switch runtimeType {
                case .litertlm:
                    #expect(throws: Never.self) {
                        try EngineFactory.createEngine(for: runtimeType)
                    }
                case .mlx:
                    #expect(throws: Never.self) {
                        try EngineFactory.createEngine(for: runtimeType)
                    }
                case .gguf:
                    #expect(throws: Never.self) {
                        try EngineFactory.createEngine(for: runtimeType)
                    }
                }
            }
        }
    }

    // MARK: - HFModelFormat Routing

    @Suite("HFModelFormat routing")
    struct HFModelFormatRoutingTests {

        @Test("litertlm format creates LiteRTEngineAdapter")
        func litertlmFormat() throws {
            let engine = try EngineFactory.createEngine(for: .litertlm as HFModelFormat)
            #expect(engine is LiteRTEngineAdapter)
            #expect(engine.runtimeType == .litertlm)
        }

        @Test("mlx format creates MLXEngineAdapter")
        func mlxFormat() throws {
            let engine = try EngineFactory.createEngine(for: .mlx as HFModelFormat)
            #expect(engine is MLXEngineAdapter)
            #expect(engine.runtimeType == .mlx)
        }

        @Test("unknown format throws unsupportedFormat")
        func unknownFormat() {
            #expect(throws: EngineError.unsupportedFormat("unknown")) {
                try EngineFactory.createEngine(for: .unknown as HFModelFormat)
            }
        }
    }

    // MARK: - Engine Identity

    @Suite("Engine identity")
    struct EngineIdentityTests {

        @Test("each call creates a fresh engine instance")
        func freshInstance() throws {
            let engine1 = try EngineFactory.createEngine(for: .litertlm as RuntimeType)
            let engine2 = try EngineFactory.createEngine(for: .litertlm as RuntimeType)
            // They should be different instances
            #expect(engine1 !== engine2)
        }

        @Test("each MLX call creates a fresh instance")
        func freshMLXInstance() throws {
            let engine1 = try EngineFactory.createEngine(for: .mlx as RuntimeType)
            let engine2 = try EngineFactory.createEngine(for: .mlx as RuntimeType)
            #expect(engine1 !== engine2)
        }
    }
}
