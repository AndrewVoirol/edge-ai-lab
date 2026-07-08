// Copyright 2026 Andrew Voirol. Apache-2.0
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
import os

#if canImport(llama)
import llama
#endif

// MARK: - GGUFEngineAdapter

/// Inference engine adapter for GGUF models via llama.cpp.
///
/// Wraps the llama.cpp C API (via our local `LlamaCpp` SPM package) to conform
/// to the `InferenceEngine` protocol. This is the same adapter pattern used by
/// `LiteRTEngineAdapter` (wraps LiteRT-LM SDK) and `MLXEngineAdapter` (wraps mlx-swift-lm).
///
/// ## Thread Safety
///
/// All llama.cpp calls execute on a serial `DispatchQueue` (`llamaQueue`).
/// The adapter is `@unchecked Sendable` — same pattern as `MLXEngineAdapter`.
///
/// ## Memory Management
///
/// llama.cpp uses manual C-style memory management:
/// - `llama_model*` — freed via `llama_model_free()`
/// - `llama_context*` — freed via `llama_free()`
/// - `llama_sampler*` — freed via `llama_sampler_free()`
///
/// All are released in `shutdown()`. The adapter tracks load state via `_isLoaded`.
///
/// ## Chat Template
///
/// Uses `llama_chat_apply_template()` which reads the Jinja template embedded in
/// GGUF metadata (`tokenizer.chat_template`). Falls back to a hardcoded Gemma
/// template if the GGUF file has no template metadata.
final class GGUFEngineAdapter: InferenceEngine, @unchecked Sendable {

    // MARK: - OSSignposter

    private static let signposter = OSSignposter(
        subsystem: "com.andrewvoirol.EdgeAILab",
        category: "gguf"
    )

    // MARK: - State

    #if canImport(llama)
    private var model: OpaquePointer?    // llama_model*
    private var context: OpaquePointer?  // llama_context*
    #endif

    private var _isLoaded = false
    private var _modelInfo: InferenceModelInfo?
    private var _lastMetrics: EnginePerformanceMetrics?
    private var _cancelled = false

    /// Serial queue for all llama.cpp operations.
    private let llamaQueue = DispatchQueue(label: "com.andrewvoirol.EdgeAILab.gguf", qos: .userInitiated)

    /// Conversation history for multi-turn chat template application.
    private var conversationHistory: [(role: String, content: String)] = []

    // MARK: - InferenceEngine Protocol

    var isLoaded: Bool { _isLoaded }
    var modelInfo: InferenceModelInfo? { _modelInfo }
    nonisolated let runtimeType: RuntimeType = .gguf
    var lastPerformanceMetrics: EnginePerformanceMetrics? { _lastMetrics }
    var lastBackendResult: BackendResult? { nil }
    var lastInferenceMetrics: InferenceMetrics? { nil }
    var supportsVision: Bool { false }
    var supportsToolCalling: Bool { false }

    /// Rich metadata extracted from the loaded GGUF model via llama.cpp API.
    /// Available after `loadModel()` succeeds. `nil` before loading.
    private(set) var ggufMetadata: GGUFLoadedMetadata? { get { _ggufMetadata } set { _ggufMetadata = newValue } }
    private var _ggufMetadata: GGUFLoadedMetadata?

    // MARK: - Loading

    func loadModel(config: ModelLoadConfig) async throws {
        #if canImport(llama)
        let signpostID = Self.signposter.makeSignpostID()
        let loadState = Self.signposter.beginInterval("ModelLoad", id: signpostID, "path=\(config.modelPath)")

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            llamaQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(throwing: EngineError.notReady("Engine was deallocated during model load"))
                    return
                }

                // Initialize backend (idempotent — safe to call multiple times)
                llama_backend_init()

                // Configure model params
                var modelParams = llama_model_default_params()
                if config.preferGPU {
                    modelParams.n_gpu_layers = -1  // Offload all layers to Metal
                } else {
                    modelParams.n_gpu_layers = 0   // CPU only
                }

