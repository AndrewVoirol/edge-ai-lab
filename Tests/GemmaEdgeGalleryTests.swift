import XCTest
import LiteRTLM

#if os(iOS)
@testable import GemmaEdgeGallery_iOS
#elseif os(macOS)
@testable import GemmaEdgeGallery_macOS
#endif

// MARK: - ViewModel Tests

final class ConversationViewModelTests: XCTestCase {

    private var mockEngine: MockInstrumentedEngine!
    private var metricsStore: MetricsStore!
    private var metricsFileURL: URL!

    @MainActor
    override func setUp() {
        super.setUp()
        mockEngine = MockInstrumentedEngine()

        // Use a temp file for metrics store to avoid polluting real data
        metricsFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_metrics_\(UUID().uuidString).json")
        metricsStore = MetricsStore(fileURL: metricsFileURL)
    }

    override func tearDown() {
        // Clean up temp metrics file
        try? FileManager.default.removeItem(at: metricsFileURL)
        super.tearDown()
    }

    @MainActor
    func testInitialState() {
        let vm = ConversationViewModel(engine: mockEngine, metricsStore: metricsStore)

        XCTAssertEqual(vm.statusMessage, "Please select a model file...")
        XCTAssertEqual(vm.responseText, "")
        XCTAssertFalse(vm.isGenerating)
        XCTAssertFalse(vm.isEngineReady)
        XCTAssertNil(vm.benchmarkInfo)
        XCTAssertTrue(vm.experimentalFlags.enableBenchmark)
    }

    @MainActor
    func testEngineInitialization() async {
        let vm = ConversationViewModel(engine: mockEngine, metricsStore: metricsStore)

        await vm.initializeEngine(modelPath: "/path/to/model.litertlm")

        // Status message now includes backend info and model filename
        XCTAssertTrue(vm.statusMessage.contains("ready"))
        XCTAssertTrue(vm.statusMessage.contains("🎉") || vm.statusMessage.contains("Fallback"))
        XCTAssertTrue(vm.isEngineReady)
        // initializeWithFallback calls initialize internally
        XCTAssertGreaterThanOrEqual(mockEngine.initializeCallCount, 1)
        XCTAssertEqual(mockEngine.lastModelPath, "/path/to/model.litertlm")
        XCTAssertNotNil(vm.backendResult)
    }

    @MainActor
    func testEngineInitializationFailure() async {
        mockEngine.initError = NSError(
            domain: "TestError",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "Mock init failure"]
        )
        let vm = ConversationViewModel(engine: mockEngine, metricsStore: metricsStore)

        await vm.initializeEngine(modelPath: "/path/to/bad_model.litertlm")

        // Both backends fail (mock throws on both attempts), so we get a failure message
        XCTAssertTrue(vm.statusMessage.contains("Failed to initialize"))
        XCTAssertFalse(vm.isEngineReady)
        XCTAssertNil(vm.backendResult)
    }

    @MainActor
    func testGenerateTextStreamsResponse() async {
        mockEngine.mockResponseChunks = ["Hello", " ", "World"]
        let vm = ConversationViewModel(engine: mockEngine, metricsStore: metricsStore)

        // Initialize first
        await vm.initializeEngine(modelPath: "/path/to/model.litertlm")
        XCTAssertTrue(vm.isEngineReady)

        // Generate
        await vm.generateText()

        XCTAssertEqual(vm.responseText, "Hello World")
        XCTAssertFalse(vm.isGenerating)
        XCTAssertEqual(mockEngine.sendMessageCallCount, 1)
    }

    @MainActor
    func testGenerateTextInferenceError() async {
        mockEngine.inferenceError = NSError(
            domain: "InferenceError",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "GPU out of memory"]
        )
        let vm = ConversationViewModel(engine: mockEngine, metricsStore: metricsStore)

        await vm.initializeEngine(modelPath: "/path/to/model.litertlm")
        await vm.generateText()

        XCTAssertTrue(vm.responseText.contains("Inference error"))
        XCTAssertFalse(vm.isGenerating)
    }

    @MainActor
    func testExperimentalFlagsPassedToEngine() async {
        let vm = ConversationViewModel(engine: mockEngine, metricsStore: metricsStore)
        vm.experimentalFlags = ExperimentalFlagsState(
            enableBenchmark: true,
            enableSpeculativeDecoding: true,
            enableConversationConstrainedDecoding: false,
            visualTokenBudget: 512
        )

        await vm.initializeEngine(modelPath: "/path/to/model.litertlm")

        let passedFlags = mockEngine.lastFlags!
        XCTAssertTrue(passedFlags.enableBenchmark)
        XCTAssertEqual(passedFlags.enableSpeculativeDecoding, true)
        XCTAssertFalse(passedFlags.enableConversationConstrainedDecoding)
        XCTAssertEqual(passedFlags.visualTokenBudget, 512)
    }

    @MainActor
    func testShutdownReleasesResources() async {
        let vm = ConversationViewModel(engine: mockEngine, metricsStore: metricsStore)

        await vm.initializeEngine(modelPath: "/path/to/model.litertlm")
        XCTAssertTrue(vm.isEngineReady)

        vm.shutdown()

        XCTAssertFalse(vm.isEngineReady)
        XCTAssertEqual(mockEngine.shutdownCallCount, 1)
    }
}

