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
import LiteRTLM
import Observation
import os

/// ViewModel managing the inference engine lifecycle, conversation state,
/// and benchmark data. Consumes InstrumentedEngineProtocol for testability.
@Observable
@MainActor
final class ConversationViewModel {
    
    /// Global shared instance to synchronize settings and engine state across the app.
    static let shared = ConversationViewModel()

    /// Console logger for runtime diagnostics (visible in Console.app).
    private static let logger = Logger(
        subsystem: "com.andrewvoirol.GemmaEdgeGallery.performance",
        category: "viewmodel"
    )

    // MARK: - Published State

    /// Status message displayed in the header (e.g., "Engine Ready! 🎉").
    var statusMessage = "Please select a model file..."

    /// User's current prompt text.
    var prompt = ""

    /// Multi-turn conversation state — replaces the old single `responseText`.
    var conversation = ConversationState()

    /// Legacy accessor: accumulated response text from the current/last inference.
    /// Now derived from the last assistant message for backward compatibility.
    var responseText: String {
        conversation.lastMessage?.content ?? ""
    }

    /// Whether an inference is currently in progress.
    var isGenerating = false

    /// Whether a model is currently being loaded.
    var isLoadingModel = false

    /// Whether GPU backend is preferred.
    var useGPU = true {
        didSet {
            Task { await reinitializeEngineIfNeeded() }
        }
    }

    /// The most recent BenchmarkInfo from completed inference.
    var benchmarkInfo: BenchmarkInfo?

    /// Whether to show the file picker.
    var isFilePickerPresented = false

    /// Result of the last backend initialization (active backend, fallback info).
    var backendResult: BackendResult?

    /// Metadata for the currently loaded model, if known.
    var activeModelMetadata: ModelMetadata?

    /// Current experimental flags configuration (user-toggleable, default ON).
    var experimentalFlags = ExperimentalFlagsState(
        enableBenchmark: true,
        enableSpeculativeDecoding: nil,
        enableConversationConstrainedDecoding: false,
        visualTokenBudget: nil
    ) {
        didSet {
            Task { await reinitializeEngineIfNeeded() }
        }
    }

    // MARK: - Sampler Configuration

    /// Top-K sampling parameter. Set to 1 for greedy (Gallery-matching) decoding.
    var topK: Int = 64 {
        didSet { Task { await reinitializeEngineIfNeeded() } }
    }

    /// Top-P (nucleus) sampling parameter.
    var topP: Float = 0.95 {
        didSet { Task { await reinitializeEngineIfNeeded() } }
    }

    /// Temperature for sampling. Higher = more random.
    var temperature: Float = 1.0 {
        didSet { Task { await reinitializeEngineIfNeeded() } }
    }

    /// Seed for reproducible generation. 0 = non-deterministic (SDK default).
    var seed: Int = 0 {
        didSet { Task { await reinitializeEngineIfNeeded() } }
    }

    /// Optional system message to set model persona/instructions.
    var systemMessage: String = "" {
        didSet { Task { await reinitializeEngineIfNeeded() } }
    }

    // MARK: - Multimodal Attachments

    /// Image data attached by the user for multimodal inference.
    /// Cleared after each generation.
    var selectedImageData: Data?

    /// Audio data attached by the user for multimodal inference.
    /// Cleared after each generation.
    var selectedAudioData: Data?

    /// Whether the user has any multimodal attachments pending.
    var hasMultimodalAttachment: Bool {
        selectedImageData != nil || selectedAudioData != nil
    }

    /// Whether the currently loaded model supports image input.
    var supportsImageInput: Bool {
        activeModelMetadata?.supportsImage ?? false
    }

    /// Whether the currently loaded model supports audio input.
    var supportsAudioInput: Bool {
        activeModelMetadata?.supportsAudio ?? false
    }

    // MARK: - Thinking Mode State

    /// Accumulated thinking content from the current streaming inference.
    /// Populated by the ThinkingParser as `<think>` blocks are received.
    var currentThinkingText: String = ""

