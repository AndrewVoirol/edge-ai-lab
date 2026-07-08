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
import os

// MARK: - ConversationViewModel + Inference

/// Inference pipeline: streaming text generation, agent mode ReAct loop,
/// thinking mode parsing, tool call tracking, and metrics persistence.
extension ConversationViewModel {

    // MARK: - Inference

    /// Generate a response for the current prompt via streaming.
    /// Routes through the agentic ReAct loop when `isAgentMode` is true.
    func generateText() async {
        guard engine.isLoaded else {
            return
        }
        guard !isGenerating else {
            return
        }

        // Route to agent mode if enabled
        if isAgentMode {
            await generateTextInAgentMode()
            return
        }
        Self.logger.info("🚀 generateText: prompt=\(self.prompt.prefix(80), privacy: .public) attachments=\(self.hasMultimodalAttachment)")

        isGenerating = true
        inferenceGenerationId += 1
        let currentGenerationId = inferenceGenerationId
        performanceMetrics = nil
        inferenceMetrics = nil
        currentThinkingText = ""
        isThinking = false
        toolCallEvents = []
        thinkingParser.reset()

        // Capture conversation identity at the START of generation so that
        // user actions during streaming (loading a different conversation,
        // creating a new one) don't corrupt the auto-save at the end.
        let capturedConversationId = activeConversationId
        let capturedIsViewingArchived = isViewingArchivedConversation

        ToolExecutionTracker.shared.registerCallback { [weak self] event in
            Task { @MainActor in
                guard let self = self else { return }
                // Check that this callback is still for the current generation.
                // If the user started a new generation or switched conversations,
                // this enqueued Task should not mutate state.
                guard self.inferenceGenerationId == currentGenerationId else { return }
                self.toolCallEvents.append(event)
                self.conversation.updateLastAssistantMessage(
                    toolCalls: self.toolCallEvents
                )
            }
        }
        defer {
            ToolExecutionTracker.shared.clearCallback()
        }

        // Capture and clear multimodal attachments before inference
        let imageData = selectedImageData
        let audioData = selectedAudioData
        selectedImageData = nil
        selectedAudioData = nil

        // Capture prompt text and clear the input field immediately
        let currentPrompt = prompt
        prompt = ""

        // Append user message to conversation
        let userMessage = ChatMessage.user(
            currentPrompt,
            imageData: imageData,
            audioData: audioData
        )
        conversation.append(userMessage)

        // Capture config snapshot at inference start — this is the "proof"
        // of what settings actually produced the response.
        let configSnapshot = InferenceConfigSnapshot.capture(
            modelName: activeModelMetadata?.name,
            runtimeType: selectedRuntimeType,
            computeBackend: backendResult?.activeBackend == .gpu ? "GPU (Metal)" : "CPU (XNNPACK)",
            flags: runtimeFlags,
            temperature: Float(temperature),
            topK: topK,
            topP: Float(topP),
            seed: seed
        )

        // Create placeholder assistant message for streaming with config attached
        conversation.append(.assistant(config: configSnapshot))

        // Accumulated text for updating the assistant message
        var accumulatedResponse = ""
        var accumulatedThinking = ""

        do {
            let stream: AsyncThrowingStream<GenerationEvent, Error>
            // Build generation config from the ViewModel's actual sampler settings.
            // MLXEngineAdapter applies these per-generation to ChatSession.generateParameters,
            // so using GenerationConfig.default would overwrite model-specific defaults
            // (e.g., maxTokens 512 instead of the model's recommended 4000).
            let genConfig = GenerationConfig(
                maxTokens: sessionController.activeModelMetadata?.defaultConfig.maxTokens ?? 4000,
                temperature: Double(temperature),
                topP: Double(topP),
                topK: topK,
                repetitionPenalty: nil,
                seed: seed > 0 ? UInt64(seed) : nil,
                imageData: imageData.map { [$0] }
            )
            stream = engine.generateStream(
                prompt: currentPrompt,
                config: genConfig
            )

            for try await event in stream {
                switch event {
                case .text(let chunk):
                    // Parse thinking tags from streaming chunks
                    if runtimeFlags.enableThinking {
                        let segments = thinkingParser.feed(chunk)
                        for segment in segments {
                            switch segment {
                            case .thinking(let text):
                                let cleaned = text.replacingOccurrences(of: "<pad>", with: "")
                                accumulatedThinking += cleaned
                                currentThinkingText = accumulatedThinking
                                isThinking = true
                            case .response(let text):
                                let cleaned = text.replacingOccurrences(of: "<pad>", with: "")
                                accumulatedResponse += cleaned
                                isThinking = false
                            }
                        }
                    } else {
                        // Thinking disabled: strip all thinking-related tags entirely
                        var cleaned = chunk.replacingOccurrences(of: "<pad>", with: "")
                        cleaned = cleaned.replacingOccurrences(of: "<think>", with: "")
                        cleaned = cleaned.replacingOccurrences(of: "<|think|>", with: "")
                        cleaned = cleaned.replacingOccurrences(of: "</think>", with: "")
                        // Gemma 4 MLX channel-based thinking markers
                        cleaned = cleaned.replacingOccurrences(of: "<|channel>thought\n", with: "")
                        cleaned = cleaned.replacingOccurrences(of: "<|channel>thought", with: "")
                        cleaned = cleaned.replacingOccurrences(of: "\n<channel|>", with: "")
                        cleaned = cleaned.replacingOccurrences(of: "<channel|>", with: "")
                        accumulatedResponse += cleaned
                    }

                    // Update the streaming assistant message
                    conversation.updateLastAssistantMessage(
                        content: accumulatedResponse,
                        thinkingContent: accumulatedThinking.isEmpty ? nil : accumulatedThinking
                    )

                case .toolCall(_):
                    // Tool calls handled via ToolExecutionTracker callbacks for now
                    break

                case .metrics(let metrics):
                    performanceMetrics = metrics
                    inferenceMetrics = engine.lastInferenceMetrics

                case .done:
                    break
                }
            }

            // Flush any remaining buffered content from the parser.
            // The parser retains trailing characters that could be partial tags;
            // finalize() treats them as literal text since no more input will arrive.
            if runtimeFlags.enableThinking {
                let remainingSegments = thinkingParser.finalize()
                for segment in remainingSegments {
                    switch segment {
                    case .thinking(let text):
                        let cleaned = text.replacingOccurrences(of: "<pad>", with: "")
                        accumulatedThinking += cleaned
                        currentThinkingText = accumulatedThinking
                    case .response(let text):
                        let cleaned = text.replacingOccurrences(of: "<pad>", with: "")
                        accumulatedResponse += cleaned
                    }
                }
            }

            isThinking = false

            Self.logger.info("✅ Generation complete: \(accumulatedResponse.count) chars")

            // Finalize the assistant message with metrics
            let benchmarkSnapshot = performanceMetrics.map {
                ChatMessage.BenchmarkSnapshot(from: $0)
            }
            conversation.updateLastAssistantMessage(
                content: accumulatedResponse,
                thinkingContent: accumulatedThinking.isEmpty ? nil : accumulatedThinking,
                toolCalls: toolCallEvents.isEmpty ? nil : toolCallEvents,
                isStreaming: false,
                benchmarkInfo: benchmarkSnapshot
            )

            // Persist to metrics store if performance data is available
            if performanceMetrics != nil {
                let modelName = activeModelURL.map { ($0.lastPathComponent as NSString).deletingPathExtension }
                    ?? "unknown"

                // LiteRT path: uses richer BenchmarkInfo when available
                if let liteRTAdapter = engine as? LiteRTEngineAdapter,
                   let benchmarkInfo = liteRTAdapter.lastBenchmarkInfo {
                    let entry = MetricsStore.createEntry(
                        from: benchmarkInfo,
                        modelName: modelName,
                        flags: RuntimeFlags(from: liteRTAdapter.flagsState),
                        inferenceMetrics: liteRTAdapter.lastInferenceMetrics
                    )
                    do {
                        try metricsStore.append(entry: entry)
                    } catch {
                        Self.logger.error("❌ MetricsStore persistence failed: \(error.localizedDescription, privacy: .public)")
                    }
                } else if let metrics = performanceMetrics {
                    // Universal path: MLX and future runtimes use EnginePerformanceMetrics directly
                    let entry = MetricsStore.createEntry(
                        from: metrics,
                        modelName: modelName,
                        runtimeType: engine.runtimeType
                    )
                    do {
                        try metricsStore.append(entry: entry)
                    } catch {
                        Self.logger.error("❌ MetricsStore persistence failed: \(error.localizedDescription, privacy: .public)")
                    }
                }
            }
        } catch {
            Self.logger.error("❌ Generation error: \(error.localizedDescription, privacy: .public)")
            // Update the assistant message with the error
            conversation.updateLastAssistantMessage(
                content: "Inference error: \(error.localizedDescription)",
                isStreaming: false
            )
        }

        isGenerating = false

        // Auto-save after inference completes.
        // Use the CAPTURED conversation identity from the start of generation,
        // not the current state — the user may have switched conversations mid-stream.
        if !capturedIsViewingArchived && conversation.count >= 2 {
            let saveId = capturedConversationId ?? activeConversationId ?? UUID()
            saveConversationWithId(saveId)
        }
    }

