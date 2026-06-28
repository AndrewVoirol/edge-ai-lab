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
import LiteRTLM
import Observation
import os

/// ViewModel managing the inference engine lifecycle, conversation state,
/// and benchmark data. Consumes InstrumentedEngineProtocol for testability.
@Observable
@MainActor
final class ConversationViewModel {
    
    // NOTE: The singleton `static let shared` was intentionally removed.
    // Views access this via @Environment injection from EdgeAILabApp.
    // See: Apple's "Managing model data in your app" (WWDC 2023+).

    /// Console logger for runtime diagnostics (visible in Console.app).
    private static let logger = Logger(
        subsystem: "com.andrewvoirol.EdgeAILab.performance",
        category: "viewmodel"
    )

    // MARK: - Published State

    /// Status message displayed in the header (e.g., "Engine Ready! 🎉").
    var statusMessage = "Please select a model file..."

    /// User's current prompt text.
    var prompt = ""

    /// When true, `didSet` handlers on sampler properties skip `reinitializeEngineIfNeeded()`.
    /// Set during `handleModelSelection()` to prevent triple-init.
    private var isSyncingSettings = false

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
    var isLoadingModel: Bool { sessionController.isLoadingModel }

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
    var backendResult: BackendResult? { sessionController.backendResult }

    /// Metadata for the currently loaded model, if known.
    var activeModelMetadata: ModelMetadata? { sessionController.activeModelMetadata }

    /// Current experimental flags configuration (user-toggleable, default ON).
    var experimentalFlags = ExperimentalFlagsState(
        enableBenchmark: true,
        enableSpeculativeDecoding: nil,
        enableConversationConstrainedDecoding: false,
        visualTokenBudget: nil
    ) {
        didSet {
            sessionController.defaultExperimentalFlags = experimentalFlags
            Task { await reinitializeEngineIfNeeded() }
        }
    }

    // MARK: - Sampler Configuration

    /// Top-K sampling parameter. Set to 1 for greedy (Gallery-matching) decoding.
    var topK: Int = 64 {
        didSet {
            sessionController.topK = topK
            if !isSyncingSettings { Task { await reinitializeEngineIfNeeded() } }
        }
    }

    /// Top-P (nucleus) sampling parameter.
    var topP: Float = 0.95 {
        didSet {
            sessionController.topP = topP
            if !isSyncingSettings { Task { await reinitializeEngineIfNeeded() } }
        }
    }

    /// Temperature for sampling. Higher = more random.
    var temperature: Float = 1.0 {
        didSet {
            sessionController.temperature = temperature
            if !isSyncingSettings { Task { await reinitializeEngineIfNeeded() } }
        }
    }

    /// Seed for reproducible generation. 0 = non-deterministic (SDK default).
    var seed: Int = 0 {
        didSet { sessionController.seed = seed; Task { await reinitializeEngineIfNeeded() } }
    }