    /// Whether the model is currently in the "thinking" phase of its response.
    var isThinking: Bool = false

    /// Parser instance for the current streaming response.
    private var thinkingParser = ThinkingParser()

    // MARK: - Tool Calling State

    /// Tool call events from the current/last inference (for observability).
    var toolCallEvents: [ToolCallEvent] = []

    // MARK: - Internal State

    /// The URL of the currently loaded model file (for security scope management).
    private(set) var activeModelURL: URL?

    /// Tracks the active model load task for cancellation support.
    private var modelLoadTask: Task<Void, Never>?

    /// Models discovered from local storage and AI Edge Gallery.
    var discoveredModels: [DiscoveredModel] = []

    /// Download manager for fetching models from HuggingFace.
    let downloadManager: ModelDownloadManager

    /// The most recent device-level inference metrics (thermal, memory, per-token latency).
    var inferenceMetrics: InferenceMetrics? { engine.lastInferenceMetrics }

    /// Whether the engine is initialized and ready for inference.
    var isEngineReady: Bool { engine.isReady }

    // MARK: - MCP Servers Support

    var mcpServers: [MCPServerConfig] = []

    #if os(macOS)
    var activeClients: [UUID: MCPClient] = [:]
    #endif

    // MARK: - Dependencies

    let engine: InstrumentedEngineProtocol
    private let metricsStore: MetricsStore
    let conversationStore: ConversationStore

    // MARK: - Persistence State

    /// The UUID of the currently active conversation (for auto-save targeting).
    var activeConversationId: UUID?

    /// Whether the current view is showing a read-only archived conversation.
    var isViewingArchivedConversation: Bool = false

    // MARK: - Init

    /// Initialize with injectable dependencies.
    /// - Parameters:
    ///   - engine: The instrumented engine (real or mock).
    ///   - metricsStore: The metrics persistence layer.
    ///   - downloadManager: The model download manager.
    ///   - conversationStore: The conversation persistence layer.
    init(
        engine: InstrumentedEngineProtocol = InstrumentedEngine(),
        metricsStore: MetricsStore = MetricsStore(),
        downloadManager: ModelDownloadManager = ModelDownloadManager(),
        conversationStore: ConversationStore? = nil
    ) {
        self.engine = engine
        self.metricsStore = metricsStore
        self.downloadManager = downloadManager
        self.conversationStore = conversationStore ?? ConversationStore()
        
        self.mcpServers = MCPServerStorage.load()
        #if os(macOS)
        Task {
            await startEnabledMCPServers()
        }
        #endif
    }

    // MARK: - Model Loading

    /// Handle a model file selection from the file picker.
    func handleModelSelection(_ url: URL) async {
        Self.logger.info("📂 Model selected: \(url.lastPathComponent, privacy: .public)")
        // Release previous security scope
        activeModelURL?.stopAccessingSecurityScopedResource()

        // Attempt to access the new file
        let hasAccess = url.startAccessingSecurityScopedResource()
        activeModelURL = url

        if !hasAccess {
            // Even without security scope, try to load (may work for non-sandboxed macOS)
        }

        // Bookmark Gallery models for future auto-discovery
        GalleryModelDiscovery.bookmarkGalleryModel(url)

        await initializeEngine(modelPath: url.path)
    }

    /// Discover available models from local storage and Gallery.
    ///
    /// Populates the sidebar model list so users can see what's available,
    /// but does NOT auto-load. Users explicitly choose which model to load
    /// by clicking it in the sidebar or the Getting Started action cards.
    func checkForLocalModels() {
        discoveredModels = GalleryModelDiscovery.discoverModels()
        Self.logger.info("🔍 Discovered \(self.discoveredModels.count) model(s)")

        if let firstModel = discoveredModels.first {
            statusMessage = "Found \(discoveredModels.count) model(s) — select one to get started."
            if firstModel.source == .edgeGallery {
                statusMessage += " (via Edge Gallery)"
            }
            // Note: We intentionally do NOT auto-load here.
            // The user should see the Getting Started UI and choose explicitly.
        }
    }