// MARK: - ExperimentalFlagsState Tests

final class ExperimentalFlagsStateTests: XCTestCase {

    func testCodableRoundTrip() throws {
        let original = ExperimentalFlagsState(
            enableBenchmark: true,
            enableSpeculativeDecoding: true,
            enableConversationConstrainedDecoding: false,
            visualTokenBudget: 1024
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ExperimentalFlagsState.self, from: data)

        XCTAssertEqual(original, decoded)
    }

    func testCodableWithNilOptionals() throws {
        let original = ExperimentalFlagsState(
            enableBenchmark: false,
            enableSpeculativeDecoding: nil,
            enableConversationConstrainedDecoding: true,
            visualTokenBudget: nil
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ExperimentalFlagsState.self, from: data)

        XCTAssertEqual(original, decoded)
    }
}

// MARK: - MetricsStore Tests

final class MetricsStoreTests: XCTestCase {

    private var tempFileURL: URL!
    private var store: MetricsStore!

    override func setUp() {
        super.setUp()
        tempFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_metrics_\(UUID().uuidString).json")
        store = MetricsStore(fileURL: tempFileURL)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempFileURL)
        super.tearDown()
    }

    func testLoadEntriesEmptyWhenFileDoesNotExist() throws {
        let entries = try store.loadEntries()
        XCTAssertTrue(entries.isEmpty)
    }

    func testAppendAndLoadSingleEntry() throws {
        let entry = makeTestEntry(model: "gemma-4-E2B", decodeSpeed: 45.2)
        try store.append(entry: entry)

        let loaded = try store.loadEntries()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].model, "gemma-4-E2B")
        XCTAssertEqual(loaded[0].metrics.decodeTokensPerSecond, 45.2, accuracy: 0.01)
    }

    func testAppendMultipleEntries() throws {
        try store.append(entry: makeTestEntry(model: "gemma-4-E2B", decodeSpeed: 45.2))
        try store.append(entry: makeTestEntry(model: "gemma-4-E2B", decodeSpeed: 42.8))
        try store.append(entry: makeTestEntry(model: "gemma-7B", decodeSpeed: 28.1))

        let loaded = try store.loadEntries()
        XCTAssertEqual(loaded.count, 3)
    }

    func testFlagsPersistedInEntry() throws {
        let flags = ExperimentalFlagsState(
            enableBenchmark: true,
            enableSpeculativeDecoding: true,
            enableConversationConstrainedDecoding: false,
            visualTokenBudget: 256
        )
        var entry = makeTestEntry(model: "test-model", decodeSpeed: 50.0)
        entry = MetricsStore.Entry(
            timestamp: entry.timestamp,
            model: entry.model,
            platform: entry.platform,
            device: entry.device,
            metrics: entry.metrics,
            flags: flags
        )
        try store.append(entry: entry)

        let loaded = try store.loadEntries()
        XCTAssertEqual(loaded[0].flags.enableSpeculativeDecoding, true)
        XCTAssertEqual(loaded[0].flags.visualTokenBudget, 256)
    }

    // MARK: - Helpers

    private func makeTestEntry(model: String, decodeSpeed: Double) -> MetricsStore.Entry {
        MetricsStore.Entry(
            timestamp: ISO8601DateFormatter().string(from: Date()),
            model: model,
            platform: "test",
            device: "test-device",
            metrics: MetricsStore.Entry.Metrics(
                initTimeSeconds: 1.5,
                ttftSeconds: 0.342,
                decodeTokensPerSecond: decodeSpeed,
                prefillTokensPerSecond: 128.7,
                lastPrefillTokenCount: 256,
                lastDecodeTokenCount: 128,
                thermalStateAtStart: nil,
                thermalStateAtEnd: nil,
                availableMemoryAtStartMB: nil,
                availableMemoryAtEndMB: nil,
                medianTokenLatencyMs: nil,
                p95TokenLatencyMs: nil,
                tokenLatenciesMs: nil
            ),
            flags: ExperimentalFlagsState(
                enableBenchmark: true,
                enableSpeculativeDecoding: nil,
                enableConversationConstrainedDecoding: false,
                visualTokenBudget: nil
            )
        )
    }
}

