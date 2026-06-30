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

// MARK: - EngineFactory

/// Routes a `RuntimeType` to the appropriate `InferenceEngine` implementation.
///
/// ## Current Support
///
/// - `.litertlm` → `LiteRTEngineAdapter` (wraps the existing `InstrumentedEngine`)
/// - `.mlx` → `MLXEngineAdapter` (wraps mlx-swift-lm, Metal GPU inference)
/// - `.gguf` → throws `runtimeNotYetAvailable` (recognized but not implemented)
///
/// ## Usage
///
/// ```swift
/// let engine = try EngineFactory.createEngine(for: .litertlm)
/// try await engine.loadModel(config: .init(modelPath: path))
/// for try await event in engine.generateStream(prompt: "Hello", config: .default) {
///     if case .text(let token) = event { print(token, terminator: "") }
/// }
/// ```
///
/// ## Extension Point
///
/// To add a new runtime:
/// 1. Create a class conforming to `InferenceEngine`
/// 2. Add a case to the switch in `createEngine(for:)`
/// 3. Add tests in `Tests/Engine/EngineFactoryTests.swift`
enum EngineFactory {

    /// Create an inference engine appropriate for the given runtime type.
    ///
    /// - Parameter runtimeType: The runtime backend to instantiate.
    /// - Returns: An engine ready to load a model and generate text.
    /// - Throws: `EngineError.runtimeNotYetAvailable` for recognized but unimplemented runtimes.
    static func createEngine(for runtimeType: RuntimeType) throws -> any InferenceEngine {
        switch runtimeType {
        case .litertlm:
            return LiteRTEngineAdapter()
        case .mlx:
            return MLXEngineAdapter()
        case .gguf:
            throw EngineError.runtimeNotYetAvailable(.gguf)
        }
    }

    /// Convenience: create an engine from an `HFModelFormat`.
    ///
    /// Maps `HFModelFormat` → `RuntimeType` and delegates to `createEngine(for:)`.
    /// - Parameter format: The detected model format.
    /// - Throws: `EngineError.unsupportedFormat` for `.unknown` format,
    ///           `EngineError.runtimeNotYetAvailable` for recognized but unimplemented runtimes.
    static func createEngine(for format: HFModelFormat) throws -> any InferenceEngine {
        switch format {
        case .litertlm:
            return try createEngine(for: RuntimeType.litertlm)
        case .mlx:
            return try createEngine(for: RuntimeType.mlx)
        case .unknown:
            throw EngineError.unsupportedFormat("unknown")
        }
    }
}