                // Load model from GGUF file
                guard let loadedModel = llama_model_load_from_file(config.modelPath, modelParams) else {
                    Self.signposter.endInterval("ModelLoad", loadState, "FAILED")
                    continuation.resume(throwing: EngineError.modelLoadFailed(
                        "Failed to load GGUF model from: \(config.modelPath)"
                    ))
                    return
                }
                self.model = loadedModel

                // Configure context params
                var ctxParams = llama_context_default_params()
                if let maxTokens = config.maxNumTokens {
                    ctxParams.n_ctx = UInt32(maxTokens)
                } else {
                    ctxParams.n_ctx = 4096  // Reasonable default for chat
                }
                ctxParams.n_batch = 512

                // Create context
                guard let ctx = llama_init_from_model(loadedModel, ctxParams) else {
                    llama_model_free(loadedModel)
                    self.model = nil
                    Self.signposter.endInterval("ModelLoad", loadState, "FAILED — context creation")
                    continuation.resume(throwing: EngineError.modelLoadFailed(
                        "Failed to create llama.cpp context"
                    ))
                    return
                }
                self.context = ctx

                // Extract model metadata from llama.cpp API (not filename guessing)
                let vocab = llama_model_get_vocab(loadedModel)
                let vocabSize = llama_vocab_n_tokens(vocab)
                let nCtx = llama_n_ctx(ctx)
                let nParams = llama_model_n_params(loadedModel)
                let nCtxTrain = llama_model_n_ctx_train(loadedModel)

                // Read model description (e.g., "gemma4 2B Q4_K - Medium")
                var descBuf = [CChar](repeating: 0, count: 256)
                llama_model_desc(loadedModel, &descBuf, descBuf.count)
                let modelDesc = String(cString: descBuf)

                // Read model name from GGUF metadata
                var nameBuf = [CChar](repeating: 0, count: 256)
                let nameLen = llama_model_meta_val_str(loadedModel, "general.name", &nameBuf, nameBuf.count)
                let modelName = nameLen > 0 ? String(cString: nameBuf) : config.modelPath.components(separatedBy: "/").last ?? "GGUF Model"

                // Read architecture
                var archBuf = [CChar](repeating: 0, count: 64)
                let archLen = llama_model_meta_val_str(loadedModel, "general.architecture", &archBuf, archBuf.count)
                let architecture = archLen > 0 ? String(cString: archBuf) : "GGUF"

                // Read size label (e.g., "4.6B")
                var sizeBuf = [CChar](repeating: 0, count: 64)
                let sizeLen = llama_model_meta_val_str(loadedModel, "general.size_label", &sizeBuf, sizeBuf.count)
                let sizeLabel = sizeLen > 0 ? String(cString: sizeBuf) : nil

                // Parse quantization from model description (format: "arch params quant")
                let descParts = modelDesc.components(separatedBy: " ")
                let quantization = descParts.count >= 3 ? descParts.dropFirst(2).joined(separator: " ") : nil

                // Format parameter count for display
                let paramDisplay: String
                if let sizeLabel {
                    paramDisplay = sizeLabel
                } else if nParams > 1_000_000_000 {
                    paramDisplay = String(format: "%.1fB", Double(nParams) / 1_000_000_000.0)
                } else if nParams > 1_000_000 {
                    paramDisplay = String(format: "%.0fM", Double(nParams) / 1_000_000.0)
                } else {
                    paramDisplay = "\(nParams)"
                }

                self._modelInfo = InferenceModelInfo(
                    name: modelName,
                    parameterCount: paramDisplay,
                    quantization: quantization,
                    runtimeType: .gguf
                )

                // Store extracted metadata for UI consumption
                self._ggufMetadata = GGUFLoadedMetadata(
                    name: modelName,
                    architecture: architecture,
                    parameterCount: nParams,
                    sizeLabel: sizeLabel,
                    quantization: quantization,
                    contextLengthTrain: Int(nCtxTrain),
                    contextLengthActive: Int(nCtx),
                    vocabSize: Int(vocabSize),
                    modelSizeBytes: Int64(llama_model_size(loadedModel))
                )

                self._isLoaded = true

                // Seed conversation with system message if provided
                self.conversationHistory.removeAll()
                if let systemMsg = config.systemMessage, !systemMsg.isEmpty {
                    self.conversationHistory.append((role: "system", content: systemMsg))
                }

