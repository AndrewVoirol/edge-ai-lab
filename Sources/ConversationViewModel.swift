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

    /// Whether GPU backend is selected.
    var useGPU = true

    /// The most recent BenchmarkInfo from completed inference.
    var benchmarkInfo: BenchmarkInfo?

    /// Whether to show the file picker.
    var isFilePickerPresented = false

    /// Current experimental flags configuration (user-toggleable, default ON).
    var experimentalFlags = ExperimentalFlagsState(
        enableBenchmark: true,
        enableSpeculativeDecoding: nil,
        enableConversationConstrainedDecoding: false,
        visualTokenBudget: nil
    )

    // MARK: - Internal State

    /// The URL of the currently loaded model file (for security scope management).
    private(set) var activeModelURL: URL?

    /// Whether the engine is initialized and ready for inference.
    var isEngineReady: Bool { engine.isReady }

    // MARK: - Dependencies

    private let engine: InstrumentedEngineProtocol
    private let metricsStore: MetricsStore

    // MARK: - Init

    /// Initialize with injectable dependencies.
    /// - Parameters:
    ///   - engine: The instrumented engine (real or mock).
    ///   - metricsStore: The metrics persistence layer.
    init(
        engine: InstrumentedEngineProtocol = InstrumentedEngine(),
        metricsStore: MetricsStore = MetricsStore()
    ) {
        self.engine = engine
        self.metricsStore = metricsStore
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

        await initializeEngine(modelPath: url.path)
    }

    /// Initialize the inference engine with a model file.
    func initializeEngine(modelPath: String) async {
        statusMessage = "Initializing Engine..."
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

            try await engine.initialize(
                modelPath: modelPath,
                useGPU: useGPU,
                cacheDir: modelCacheDirectory.path,
                flags: experimentalFlags
            )

            statusMessage = "Engine Ready! 🎉"
        } catch {
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

        do {
            for try await chunk in engine.sendMessageStream(prompt) {
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
                    flags: engine.flagsState
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
    func shutdown() {
        activeModelURL?.stopAccessingSecurityScopedResource()
        activeModelURL = nil
        engine.shutdown()
        benchmarkInfo = nil
    }
}
