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

// MARK: - InferenceEngine Protocol Tests

/// Tests for the `InferenceEngine` protocol, `GenerationConfig`, `ModelLoadConfig`,
/// `InferenceModelInfo`, and `EngineError` types declared in `InferenceEngine.swift`.
///
/// These tests verify protocol requirements, type construction, and error descriptions
/// without requiring a live model or LiteRT-LM SDK.
@Suite("InferenceEngine Protocol")
struct InferenceEngineProtocolTests {

    // MARK: - GenerationConfig

    @Suite("GenerationConfig")
    struct GenerationConfigTests {

        @Test("default config has expected values")
        func defaultValues() {
            let config = GenerationConfig.default
            #expect(config.maxTokens == 512)
            #expect(config.temperature == 0.7)
            #expect(config.topP == 0.9)
            #expect(config.topK == 40)
            #expect(config.diffusionSteps == nil)
            #expect(config.diffusionSchedule == nil)
        }

        @Test("custom config preserves all parameters")
        func customValues() {
            let config = GenerationConfig(
                maxTokens: 1024,
                temperature: 1.2,
                topP: 0.95,
                topK: 50,
                diffusionSteps: 32,
                diffusionSchedule: "cosine"
            )
            #expect(config.maxTokens == 1024)
            #expect(config.temperature == 1.2)
            #expect(config.topP == 0.95)
            #expect(config.topK == 50)
            #expect(config.diffusionSteps == 32)
            #expect(config.diffusionSchedule == "cosine")
        }

        @Test("default init uses default parameter values")
        func defaultInit() {
            let config = GenerationConfig()
            #expect(config.maxTokens == 512)
            #expect(config.temperature == 0.7)
            #expect(config.topP == 0.9)
            #expect(config.topK == 40)
            #expect(config.diffusionSteps == nil)
            #expect(config.diffusionSchedule == nil)
        }

        @Test("config is Equatable")
        func equatable() {
            let a = GenerationConfig.default
            let b = GenerationConfig(maxTokens: 512, temperature: 0.7, topP: 0.9, topK: 40)
            #expect(a == b)
        }

        @Test("configs with different diffusion steps are not equal")
        func notEqualDiffusionSteps() {
            let a = GenerationConfig(diffusionSteps: 16)
            let b = GenerationConfig(diffusionSteps: 32)
            #expect(a != b)
        }

        @Test("config is Sendable")
        func sendable() {
            let config = GenerationConfig.default
            // Verify Sendable by passing across isolation boundary.
            let box: Sendable = config
            #expect(box is GenerationConfig)
        }

        @Test("config with only diffusion params set")
        func diffusionOnly() {
            let config = GenerationConfig(
                diffusionSteps: 48,
                diffusionSchedule: "linear"
            )
            // Standard params still have defaults
            #expect(config.maxTokens == 512)
            #expect(config.temperature == 0.7)
            // Diffusion params set
            #expect(config.diffusionSteps == 48)
            #expect(config.diffusionSchedule == "linear")
        }
    }

    // MARK: - ModelLoadConfig

    @Suite("ModelLoadConfig")
    struct ModelLoadConfigTests {

        @Test("required-only init")
        func requiredOnly() {
            let config = ModelLoadConfig(modelPath: "/path/to/model.litertlm")
            #expect(config.modelPath == "/path/to/model.litertlm")
            #expect(config.preferGPU == true) // default
            #expect(config.cacheDir == nil) // default
        }

        @Test("full init preserves all values")
        func fullInit() {
            let config = ModelLoadConfig(
                modelPath: "/models/gemma.litertlm",
                preferGPU: false,
                cacheDir: "/tmp/cache"
            )
            #expect(config.modelPath == "/models/gemma.litertlm")
            #expect(config.preferGPU == false)
            #expect(config.cacheDir == "/tmp/cache")
        }

        @Test("config is Equatable")
        func equatable() {
            let a = ModelLoadConfig(modelPath: "/path/a", preferGPU: true, cacheDir: "/cache")
            let b = ModelLoadConfig(modelPath: "/path/a", preferGPU: true, cacheDir: "/cache")
            #expect(a == b)
        }

        @Test("configs with different paths are not equal")
        func notEqual() {
            let a = ModelLoadConfig(modelPath: "/path/a")
            let b = ModelLoadConfig(modelPath: "/path/b")
            #expect(a != b)
        }

        @Test("config is Sendable")
        func sendable() {
            let config = ModelLoadConfig(modelPath: "/test")
            let box: Sendable = config
            #expect(box is ModelLoadConfig)
        }
    }

    // MARK: - InferenceModelInfo