                Self.signposter.endInterval("ModelLoad", loadState, "name=\(modelName), params=\(paramDisplay), ctx=\(nCtx), quant=\(quantization ?? "none")")
                continuation.resume()
            }
        }
        #else
        throw EngineError.runtimeNotYetAvailable(.gguf)
        #endif
    }

    // MARK: - Generation

    func generateStream(
        prompt: String,
        config: GenerationConfig
    ) -> AsyncThrowingStream<GenerationEvent, Error> {
        AsyncThrowingStream<GenerationEvent, Error>(bufferingPolicy: .unbounded) { (continuation: AsyncThrowingStream<GenerationEvent, Error>.Continuation) in
            #if canImport(llama)
            llamaQueue.async { [weak self] in
                guard let self, let model = self.model, let ctx = self.context else {
                    continuation.finish(throwing: EngineError.modelNotLoaded)
                    return
                }

                let signpostID = Self.signposter.makeSignpostID()
                let inferenceState = Self.signposter.beginInterval("Inference", id: signpostID, "prompt=\(prompt.prefix(50))...")

                self._cancelled = false

                // Add user message to conversation history
                self.conversationHistory.append((role: "user", content: prompt))

                // Apply chat template
                let formattedPrompt: String
                do {
                    formattedPrompt = try self.applyChatTemplate(model: model)
                } catch {
                    continuation.finish(throwing: error)
                    return
                }

                // Tokenize
                let vocab = llama_model_get_vocab(model)
                let utf8Count = formattedPrompt.utf8.count
                let maxTokens = utf8Count + 2  // Conservative estimate
                var tokens = [llama_token](repeating: 0, count: maxTokens)
                let tokenCount = llama_tokenize(
                    vocab,
                    formattedPrompt,
                    Int32(utf8Count),
                    &tokens,
                    Int32(maxTokens),
                    true,  // add BOS
                    true   // special tokens
                )

                guard tokenCount > 0 else {
                    Self.signposter.endInterval("Inference", inferenceState, "FAILED — tokenization")
                    continuation.finish(throwing: EngineError.generationFailed("Failed to tokenize prompt"))
                    return
                }

                let promptTokens = Array(tokens.prefix(Int(tokenCount)))
                let nCtx = Int(llama_n_ctx(ctx))

                // Reset KV cache position tracking for this generation
                llama_memory_clear(llama_get_memory(ctx), true)

                // Create batch and process prompt
                var batch = llama_batch_init(Int32(promptTokens.count), 0, 1)
                defer { llama_batch_free(batch) }

                // Fill batch with prompt tokens
                batch.n_tokens = Int32(promptTokens.count)
                for i in 0..<promptTokens.count {
                    batch.token[i] = promptTokens[i]
                    batch.pos[i] = Int32(i)
                    batch.n_seq_id[i] = 1
                    if let seqIds = batch.seq_id, let seqId = seqIds[i] {
                        seqId[0] = 0
                    }
                    batch.logits[i] = 0
                }
                // Only compute logits for the last token
                if batch.n_tokens > 0 {
                    batch.logits[Int(batch.n_tokens) - 1] = 1
                }

                // Evaluate prompt
                let promptStartTime = CFAbsoluteTimeGetCurrent()
                guard llama_decode(ctx, batch) == 0 else {
                    Self.signposter.endInterval("Inference", inferenceState, "FAILED — decode")
                    continuation.finish(throwing: EngineError.generationFailed("llama_decode failed on prompt"))
                    return
                }

                // Build sampler chain
                let sampler = GGUFSamplerBuilder.build(from: config)
                defer { llama_sampler_free(sampler) }

                // Token generation loop
                let generationStartTime = CFAbsoluteTimeGetCurrent()
                var firstTokenTime: CFAbsoluteTime?
                var generatedText = ""
                var nGenerated = 0
                var nCur = batch.n_tokens
                let maxGenTokens = min(config.maxTokens, nCtx - Int(nCur))

                for _ in 0..<maxGenTokens {
                    // Check cancellation
                    if self._cancelled {
                        break
                    }

                    // Sample next token
                    let nextToken = llama_sampler_sample(sampler, ctx, batch.n_tokens - 1)

                    // Check for EOS
                    if llama_vocab_is_eog(vocab, nextToken) {
                        break
                    }

                    // Skip control tokens that aren't marked as EOG
                    // (e.g., <bos>, <pad>, <mask>, <|think|>).
                    if llama_vocab_is_control(vocab, nextToken) {
                        break
                    }

                    // Record TTFT
                    if firstTokenTime == nil {
                        firstTokenTime = CFAbsoluteTimeGetCurrent()
                    }

                    // Convert token to text
                    var buffer = [CChar](repeating: 0, count: 256)
                    let length = llama_token_to_piece(vocab, nextToken, &buffer, Int32(buffer.count), 0, false)
                    if length > 0 {
                        buffer[Int(length)] = 0  // Null-terminate
                        let tokenText = String(cString: buffer)
                        generatedText += tokenText
                        nGenerated += 1

                        // Yield text event
                        continuation.yield(.text(tokenText))
                    }

                    // Prepare batch for next token
                    batch.n_tokens = 1
                    batch.token[0] = nextToken
                    batch.pos[0] = nCur
                    batch.n_seq_id[0] = 1
                    if let seqIds = batch.seq_id, let seqId = seqIds[0] {
                        seqId[0] = 0
                    }
                    batch.logits[0] = 1
                    nCur += 1

                    // Decode
                    guard llama_decode(ctx, batch) == 0 else {
                        continuation.finish(throwing: EngineError.generationFailed("llama_decode failed during generation"))
                        return
                    }
                }

                // Compute metrics
                let generationEndTime = CFAbsoluteTimeGetCurrent()
                let totalGenTime = generationEndTime - generationStartTime
                let promptTime = generationStartTime - promptStartTime
                let ttft = firstTokenTime.map { $0 - promptStartTime }

                let tokPerSec = nGenerated > 0 ? Double(nGenerated) / totalGenTime : 0
                let promptTokPerSec = promptTokens.count > 0 ? Double(promptTokens.count) / promptTime : 0

                let metrics = EnginePerformanceMetrics(
                    tokensPerSecond: tokPerSec,
                    promptTokensPerSecond: promptTokPerSec,
                    timeToFirstToken: ttft,
                    peakMemoryBytes: nil,
                    tokenCount: nGenerated,
                    runtimeType: .gguf,
                    promptTokenCount: promptTokens.count,
                    promptTimeSeconds: promptTime,
                    generateTimeSeconds: totalGenTime
                )
                self._lastMetrics = metrics

                // Add assistant response to history
                self.conversationHistory.append((role: "assistant", content: generatedText))

                // Yield metrics and done
                continuation.yield(.metrics(metrics))
                continuation.yield(.done)

                Self.signposter.endInterval(
                    "Inference", inferenceState,
                    "\(nGenerated) tok, \(String(format: "%.1f", tokPerSec)) tok/s, TTFT=\(ttft.map { String(format: "%.0f", $0 * 1000) + "ms" } ?? "N/A")"
                )

                continuation.finish()
            }
            #else
            continuation.finish(throwing: EngineError.runtimeNotYetAvailable(.gguf))
            #endif
        }
    }

    // MARK: - Lifecycle

    func shutdown() {
        #if canImport(llama)
        llamaQueue.sync { [weak self] in
            guard let self else { return }
            if let ctx = self.context {
                llama_free(ctx)
                self.context = nil
            }
            if let mdl = self.model {
                llama_model_free(mdl)
                self.model = nil
            }
            llama_backend_free()
            self._isLoaded = false
            self._modelInfo = nil
            self._lastMetrics = nil
            self._ggufMetadata = nil
            self.conversationHistory.removeAll()
        }
        #endif
    }

    func resetConversation() async throws {
        #if canImport(llama)
        llamaQueue.sync { [weak self] in
            guard let self, let ctx = self.context else { return }
            llama_memory_clear(llama_get_memory(ctx), true)
            self.conversationHistory.removeAll()
        }
        #endif
    }

    func cancelGeneration() {
        _cancelled = true
    }

    func warmup() async throws {
        // Short throwaway generation to prime caches
        var collected = ""
        for try await event in generateStream(prompt: "Hi", config: GenerationConfig(maxTokens: 1)) {
            if case .text(let t) = event { collected += t }
        }
        // Clear warmup from conversation history
        if conversationHistory.count >= 2 {
            conversationHistory.removeLast(2)
        }
    }

    // MARK: - Chat Template

    #if canImport(llama)
    /// Apply the Gemma chat template to format conversation history for inference.
    ///
    /// We intentionally bypass `llama_chat_apply_template()` which reads the Jinja
    /// template embedded in the GGUF metadata. The Unsloth-converted Gemma 4 GGUF
    /// contains a Jinja template that renders ChatML format with `<|im_end>` — a token
    /// that does NOT exist as a special token in Gemma 4's vocabulary (EOG tokens are
    /// `<eos>` (1), `<turn|>` (106), `<|tool_response>` (50)). This causes `<|im_end>`
    /// to be tokenized as regular BPE pieces and echoed verbatim in the model's output.
    ///
    /// The correct Gemma 4 format uses `<start_of_turn>` / `<end_of_turn>` which map to
    /// `<turn|>` (token 106) — a recognized EOG token that properly terminates generation.
    private func applyChatTemplate(model: OpaquePointer) throws -> String {
        return GemmaChatTemplateFallback.apply(
            messages: conversationHistory,
            addGenerationPrompt: true
        )
    }
    #endif

    deinit {
        shutdown()
    }
}

