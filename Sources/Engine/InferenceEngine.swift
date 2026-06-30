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

// MARK: - GenerationEvent

/// Events emitted during generation — unified across all runtimes.
///
/// Consumers iterate over `AsyncThrowingStream<GenerationEvent, Error>` and switch
/// on each case. This replaces the old `AsyncThrowingStream<String, Error>` to
/// support tool calling and per-generation metrics alongside text streaming.
enum GenerationEvent: Sendable {
    /// A text token or chunk.
    case text(String)
    /// A tool call detected in the model output.
    case toolCall(AppToolCall)
    /// Performance metrics for the completed generation.
    case metrics(EnginePerformanceMetrics)
    /// Generation completed normally.
    case done
}

// MARK: - AppToolCall

/// App-local tool call representation (runtime-agnostic).
///
/// Both LiteRT-LM and MLX emit tool calls in different formats; their respective
/// adapters convert to this common type before yielding `.toolCall` events.
struct AppToolCall: Sendable, Codable, Equatable {
    let id: String
    let toolName: String
    let arguments: [String: String]
}

// MARK: - EnginePerformanceMetrics

/// Runtime-agnostic performance metrics for a completed generation.
///
/// Populated from `BenchmarkInfo` (LiteRT-LM) or `GenerateCompletionInfo` (MLX).
struct EnginePerformanceMetrics: Sendable, Equatable, Codable {
    /// Tokens generated per second (decode speed).
    let tokensPerSecond: Double
    /// Prompt tokens processed per second (prefill speed). MLX provides this natively.
    let promptTokensPerSecond: Double?
    /// Time to first token in seconds.
    let timeToFirstToken: Double?
    /// Peak memory usage in bytes during generation.
    let peakMemoryBytes: UInt64?
    /// Number of tokens generated.
    let tokenCount: Int?
    /// Memory delta in MB during inference (footprint change).
    let memoryDeltaMB: Double?
    /// Whether the thermal state changed during inference.
    let thermalStateChanged: Bool?
    /// The runtime that produced these metrics.
    let runtimeType: RuntimeType
}

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
/// - **Streaming (`generateStream`):** Yields `GenerationEvent` values as they occur.
///   Text tokens arrive as `.text(String)`, tool calls as `.toolCall(AppToolCall)`,
///   and performance metrics as `.metrics(EnginePerformanceMetrics)`.
///
/// - **Batch (`generateBatch`):** Returns the complete response as a single string.
///   Used by diffusion models (e.g., DiffusionGemma) that produce all tokens in parallel
///   across multiple refinement steps. Also useful for autoregressive models when streaming
///   is not needed (the default implementation collects `.text` events).
///
/// ## Conformance
///
/// - `LiteRTEngineAdapter` wraps `InstrumentedEngine` for LiteRT-LM models.
/// - `MLXEngineAdapter` wraps `mlx-swift-lm` for MLX models.
/// - Future: `GGUFEngine` for additional runtimes.
protocol InferenceEngine: AnyObject, Sendable {

    // MARK: - Loading

    /// Load a model from a filesystem path or HuggingFace identifier.
    ///
    /// - Parameter config: Configuration specifying the model path and load options.
    /// - Throws: If the model file is missing, corrupt, or incompatible with this runtime.
    func loadModel(config: ModelLoadConfig) async throws

    /// Whether a model is currently loaded and ready for inference.
    var isLoaded: Bool { get }

    /// Information about the currently loaded model, or nil if no model is loaded.
    var modelInfo: InferenceModelInfo? { get }

    /// The runtime backend this engine uses.
    var runtimeType: RuntimeType { get }

    // MARK: - Generation

    /// Generate a streaming response for the given prompt.
    ///
    /// Each element in the returned stream is a `GenerationEvent`.
    /// The stream completes with `.done` when generation finishes normally.
    ///
    /// - Parameters:
    ///   - prompt: The input text prompt.
    ///   - config: Generation parameters (temperature, maxTokens, etc.).
    /// - Returns: An `AsyncThrowingStream` of `GenerationEvent` values.
    func generateStream(
        prompt: String,
        config: GenerationConfig
    ) -> AsyncThrowingStream<GenerationEvent, Error>

    /// Generate a complete response for the given prompt.
    ///
    /// For autoregressive engines, the default implementation collects all `.text` chunks
    /// from `generateStream`. For diffusion engines, this is the native generation mode.
    ///
    /// - Parameters:
    ///   - prompt: The input text prompt.
    ///   - config: Generation parameters (temperature, maxTokens, diffusion steps, etc.).
    /// - Returns: The complete generated text.
    func generateBatch(
        prompt: String,
        config: GenerationConfig
    ) async throws -> String

    // MARK: - Lifecycle

    /// Release all model resources (weights, KV cache, Metal buffers).
    func shutdown()

    /// Reset conversation state (clear KV cache and history) without unloading the model.
    func resetConversation() async throws

    /// Cancel any in-progress generation.
    func cancelGeneration()

    /// Warm up the engine with a short throwaway prompt.
    /// Used before benchmarking to prime caches and counters.
    func warmup() async throws

