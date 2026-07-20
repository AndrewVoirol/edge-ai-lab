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
import LiteRTLM  // Still needed for BenchmarkInfo references in MetricsStore during Phase 2 migration
import Observation
import os

/// ViewModel managing the inference engine lifecycle, conversation state,
/// and benchmark data. Consumes InferenceEngine for testability.
@Observable
@MainActor
final class ConversationViewModel {
    
    // NOTE: The singleton `static let shared` was intentionally removed.
    // Views access this via @Environment injection from EdgeAILabApp.
    // See: Apple's "Managing model data in your app" (WWDC 2023+).

    /// Console logger for runtime diagnostics (visible in Console.app).
    /// Internal (not private) because extensions in separate files need access.
    static let logger = Logger(
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

    /// User-selected inference backend (per-session, resets to GPU-preferred on new session).
    /// Controls whether the engine uses GPU or CPU acceleration.
    /// Replaces the raw `useGPU` Bool with a typed option extensible for NPU.
    var preferredBackend: BackendOption = .gpu {
        didSet {
            scheduleReinit()
        }
    }

    /// Whether GPU backend is preferred — derived from `preferredBackend`.
    /// Backward-compatible accessor for existing engine initialization path.
    var useGPU: Bool {
        BackendPickerLogic.useGPU(for: preferredBackend)
    }

    /// Maximum number of tokens for the KV-cache (per-session, nil = auto/SDK default).
    /// Controls context window size and memory usage.
    var maxNumTokens: Int? = nil {
        didSet {
            sessionController.maxNumTokens = maxNumTokens
            scheduleReinit()
        }
    }

    /// The backend and KV-cache settings that were active when the engine was last initialized.
    /// Used to detect whether the user has changed settings since last load.
    private var lastInitializedBackend: BackendOption?
    private var lastInitializedMaxNumTokens: Int??

    /// Whether the current backend/KV-cache settings differ from what's running.
    /// When true, the UI should show a "Restart Engine" prompt.
    var engineConfigChanged: Bool {
        guard isEngineReady else { return false }
        if let lastBackend = lastInitializedBackend, lastBackend != preferredBackend {
            return true
        }
        // Compare Optional<Int> — double-optional unwrap
        if let lastTokens = lastInitializedMaxNumTokens, lastTokens != maxNumTokens {
            return true
        }
        return false
    }


    /// The most recent performance metrics from completed inference.
    var performanceMetrics: EnginePerformanceMetrics?

    /// Backward-compatible accessor for views still using `BenchmarkInfo`.
    /// Returns the LiteRT-LM `BenchmarkInfo` if the engine is a `LiteRTEngineAdapter`.
    /// Will be removed in Phase 2 Consumers when all views migrate to `EnginePerformanceMetrics`.
    var benchmarkInfo: BenchmarkInfo? {
        (engine as? LiteRTEngineAdapter)?.lastBenchmarkInfo
    }

    /// Whether to show the file picker.
    var isFilePickerPresented = false

    /// Result of the last backend initialization (active backend, fallback info).
    var backendResult: BackendResult?

    /// Capability profile for the currently loaded model.
    /// The single source of truth for model identity, capabilities, and operational config.
    /// Synced from ModelSessionController via `onActiveModelChanged` callback.
    var activeCapabilityProfile: ModelCapabilityProfile?

    /// Current runtime flags configuration (user-toggleable, default ON).
    var runtimeFlags = RuntimeFlags(
        enableBenchmark: true,
        enableSpeculativeDecoding: nil,
        enableConversationConstrainedDecoding: false,
        visualTokenBudget: nil
    ) {
        didSet {
            sessionController.defaultRuntimeFlags = runtimeFlags
            scheduleReinit()
        }
    }

    // MARK: - Sampler Configuration

    /// Top-K sampling parameter. Set to 1 for greedy (Gallery-matching) decoding.
    var topK: Int = 64 {
        didSet {
            sessionController.topK = topK
            if !isSyncingSettings && !sessionController.applySamplerSettingsInPlace() {
                scheduleReinit()
            }
        }
    }

    /// Top-P (nucleus) sampling parameter.
    var topP: Float = 0.95 {
        didSet {
            sessionController.topP = topP
            if !isSyncingSettings && !sessionController.applySamplerSettingsInPlace() {
                scheduleReinit()
            }
        }
    }

    /// Temperature for sampling. Higher = more random.
    var temperature: Float = 1.0 {
        didSet {
            sessionController.temperature = temperature
            if !isSyncingSettings && !sessionController.applySamplerSettingsInPlace() {
                scheduleReinit()
            }
        }
    }

    /// Seed for reproducible generation. 0 = non-deterministic (SDK default).
    var seed: Int = 0 {
        didSet {
            sessionController.seed = seed
            if !sessionController.applySamplerSettingsInPlace() {
                scheduleReinit()
            }
        }
    }

    /// Optional system message to set model persona/instructions.
    var systemMessage: String = "" {
        didSet { sessionController.systemMessage = systemMessage; scheduleReinit() }
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
        activeCapabilityProfile?.hasVision ?? false
    }

    /// Whether the currently loaded model supports audio input.
    var supportsAudioInput: Bool {
        activeCapabilityProfile?.hasAudio ?? false
    }

    // MARK: - Thinking Mode State

    /// Accumulated thinking content from the current streaming inference.
    /// Populated by the ThinkingParser as `<think>` blocks are received.
    var currentThinkingText: String = ""

    /// Whether the model is currently in the "thinking" phase of its response.
    var isThinking: Bool = false

    /// Parser instance for the current streaming response.
    var thinkingParser = ThinkingParser()

    // MARK: - Tool Calling State

    /// Tool call events from the current/last inference (for observability).
    var toolCallEvents: [ToolCallEvent] = []

    // MARK: - Agent Mode

    /// When true, the next prompt submission runs through the agentic ReAct loop
    /// instead of a single inference turn.
    var isAgentMode = false

    /// The stateful harness that drives multi-step autonomous reasoning.
    let agentHarness = AgentHarness()

    /// Tool names from `ToolRegistry.defaultTools`, used in the agent system prompt.
    nonisolated static let availableToolNames: [String] = [
        CalculatorTool.name,
        DateTimeTool.name,
        DeviceInfoTool.name,
        UnitConverterTool.name,
        TextAnalyzerTool.name,
        SystemHealthTool.name,
        LocationTool.name,
        MotionTool.name,
        CameraTool.name,
        FileSearchTool.name,
        SensorsTool.name,
        WiFiTool.name,
        ShortcutsTool.name,
    ]

    // MARK: - Internal State

    /// Tracks the active engine switch task to prevent concurrent switches.
    /// If the user clicks through engines rapidly (LiteRT → MLX → GGUF),
    /// each switch cancels the previous one so only the final engine is started.
    private var activeSwitchTask: Task<Void, Never>?

    /// True during an active engine switch. Prevents `reinitializeEngineIfNeeded()`
    /// from racing with the switch's shutdown → create → load sequence.
    private var isEngineSwitching = false

    /// Tracks the active reinit task to cancel-and-replace on rapid settings changes.
    /// Prevents rapid slider changes (temperature, topK) from launching parallel reinit Tasks.
    private var activeReinitTask: Task<Void, Never>?

    /// The URL of the currently loaded model file (for security scope management).
    /// Stored (not computed) so that @Observable tracks mutations and SwiftUI re-renders.
    /// Synced from ModelSessionController via `onActiveModelChanged` callback.
    var activeModelURL: URL?

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
    /// Stored property (not computed) because `engine` is `@ObservationIgnored`.
    var inferenceMetrics: InferenceMetrics?

    /// Whether the engine is initialized and ready for inference.
    ///
    /// This is a tracked stored property (not a computed property) because the engine
    /// is `@ObservationIgnored`. If we derived this from `engine.isReady`, SwiftUI would
    /// never observe changes — views would show stale state (e.g., "No Model Loaded" after
    /// a conversation reset even though the model is still loaded). The ViewModel explicitly
    /// updates this via `onEngineReadyChanged` from ModelSessionController.
    private(set) var isEngineReady: Bool = false

    // MARK: - Canvas Panel State

    /// The HTML content currently displayed in the Canvas side panel.
    /// Set by CodeBlockView's "Open in Canvas" button, cleared by the panel's close button.
    var activeCanvasContent: CanvasContent?

    /// Stashed canvas content for ⌘⇧K toggle restore. Populated when canvas is closed
    /// so the toggle command can reopen the last viewed content.
    var lastCanvasContent: CanvasContent?

    // MARK: - Model Showcase State

    /// The model to display in the Model Showcase sheet.
    /// Set by context menus (macOS sidebar, iOS model hub) and toolbar buttons (iOS detail view).
    var showcaseModel: ModelMetadata?

    /// The file URL for the model shown in the showcase sheet.
    var showcaseModelURL: URL?

    // MARK: - MCP Servers Support

    var mcpServers: [MCPServerConfig] = []

    #if os(macOS)
    var activeClients: [UUID: MCPClient] = [:]
    #endif

    // MARK: - Dependencies

    /// @ObservationIgnored: Internal dependencies — views never observe these directly.
    @ObservationIgnored
    private(set) var engine: any InferenceEngine
    @ObservationIgnored
    let metricsStore: MetricsStore
    /// @ObservationIgnored: Views that need ConversationStore should observe it
    /// directly via @Environment or receive it as a parameter.
    @ObservationIgnored
    let conversationStore: ConversationStore
    /// @ObservationIgnored: Session controller owns engine init, sampler config,
    /// tool setup, and backend fallback. Not directly observable by views.
    @ObservationIgnored
    let sessionController: ModelSessionController

    /// The currently selected runtime type for inference.
    /// Changing this triggers an engine swap via `switchEngine(to:)`.
    var selectedRuntimeType: RuntimeType = .litertlm

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
        engine: any InferenceEngine = LiteRTEngineAdapter(),
        metricsStore: MetricsStore = MetricsStore(),
        downloadManager: ModelDownloadManager? = nil,
        conversationStore: ConversationStore? = nil,
        dynamicModelCatalog: DynamicModelCatalog? = nil
    ) {
        self.engine = engine
        self.selectedRuntimeType = engine.runtimeType
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
            // Sync backendResult — it's set just before this callback fires
            self?.backendResult = controller.backendResult
            if ready {
                // Snapshot current config so we can detect mid-session changes
                self?.lastInitializedBackend = self?.preferredBackend
                self?.lastInitializedMaxNumTokens = self?.maxNumTokens
            }
        }
        // Sync sampler defaults back to the VM when model-specific configs are applied
        controller.onSamplerDefaultsApplied = { [weak self] topK, topP, temperature in
            self?.topK = topK
            self?.topP = topP
            self?.temperature = temperature
        }
        // Sync active model identity so SwiftUI observes changes
        controller.onActiveModelChanged = { [weak self] profile, url in
            self?.activeCapabilityProfile = profile
            self?.activeModelURL = url
            self?.backendResult = controller.backendResult
        }
        // Give the controller access to the VM's experimental flags by default
        controller.defaultRuntimeFlags = runtimeFlags

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

