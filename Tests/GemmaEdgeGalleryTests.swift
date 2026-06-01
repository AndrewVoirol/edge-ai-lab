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

// MARK: - InferenceMetrics Tests

final class InferenceMetricsTests: XCTestCase {

    // MARK: - Computed Statistics

    func testMedianLatencyOddCount() {
        let metrics = makeMetrics(latencies: [10.0, 20.0, 30.0, 40.0, 50.0])
        XCTAssertEqual(metrics.medianTokenLatencyMs, 30.0, accuracy: 0.01)
    }

    func testMedianLatencyEvenCount() {
        let metrics = makeMetrics(latencies: [10.0, 20.0, 30.0, 40.0])
        // Even count: average of middle two → (20 + 30) / 2 = 25
        XCTAssertEqual(metrics.medianTokenLatencyMs, 25.0, accuracy: 0.01)
    }

    func testMedianLatencySingleElement() {
        let metrics = makeMetrics(latencies: [42.0])
        XCTAssertEqual(metrics.medianTokenLatencyMs, 42.0, accuracy: 0.01)
    }

    func testMedianLatencyEmpty() {
        let metrics = makeMetrics(latencies: [])
        XCTAssertEqual(metrics.medianTokenLatencyMs, 0.0, accuracy: 0.01)
    }

    func testP95Latency() {
        // 20 values: P95 = sorted[index 19] = largest value
        let latencies = (1...20).map { Double($0) }
        let metrics = makeMetrics(latencies: latencies)
        // P95 index = min(Int(20 * 0.95), 19) = min(19, 19) = 19 → sorted[19] = 20.0
        XCTAssertEqual(metrics.p95TokenLatencyMs, 20.0, accuracy: 0.01)
    }

    func testP95LatencySmallSample() {
        let metrics = makeMetrics(latencies: [5.0, 15.0, 25.0, 35.0, 100.0])
        // P95 index = min(Int(5 * 0.95), 4) = min(4, 4) = 4 → sorted[4] = 100.0
        XCTAssertEqual(metrics.p95TokenLatencyMs, 100.0, accuracy: 0.01)
    }

    func testP95LatencyEmpty() {
        let metrics = makeMetrics(latencies: [])
        XCTAssertEqual(metrics.p95TokenLatencyMs, 0.0, accuracy: 0.01)
    }

    func testMinMaxLatency() {
        let metrics = makeMetrics(latencies: [50.0, 10.0, 90.0, 30.0, 70.0])
        XCTAssertEqual(metrics.minTokenLatencyMs, 10.0, accuracy: 0.01)
        XCTAssertEqual(metrics.maxTokenLatencyMs, 90.0, accuracy: 0.01)
    }

    func testMinMaxLatencyEmpty() {
        let metrics = makeMetrics(latencies: [])
        XCTAssertEqual(metrics.minTokenLatencyMs, 0.0, accuracy: 0.01)
        XCTAssertEqual(metrics.maxTokenLatencyMs, 0.0, accuracy: 0.01)
    }

    func testMemoryDeltaPositive() {
        // End has more memory than start → positive delta (memory freed)
        let metrics = makeMetrics(startMemoryMB: 2000.0, endMemoryMB: 2500.0)
        XCTAssertEqual(metrics.memoryDeltaMB, 500.0, accuracy: 0.01)
    }

    func testMemoryDeltaNegative() {
        // End has less memory → negative delta (memory consumed)
        let metrics = makeMetrics(startMemoryMB: 3000.0, endMemoryMB: 2800.0)
        XCTAssertEqual(metrics.memoryDeltaMB, -200.0, accuracy: 0.01)
    }

    func testThermalStateChangedTrue() {
        let metrics = makeMetrics(startThermal: .nominal, endThermal: .serious)
        XCTAssertTrue(metrics.thermalStateChanged)
    }

    func testThermalStateChangedFalse() {
        let metrics = makeMetrics(startThermal: .fair, endThermal: .fair)
        XCTAssertFalse(metrics.thermalStateChanged)
    }

    func testTotalTokenCount() {
        let metrics = makeMetrics(latencies: [10.0, 20.0, 30.0], tokenCount: 3)
        XCTAssertEqual(metrics.totalTokenCount, 3)
    }

    // MARK: - Codable Round-Trip