    /// Refresh the discovered models list without auto-loading.
    func refreshDiscoveredModels() {
        discoveredModels = GalleryModelDiscovery.discoverModels()
    }

    /// Initialize the inference engine with a model file, using smart backend fallback.
    func initializeEngine(modelPath: String) async {
        // Cancel any in-progress load
        modelLoadTask?.cancel()

        isLoadingModel = true
        statusMessage = "Initializing Engine..."

        // Start a timeout timer that updates the status message
        let timeoutTask = Task {
            try? await Task.sleep(for: .seconds(30))
            if !Task.isCancelled && self.isLoadingModel {
                self.statusMessage += " (taking longer than expected…)"
            }
        }

        let modelName = (modelPath as NSString).lastPathComponent
        Self.logger.info("⏳ initializeEngine: \(modelName, privacy: .public) GPU=\(self.useGPU)")

        // Look up model metadata for known models
        activeModelMetadata = ModelRegistry.lookup(path: modelPath)
        if let metadata = activeModelMetadata {
            statusMessage = "Loading \(metadata.name)..."
            // Apply model's default sampler config
            topK = metadata.defaultConfig.topK
            topP = Float(metadata.defaultConfig.topP)
            temperature = Float(metadata.defaultConfig.temperature)
        }

        do {
            let fileManager = FileManager.default
            guard let cacheBaseDirectory = fileManager.urls(
                for: .cachesDirectory, in: .userDomainMask
            ).first else {
                statusMessage = "Could not find caches directory"
                isLoadingModel = false
                timeoutTask.cancel()
                return
            }

            // Create a unique cache directory per model to prevent collisions
            let modelFilename = (modelPath as NSString).lastPathComponent
            let modelCacheDirectory = cacheBaseDirectory.appendingPathComponent(modelFilename)

            if !fileManager.fileExists(atPath: modelCacheDirectory.path) {
                try fileManager.createDirectory(
                    at: modelCacheDirectory,
                    withIntermediateDirectories: true
                )
            }

            // Build sampler config from current settings
            // LiteRTLM WebGPU sampler expects topK <= 1 if temperature is 0.0 (greedy decoding)
            // Additionally, Mobile GPU (web) variants are hard-compiled with topK=1 limitation.
            var actualTopK = topK
            if temperature == 0.0 || modelFilename.contains("-web") {
                actualTopK = 1
            }
            let samplerConfig: SamplerConfig?
            do {
                samplerConfig = try SamplerConfig(
                    topK: actualTopK,
                    topP: topP,
                    temperature: temperature,
                    seed: seed
                )
            } catch {
                // Log the error rather than silently swallowing it
                Self.logger.warning("⚠️ SamplerConfig creation failed: \(error.localizedDescription, privacy: .public). Using SDK defaults.")
                samplerConfig = nil
            }

            // Prepare tools if tool calling is enabled
            var activeTools: [Tool] = []
            if experimentalFlags.enableToolCalling {
                activeTools.append(contentsOf: ToolRegistry.defaultTools)
                
                if experimentalFlags.enableAgentSkills {
                    activeTools.append(WikipediaSkillTool())
                    activeTools.append(MapSkillTool())
                }
                
                #if os(macOS)
                // Bridge MCP tools
                MCPBridgeManager.shared.clear()
                for (_, client) in activeClients {
                    if case .connected(let toolsList) = client.state {
                        let bridged = MCPBridgeManager.shared.bridge(tools: toolsList, client: client)
                        activeTools.append(contentsOf: bridged)
                    }
                }
                #endif
            }
            let tools: [Tool]? = activeTools.isEmpty ? nil : activeTools

            var activeFlags = experimentalFlags
            
            // Optimize TTFT by automatically enabling MTP if the model supports it.
            // MTP + CPU crashes on iOS devices. On macOS, 12B models can also crash if memory is constrained.
            if activeFlags.enableSpeculativeDecoding == nil, activeModelMetadata?.supportsMTP == true {
                // Safest to leave it off by default and let user manually enable it if desired.
                activeFlags.enableSpeculativeDecoding = false
            }

            // Compose system message: inject the Gemma 4 thinking trigger token.
            // Per official docs, E2B/E4B models require a system message containing
            // the <|think|> token to activate the "thought" channel in responses.
            let thinkingTrigger = "<|think|>"
            let composedSystemMessage: String? = {
                let parts = [
                    experimentalFlags.enableThinking ? thinkingTrigger : nil,
                    systemMessage.isEmpty ? nil : systemMessage
                ].compactMap { $0 }
                return parts.isEmpty ? nil : parts.joined(separator: "\n")
            }()

            // Use smart fallback initialization
            let result = try await engine.initializeWithFallback(
                modelPath: modelPath,
                preferGPU: useGPU,
                cacheDir: modelCacheDirectory.path,
                flags: activeFlags,
                samplerConfig: samplerConfig,
                systemMessage: composedSystemMessage,
                tools: tools,
                supportsVision: activeModelMetadata?.supportsImage ?? false,
                supportsAudio: activeModelMetadata?.supportsAudio ?? false
            )

            backendResult = result

            let backendLabel = result.activeBackend == .gpu ? "GPU" : "CPU"
            let modelLabel = activeModelMetadata?.name ?? modelFilename

            if result.didFallback {
                statusMessage = "\(modelLabel) ready (\(backendLabel)) ⚠️ Fallback"
            } else {
                statusMessage = "\(modelLabel) ready (\(backendLabel))"
            }

            Self.logger.info("✅ Engine initialized: \(self.statusMessage, privacy: .public)")

            // Start a new conversation when loading a new model
            conversation.clear()

        } catch {
            backendResult = nil
            statusMessage = "Failed to initialize: \(error.localizedDescription)"
            Self.logger.error("❌ Engine init failed: \(error.localizedDescription, privacy: .public)")
        }

        timeoutTask.cancel()
        isLoadingModel = false
    }