    /// Optional system message to set model persona/instructions.
    var systemMessage: String = "" {
        didSet { sessionController.systemMessage = systemMessage; Task { await reinitializeEngineIfNeeded() } }
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
    var activeModelURL: URL? { sessionController.activeModelURL }

    /// Models discovered from local storage and AI Edge Gallery.
    var discoveredModels: [DiscoveredModel] = []

    /// Download manager for fetching models from HuggingFace.
    /// @ObservationIgnored: Views should observe ModelDownloadManager directly
    /// via @Environment, not transitively through the ViewModel.
    @ObservationIgnored
    let downloadManager: ModelDownloadManager

    /// Shared dynamic model catalog for imported/community models.
    /// @ObservationIgnored: Views that need to observe catalog changes should
    /// access this instance directly — it is @Observable on its own.
    @ObservationIgnored
    let dynamicModelCatalog: DynamicModelCatalog

    /// The most recent device-level inference metrics (thermal, memory, per-token latency).
    var inferenceMetrics: InferenceMetrics? { engine.lastInferenceMetrics }

    /// Whether the engine is initialized and ready for inference.
    ///
    /// This is a tracked stored property (not a computed property) because the engine
    /// is `@ObservationIgnored`. If we derived this from `engine.isReady`, SwiftUI would
    /// never observe changes — views would show stale state (e.g., "No Model Loaded" after
    /// a conversation reset even though the model is still loaded). The ViewModel explicitly
    /// updates this via `onEngineReadyChanged` from ModelSessionController.
    private(set) var isEngineReady: Bool = false

    // MARK: - MCP Servers Support

    var mcpServers: [MCPServerConfig] = []

    #if os(macOS)
    var activeClients: [UUID: MCPClient] = [:]
    #endif

    // MARK: - Dependencies

    /// @ObservationIgnored: Internal dependencies — views never observe these directly.
    @ObservationIgnored
    let engine: InstrumentedEngineProtocol
    @ObservationIgnored
    private let metricsStore: MetricsStore
    /// @ObservationIgnored: Views that need ConversationStore should observe it
    /// directly via @Environment or receive it as a parameter.
    @ObservationIgnored
    let conversationStore: ConversationStore
    /// @ObservationIgnored: Session controller owns engine init, sampler config,
    /// tool setup, and backend fallback. Not directly observable by views.
    @ObservationIgnored
    let sessionController: ModelSessionController

    // MARK: - Persistence State

    /// The UUID of the currently active conversation (for auto-save targeting).
    var activeConversationId: UUID?

    /// Whether the current view is showing a read-only archived conversation.
    var isViewingArchivedConversation: Bool = false

    // MARK: - URL Import

    /// Shared URL import manager for the "Paste and Go" feature.
    /// @ObservationIgnored: The manager is @Observable on its own — views
    /// that need to observe import state should access it directly.
    @ObservationIgnored
    lazy var urlImportManager: URLImportManager = {
        URLImportManager(browser: HFModelBrowser(), catalog: dynamicModelCatalog)
    }()

    /// Whether the URL import sheet is currently presented.
    var showURLImportSheet: Bool = false

    /// A URL pending import — set by the inline quick-paste field before opening the sheet.
    /// The sheet reads and clears this on appear.
    var pendingImportURL: String?

    // MARK: - Init

    /// Initialize with injectable dependencies.
    /// - Parameters:
    ///   - engine: The instrumented engine (real or mock).
    ///   - metricsStore: The metrics persistence layer.
    ///   - downloadManager: The model download manager.
    ///   - conversationStore: The conversation persistence layer.
    ///   - dynamicModelCatalog: Shared catalog for imported/community models.
    init(
        engine: InstrumentedEngineProtocol = InstrumentedEngine(),
        metricsStore: MetricsStore = MetricsStore(),
        downloadManager: ModelDownloadManager? = nil,
        conversationStore: ConversationStore? = nil,
        dynamicModelCatalog: DynamicModelCatalog? = nil
    ) {
        self.engine = engine
        self.metricsStore = metricsStore
        self.downloadManager = downloadManager ?? ModelDownloadManager()
        self.conversationStore = conversationStore ?? ConversationStore()
        self.dynamicModelCatalog = dynamicModelCatalog ?? DynamicModelCatalog()

        // Create the session controller with a status message callback.
        // The closure captures `self` weakly to avoid retain cycles.
        let controller = ModelSessionController(
            engine: engine,
            onStatusMessage: { _ in } // Temporary — replaced below
        )
        self.sessionController = controller

        // Now wire the status message callback (can't capture self in init above)
        controller.onStatusMessage = { [weak self] message in
            self?.statusMessage = message
        }
        // Wire engine readiness callback so the tracked property stays in sync
        controller.onEngineReadyChanged = { [weak self] ready in
            self?.isEngineReady = ready
        }
        // Sync sampler defaults back to the VM when model-specific configs are applied
        controller.onSamplerDefaultsApplied = { [weak self] topK, topP, temperature in
            self?.topK = topK
            self?.topP = topP
            self?.temperature = temperature
        }
        // Give the controller access to the VM's experimental flags by default
        controller.defaultExperimentalFlags = experimentalFlags

        self.mcpServers = MCPServerStorage.load()
        // Auto-refresh discovered models when any download completes.
        // Without this, a downloaded model stays in the "downloadable" sidebar section
        // (which has no tap handler) and never moves to the "discovered" section
        // until the app restarts and checkForLocalModels() runs.
        self.downloadManager.onDownloadCompleted = { [weak self] _, _ in
            self?.refreshDiscoveredModels()
        }
        #if os(macOS)
        Task {
            await startEnabledMCPServers()
        }
        #endif
    }

    // MARK: - Model Loading

    /// Handle a model file selection from the file picker.
    func handleModelSelection(_ url: URL) async {
        await sessionController.handleModelSelection(url)
        // Sync sampler config from model defaults that the controller may have applied.
        // Use isSyncingSettings to suppress the didSet → reinitializeEngineIfNeeded() cascade.
        // Without this guard, each property set fires a full engine shutdown + re-init,
        // causing isEngineReady to flip false→true twice (the "triple-init" bug).
        isSyncingSettings = true
        topK = sessionController.topK
        topP = sessionController.topP
        temperature = sessionController.temperature
        isSyncingSettings = false
        // Sync engine readiness — sessionController.onEngineReadyChanged fires during init,
        // but also sync explicitly here for safety.
        isEngineReady = engine.isReady
        // Start a new conversation when loading a new model
        conversation.clear()
        // Refresh discovered models so the Models tab immediately reflects the active model
        refreshDiscoveredModels()
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

    /// Cancel an in-progress model load.
    func cancelModelLoad() {
        sessionController.cancelModelLoad()
    }

    /// Reboots the engine to apply new core settings if a model is currently loaded.
    private func reinitializeEngineIfNeeded() async {
        var mcpClients: [UUID: Any] = [:]
        #if os(macOS)
        mcpClients = activeClients
        #endif
        await sessionController.reinitializeIfNeeded(
            experimentalFlags: experimentalFlags,
            useGPU: useGPU,
            mcpClients: mcpClients
        )
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

        let config = ExperimentConfig.capture(
            modelMetadata: activeModelMetadata,
            modelURL: activeModelURL,
            backendResult: backendResult,
            topK: topK,
            topP: topP,
            temperature: temperature,
            seed: seed,
            systemMessage: systemMessage,
            flags: experimentalFlags
        )
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

    /// Delete all saved conversations.
    func deleteAllConversations() {
        // Clear active conversation state if it will be deleted
        clearActiveConversationIfNeeded()
        do {
            let count = try conversationStore.deleteAll()
            Self.logger.info("🗑️ Deleted all \(count) conversations")
        } catch {
            Self.logger.error("❌ Failed to delete all conversations: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Delete multiple conversations by their IDs.
    func deleteSelectedConversations(ids: Set<UUID>) {
        if let activeId = activeConversationId, ids.contains(activeId) {
            clearActiveConversationIfNeeded()
        }
        do {
            let count = try conversationStore.deleteMultiple(ids: ids)
            Self.logger.info("🗑️ Deleted \(count) selected conversations")
        } catch {
            Self.logger.error("❌ Failed to delete selected conversations: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Delete conversations older than a given number of days.
    func deleteConversationsOlderThan(days: Int) {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        // Check if active conversation is in the deletion set
        if let activeId = activeConversationId,
           let activeEntry = conversationStore.indexEntries.first(where: { $0.id == activeId }),
           activeEntry.lastModifiedAt < cutoff {
            clearActiveConversationIfNeeded()
        }
        do {
            let count = try conversationStore.deleteOlderThan(cutoff)
            Self.logger.info("🗑️ Deleted \(count) conversations older than \(days) days")
        } catch {
            Self.logger.error("❌ Failed to delete old conversations: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Helper: Clears the active conversation state when the active conversation is being deleted.
    private func clearActiveConversationIfNeeded() {
        activeConversationId = nil
        if isViewingArchivedConversation {
            conversation.clear()
            isViewingArchivedConversation = false
        }
    }

    // MARK: - Cleanup

    /// Shut down the engine and release resources.
    func shutdown() async {
        Self.logger.info("🛑 Shutdown initiated")
        await sessionController.shutdown()
        isEngineReady = false
        benchmarkInfo = nil
        conversation.clear()
        
        #if os(macOS)
        for client in activeClients.values {
            client.stop()
        }
        activeClients.removeAll()
        #endif
    }

    // MARK: - URL Import

    /// Start importing a model from a HuggingFace URL.
    ///
    /// This opens the import sheet and begins the pipeline. Both the inline
    /// quick-paste field and the ⌘I shortcut call this method.
    ///
    /// - Parameter urlString: The HuggingFace URL to import from.
    func startURLImport(_ urlString: String) {
        pendingImportURL = urlString
        showURLImportSheet = true
    }

    /// Load a model that was imported via URL Import.
    ///
    /// Discovers the downloaded file on disk, then loads it into the engine.
    /// Called from the import sheet's "Load Model" button after download completes.
    ///
    /// - Parameter metadata: The imported model's `DynamicModelMetadata`.
    func loadImportedModel(_ metadata: DynamicModelMetadata) {
        // Refresh to pick up newly downloaded file
        refreshDiscoveredModels()

        // Find the downloaded file among discovered models
        // Check both known and community discovered models
        let filename = metadata.metadata.modelFile

        // Search discovered models for a matching file
        if let match = discoveredModels.first(where: { $0.filename.contains(filename) || filename.contains($0.filename) }) {
            Task {
                await handleModelSelection(match.url)
            }
        } else {
            // If not found in standard discovery, check community models
            statusMessage = "Model downloaded. Select it from the sidebar to load."
        }
    }
}