    // MARK: - Agent Mode Inference

    /// Run the agentic ReAct loop using the current prompt.
    ///
    /// Instead of a single inference turn, the agent reasons step-by-step, calling
    /// tools and examining results until it reaches a conclusion or hits the iteration
    /// limit. The UI stays updated via the `agentHarness` observable.
    private func generateTextInAgentMode() async {
        Self.logger.info("🤖 generateTextInAgentMode: prompt=\(self.prompt.prefix(80), privacy: .public)")

        isGenerating = true

        let currentPrompt = prompt
        prompt = ""

        // Append user message to conversation
        let userMessage = ChatMessage.user(currentPrompt)
        conversation.append(userMessage)

        // Capture config snapshot for agent mode responses
        let configSnapshot = InferenceConfigSnapshot.capture(
            modelName: activeModelMetadata?.name,
            runtimeType: selectedRuntimeType,
            computeBackend: backendResult?.activeBackend == .gpu ? "GPU (Metal)" : "CPU (XNNPACK)",
            flags: runtimeFlags,
            temperature: Float(temperature),
            topK: topK,
            topP: Float(topP),
            seed: seed
        )

        // Create placeholder assistant message for the agent's running output
        conversation.append(.assistant(config: configSnapshot))

        await agentHarness.run(
            initialPrompt: currentPrompt,
            availableToolNames: Self.availableToolNames,
            generateResponse: { [weak self] agentPrompt in
                guard let self = self else {
                    throw NSError(domain: "EdgeAILab", code: -1, userInfo: [
                        NSLocalizedDescriptionKey: "ViewModel deallocated during agent loop"
                    ])
                }

                // Collect tool events during this inference turn
                var turnToolEvents: [ToolCallEvent] = []
                ToolExecutionTracker.shared.registerCallback { event in
                    turnToolEvents.append(event)
                }
                defer {
                    ToolExecutionTracker.shared.clearCallback()
                }

                // Run a single inference turn with the ViewModel's actual sampler settings.
                var accumulatedResponse = ""
                let agentGenConfig = GenerationConfig(
                    maxTokens: self.sessionController.activeModelMetadata?.defaultConfig.maxTokens ?? 4000,
                    temperature: Double(self.temperature),
                    topP: Double(self.topP),
                    topK: self.topK,
                    repetitionPenalty: nil,
                    seed: self.seed > 0 ? UInt64(self.seed) : nil
                )
                let stream = self.engine.generateStream(
                    prompt: agentPrompt,
                    config: agentGenConfig
                )
                for try await event in stream {
                    guard case .text(let chunk) = event else { continue }
                    let cleaned = chunk.replacingOccurrences(of: "<pad>", with: "")
                        .replacingOccurrences(of: "<think>", with: "")
                        .replacingOccurrences(of: "<|think|>", with: "")
                        .replacingOccurrences(of: "</think>", with: "")
                        // Gemma 4 MLX channel-based thinking markers
                        .replacingOccurrences(of: "<|channel>thought\n", with: "")
                        .replacingOccurrences(of: "<|channel>thought", with: "")
                        .replacingOccurrences(of: "\n<channel|>", with: "")
                        .replacingOccurrences(of: "<channel|>", with: "")
                    accumulatedResponse += cleaned

                    // Update the streaming assistant message with agent progress
                    self.conversation.updateLastAssistantMessage(
                        content: accumulatedResponse,
                        toolCalls: turnToolEvents.isEmpty ? nil : turnToolEvents
                    )
                }

                // Append tool events to the main list for observability
                self.toolCallEvents.append(contentsOf: turnToolEvents)

                return (response: accumulatedResponse, toolEvents: turnToolEvents)
            }
        )

        // Finalize the assistant message
        if case .completed(let summary) = agentHarness.status {
            conversation.updateLastAssistantMessage(
                content: summary,
                toolCalls: toolCallEvents.isEmpty ? nil : toolCallEvents,
                isStreaming: false
            )
        } else if case .forceStopped(let summary) = agentHarness.status {
            conversation.updateLastAssistantMessage(
                content: summary,
                toolCalls: toolCallEvents.isEmpty ? nil : toolCallEvents,
                isStreaming: false
            )
        }

        isGenerating = false
    }

    /// Stop an active text generation.
    func stopGenerating() {
        guard isGenerating else { return }
        Self.logger.info("🛑 stopGenerating called")
        engine.cancelGeneration()
        isGenerating = false
        isThinking = false
        statusMessage = "Generation stopped"
        conversation.updateLastAssistantMessage(
            content: "\n[Inference stopped by user]",
            isStreaming: false
        )
    }
}