// MARK: - ModelMetadata Tests

final class ModelMetadataTests: XCTestCase {

    func testLookupByFilename() {
        let metadata = ModelRegistry.lookup(filename: "gemma-4-E2B-it.litertlm")
        XCTAssertNotNil(metadata)
        XCTAssertEqual(metadata?.name, "Gemma 4 E2B · Desktop GPU+CPU")
    }

    func testLookupByFilenameWebVariant() {
        let metadata = ModelRegistry.lookup(filename: "gemma-4-E2B-it-web.litertlm")
        XCTAssertNotNil(metadata)
        XCTAssertEqual(metadata?.name, "Gemma 4 E2B · Mobile GPU")
    }

    func testLookupByPath() {
        let metadata = ModelRegistry.lookup(path: "/path/to/models/gemma-4-E2B-it.litertlm")
        XCTAssertNotNil(metadata)
        XCTAssertEqual(metadata?.name, "Gemma 4 E2B · Desktop GPU+CPU")
    }

    func testLookupUnknownReturnsNil() {
        let metadata = ModelRegistry.lookup(filename: "unknown-model.litertlm")
        XCTAssertNil(metadata)
    }

    func testRecommendedBackendForUnknownModel() {
        let recommendation = ModelRegistry.recommendedBackend(for: "/path/to/unknown.litertlm")
        XCTAssertEqual(recommendation, .probeRequired)
    }

    func testE2BStandardSupportsMTP() {
        let metadata = ModelRegistry.gemma4E2BStandard
        XCTAssertTrue(metadata.supportsMTP)
        XCTAssertTrue(metadata.capabilities.contains("speculative_decoding"))
    }



    func testKnownModelCountIsTwo() {
        XCTAssertEqual(ModelRegistry.knownModels.count, 2)
    }

    func testBackendCapabilitySupportsGPU() {
        XCTAssertTrue(BackendCapability.gpuOnly.supportsGPU)
        XCTAssertTrue(BackendCapability.gpuAndCpu.supportsGPU)
        XCTAssertFalse(BackendCapability.cpuOnly.supportsGPU)
        XCTAssertFalse(BackendCapability.unknown.supportsGPU)
    }

    func testBackendCapabilitySupportsCPU() {
        XCTAssertTrue(BackendCapability.cpuOnly.supportsCPU)
        XCTAssertTrue(BackendCapability.gpuAndCpu.supportsCPU)
        XCTAssertFalse(BackendCapability.gpuOnly.supportsCPU)
        XCTAssertFalse(BackendCapability.unknown.supportsCPU)
    }

    func testPlatformSupportCurrentPlatform() {
        let support = PlatformSupport(
            macOS: .gpuAndCpu,
            iOSDevice: .cpuOnly,
            iOSSimulator: .cpuOnly
        )
        // Depending on test platform, verify we get a valid capability
        let current = support.currentPlatform
        XCTAssertNotEqual(current, .unknown)
    }
}