    /// Cancel an in-progress model load.
    func cancelModelLoad() {
        modelLoadTask?.cancel()
        modelLoadTask = nil
        isLoadingModel = false
        statusMessage = "Model load cancelled"
    }

    /// Reboots the engine to apply new core settings if a model is currently loaded.
    private func reinitializeEngineIfNeeded() async {
        guard engine.isReady, let url = activeModelURL else { return }
        Self.logger.info("♻️ Settings changed, rebooting engine to apply new configuration...")
        statusMessage = "Applying new settings..."
        await engine.shutdown()
        await initializeEngine(modelPath: url.path)
    }

    // MARK: - Inference

    /// Generate a response for the current prompt via streaming.
    /// Integrates thinking mode parsing and multi-turn chat state.
    func generateText() async {
        guard engine.isReady else { return }
        guard !isGenerating else { return }
        Self.logger.info("🚀 generateText: prompt=\(self.prompt.prefix(80), privacy: .public) attachments=\(self.hasMultimodalAttachment)")

        isGenerating = true
        benchmarkInfo = nil
        currentThinkingText = ""
        isThinking = false
        toolCallEvents = []
        thinkingParser.reset()

        ToolExecutionTracker.shared.registerCallback { [weak self] event in
            Task { @MainActor in
                guard let self = self else { return }
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

        // Create placeholder assistant message for streaming
        conversation.append(.assistant())

        // Accumulated text for updating the assistant message
        var accumulatedResponse = ""
        var accumulatedThinking = ""

        do {
            let stream: AsyncThrowingStream<String, Error>
            if imageData != nil || audioData != nil {
                stream = engine.sendMessageStream(
                    currentPrompt,
                    imageData: imageData,
                    audioData: audioData,
                    enableThinking: experimentalFlags.enableThinking
                )
            } else {
                stream = engine.sendMessageStream(currentPrompt, enableThinking: experimentalFlags.enableThinking)
            }

            for try await chunk in stream {
                // Parse thinking tags from streaming chunks
                if experimentalFlags.enableThinking {
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
                    // Thinking disabled: strip <think> tags entirely so they don't leak
                    // into the visible response as raw text.
                    var cleaned = chunk.replacingOccurrences(of: "<pad>", with: "")
                    cleaned = cleaned.replacingOccurrences(of: "<think>", with: "")
                    cleaned = cleaned.replacingOccurrences(of: "<|think|>", with: "")
                    cleaned = cleaned.replacingOccurrences(of: "</think>", with: "")
                    accumulatedResponse += cleaned
                }

                // Update the streaming assistant message
                conversation.updateLastAssistantMessage(
                    content: accumulatedResponse,
                    thinkingContent: accumulatedThinking.isEmpty ? nil : accumulatedThinking
                )
            }

            // Finalize thinking parser
            if experimentalFlags.enableThinking {
                let finalSegments = thinkingParser.finalize()
                for segment in finalSegments {
                    switch segment {
                    case .thinking(let text):
                        accumulatedThinking += text
                    case .response(let text):
                        accumulatedResponse += text
                    }
                }
            }

            isThinking = false

            // Capture benchmark data after inference completes
            benchmarkInfo = engine.lastBenchmarkInfo
            Self.logger.info("✅ Generation complete: \(accumulatedResponse.count) chars")

            // Finalize the assistant message
            let benchmarkSnapshot = benchmarkInfo.map { ChatMessage.BenchmarkSnapshot(from: $0) }
            conversation.updateLastAssistantMessage(
                content: accumulatedResponse,
                thinkingContent: accumulatedThinking.isEmpty ? nil : accumulatedThinking,
                toolCalls: toolCallEvents.isEmpty ? nil : toolCallEvents,
                isStreaming: false,
                benchmarkInfo: benchmarkSnapshot
            )

            // Persist to metrics store if benchmark data is available
            if let info = benchmarkInfo {
                let modelName = activeModelURL.map { ($0.lastPathComponent as NSString).deletingPathExtension }
                    ?? "unknown"
                let entry = MetricsStore.createEntry(
                    from: info,
                    modelName: modelName,
                    flags: engine.flagsState,
                    inferenceMetrics: engine.lastInferenceMetrics
                )
                do {
                    try metricsStore.append(entry: entry)
                } catch {
                    // Don't fail inference over metrics persistence errors
                    Self.logger.error("❌ MetricsStore persistence failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        } catch {
            Self.logger.error("❌ Generation failed: \(error.localizedDescription, privacy: .public)")
            // Update the assistant message with the error
            conversation.updateLastAssistantMessage(
                content: "Inference error: \(error.localizedDescription)",
                isStreaming: false
            )
        }

        isGenerating = false

        // Auto-save after inference completes (only for non-archived, non-empty conversations)
        if !isViewingArchivedConversation && conversation.count >= 2 {
            saveCurrentConversation()
        }
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

    // MARK: - Conversation Management

    /// Start a new conversation — saves current, clears chat history, resets engine.
    func newConversation() async {
        Self.logger.info("🔄 New conversation requested")

        // Auto-save the current conversation before clearing
        if !isViewingArchivedConversation && !conversation.isEmpty {
            saveCurrentConversation()
        }

        conversation.clear()
        currentThinkingText = ""
        isThinking = false
        toolCallEvents = []
        benchmarkInfo = nil
        activeConversationId = nil
        isViewingArchivedConversation = false

        // Reset the engine conversation (preserves model weights, clears context window)
        if engine.isReady {
            do {
                try await engine.resetConversation()
            } catch {
                statusMessage = "Failed to reset conversation: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Conversation Persistence

    /// Save the current conversation to the store.
    func saveCurrentConversation() {
        guard !conversation.isEmpty else { return }

        let config = ExperimentConfig.capture(from: self)
        let summary = ExperimentSummary.compute(from: conversation.messages)
        let now = Date()

        let id = activeConversationId ?? UUID()
        let title: String
        if let existingEntry = conversationStore.indexEntries.first(where: { $0.id == id }) {
            title = existingEntry.title
        } else {
            title = SavedConversation.generateTitle(config: config, messages: conversation.messages)
        }

        let saved = SavedConversation(
            id: id,
            title: title,
            config: config,
            messages: conversation.messages,
            summary: summary,
            createdAt: conversationStore.indexEntries.first(where: { $0.id == id })?.createdAt ?? now,
            lastModifiedAt: now,
            forkedFrom: nil
        )

        do {
            try conversationStore.save(saved)
            activeConversationId = id
            Self.logger.info("💾 Auto-saved conversation: \(title, privacy: .public)")
        } catch {
            Self.logger.error("❌ Failed to auto-save: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Load a saved conversation for viewing (read-only archive mode).
    func loadConversation(id: UUID) {
        do {
            let saved = try conversationStore.load(id: id)
            conversation = ConversationState()
            for message in saved.messages {
                conversation.append(message)
            }
            activeConversationId = saved.id
            isViewingArchivedConversation = true
            currentThinkingText = ""
            isThinking = false
            toolCallEvents = []
            benchmarkInfo = nil
            Self.logger.info("📂 Loaded archived conversation: \(saved.title, privacy: .public)")
        } catch {
            Self.logger.error("❌ Failed to load conversation: \(error.localizedDescription, privacy: .public)")
            statusMessage = "Failed to load conversation: \(error.localizedDescription)"
        }
    }

    /// Fork a saved conversation — creates a new editable experiment with copied data.
    func forkConversation(id: UUID) {
        do {
            let original = try conversationStore.load(id: id)
            let newId = UUID()

            // Copy messages into current conversation state
            conversation = ConversationState()
            for message in original.messages {
                conversation.append(message)
            }

            // Create the forked conversation with a new ID
            let forked = SavedConversation(
                id: newId,
                title: "Fork of \(original.title)",
                config: original.config,
                messages: original.messages,
                summary: original.summary,
                createdAt: Date(),
                lastModifiedAt: Date(),
                forkedFrom: original.id
            )

            try conversationStore.save(forked)
            activeConversationId = newId
            isViewingArchivedConversation = false
            Self.logger.info("🔀 Forked conversation: \(original.title, privacy: .public) → \(forked.title, privacy: .public)")
        } catch {
            Self.logger.error("❌ Failed to fork conversation: \(error.localizedDescription, privacy: .public)")
            statusMessage = "Failed to fork conversation: \(error.localizedDescription)"
        }
    }

    /// Delete a saved conversation.
    func deleteConversation(id: UUID) {
        do {
            try conversationStore.delete(id: id)
            if activeConversationId == id {
                activeConversationId = nil
                if isViewingArchivedConversation {
                    conversation.clear()
                    isViewingArchivedConversation = false
                }
            }
            Self.logger.info("🗑️ Deleted conversation: \(id)")
        } catch {
            Self.logger.error("❌ Failed to delete conversation: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Rename a saved conversation.
    func renameConversation(id: UUID, newTitle: String) {
        do {
            try conversationStore.rename(id: id, newTitle: newTitle)
            Self.logger.info("✏️ Renamed conversation: \(newTitle, privacy: .public)")
        } catch {
            Self.logger.error("❌ Failed to rename conversation: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Cleanup

    /// Shut down the engine and release resources.
    func shutdown() async {
        Self.logger.info("🛑 Shutdown initiated")
        activeModelURL?.stopAccessingSecurityScopedResource()
        activeModelURL = nil
        activeModelMetadata = nil
        backendResult = nil
        await engine.shutdown()
        benchmarkInfo = nil
        conversation.clear()
        
        #if os(macOS)
        for client in activeClients.values {
            client.stop()
        }
        activeClients.removeAll()
        #endif
    }
}