    // MARK: - Metrics

    /// Performance metrics from the most recent generation, if available.
    var lastPerformanceMetrics: EnginePerformanceMetrics? { get }

    // MARK: - Capabilities

    /// Whether this engine supports vision/image input.
    var supportsVision: Bool { get }

    /// Whether this engine supports tool calling (function calling).
    var supportsToolCalling: Bool { get }
}

// MARK: - Default Implementations

extension InferenceEngine {

    /// Default `generateBatch` collects all `.text` chunks from `generateStream` into a single string.
    /// Diffusion engines should override this with their native batch generation.
    func generateBatch(
        prompt: String,
        config: GenerationConfig
    ) async throws -> String {
        var result = ""
        for try await event in generateStream(prompt: prompt, config: config) {
            if case .text(let chunk) = event {
                result += chunk
            }
        }
        return result
    }

    /// Default: no vision support.
    var supportsVision: Bool { false }

    /// Default: no tool calling support.
    var supportsToolCalling: Bool { false }

    /// Default: no-op cancellation.
    func cancelGeneration() { }

    /// Default warmup: send a short throwaway prompt to prime caches and counters.
    func warmup() async throws {
        _ = try await generateBatch(prompt: "Hi", config: .default)
    }

    /// Default: no metrics available.
    var lastPerformanceMetrics: EnginePerformanceMetrics? { nil }
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
    /// Used by LiteRT-LM; ignored by MLX (which uses topP-only sampling).
    var topK: Int

    /// Repetition penalty multiplier. MLX only; ignored by LiteRT-LM.
    /// Values > 1.0 penalize repeated tokens (e.g., 1.1 is a mild penalty).
    var repetitionPenalty: Double?

    /// Random seed for reproducible generation.
    /// LiteRT-LM uses this natively; MLX uses `MLXRandom.seed()`.
    var seed: UInt64?

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
        repetitionPenalty: nil,
        seed: nil,
        diffusionSteps: nil,
        diffusionSchedule: nil
    )

    init(
        maxTokens: Int = 512,
        temperature: Double = 0.7,
        topP: Double = 0.9,
        topK: Int = 40,
        repetitionPenalty: Double? = nil,
        seed: UInt64? = nil,
        diffusionSteps: Int? = nil,
        diffusionSchedule: String? = nil
    ) {
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.topP = topP
        self.topK = topK
        self.repetitionPenalty = repetitionPenalty
        self.seed = seed
        self.diffusionSteps = diffusionSteps
        self.diffusionSchedule = diffusionSchedule
    }
}

// MARK: - ModelLoadConfig

/// Configuration for loading a model into an inference engine.
struct ModelLoadConfig: Sendable, Equatable {

    /// Filesystem path to the model file, directory, or HuggingFace model ID.
    let modelPath: String

    /// Whether to prefer GPU acceleration if available.
    var preferGPU: Bool

    /// Cache directory for engine-specific artifacts (KV cache, compiled kernels, etc.).
    var cacheDir: String?

    /// System message to prepend to conversations.
    var systemMessage: String?

    /// Tools available for function calling during inference.
    /// Stored as `[any AppTool]` — each adapter bridges to its native format.
    var tools: [any AppTool]?

    /// Whether the model supports vision input.
    var supportsVision: Bool

    /// Whether the model supports audio input.
    var supportsAudio: Bool

    /// Generation parameters to apply at model load time.
    /// LiteRT-LM binds sampler config at conversation creation, so these are set here.
    var generationConfig: GenerationConfig?

    /// LiteRT-LM specific: experimental flags configuration.
    /// Ignored by MLX and other runtimes.
    var experimentalFlags: ExperimentalFlagsState?

    init(
        modelPath: String,
        preferGPU: Bool = true,
        cacheDir: String? = nil,
        systemMessage: String? = nil,
        tools: [any AppTool]? = nil,
        supportsVision: Bool = false,
        supportsAudio: Bool = false,
        generationConfig: GenerationConfig? = nil,
        experimentalFlags: ExperimentalFlagsState? = nil
    ) {
        self.modelPath = modelPath
        self.preferGPU = preferGPU
        self.cacheDir = cacheDir
        self.systemMessage = systemMessage
        self.tools = tools
        self.supportsVision = supportsVision
        self.supportsAudio = supportsAudio
        self.generationConfig = generationConfig
        self.experimentalFlags = experimentalFlags
    }

    /// Manual Equatable — `tools: [any AppTool]?` can't auto-synthesize.
    /// Tools are intentionally excluded from equality since they're existential types.
    static func == (lhs: ModelLoadConfig, rhs: ModelLoadConfig) -> Bool {
        lhs.modelPath == rhs.modelPath
            && lhs.preferGPU == rhs.preferGPU
            && lhs.cacheDir == rhs.cacheDir
            && lhs.systemMessage == rhs.systemMessage
            && lhs.supportsVision == rhs.supportsVision
            && lhs.supportsAudio == rhs.supportsAudio
            && lhs.generationConfig == rhs.generationConfig
            && lhs.experimentalFlags == rhs.experimentalFlags
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
