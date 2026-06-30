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
import LiteRTLM  // Still needed for SamplerConfig, Tool, BackendResult during Phase 2 migration
import os

/// Manages engine initialization, sampler configuration, tool setup, and backend fallback.
///
/// Extracted from `ConversationViewModel` to separate "configure and boot a model" from
/// "run a conversation." This class is owned by the ViewModel and is NOT injected into the
/// SwiftUI environment — views continue observing the ViewModel's forwarded properties.
///
/// Responsibilities:
/// - Model file selection and security-scoped resource management
/// - Engine initialization with smart backend fallback (GPU → CPU)
/// - Sampler config building (topK, topP, temperature, seed)
/// - Tool setup (built-in tools + MCP bridges + agent skills)
/// - Re-initialization when settings change
@MainActor
final class ModelSessionController {

    private static let logger = Logger(
        subsystem: "com.andrewvoirol.EdgeAILab.performance",
        category: "sessionController"
    )

    // MARK: - State

    /// The URL of the currently loaded model file (for security scope management).
    private(set) var activeModelURL: URL?

    /// Metadata for the currently loaded model, if known.
    private(set) var activeModelMetadata: ModelMetadata?

    /// Result of the last backend initialization (active backend, fallback info).
    private(set) var backendResult: BackendResult?

    /// Whether a model is currently being loaded.
    private(set) var isLoadingModel = false

    /// Tracks the active model load task for cancellation support.
    private var modelLoadTask: Task<Void, Never>?

    // MARK: - Sampler Configuration

    /// Top-K sampling parameter. Set to 1 for greedy (Gallery-matching) decoding.
    var topK: Int = 64

    /// Top-P (nucleus) sampling parameter.
    var topP: Float = 0.95

    /// Temperature for sampling. Higher = more random.
    var temperature: Float = 1.0

    /// Seed for reproducible generation. 0 = non-deterministic (SDK default).
    var seed: Int = 0

    /// Optional system message to set model persona/instructions.
    var systemMessage: String = ""

    // MARK: - Dependencies

    let engine: any InferenceEngine
    var onStatusMessage: (String) -> Void
    /// Callback when model-specific sampler defaults are applied (so the ViewModel can sync).
    var onSamplerDefaultsApplied: ((Int, Float, Float) -> Void)?
    /// Callback when engine readiness state changes (so the ViewModel can update its tracked property).
    var onEngineReadyChanged: ((Bool) -> Void)?
    /// Default experimental flags to use when none are explicitly passed.
    var defaultExperimentalFlags: ExperimentalFlagsState?

    // MARK: - Init

    /// Initialize with dependencies.
    /// - Parameters:
    ///   - engine: The instrumented engine (real or mock).
    ///   - onStatusMessage: Callback for status message updates to the ViewModel.
    init(
        engine: any InferenceEngine,
        onStatusMessage: @escaping (String) -> Void
    ) {
        self.engine = engine
        self.onStatusMessage = onStatusMessage
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

    /// Initialize the inference engine with a model file, using smart backend fallback.
    ///
    /// - Parameters:
    ///   - modelPath: Absolute path to the model file.
    ///   - experimentalFlags: Current experimental flags configuration.
    ///   - useGPU: Whether GPU backend is preferred.
    ///   - mcpClients: Active MCP clients (macOS only) for tool bridging.
    func initializeEngine(
        modelPath: String,
        experimentalFlags: ExperimentalFlagsState? = nil,
        useGPU: Bool? = nil,
        mcpClients: [UUID: Any] = [:]
    ) async {
        // Cancel any in-progress load
        modelLoadTask?.cancel()

        isLoadingModel = true
        onStatusMessage("Initializing Engine...")

        // Start a timeout timer that updates the status message
        let timeoutTask = Task {
            try? await Task.sleep(for: .seconds(30))
            if !Task.isCancelled && self.isLoadingModel {
                self.onStatusMessage("Initializing Engine... (taking longer than expected…)")
            }
        }

        let modelName = (modelPath as NSString).lastPathComponent
        let preferGPU = useGPU ?? true
        Self.logger.info("⏳ initializeEngine: \(modelName, privacy: .public) GPU=\(preferGPU)")

        // Look up model metadata for known models
        activeModelMetadata = ModelRegistry.lookup(path: modelPath)
        if let metadata = activeModelMetadata {
            onStatusMessage("Loading \(metadata.name)...")
            // Apply model's default sampler config
            topK = metadata.defaultConfig.topK
            topP = Float(metadata.defaultConfig.topP)
            temperature = Float(metadata.defaultConfig.temperature)
            // Notify the ViewModel so it can sync its own properties
            onSamplerDefaultsApplied?(topK, topP, temperature)
        }

        let flags = experimentalFlags ?? defaultExperimentalFlags ?? ExperimentalFlagsState(
            enableBenchmark: true,
            enableSpeculativeDecoding: nil,
            enableConversationConstrainedDecoding: false,
            visualTokenBudget: nil
        )

        do {
            let fileManager = FileManager.default
            guard let cacheBaseDirectory = fileManager.urls(
                for: .cachesDirectory, in: .userDomainMask
            ).first else {
                onStatusMessage("Could not find caches directory")
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
            let samplerConfig = buildSamplerConfig(modelFilename: modelFilename)

            // Prepare tools if tool calling is enabled
            let tools = buildActiveTools(flags: flags, mcpClients: mcpClients)

            var activeFlags = flags

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
                    flags.enableThinking ? thinkingTrigger : nil,
                    systemMessage.isEmpty ? nil : systemMessage
                ].compactMap { $0 }
                return parts.isEmpty ? nil : parts.joined(separator: "\n")
            }()

            // Use runtime-specific initialization
            if let liteRTAdapter = engine as? LiteRTEngineAdapter {
                // LiteRT path: use loadWithLiteRTConfig for full tool/flags/backend support
                let result = try await liteRTAdapter.loadWithLiteRTConfig(
                    modelPath: modelPath,
                    preferGPU: preferGPU,
                    cacheDir: modelCacheDirectory.path,
                    flags: activeFlags,
                    samplerConfig: samplerConfig,
                    systemMessage: composedSystemMessage,
                    tools: tools,
                    supportsVision: activeModelMetadata?.supportsImage ?? false,
                    supportsAudio: activeModelMetadata?.supportsAudio ?? false
                )
                backendResult = result
            } else {
                // Generic InferenceEngine path (MLX, future runtimes)
                let genConfig = GenerationConfig(
                    temperature: Double(temperature),
                    topP: Double(topP),
                    topK: Int(topK),
                    seed: seed > 0 ? UInt64(seed) : nil
                )
                let loadConfig = ModelLoadConfig(
                    modelPath: modelPath,
                    preferGPU: preferGPU,
                    cacheDir: modelCacheDirectory.path,
                    systemMessage: composedSystemMessage,
                    supportsVision: activeModelMetadata?.supportsImage ?? false,
                    supportsAudio: activeModelMetadata?.supportsAudio ?? false,
                    generationConfig: genConfig,
                    experimentalFlags: activeFlags
                )
                try await engine.loadModel(config: loadConfig)
                backendResult = nil
            }
            let modelLabel = activeModelMetadata?.name ?? modelFilename

            if let result = backendResult {
                let backendLabel = result.activeBackend == .gpu ? "GPU" : "CPU"
                if result.didFallback {
                    onStatusMessage("\(modelLabel) ready (\(backendLabel)) ⚠️ Fallback")
                } else {
                    onStatusMessage("\(modelLabel) ready (\(backendLabel))")
                }
                Self.logger.info("✅ Engine initialized: backend=\(backendLabel, privacy: .public)")
            } else {
                // Generic engine (MLX, etc.) — no backend info
                onStatusMessage("\(modelLabel) ready")
                Self.logger.info("✅ Engine initialized")
            }
            onEngineReadyChanged?(true)

        } catch {
            backendResult = nil
            onStatusMessage("Failed to initialize: \(error.localizedDescription)")
            Self.logger.error("❌ Engine init failed: \(error.localizedDescription, privacy: .public)")
            onEngineReadyChanged?(false)
        }

        timeoutTask.cancel()
        isLoadingModel = false
    }

