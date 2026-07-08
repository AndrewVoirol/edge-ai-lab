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

#if canImport(LlamaCpp)
import LlamaCpp
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

    #if canImport(LlamaCpp)
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

    // MARK: - Loading

    func loadModel(config: ModelLoadConfig) async throws {
        #if canImport(LlamaCpp)
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

                // Extract model info
                let vocab = llama_model_get_vocab(loadedModel)
                let vocabSize = llama_vocab_n_tokens(vocab)
                let nCtx = llama_n_ctx(ctx)

                self._modelInfo = InferenceModelInfo(
                    name: config.modelPath.components(separatedBy: "/").last ?? "GGUF Model",
                    parameterCount: nil,
                    contextLength: Int(nCtx),
                    vocabularySize: Int(vocabSize),
                    quantization: nil  // Could parse from filename but not reliable
                )

                self._isLoaded = true

                // Seed conversation with system message if provided
                self.conversationHistory.removeAll()
                if let systemMsg = config.systemMessage, !systemMsg.isEmpty {
                    self.conversationHistory.append((role: "system", content: systemMsg))
                }

                Self.signposter.endInterval("ModelLoad", loadState, "vocab=\(vocabSize), ctx=\(nCtx)")
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
        AsyncThrowingStream { continuation in
            #if canImport(LlamaCpp)
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
                    decodeTokenCount: nGenerated,
                    promptTokenCount: promptTokens.count,
                    prefillTimeSeconds: promptTime
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
        #if canImport(LlamaCpp)
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
            self.conversationHistory.removeAll()
        }
        #endif
    }

    func resetConversation() async throws {
        #if canImport(LlamaCpp)
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

    #if canImport(LlamaCpp)
    /// Apply the chat template from GGUF metadata, falling back to hardcoded Gemma template.
    private func applyChatTemplate(model: OpaquePointer) throws -> String {
        let messages = conversationHistory.map { msg -> llama_chat_message in
            // These strings need to live until after the C call completes
            let role = strdup(msg.role)!
            let content = strdup(msg.content)!
            return llama_chat_message(role: role, content: content)
        }
        defer {
            for msg in messages {
                free(UnsafeMutablePointer(mutating: msg.role))
                free(UnsafeMutablePointer(mutating: msg.content))
            }
        }

        // First pass: determine required buffer size
        let needed = llama_chat_apply_template(
            nil,       // NULL → read template from GGUF metadata
            messages,
            messages.count,
            true,      // add assistant turn prompt
            nil,
            0
        )

        if needed > 0 {
            // Second pass: render into buffer
            var buffer = [CChar](repeating: 0, count: Int(needed) + 1)
            let written = llama_chat_apply_template(
                nil,
                messages,
                messages.count,
                true,
                &buffer,
                Int32(buffer.count)
            )
            if written > 0 {
                return String(cString: buffer)
            }
        }

        // Fallback: hardcoded Gemma template
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

/// Hardcoded Gemma chat template for GGUF files that lack `tokenizer.chat_template` metadata.
///
/// Format:
/// ```
/// <start_of_turn>user
/// Hello<end_of_turn>
/// <start_of_turn>model
/// ```
enum GemmaChatTemplateFallback {
    static func apply(messages: [(role: String, content: String)], addGenerationPrompt: Bool) -> String {
        var result = ""
        for msg in messages {
            let role = msg.role == "assistant" ? "model" : msg.role
            result += "<start_of_turn>\(role)\n\(msg.content.trimmingCharacters(in: .whitespaces))<end_of_turn>\n"
        }
        if addGenerationPrompt {
            result += "<start_of_turn>model\n"
        }
        return result
    }
}
