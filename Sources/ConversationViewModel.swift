import Foundation
import LiteRTLM
import Observation

/// ViewModel managing the inference engine lifecycle, conversation state,
/// and benchmark data. Consumes InstrumentedEngineProtocol for testability.
@Observable
@MainActor
final class ConversationViewModel {

    // MARK: - Published State

    /// Status message displayed in the header (e.g., "Engine Ready! 🎉").
    var statusMessage = "Please select a model file..."

    /// User's current prompt text.
    var prompt = "Explain quantum computing in one sentence."

    /// Accumulated response text from the current inference.
    var responseText = ""

    /// Whether an inference is currently in progress.
    var isGenerating = false

    /// Whether GPU backend is preferred.
    var useGPU = true

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
    )

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

    // MARK: - Internal State

    /// The URL of the currently loaded model file (for security scope management).
    private(set) var activeModelURL: URL?

    /// Models discovered from local storage and AI Edge Gallery.
    var discoveredModels: [DiscoveredModel] = []

    /// Download manager for fetching models from HuggingFace.
    let downloadManager: ModelDownloadManager

    /// The most recent device-level inference metrics (thermal, memory, per-token latency).
    var inferenceMetrics: InferenceMetrics? { engine.lastInferenceMetrics }

    /// Whether the engine is initialized and ready for inference.
    var isEngineReady: Bool { engine.isReady }

    // MARK: - Dependencies

    let engine: InstrumentedEngineProtocol
    private let metricsStore: MetricsStore

    // MARK: - Init

    /// Initialize with injectable dependencies.
    /// - Parameters:
    ///   - engine: The instrumented engine (real or mock).
    ///   - metricsStore: The metrics persistence layer.
    ///   - downloadManager: The model download manager.
    init(
        engine: InstrumentedEngineProtocol = InstrumentedEngine(),
        metricsStore: MetricsStore = MetricsStore(),
        downloadManager: ModelDownloadManager = ModelDownloadManager()
    ) {
        self.engine = engine
        self.metricsStore = metricsStore
        self.downloadManager = downloadManager
    }

    // MARK: - Model Loading

    /// Handle a model file selection from the file picker.
    func handleModelSelection(_ url: URL) async {
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

    /// Discover available models from local storage and Gallery, auto-load if possible.
    func checkForLocalModels() {
        discoveredModels = GalleryModelDiscovery.discoverModels()

        if let firstModel = discoveredModels.first {
            statusMessage = "Found model: \(firstModel.filename)"
            if firstModel.source == .edgeGallery {
                statusMessage += " (via Edge Gallery)"
            }
            activeModelURL = firstModel.url
            Task {
                await initializeEngine(modelPath: firstModel.url.path)
            }
        }
    }

    /// Refresh the discovered models list without auto-loading.
    func refreshDiscoveredModels() {
        discoveredModels = GalleryModelDiscovery.discoverModels()
    }

    /// Initialize the inference engine with a model file, using smart backend fallback.
    func initializeEngine(modelPath: String) async {
        statusMessage = "Initializing Engine..."

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
            let samplerConfig = try? SamplerConfig(
                topK: topK,
                topP: topP,
                temperature: temperature,
                seed: seed
            )

            // Use smart fallback initialization
            let result = try await engine.initializeWithFallback(
                modelPath: modelPath,
                preferGPU: useGPU,
                cacheDir: modelCacheDirectory.path,
                flags: experimentalFlags,
                samplerConfig: samplerConfig,
                systemMessage: systemMessage.isEmpty ? nil : systemMessage
            )

            backendResult = result

            let backendLabel = result.activeBackend == .gpu ? "GPU 🚀" : "CPU"
            let modelLabel = activeModelMetadata?.name ?? modelFilename

            if result.didFallback {
                statusMessage = "\(modelLabel) ready (\(backendLabel)) ⚠️ Fallback"
            } else {
                statusMessage = "\(modelLabel) ready (\(backendLabel)) 🎉"
            }
        } catch {
            backendResult = nil
            statusMessage = "Failed to initialize: \(error.localizedDescription)"
        }
    }

    // MARK: - Inference

    /// Generate a response for the current prompt via streaming.
    func generateText() async {
        guard engine.isReady else { return }

        isGenerating = true
        responseText = ""
        benchmarkInfo = nil

        // Capture and clear multimodal attachments before inference
        let imageData = selectedImageData
        let audioData = selectedAudioData
        selectedImageData = nil
        selectedAudioData = nil

        do {
            let stream: AsyncThrowingStream<String, Error>
            if imageData != nil || audioData != nil {
                stream = engine.sendMessageStream(
                    prompt,
                    imageData: imageData,
                    audioData: audioData
                )
            } else {
                stream = engine.sendMessageStream(prompt)
            }

            for try await chunk in stream {
                responseText += chunk
            }

            // Capture benchmark data after inference completes
            benchmarkInfo = engine.lastBenchmarkInfo

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
                    print("[MetricsStore] Failed to persist entry: \(error.localizedDescription)")
                }
            }
        } catch {
            responseText = "Inference error: \(error.localizedDescription)"
        }

        isGenerating = false
    }

    // MARK: - Cleanup

    /// Shut down the engine and release resources.
    func shutdown() async {
        activeModelURL?.stopAccessingSecurityScopedResource()
        activeModelURL = nil
        activeModelMetadata = nil
        backendResult = nil
        await engine.shutdown()
        benchmarkInfo = nil
    }
}