    // MARK: - Engine Switching

    /// Switch the active inference engine to a different runtime type.
    ///
    /// This performs a safe engine swap:
    /// 1. Stop any in-flight generation (prevents dangling async tasks on old engine)
    /// 2. Cancel any in-flight engine switch (prevents orphan engines on rapid switching)
    /// 3. Shut down the current engine via session controller (awaits full resource release)
    /// 4. Create a new engine via `EngineFactory`
    /// 5. Update both the ViewModel and SessionController references
    /// 6. Reset stale state (conversation, metrics, config flags)
    /// 7. Rollback picker binding on failure so UI always matches actual engine
    ///
    /// If a model was loaded, the caller should trigger a reload on the new engine.
    func switchEngine(to runtimeType: RuntimeType) async {
        guard runtimeType != self.engine.runtimeType else { return }

        isEngineSwitching = true
        defer { isEngineSwitching = false }

        // Capture for rollback if the switch fails (Defect #4 fix).
        // The EnginePickerView binding has already updated `selectedRuntimeType`
        // via the two-way `$viewModel.selectedRuntimeType` binding before this
        // method runs, so we save the actual engine's type for rollback.
        let previousRuntime = self.engine.runtimeType

        // Stop any in-flight generation before switching (Defect #3 fix).
        // Without this, the generation Task holds a strong reference to the old
        // engine and may access it after shutdown(), causing use-after-free.
        if isGenerating {
            stopGenerating()
        }

        // Cancel any in-flight switch (Defect #5 fix, Phase 2 completion).
        // Rapid engine picker changes (LiteRT → MLX → GGUF) would otherwise
        // create multiple engine instances with only the last one assigned.
        activeSwitchTask?.cancel()

        // Clear stale state from the previous engine (Defect #6 fix).
        // These values are engine-specific and meaningless after a switch.
        isEngineReady = false
        performanceMetrics = nil
        inferenceMetrics = nil
        lastInitializedBackend = nil       // Prevent false "Restart Engine" prompt
        lastInitializedMaxNumTokens = nil  // Prevent false "Restart Engine" prompt
        conversation.clear()

        // Wrap the expensive async work in a tracked Task so rapid switches
        // can cancel in-flight work. We await it to preserve the async contract
        // for callers that depend on switch completion (tests, handleModelSelection).
        let task = Task { @MainActor [weak self] in
            guard let self else { return }

            do {
                let newEngine = try EngineFactory.createEngine(for: runtimeType)

                // Check cancellation before the expensive shutdown + swap.
                // If a newer switch arrived while we were creating the engine,
                // discard this one — the newer switch will handle cleanup.
                try Task.checkCancellation()

                // Delegate the safe shutdown + swap to the session controller.
                // This awaits the old engine's shutdown(), ensuring Metal resources
                // and C++ handles are fully released before the new engine starts.
                await sessionController.replaceEngine(newEngine)

                try Task.checkCancellation()

                // Sync the ViewModel's own engine reference
                engine = newEngine
                selectedRuntimeType = runtimeType

                Self.logger.info("✅ Engine switched to \(runtimeType.displayName)")
            } catch is CancellationError {
                // Switch was superseded by a newer switch request — expected behavior.
                Self.logger.info("⏭️ Engine switch to \(runtimeType.displayName) cancelled (superseded)")
            } catch {
                // Rollback the picker binding to match the actual engine state (Defect #4 fix).
                // Without this, the EnginePickerView shows the requested engine but
                // the actual engine is still the previous one.
                selectedRuntimeType = previousRuntime
                statusMessage = "Failed to create \(runtimeType.displayName) engine: \(error.localizedDescription)"
                Self.logger.error("❌ Engine switch failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        activeSwitchTask = task

        // Await the task so callers can depend on switch completion.
        await task.value
    }

    // MARK: - Model Loading

    /// Handle a model file selection from the file picker.
    ///
    /// Auto-detects the model format and switches engines if needed before loading.
    func handleModelSelection(_ url: URL) async {
        // Cancel any in-flight engine switch — model selection takes priority (Defect #7 fix).
        // This prevents a race where a switch task is mid-shutdown while we try to load a model.
        activeSwitchTask?.cancel()
        activeSwitchTask = nil

        // Auto-detect format and switch engines if the model requires a different runtime.
        let detectedFormat = ModelFormatDetector.detectFormat(at: url)

        if let detectedFormat, detectedFormat != self.engine.runtimeType {
            Self.logger.info("🔄 Auto-switching engine: \(self.engine.runtimeType.displayName) → \(detectedFormat.displayName) for \(url.lastPathComponent, privacy: .public)")
            // Switch the engine — it's now purely lifecycle (shutdown old → create new).
            // Model loading always happens below via sessionController.handleModelSelection.
            await switchEngine(to: detectedFormat)
        }

        // Resolve metadata from discoveredModels for community/imported models.
        let discoveredMatch = discoveredModels.first { $0.url == url }
        let discoveredMeta = discoveredMatch?.resolvedMetadata

        await sessionController.handleModelSelection(url, metadata: discoveredMeta, mmProjPath: discoveredMatch?.mmProjPath)
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
        isEngineReady = self.engine.isLoaded
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

    /// Download an MLX model from the registry using the multi-file download flow.
    ///
    /// This fetches the file manifest from HuggingFace, filters to required MLX files,
    /// and initiates a parallel multi-file download via `ModelDownloadManager`.
    ///
    /// - Parameter model: The registry model metadata for the MLX model.
    func downloadMLXRegistryModel(_ model: ModelMetadata) async {
        Self.logger.info("🔽 downloadMLXRegistryModel: \(model.name, privacy: .public) (\(model.modelId, privacy: .public))")
        guard model.isMLXDirectoryModel else {
            Self.logger.warning("⚠️ Model is not MLX directory type, falling back to single-file download")
            downloadManager.download(model)
            return
        }

        statusMessage = "Fetching model manifest..."
        let browser = HFModelBrowser()
        do {
            let manifest = try await browser.fetchFileManifest(for: model.modelId)
            let required = HFModelBrowser.filterRequiredMLXFiles(manifest)
            Self.logger.info("📋 Manifest: \(manifest.count) total files, \(required.count) required for \(model.modelId, privacy: .public)")
            let descriptors = HFModelBrowser.downloadDescriptors(
                repoId: model.modelId,
                requiredFiles: required
            )
            downloadManager.downloadMLXModel(
                modelId: model.modelId,
                descriptors: descriptors
            )
            statusMessage = "Downloading \(model.name)..."
            Self.logger.info("✅ MLX directory download started for \(model.name, privacy: .public)")
        } catch {
            statusMessage = "Failed to fetch manifest: \(error.localizedDescription)"
            Self.logger.error("❌ Manifest fetch failed for \(model.modelId, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Cancel an in-progress model load.
    func cancelModelLoad() {
        sessionController.cancelModelLoad()
    }

    /// Reboots the engine to apply new core settings if a model is currently loaded.
    private func reinitializeEngineIfNeeded() async {
        guard !isEngineSwitching else { return }
        var mcpClients: [UUID: Any] = [:]
        #if os(macOS)
        mcpClients = activeClients
        #endif
        await sessionController.reinitializeIfNeeded(
            runtimeFlags: runtimeFlags,
            useGPU: useGPU,
            mcpClients: mcpClients
        )
    }

    /// Debounced reinit scheduler. Cancels any pending reinit and starts a new one
    /// after 200ms of idle time. This prevents rapid slider changes from triggering
    /// multiple concurrent engine shutdowns + reinitializations.
    private func scheduleReinit() {
        activeReinitTask?.cancel()
        activeReinitTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            await self?.reinitializeEngineIfNeeded()
        }
    }

    /// Force-restarts the engine with current settings.
    /// Called from the "Restart Engine" button when backend or KV-cache settings
    /// have changed mid-session and the user explicitly requests a restart.
    func restartEngine() async {
        await reinitializeEngineIfNeeded()
    }

    // MARK: - Inference State

    /// Monotonically increasing generation counter. Tool callback Tasks check this
    /// to avoid mutating conversation state after a generation has been superseded.
    /// Declared here because Swift extensions cannot add stored properties to classes.
    /// Used by ConversationViewModel+Inference.swift.
    var inferenceGenerationId: Int = 0

    // MARK: - Cleanup

    /// Shut down the engine and release resources.
    func shutdown() async {
        Self.logger.info("🛑 Shutdown initiated")
        await sessionController.shutdown()
        isEngineReady = false
        performanceMetrics = nil
        activeCapabilityProfile = nil
        activeModelURL = nil
        backendResult = nil
        statusMessage = "Model unloaded. Select a model to get started."
        conversation.clear()
        
        #if os(macOS)
        for client in activeClients.values {
            client.stop()
        }
        activeClients.removeAll()
        #endif
    }
}