    func testInferenceMetricsCodableRoundTrip() throws {
        let original = makeMetrics(
            latencies: [12.5, 8.3, 9.1, 15.0, 7.2],
            tokenCount: 5,
            startThermal: .nominal,
            endThermal: .fair,
            startMemoryMB: 4096.0,
            endMemoryMB: 3800.0
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(InferenceMetrics.self, from: data)

        XCTAssertEqual(decoded.tokenLatenciesMs.count, 5)
        XCTAssertEqual(decoded.totalTokenCount, 5)
        XCTAssertEqual(decoded.startSnapshot.thermalLevel, .nominal)
        XCTAssertEqual(decoded.endSnapshot.thermalLevel, .fair)
        XCTAssertEqual(decoded.medianTokenLatencyMs, original.medianTokenLatencyMs, accuracy: 0.01)
        XCTAssertEqual(decoded.memoryDeltaMB, original.memoryDeltaMB, accuracy: 0.01)
    }

    // MARK: - Helpers

    private func makeMetrics(
        latencies: [Double] = [10.0, 20.0, 30.0],
        tokenCount: Int? = nil,
        startThermal: ThermalLevel = .nominal,
        endThermal: ThermalLevel = .nominal,
        startMemoryMB: Double = 4096.0,
        endMemoryMB: Double = 4096.0
    ) -> InferenceMetrics {
        InferenceMetrics(
            startSnapshot: DeviceMetricsSnapshot(
                timestamp: Date(),
                thermalLevel: startThermal,
                availableMemoryMB: startMemoryMB,
                deviceModel: "TestDevice"
            ),
            endSnapshot: DeviceMetricsSnapshot(
                timestamp: Date(),
                thermalLevel: endThermal,
                availableMemoryMB: endMemoryMB,
                deviceModel: "TestDevice"
            ),
            tokenLatenciesMs: latencies,
            totalTokenCount: tokenCount ?? latencies.count
        )
    }
}

// MARK: - InferenceMetrics Integration Tests (ViewModel + MetricsStore)

final class InferenceMetricsIntegrationTests: XCTestCase {

    private var mockEngine: MockInstrumentedEngine!
    private var metricsStore: MetricsStore!
    private var metricsFileURL: URL!

    @MainActor
    override func setUp() {
        super.setUp()
        mockEngine = MockInstrumentedEngine()
        metricsFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_metrics_im_\(UUID().uuidString).json")
        metricsStore = MetricsStore(fileURL: metricsFileURL)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: metricsFileURL)
        super.tearDown()
    }

    @MainActor
    func testInferenceMetricsPopulatedAfterGenerate() async {
        // Configure the mock with InferenceMetrics
        let expectedMetrics = makeTestInferenceMetrics()
        mockEngine.mockInferenceMetrics = expectedMetrics
        mockEngine.mockResponseChunks = ["Test", " ", "response"]

        let vm = ConversationViewModel(engine: mockEngine, metricsStore: metricsStore)

        // Initialize and generate
        await vm.initializeEngine(modelPath: "/path/to/model.litertlm")
        XCTAssertTrue(vm.isEngineReady)

        await vm.generateText()

        // Verify InferenceMetrics is populated on the ViewModel
        XCTAssertNotNil(vm.inferenceMetrics, "InferenceMetrics should be populated after generate")
        XCTAssertEqual(vm.inferenceMetrics?.totalTokenCount, 5)
        XCTAssertEqual(vm.inferenceMetrics?.tokenLatenciesMs.count, 5)
        XCTAssertEqual(vm.inferenceMetrics?.startSnapshot.thermalLevel, .nominal)
        XCTAssertEqual(vm.inferenceMetrics?.endSnapshot.thermalLevel, .fair)
    }

    @MainActor
    func testInferenceMetricsNilWhenNotConfigured() async {
        // Don't set mockInferenceMetrics (defaults to nil)
        let vm = ConversationViewModel(engine: mockEngine, metricsStore: metricsStore)

        await vm.initializeEngine(modelPath: "/path/to/model.litertlm")
        await vm.generateText()

        XCTAssertNil(vm.inferenceMetrics, "InferenceMetrics should be nil when mock doesn't provide them")
    }

    @MainActor
    func testInferenceMetricsClearedOnReset() async throws {
        mockEngine.mockInferenceMetrics = makeTestInferenceMetrics()
        mockEngine.mockResponseChunks = ["Hello"]

        let vm = ConversationViewModel(engine: mockEngine, metricsStore: metricsStore)
        await vm.initializeEngine(modelPath: "/path/to/model.litertlm")
        await vm.generateText()

        // Verify metrics exist
        XCTAssertNotNil(mockEngine.lastInferenceMetrics)

        // Reset conversation should clear metrics
        try await mockEngine.resetConversation()
        XCTAssertNil(mockEngine.lastInferenceMetrics, "InferenceMetrics should be nil after resetConversation")
    }

    @MainActor
    func testInferenceMetricsClearedOnShutdown() async {
        mockEngine.mockInferenceMetrics = makeTestInferenceMetrics()
        mockEngine.mockResponseChunks = ["Hello"]

        let vm = ConversationViewModel(engine: mockEngine, metricsStore: metricsStore)
        await vm.initializeEngine(modelPath: "/path/to/model.litertlm")
        await vm.generateText()

        // Verify metrics exist
        XCTAssertNotNil(mockEngine.lastInferenceMetrics)

        // Shutdown should clear metrics
        vm.shutdown()
        XCTAssertNil(mockEngine.lastInferenceMetrics, "InferenceMetrics should be nil after shutdown")
    }