    @Suite("InferenceModelInfo")
    struct InferenceModelInfoTests {

        @Test("construction with all fields")
        func fullConstruction() {
            let info = InferenceModelInfo(
                name: "Gemma-4-E2B-it",
                parameterCount: "2B",
                quantization: "INT4",
                runtimeType: .litertlm
            )
            #expect(info.name == "Gemma-4-E2B-it")
            #expect(info.parameterCount == "2B")
            #expect(info.quantization == "INT4")
            #expect(info.runtimeType == .litertlm)
        }

        @Test("construction with nil optionals")
        func nilOptionals() {
            let info = InferenceModelInfo(
                name: "Unknown Model",
                parameterCount: nil,
                quantization: nil,
                runtimeType: .mlx
            )
            #expect(info.name == "Unknown Model")
            #expect(info.parameterCount == nil)
            #expect(info.quantization == nil)
            #expect(info.runtimeType == .mlx)
        }

        @Test("model info is Equatable")
        func equatable() {
            let a = InferenceModelInfo(name: "A", parameterCount: "2B", quantization: "INT4", runtimeType: .litertlm)
            let b = InferenceModelInfo(name: "A", parameterCount: "2B", quantization: "INT4", runtimeType: .litertlm)
            #expect(a == b)
        }

        @Test("model info with different runtime types are not equal")
        func notEqual() {
            let a = InferenceModelInfo(name: "A", parameterCount: nil, quantization: nil, runtimeType: .litertlm)
            let b = InferenceModelInfo(name: "A", parameterCount: nil, quantization: nil, runtimeType: .mlx)
            #expect(a != b)
        }

        @Test("model info is Sendable")
        func sendable() {
            let info = InferenceModelInfo(name: "Test", parameterCount: nil, quantization: nil, runtimeType: .gguf)
            let box: Sendable = info
            #expect(box is InferenceModelInfo)
        }

        @Test("all RuntimeType values can be used in model info")
        func allRuntimeTypes() {
            for runtime in RuntimeType.allCases {
                let info = InferenceModelInfo(
                    name: "model-\(runtime.rawValue)",
                    parameterCount: nil,
                    quantization: nil,
                    runtimeType: runtime
                )
                #expect(info.runtimeType == runtime)
            }
        }
    }

    // MARK: - EngineError

    @Suite("EngineError")
    struct EngineErrorTests {

        @Test("runtimeNotYetAvailable error description includes runtime name")
        func runtimeNotYetAvailableDescription() {
            let error = EngineError.runtimeNotYetAvailable(.mlx)
            let description = error.errorDescription ?? ""
            #expect(description.contains("MLX"))
            #expect(description.contains("not yet available"))
        }

        @Test("runtimeNotYetAvailable for GGUF")
        func runtimeNotYetAvailableGGUF() {
            let error = EngineError.runtimeNotYetAvailable(.gguf)
            let description = error.errorDescription ?? ""
            #expect(description.contains("GGUF"))
        }

        @Test("unsupportedFormat error description includes format name")
        func unsupportedFormatDescription() {
            let error = EngineError.unsupportedFormat("pytorch")
            let description = error.errorDescription ?? ""
            #expect(description.contains("pytorch"))
            #expect(description.contains("Unsupported"))
        }

        @Test("notReady error description includes reason")
        func notReadyDescription() {
            let error = EngineError.notReady("Model not loaded")
            let description = error.errorDescription ?? ""
            #expect(description.contains("Model not loaded"))
            #expect(description.contains("not ready"))
        }

        @Test("EngineError conforms to LocalizedError")
        func localizedError() {
            let error: any Error = EngineError.runtimeNotYetAvailable(.mlx)
            #expect(error.localizedDescription.contains("MLX"))
        }

        @Test("EngineError is Equatable")
        func equatable() {
            #expect(EngineError.runtimeNotYetAvailable(.mlx) == EngineError.runtimeNotYetAvailable(.mlx))
            #expect(EngineError.runtimeNotYetAvailable(.mlx) != EngineError.runtimeNotYetAvailable(.gguf))
            #expect(EngineError.unsupportedFormat("a") == EngineError.unsupportedFormat("a"))
            #expect(EngineError.unsupportedFormat("a") != EngineError.unsupportedFormat("b"))
            #expect(EngineError.notReady("x") == EngineError.notReady("x"))
        }

        @Test("different error kinds are not equal")
        func differentKinds() {
            let a = EngineError.runtimeNotYetAvailable(.mlx)
            let b = EngineError.unsupportedFormat("MLX")
            #expect(a != b)
        }
    }
}