    /// Cancel an in-progress model load.
    func cancelModelLoad() {
        modelLoadTask?.cancel()
        modelLoadTask = nil
        isLoadingModel = false
        onStatusMessage("Model load cancelled")
    }

    /// Reboots the engine to apply new core settings if a model is currently loaded.
    func reinitializeIfNeeded(
        experimentalFlags: ExperimentalFlagsState,
        useGPU: Bool,
        mcpClients: [UUID: Any] = [:]
    ) async {
        guard engine.isLoaded, let url = activeModelURL else { return }
        Self.logger.info("♻️ Settings changed, rebooting engine to apply new configuration...")
        onStatusMessage("Applying new settings...")
        engine.shutdown()
        await initializeEngine(
            modelPath: url.path,
            experimentalFlags: experimentalFlags,
            useGPU: useGPU,
            mcpClients: mcpClients
        )
    }

    /// Shut down the engine and release resources.
    func shutdown() async {
        Self.logger.info("🛑 Session shutdown initiated")
        activeModelURL?.stopAccessingSecurityScopedResource()
        activeModelURL = nil
        activeModelMetadata = nil
        backendResult = nil
        engine.shutdown()
        onEngineReadyChanged?(false)
    }

    // MARK: - Private Helpers

    /// Build a SamplerConfig from current settings.
    private func buildSamplerConfig(modelFilename: String) -> SamplerConfig? {
        // LiteRTLM WebGPU sampler expects topK <= 1 if temperature is 0.0 (greedy decoding)
        // Additionally, Mobile GPU (web) variants are hard-compiled with topK=1 limitation.
        var actualTopK = topK
        if temperature == 0.0 || modelFilename.contains("-web") {
            actualTopK = 1
        }
        do {
            return try SamplerConfig(
                topK: actualTopK,
                topP: topP,
                temperature: temperature,
                seed: seed
            )
        } catch {
            Self.logger.warning("⚠️ SamplerConfig creation failed: \(error.localizedDescription, privacy: .public). Using SDK defaults.")
            return nil
        }
    }

    /// Build the list of active tools based on flags and MCP clients.
    private func buildActiveTools(
        flags: ExperimentalFlagsState,
        mcpClients: [UUID: Any]
    ) -> [Tool]? {
        guard flags.enableToolCalling else { return nil }

        var activeTools: [Tool] = []
        activeTools.append(contentsOf: ToolRegistry.defaultTools)

        if flags.enableAgentSkills {
            activeTools.append(WikipediaSkillTool())
            activeTools.append(MapSkillTool())
        }

        #if os(macOS)
        // Bridge MCP tools
        MCPBridgeManager.shared.clear()
        for (_, client) in mcpClients {
            if let mcpClient = client as? MCPClient,
               case .connected(let toolsList) = mcpClient.state {
                let bridged = MCPBridgeManager.shared.bridge(tools: toolsList, client: mcpClient)
                activeTools.append(contentsOf: bridged)
            }
        }
        #endif

        return activeTools.isEmpty ? nil : activeTools
    }
}
