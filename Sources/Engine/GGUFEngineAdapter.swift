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

    // MARK: - Multimodal (mtmd)
    private var mtmdContext: OpaquePointer?  // mtmd_context*
    #endif

    private var _isLoaded = false
    private var _modelInfo: InferenceModelInfo?
    private var _lastMetrics: EnginePerformanceMetrics?
    private var _cancelled = false

    /// Registered tools for function calling dispatch.
    private var registeredTools: [any AppTool] = []

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
    var supportsVision: Bool {
        #if canImport(llama)
        return mtmdContext != nil && mtmd_support_vision(mtmdContext!)
        #else
        return false
        #endif
    }
    var supportsAudio: Bool {
        #if canImport(llama)
        return mtmdContext != nil && mtmd_support_audio(mtmdContext!)
        #else
        return false
        #endif
    }
    var supportsToolCalling: Bool { !registeredTools.isEmpty }

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
                // n_batch must be large enough to handle tool-augmented system prompts.
                // With 13 tools and JSON schemas, prompts can easily exceed 512 tokens.
                // Setting n_batch = n_ctx allows processing the full prompt in one batch.
                ctxParams.n_batch = ctxParams.n_ctx

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

                // MARK: Multimodal projector loading
                if let mmProjPath = config.mmProjPath {
                    var mtmdParams = mtmd_context_params_default()
                    mtmdParams.use_gpu = config.preferGPU
                    mtmdParams.print_timings = false

                    if let mtmd = mtmd_init_from_file(mmProjPath, loadedModel, mtmdParams) {
                        self.mtmdContext = mtmd
                        let hasVision = mtmd_support_vision(mtmd)
                        let hasAudio = mtmd_support_audio(mtmd)
                        print("[GGUFEngine] Multimodal projector loaded: vision=\(hasVision), audio=\(hasAudio)")
                    } else {
                        print("[GGUFEngine] WARNING: Failed to load multimodal projector from: \(mmProjPath)")
                    }
                }

                // Store registered tools for function calling dispatch
                if let tools = config.tools, !tools.isEmpty {
                    self.registeredTools = tools
                } else {
                    self.registeredTools = []
                }

                // Seed conversation with system message if provided,
                // appending tool descriptions when tools are registered.
                self.conversationHistory.removeAll()
                var systemContent = config.systemMessage ?? ""
                if let toolPrompt = GGUFToolCallParser.toolSystemPrompt(for: self.registeredTools) {
                    systemContent += toolPrompt
                }
                if !systemContent.isEmpty {
                    self.conversationHistory.append((role: "system", content: systemContent))
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

                let nBatch = Int(llama_n_batch(ctx))
                let promptStartTime = CFAbsoluteTimeGetCurrent()

                // MARK: - Multimodal prompt processing
                // If media data is present AND we have an mtmd context, use the
                // multimodal tokenize→eval path. Otherwise fall through to the
                // standard text-only tokenize→decode loop.
                let mediaItems: [Data] = (config.imageData ?? []) + (config.audioData ?? [])
                let imageCount = config.imageData?.count ?? 0
                let useMultimodal = !mediaItems.isEmpty && self.mtmdContext != nil

                var nProcessed = 0
                var lastChunkLogitIdx: Int32 = 0

                if useMultimodal {
                    guard let mtmd = self.mtmdContext else {
                        continuation.finish(throwing: EngineError.generationFailed("mtmd context unexpectedly nil"))
                        return
                    }

                    // Build media markers — one <__media__> per media item, prepended to prompt
                    let markers = mediaItems.map { _ in "<__media__>" }.joined(separator: "\n")
                    let multimodalPrompt = markers + "\n" + formattedPrompt

                    // Create bitmaps from raw data buffers
                    // mtmd_helper_bitmap_init_from_buf returns mtmd_helper_bitmap_wrapper struct
                    // containing .bitmap (mtmd_bitmap*) and .video_ctx. We extract .bitmap.
                    var bitmaps: [OpaquePointer] = []
                    var bitmapCleanup: [OpaquePointer] = []
                    defer {
                        for bmp in bitmapCleanup {
                            mtmd_bitmap_free(bmp)
                        }
                    }

                    for (index, data) in mediaItems.enumerated() {
                        // Items at indices [0..<imageCount] are image data,
                        // items at indices [imageCount...] are audio data.
                        let isAudio = index >= imageCount
                        let bitmap: OpaquePointer? = data.withUnsafeBytes { rawBuf -> OpaquePointer? in
                            guard let baseAddr = rawBuf.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                                return nil
                            }
                            let wrapper = mtmd_helper_bitmap_init_from_buf(mtmd, baseAddr, rawBuf.count, isAudio)
                            return wrapper.bitmap
                        }
                        guard let bmp = bitmap else {
                            print("[GGUFEngine] WARNING: Failed to create bitmap for media item \(index)")
                            Self.signposter.endInterval("Inference", inferenceState, "FAILED — bitmap creation")
                            continuation.finish(throwing: EngineError.generationFailed(
                                "Failed to create mtmd bitmap from media data (item \(index))"
                            ))
                            return
                        }
                        bitmaps.append(bmp)
                        bitmapCleanup.append(bmp)
                    }

                    // Tokenize text+media into chunks
                    guard let chunks = mtmd_input_chunks_init() else {
                        Self.signposter.endInterval("Inference", inferenceState, "FAILED — chunks init")
                        continuation.finish(throwing: EngineError.generationFailed("Failed to init mtmd input chunks"))
                        return
                    }
                    defer { mtmd_input_chunks_free(chunks) }

                    // Set up mtmd_input_text (plain C struct)
                    var inputText = mtmd_input_text(
                        text: nil,
                        add_special: true,
                        parse_special: true
                    )

                    let tokenizeResult: Int32 = multimodalPrompt.withCString { cStr in
                        inputText.text = cStr
                        // Swift imports `const mtmd_bitmap **` as `UnsafeMutablePointer<OpaquePointer?>?`
                        var optionalBitmaps: [OpaquePointer?] = bitmaps.map { Optional($0) }
                        return optionalBitmaps.withUnsafeMutableBufferPointer { bmpBuf -> Int32 in
                            return withUnsafePointer(to: &inputText) { textPtr in
                                mtmd_tokenize(mtmd, chunks, textPtr, bmpBuf.baseAddress, bitmaps.count)
                            }
                        }
                    }

                    guard tokenizeResult == 0 else {
                        let errDesc: String
                        switch tokenizeResult {
                        case 1: errDesc = "bitmap count mismatch with markers"
                        case 2: errDesc = "image preprocessing error"
                        default: errDesc = "unknown error (\(tokenizeResult))"
                        }
                        print("[GGUFEngine] Multimodal tokenize failed: \(errDesc)")
                        Self.signposter.endInterval("Inference", inferenceState, "FAILED — mtmd_tokenize")
                        continuation.finish(throwing: EngineError.generationFailed(
                            "mtmd_tokenize failed: \(errDesc)"
                        ))
                        return
                    }

                    let totalMmTokens = mtmd_helper_get_n_tokens(chunks)
                    print("[GGUFEngine] Multimodal tokenized: \(totalMmTokens) total tokens from \(mediaItems.count) media item(s)")

                    // Eval all chunks (text + encoded media) through the model
                    var newNPast: llama_pos = 0
                    let evalResult = mtmd_helper_eval_chunks(
                        mtmd,
                        ctx,
                        chunks,
                        0,          // n_past
                        0,          // seq_id
                        Int32(nBatch),
                        true,       // logits_last
                        &newNPast
                    )

                    guard evalResult == 0 else {
                        print("[GGUFEngine] mtmd_helper_eval_chunks failed with code \(evalResult)")
                        Self.signposter.endInterval("Inference", inferenceState, "FAILED — mtmd eval")
                        continuation.finish(throwing: EngineError.generationFailed(
                            "mtmd_helper_eval_chunks failed (code \(evalResult))"
                        ))
                        return
                    }

                    nProcessed = Int(newNPast)
                    // After mtmd_helper_eval_chunks with logits_last=true,
                    // the logits are at the last position of the last internal batch.
                    // The sampler should use index = (batch.n_tokens - 1) of the last batch.
                    // Since eval_chunks handles batching internally, we need to compute
                    // the index. For simplicity, use -1 which means "last token" in
                    // the llama_decode context. Actually, llama_sampler_sample uses
                    // the index into the last llama_decode call's batch. With
                    // logits_last=true, eval_chunks ensures the last token has logits.
                    // The batch size of the last internal decode varies, so we get
                    // n_tokens from the llama context.
                    lastChunkLogitIdx = Int32(nProcessed - 1)
                    // Actually, llama_sampler_sample takes the index into the
                    // logits array of the LAST llama_decode call. Since
                    // mtmd_helper_eval_chunks does multiple llama_decode calls
                    // internally, the last call's batch.n_tokens - 1 is what we want.
                    // The safest approach: use the llama_decode output directly.
                    // For now, we use -1 which llama_sampler_sample interprets as
                    // "the last logits position".
                    lastChunkLogitIdx = -1

                    print("[GGUFEngine] Multimodal eval complete: n_past=\(newNPast)")

                } else {
                    // MARK: - Standard text-only prompt processing
                    // Process prompt in chunks of n_batch to avoid exceeding llama.cpp's
                    // batch size limit. This is critical when tool descriptions inflate the
                    // system prompt beyond n_batch tokens.
                    // Track the logit index from the last chunk for the first sampler call.
                    // llama_sampler_sample uses this index into the decoded batch's logits.

                    while nProcessed < promptTokens.count {
                        let chunkSize = min(nBatch, promptTokens.count - nProcessed)
                        let isLastChunk = (nProcessed + chunkSize) >= promptTokens.count

                        var batch = llama_batch_init(Int32(chunkSize), 0, 1)
                        batch.n_tokens = Int32(chunkSize)
                        for i in 0..<chunkSize {
                            batch.token[i] = promptTokens[nProcessed + i]
                            batch.pos[i] = Int32(nProcessed + i)
                            batch.n_seq_id[i] = 1
                            if let seqIds = batch.seq_id, let seqId = seqIds[i] {
                                seqId[0] = 0
                            }
                            // Only compute logits for the very last token of the entire prompt
                            batch.logits[i] = (isLastChunk && i == chunkSize - 1) ? 1 : 0
                        }

                        guard llama_decode(ctx, batch) == 0 else {
                            llama_batch_free(batch)
                            Self.signposter.endInterval("Inference", inferenceState, "FAILED — decode")
                            continuation.finish(throwing: EngineError.generationFailed("llama_decode failed on prompt chunk"))
                            return
                        }
                        // The logit index for sampling is the last token position in this batch
                        lastChunkLogitIdx = batch.n_tokens - 1
                        llama_batch_free(batch)
                        nProcessed += chunkSize
                    }
                }

                // Build sampler chain
                let sampler = GGUFSamplerBuilder.build(from: config)
                defer { llama_sampler_free(sampler) }

                // Token generation loop
                let generationStartTime = CFAbsoluteTimeGetCurrent()
                var firstTokenTime: CFAbsoluteTime?
                var generatedText = ""
                var nGenerated = 0
                var nCur = useMultimodal ? Int32(nProcessed) : Int32(promptTokens.count)
                let maxGenTokens = min(config.maxTokens, nCtx - Int(nCur))

                // Single-token batch for autoregressive generation
                var genBatch = llama_batch_init(1, 0, 1)
                defer { llama_batch_free(genBatch) }

                // The sampler needs the index of the last logits position.
                // After prompt processing, that's the last token in the last chunk.
                // After each generation step, it's always index 0 in genBatch.
                var samplerIdx: Int32 = lastChunkLogitIdx

                for _ in 0..<maxGenTokens {
                    // Check cancellation
                    if self._cancelled {
                        break
                    }

                    // Sample next token
                    let nextToken = llama_sampler_sample(sampler, ctx, samplerIdx)

                    // Check for EOS
                    if llama_vocab_is_eog(vocab, nextToken) {
                        break
                    }

                    // Skip control tokens that aren't marked as EOG.
                    // These include <bos>, <pad>, <mask>, <|think|>, <|tool|>, etc.
                    // Important: do NOT break here — Gemma 4 emits <|think|> at the
                    // start of responses (thinking mode). Breaking on it would produce
                    // empty responses. Only EOG tokens (checked above) should terminate.
                    if llama_vocab_is_control(vocab, nextToken) {
                        // BOS re-emission is always wrong — stop to prevent loops.
                        let vocab_bos = llama_vocab_bos(vocab)
                        if nextToken == vocab_bos {
                            break
                        }
                        // All other control tokens: skip (don't include in output).
                        continue
                    }

                    // Record TTFT and emit FirstToken signpost event
                    if firstTokenTime == nil {
                        firstTokenTime = CFAbsoluteTimeGetCurrent()
                        let ttftMs = (firstTokenTime! - promptStartTime) * 1000
                        Self.signposter.emitEvent(
                            "FirstToken",
                            "TTFT=\(String(format: "%.1f", ttftMs))ms"
                        )
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

                    // Prepare single-token batch for next decode step
                    genBatch.n_tokens = 1
                    genBatch.token[0] = nextToken
                    genBatch.pos[0] = nCur
                    genBatch.n_seq_id[0] = 1
                    if let seqIds = genBatch.seq_id, let seqId = seqIds[0] {
                        seqId[0] = 0
                    }
                    genBatch.logits[0] = 1
                    nCur += 1
                    samplerIdx = 0  // After first decode, logits are at index 0

                    // Decode
                    guard llama_decode(ctx, genBatch) == 0 else {
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

                // Parse tool calls from generated text and yield events.
                // The model may embed function_call JSON in its response when tools
                // are registered. We detect and dispatch them here, yielding
                // .toolCall events before .metrics/.done.
                // NOTE: Tool execution is the responsibility of the consumer
                // (EvalRunner, ConversationViewModel), not the engine adapter.
                // The adapter only detects and yields tool call events.
                if !self.registeredTools.isEmpty,
                   GGUFToolCallParser.mightContainToolCall(generatedText) {
                    let toolCalls = GGUFToolCallParser.parseToolCalls(from: generatedText)
                    for toolCall in toolCalls {
                        Self.signposter.emitEvent(
                            "ToolCall",
                            "name=\(toolCall.toolName), args=\(toolCall.arguments.count)"
                        )
                        continuation.yield(.toolCall(toolCall))
                    }
                }

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

    func shutdown() async {
        #if canImport(llama)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            llamaQueue.async { [weak self] in
                self?.cleanupLlamaResources()
                continuation.resume()
            }
        }
        #endif
    }

    /// Synchronous resource cleanup for use in `deinit` and `shutdown()`.
    ///
    /// Swift `deinit` cannot call async methods. This private method provides
    /// a synchronous cleanup path that both `deinit` (via `llamaQueue.sync`)
    /// and `shutdown()` (via `llamaQueue.async` + continuation) can share.
    ///
    /// Reference: Swift community best practice is to extract cleanup into a
    /// synchronous helper and call it from both paths. The async `shutdown()`
    /// moves the work off the calling thread to avoid main-thread beachballs
    /// when freeing multi-GB models.
    private func cleanupLlamaResources() {
        #if canImport(llama)
        // Free mtmd context before model (it references the model internally)
        if let mtmd = self.mtmdContext {
            mtmd_free(mtmd)
            self.mtmdContext = nil
        }
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
        self.registeredTools = []
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

    /// Reset conversation state but preserve the system message.
    ///
    /// Used by the eval runner to give each prompt a clean context while
    /// retaining tool descriptions in the system prompt. The standard
    /// `resetConversation()` wipes everything including the system message.
    func resetConversationKeepingSystem() async {
        #if canImport(llama)
        llamaQueue.sync { [weak self] in
            guard let self, let ctx = self.context else { return }
            llama_memory_clear(llama_get_memory(ctx), true)
            // Keep only the system message (index 0), remove user/assistant turns
            if let systemMsg = self.conversationHistory.first, systemMsg.role == "system" {
                self.conversationHistory = [systemMsg]
            } else {
                self.conversationHistory.removeAll()
            }
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
        // Cannot call async shutdown() from deinit.
        // Use synchronous cleanup as a safety net for the "forgot to call shutdown" case.
        // This blocks on llamaQueue but deinit should only fire at app teardown.
        #if canImport(llama)
        llamaQueue.sync { [weak self] in
            self?.cleanupLlamaResources()
        }
        #endif
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
            // Map roles: assistant → model, tool → user (tool results are user-side context)
            let role: String
            switch msg.role {
            case "assistant": role = "model"
            case "tool": role = "user"  // Tool responses go as user context for next model turn
            default: role = msg.role
            }
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
