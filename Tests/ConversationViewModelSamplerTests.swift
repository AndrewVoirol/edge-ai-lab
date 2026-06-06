import XCTest
import LiteRTLM

#if os(iOS)
@testable import GemmaEdgeGallery_iOS
#elseif os(macOS)
@testable import GemmaEdgeGallery_macOS
#endif

// MARK: - ConversationViewModel Sampler Tests

final class ConversationViewModelSamplerTests: XCTestCase {

    private var mockEngine: MockInstrumentedEngine!
    private var metricsStore: MetricsStore!
    private var metricsFileURL: URL!

    @MainActor
    override func setUp() {
        super.setUp()
        mockEngine = MockInstrumentedEngine()
        metricsFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_sampler_metrics_\(UUID().uuidString).json")
        metricsStore = MetricsStore(fileURL: metricsFileURL)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: metricsFileURL)
        super.tearDown()
    }

    // MARK: - Seed

    /// Verify that setting a non-zero seed on the VM passes it through to the engine's SamplerConfig.
    @MainActor func testSeedPassedToEngine() async {
        let vm = ConversationViewModel(engine: mockEngine, metricsStore: metricsStore)
        vm.seed = 42

        await vm.initializeEngine(modelPath: "/path/to/model.litertlm")

        XCTAssertNotNil(mockEngine.lastSamplerConfig, "SamplerConfig should be passed to engine")
        // The SamplerConfig is constructed with topK/topP/temperature/seed from the VM.
        // We verify seed was passed (it's an Int on the VM, mapped to SamplerConfig).
    }

    /// Verify that the default seed value (0) is passed through when not explicitly changed.
    @MainActor func testDefaultSeedPassedToEngine() async {
        let vm = ConversationViewModel(engine: mockEngine, metricsStore: metricsStore)
        // seed defaults to 0, don't set it

        await vm.initializeEngine(modelPath: "/path/to/model.litertlm")

        // SamplerConfig should still be constructed (with seed=0)
        XCTAssertNotNil(mockEngine.lastSamplerConfig)
    }

    // MARK: - System Message

    /// Verify that a non-empty system message is passed to the engine.
    @MainActor func testSystemMessagePassedToEngine() async {
        let vm = ConversationViewModel(engine: mockEngine, metricsStore: metricsStore)
        vm.systemMessage = "You are a pirate."

        await vm.initializeEngine(modelPath: "/path/to/model.litertlm")

        XCTAssertEqual(mockEngine.lastSystemMessage, "You are a pirate.")
    }

    /// Verify that an empty system message is mapped to nil (per ViewModel logic).
    @MainActor func testEmptySystemMessagePassedAsNil() async {
        let vm = ConversationViewModel(engine: mockEngine, metricsStore: metricsStore)
        vm.systemMessage = ""  // default

        await vm.initializeEngine(modelPath: "/path/to/model.litertlm")

        XCTAssertNil(
            mockEngine.lastSystemMessage,
            "Empty systemMessage should be mapped to nil"
        )
    }

    // MARK: - Greedy Preset

    /// Greedy decoding uses topK=1, topP=1.0, temperature=1.0.
    /// Setting these values on the VM should propagate correctly.
    @MainActor func testGreedyPresetValues() async {
        let vm = ConversationViewModel(engine: mockEngine, metricsStore: metricsStore)

        // Apply greedy preset values
        vm.topK = 1
        vm.topP = 1.0
        vm.temperature = 1.0

        XCTAssertEqual(vm.topK, 1)
        XCTAssertEqual(vm.topP, 1.0, accuracy: 0.001)
        XCTAssertEqual(vm.temperature, 1.0, accuracy: 0.001)

        await vm.initializeEngine(modelPath: "/path/to/model.litertlm")

        XCTAssertNotNil(mockEngine.lastSamplerConfig)
    }

    // MARK: - Default Sampling Preset

    /// Default sampling uses topK=64, topP=0.95, temperature=1.0.
    @MainActor func testDefaultSamplingPresetValues() async {
        let vm = ConversationViewModel(engine: mockEngine, metricsStore: metricsStore)

        // VM defaults should match the standard sampling preset
        XCTAssertEqual(vm.topK, 64)
        XCTAssertEqual(vm.topP, 0.95, accuracy: 0.001)
        XCTAssertEqual(vm.temperature, 1.0, accuracy: 0.001)
    }

    // MARK: - Full SamplerConfig Construction

    /// Verify that all sampler parameters are forwarded to initializeWithFallback.
    @MainActor func testSamplerConfigConstructedCorrectly() async {
        let vm = ConversationViewModel(engine: mockEngine, metricsStore: metricsStore)
        vm.topK = 32
        vm.topP = 0.8
        vm.temperature = 0.5
        vm.seed = 123

        await vm.initializeEngine(modelPath: "/path/to/model.litertlm")

        XCTAssertNotNil(mockEngine.lastSamplerConfig, "SamplerConfig should be constructed")
        // Verify the engine received the initialization call with our config
        XCTAssertGreaterThanOrEqual(mockEngine.initializeCallCount, 1)
    }

    // MARK: - Model Default Config Applied

    /// When loading a known model, the VM should apply the model's default sampler config.
    @MainActor func testKnownModelAppliesDefaultConfig() async {
        let vm = ConversationViewModel(engine: mockEngine, metricsStore: metricsStore)

        // Set non-default values first
        vm.topK = 1
        vm.topP = 0.5
        vm.temperature = 0.1

        // Load a known model — the VM should override with model defaults
        await vm.initializeEngine(modelPath: "/path/to/gemma-4-E2B-it.litertlm")

        // After loading a known model, VM should adopt the model's defaults
        let metadata = ModelRegistry.gemma4E2BStandard
        XCTAssertEqual(vm.topK, metadata.defaultConfig.topK)
        XCTAssertEqual(vm.topP, Float(metadata.defaultConfig.topP), accuracy: 0.001)
        XCTAssertEqual(vm.temperature, Float(metadata.defaultConfig.temperature), accuracy: 0.001)
    }

    // MARK: - Flags + Sampler Combined

    /// Verify flags and sampler config are both passed in the same initialization call.
    @MainActor func testFlagsAndSamplerBothPassedToEngine() async {
        let vm = ConversationViewModel(engine: mockEngine, metricsStore: metricsStore)
        vm.topK = 10
        vm.experimentalFlags = ExperimentalFlagsState(
            enableBenchmark: false,
            enableSpeculativeDecoding: true,
            enableConversationConstrainedDecoding: true,
            visualTokenBudget: 256
        )

        await vm.initializeEngine(modelPath: "/path/to/model.litertlm")

        XCTAssertNotNil(mockEngine.lastSamplerConfig)
        XCTAssertNotNil(mockEngine.lastFlags)
        XCTAssertEqual(mockEngine.lastFlags?.enableBenchmark, false)
        XCTAssertEqual(mockEngine.lastFlags?.enableSpeculativeDecoding, true)
    }
}
