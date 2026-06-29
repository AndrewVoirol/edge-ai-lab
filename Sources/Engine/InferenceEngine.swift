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

// MARK: - InferenceEngine Protocol

/// A runtime-agnostic protocol for on-device model inference.
///
/// `InferenceEngine` abstracts over different inference backends (LiteRT-LM, MLX, GGUF)
/// and supports both autoregressive (token streaming) and non-autoregressive (batch/diffusion)
/// generation modes.
///
/// ## Design Rationale
///
/// This protocol sits above the existing `InstrumentedEngineProtocol`, which is tightly
/// coupled to LiteRT-LM's SDK types (`SamplerConfig`, `ExperimentalFlagsState`, `Tool`).
/// `InferenceEngine` uses runtime-agnostic types (`GenerationConfig`, `InferenceModelInfo`)
/// so that new backends can be added without importing LiteRT-LM.
///
/// ## Generation Modes
///
/// - **Streaming (`generateStream`):** Yields tokens one at a time as they are generated.
///   Used by autoregressive models (e.g., Gemma via LiteRT-LM). Callers iterate
///   with `for try await token in stream { ... }`.
///
/// - **Batch (`generateBatch`):** Returns the complete response as a single string.
///   Used by diffusion models (e.g., DiffusionGemma) that produce all tokens in parallel
///   across multiple refinement steps. Also useful for autoregressive models when streaming
///   is not needed (the default implementation collects stream output).
///
/// ## Conformance
///
/// - `LiteRTEngineAdapter` wraps `InstrumentedEngine` for LiteRT-LM models.
/// - Future: `MLXEngine`, `GGUFEngine` for additional runtimes.
protocol InferenceEngine: AnyObject, Sendable {

    /// Load a model from a filesystem path.
    ///
    /// - Parameter config: Configuration specifying the model path and load options.
    /// - Throws: If the model file is missing, corrupt, or incompatible with this runtime.
    func loadModel(config: ModelLoadConfig) async throws

    /// Generate a streaming response for the given prompt.
    ///
    /// Each element in the returned stream is a text chunk (typically one or a few tokens).
    /// The stream completes when generation finishes or is cancelled.
    ///
    /// - Parameters:
    ///   - prompt: The input text prompt.
    ///   - config: Generation parameters (temperature, maxTokens, etc.).
    /// - Returns: An `AsyncThrowingStream` of text chunks.
    func generateStream(
        prompt: String,
        config: GenerationConfig
    ) -> AsyncThrowingStream<String, Error>

    /// Generate a complete response for the given prompt.
    ///
    /// For autoregressive engines, the default implementation collects all chunks from
    /// `generateStream`. For diffusion engines, this is the native generation mode.
    ///
    /// - Parameters:
    ///   - prompt: The input text prompt.
    ///   - config: Generation parameters (temperature, maxTokens, diffusion steps, etc.).
    /// - Returns: The complete generated text.
    func generateBatch(
        prompt: String,
        config: GenerationConfig
    ) async throws -> String

    /// Whether a model is currently loaded and ready for inference.
    var isLoaded: Bool { get }

    /// Information about the currently loaded model, or nil if no model is loaded.
    var modelInfo: InferenceModelInfo? { get }

    /// The runtime backend this engine uses.
    var runtimeType: RuntimeType { get }
}

// MARK: - Default Implementations

extension InferenceEngine {

    /// Default `generateBatch` collects all chunks from `generateStream` into a single string.
    /// Diffusion engines should override this with their native batch generation.
    func generateBatch(
        prompt: String,
        config: GenerationConfig
    ) async throws -> String {
        var result = ""
        for try await chunk in generateStream(prompt: prompt, config: config) {
            result += chunk
        }
        return result
    }
}

// MARK: - GenerationConfig

/// Runtime-agnostic generation parameters.
///
/// Contains parameters applicable to both autoregressive and diffusion generation.
/// Runtime-specific parameters that don't apply to a given engine are ignored.
struct GenerationConfig: Sendable, Equatable {

    /// Maximum number of tokens to generate.
    var maxTokens: Int

    /// Sampling temperature (higher = more random). Range: [0.0, 2.0].
    var temperature: Double

    /// Nucleus sampling: only consider tokens with cumulative probability ≤ topP.
    var topP: Double

    /// Top-K sampling: only consider the K most probable tokens.
    var topK: Int

    // MARK: - Diffusion-Specific (Optional)

    /// Number of denoising steps for diffusion models. Ignored by autoregressive engines.
    var diffusionSteps: Int?

    /// Noise schedule name for diffusion models (e.g., "cosine", "linear").
    /// Ignored by autoregressive engines.
    var diffusionSchedule: String?

    /// Sensible defaults for autoregressive generation.
    static let `default` = GenerationConfig(
        maxTokens: 512,
        temperature: 0.7,
        topP: 0.9,
        topK: 40,
        diffusionSteps: nil,
        diffusionSchedule: nil
    )

    init(
        maxTokens: Int = 512,
        temperature: Double = 0.7,
        topP: Double = 0.9,
        topK: Int = 40,
        diffusionSteps: Int? = nil,
        diffusionSchedule: String? = nil
    ) {
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.topP = topP
        self.topK = topK
        self.diffusionSteps = diffusionSteps
        self.diffusionSchedule = diffusionSchedule
    }
}

// MARK: - ModelLoadConfig

/// Configuration for loading a model into an inference engine.
struct ModelLoadConfig: Sendable, Equatable {

    /// Filesystem path to the model file or directory.
    let modelPath: String

    /// Whether to prefer GPU acceleration if available.
    var preferGPU: Bool

    /// Cache directory for engine-specific artifacts (KV cache, compiled kernels, etc.).
    var cacheDir: String?

    init(
        modelPath: String,
        preferGPU: Bool = true,
        cacheDir: String? = nil
    ) {
        self.modelPath = modelPath
        self.preferGPU = preferGPU
        self.cacheDir = cacheDir
    }
}

// MARK: - InferenceModelInfo

/// Runtime-agnostic metadata about a loaded model.
struct InferenceModelInfo: Sendable, Equatable {

    /// Human-readable model name (e.g., "Gemma-4-E2B-it").
    let name: String

    /// Parameter count description (e.g., "2B", "26B-A4B").
    let parameterCount: String?

    /// Quantization format (e.g., "INT4", "INT8", "FP16").
    let quantization: String?

    /// The runtime type that loaded this model.
    let runtimeType: RuntimeType
}

// MARK: - EngineError

/// Errors produced by the `InferenceEngine` abstraction layer.
enum EngineError: LocalizedError, Equatable {

    /// The requested runtime is recognized but not yet implemented.
    case runtimeNotYetAvailable(RuntimeType)

    /// The model format is not supported by any available engine.
    case unsupportedFormat(String)

    /// The engine is not in a valid state for the requested operation.
    case notReady(String)

    var errorDescription: String? {
        switch self {
        case .runtimeNotYetAvailable(let runtime):
            return "\(runtime.displayName) runtime is recognized but not yet available. Check back in a future release."
        case .unsupportedFormat(let format):
            return "Unsupported model format: \(format). Supported formats: LiteRT-LM, MLX, GGUF."
        case .notReady(let reason):
            return "Engine not ready: \(reason)"
        }
    }
}