// MARK: - Gemma Chat Template Fallback

/// Hardcoded Gemma 4 chat template using the vocabulary's actual special token strings.
///
/// Gemma 4's GGUF vocabulary defines:
/// - Token 105: `<|turn>`  — start of turn (control token)
/// - Token 106: `<turn|>`  — end of turn (EOG token)
///
/// This differs from Gemma 2 which used `<start_of_turn>` / `<end_of_turn>`.
/// Using the exact token strings ensures `llama_tokenize(parse_special: true)` maps
/// them to their special token IDs, so `llama_vocab_is_eog()` correctly catches
/// the end-of-turn token during generation.
///
/// Format:
/// ```
/// <|turn>user
/// Hello<turn|>
/// <|turn>model
/// ```
enum GemmaChatTemplateFallback {
    static func apply(messages: [(role: String, content: String)], addGenerationPrompt: Bool) -> String {
        var result = ""
        for msg in messages {
            let role = msg.role == "assistant" ? "model" : msg.role
            result += "<|turn>\(role)\n\(msg.content.trimmingCharacters(in: .whitespaces))<turn|>\n"
        }
        if addGenerationPrompt {
            result += "<|turn>model\n"
        }
        return result
    }
}

// MARK: - GGUF Loaded Metadata

/// Metadata extracted from a loaded GGUF model via llama.cpp's C API.
///
/// All fields are populated from actual model data at load time — none are
/// estimated from filenames or file sizes. This replaces the filename-parsing
/// heuristics in `DiscoveredModel.synthesizeMetadata()` for loaded models.
struct GGUFLoadedMetadata: Sendable {
    /// Model name from `general.name` GGUF metadata key.
    let name: String

    /// Model architecture from `general.architecture` (e.g., "gemma4", "llama").
    let architecture: String

    /// Total parameter count from `llama_model_n_params()`.
    let parameterCount: UInt64

    /// Size label from `general.size_label` (e.g., "4.6B"). May be nil.
    let sizeLabel: String?

    /// Quantization string parsed from `llama_model_desc()` (e.g., "Q4_K - Medium").
    let quantization: String?

    /// Maximum context length the model was trained with.
    let contextLengthTrain: Int

    /// Active context length configured for this session.
    let contextLengthActive: Int

    /// Vocabulary size (total tokens).
    let vocabSize: Int

    /// Model file size in bytes from `llama_model_size()`.
    let modelSizeBytes: Int64

    /// Estimated minimum RAM in GB (model size + ~20% overhead for KV cache and buffers).
    var estimatedMinRAMGB: Int {
        max(2, Int(ceil(Double(modelSizeBytes) / 1_073_741_824.0 * 1.2)))
    }
}