    // MARK: - Helpers

    private func makeTestInferenceMetrics() -> InferenceMetrics {
        InferenceMetrics(
            startSnapshot: DeviceMetricsSnapshot(
                timestamp: Date(),
                thermalLevel: .nominal,
                availableMemoryMB: 4096.0,
                deviceModel: "TestDevice"
            ),
            endSnapshot: DeviceMetricsSnapshot(
                timestamp: Date(),
                thermalLevel: .fair,
                availableMemoryMB: 3800.0,
                deviceModel: "TestDevice"
            ),
            tokenLatenciesMs: [25.0, 12.5, 8.3, 9.1, 15.0],
            totalTokenCount: 5
        )
    }
}

// MARK: - MetricsStore InferenceMetrics Tests

final class MetricsStoreInferenceMetricsTests: XCTestCase {

    private var tempFileURL: URL!
    private var store: MetricsStore!

    override func setUp() {
        super.setUp()
        tempFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_metrics_store_im_\(UUID().uuidString).json")
        store = MetricsStore(fileURL: tempFileURL)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempFileURL)
        super.tearDown()
    }

    func testEntryWithInferenceMetricsPersistence() throws {
        let entry = makeTestEntryWithInferenceMetrics()
        try store.append(entry: entry)

        let loaded = try store.loadEntries()
        XCTAssertEqual(loaded.count, 1)

        let metrics = loaded[0].metrics
        XCTAssertEqual(metrics.thermalStateAtStart, "nominal")
        XCTAssertEqual(metrics.thermalStateAtEnd, "fair")
        XCTAssertEqual(metrics.availableMemoryAtStartMB ?? 0, 4096.0, accuracy: 0.01)
        XCTAssertEqual(metrics.availableMemoryAtEndMB ?? 0, 3800.0, accuracy: 0.01)
        XCTAssertNotNil(metrics.medianTokenLatencyMs)
        XCTAssertNotNil(metrics.p95TokenLatencyMs)
        XCTAssertNotNil(metrics.tokenLatenciesMs)
        XCTAssertEqual(metrics.tokenLatenciesMs?.count, 5)
    }

    func testEntryWithoutInferenceMetricsBackwardCompatibility() throws {
        // Ensure entries without InferenceMetrics still work (backward compat)
        let entry = makeTestEntryWithoutInferenceMetrics()
        try store.append(entry: entry)

        let loaded = try store.loadEntries()
        XCTAssertEqual(loaded.count, 1)

        let metrics = loaded[0].metrics
        XCTAssertNil(metrics.thermalStateAtStart)
        XCTAssertNil(metrics.thermalStateAtEnd)
        XCTAssertNil(metrics.availableMemoryAtStartMB)
        XCTAssertNil(metrics.availableMemoryAtEndMB)
        XCTAssertNil(metrics.medianTokenLatencyMs)
        XCTAssertNil(metrics.p95TokenLatencyMs)
        XCTAssertNil(metrics.tokenLatenciesMs)
    }

    func testMixedEntriesRoundTrip() throws {
        // Append one with and one without InferenceMetrics
        try store.append(entry: makeTestEntryWithInferenceMetrics())
        try store.append(entry: makeTestEntryWithoutInferenceMetrics())

        let loaded = try store.loadEntries()
        XCTAssertEqual(loaded.count, 2)

        // First entry has InferenceMetrics data
        XCTAssertNotNil(loaded[0].metrics.thermalStateAtStart)
        XCTAssertNotNil(loaded[0].metrics.tokenLatenciesMs)

        // Second entry does not
        XCTAssertNil(loaded[1].metrics.thermalStateAtStart)
        XCTAssertNil(loaded[1].metrics.tokenLatenciesMs)
    }

    // MARK: - Helpers

    private func makeTestEntryWithInferenceMetrics() -> MetricsStore.Entry {
        MetricsStore.Entry(
            timestamp: ISO8601DateFormatter().string(from: Date()),
            model: "gemma-4-E2B-im-test",
            platform: "test",
            device: "test-device",
            metrics: MetricsStore.Entry.Metrics(
                initTimeSeconds: 1.5,
                ttftSeconds: 0.025,
                decodeTokensPerSecond: 45.2,
                prefillTokensPerSecond: 128.7,
                lastPrefillTokenCount: 256,
                lastDecodeTokenCount: 128,
                thermalStateAtStart: "nominal",
                thermalStateAtEnd: "fair",
                availableMemoryAtStartMB: 4096.0,
                availableMemoryAtEndMB: 3800.0,
                medianTokenLatencyMs: 12.5,
                p95TokenLatencyMs: 25.0,
                tokenLatenciesMs: [25.0, 12.5, 8.3, 9.1, 15.0]
            ),
            flags: ExperimentalFlagsState(
                enableBenchmark: true,
                enableSpeculativeDecoding: nil,
                enableConversationConstrainedDecoding: false,
                visualTokenBudget: nil
            )
        )
    }

    private func makeTestEntryWithoutInferenceMetrics() -> MetricsStore.Entry {
        MetricsStore.Entry(
            timestamp: ISO8601DateFormatter().string(from: Date()),
            model: "gemma-4-E2B-no-im",
            platform: "test",
            device: "test-device",
            metrics: MetricsStore.Entry.Metrics(
                initTimeSeconds: 1.5,
                ttftSeconds: 0.342,
                decodeTokensPerSecond: 45.2,
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

// MARK: - ThermalLevel Tests

final class ThermalLevelTests: XCTestCase {

    func testThermalLevelFromSystemState() {
        XCTAssertEqual(ThermalLevel(from: .nominal), .nominal)
        XCTAssertEqual(ThermalLevel(from: .fair), .fair)
        XCTAssertEqual(ThermalLevel(from: .serious), .serious)
        XCTAssertEqual(ThermalLevel(from: .critical), .critical)
    }

    func testThermalLevelSymbolNames() {
        XCTAssertEqual(ThermalLevel.nominal.symbolName, "thermometer.low")
        XCTAssertEqual(ThermalLevel.fair.symbolName, "thermometer.medium")
        XCTAssertEqual(ThermalLevel.serious.symbolName, "thermometer.high")
        XCTAssertEqual(ThermalLevel.critical.symbolName, "thermometer.sun.fill")
    }

    func testThermalLevelColorNames() {
        XCTAssertEqual(ThermalLevel.nominal.colorName, "green")
        XCTAssertEqual(ThermalLevel.fair.colorName, "yellow")
        XCTAssertEqual(ThermalLevel.serious.colorName, "orange")
        XCTAssertEqual(ThermalLevel.critical.colorName, "red")
    }

    func testThermalLevelLabels() {
        XCTAssertEqual(ThermalLevel.nominal.label, "Nominal")
        XCTAssertEqual(ThermalLevel.fair.label, "Fair")
        XCTAssertEqual(ThermalLevel.serious.label, "Serious")
        XCTAssertEqual(ThermalLevel.critical.label, "Critical")
    }

    func testThermalLevelCodableRoundTrip() throws {
        let levels: [ThermalLevel] = [.nominal, .fair, .serious, .critical]

        for level in levels {
            let encoder = JSONEncoder()
            let data = try encoder.encode(level)
            let decoder = JSONDecoder()
            let decoded = try decoder.decode(ThermalLevel.self, from: data)
            XCTAssertEqual(level, decoded, "ThermalLevel \(level) should survive Codable round-trip")
        }
    }

    func testThermalLevelRawValues() {
        XCTAssertEqual(ThermalLevel.nominal.rawValue, "nominal")
        XCTAssertEqual(ThermalLevel.fair.rawValue, "fair")
        XCTAssertEqual(ThermalLevel.serious.rawValue, "serious")
        XCTAssertEqual(ThermalLevel.critical.rawValue, "critical")
    }
}

// MARK: - DeviceMetricsSnapshot Tests

final class DeviceMetricsSnapshotTests: XCTestCase {

    func testCaptureSnapshot() {
        let snapshot = DeviceMetrics.captureSnapshot()

        // Should have reasonable values
        XCTAssertGreaterThan(snapshot.availableMemoryMB, 0, "Available memory should be positive")
        XCTAssertFalse(snapshot.deviceModel.isEmpty, "Device model should not be empty")
        // Thermal level is always one of the valid enum cases
        let validLevels: [ThermalLevel] = [.nominal, .fair, .serious, .critical]
        XCTAssertTrue(validLevels.contains(snapshot.thermalLevel))
    }

    func testSnapshotCodableRoundTrip() throws {
        let original = DeviceMetricsSnapshot(
            timestamp: Date(),
            thermalLevel: .serious,
            availableMemoryMB: 2048.5,
            deviceModel: "iPhone17,2"
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(DeviceMetricsSnapshot.self, from: data)

        XCTAssertEqual(decoded.thermalLevel, .serious)
        XCTAssertEqual(decoded.availableMemoryMB, 2048.5, accuracy: 0.01)
        XCTAssertEqual(decoded.deviceModel, "iPhone17,2")
    }

    func testFormattedAvailableMemory() {
        // Just verify it returns a non-empty string with a valid format
        let formatted = DeviceMetrics.formattedAvailableMemory
        XCTAssertFalse(formatted.isEmpty)
        XCTAssertTrue(formatted.contains("free"), "Formatted memory should contain 'free'")
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
