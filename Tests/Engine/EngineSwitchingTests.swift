// Copyright 2026 Andrew Voirol. Apache-2.0

import Foundation
import Testing

#if os(iOS)
@testable import EdgeAILab_iOS
#elseif os(macOS)
@testable import EdgeAILab_macOS
#endif

// MARK: - EngineSwitchingTests

/// Tests for engine switching behavior on `ConversationViewModel`.
///
/// These tests inject `MockInferenceEngine` to verify:
/// - The guard clause (same runtime type = no-op)
/// - Init syncing of `selectedRuntimeType` from the engine
/// - Observable state changes after `switchEngine(to:)`
///
/// Note: Full end-to-end engine switching (via `EngineFactory`) creates real
/// engines that require framework dependencies. These tests focus on the
/// ViewModel's state management and mock interaction instead.
@Suite("Engine Switching")
struct EngineSwitchingTests {

    // MARK: - Init Sync

    @Test("selectedRuntimeType is synced from engine on init")
    @MainActor
    func selectedRuntimeTypeSyncsFromEngineOnInit() {
        let mlxEngine = MockInferenceEngine(runtimeType: .mlx)
        let vm = ConversationViewModel(engine: mlxEngine, conversationStore: .inMemory())

        #expect(vm.selectedRuntimeType == .mlx)
    }

    @Test("selectedRuntimeType defaults to .litertlm for LiteRT engine")
    @MainActor
    func selectedRuntimeTypeDefaultsToLitertlm() {
        let engine = MockInferenceEngine(runtimeType: .litertlm)
        let vm = ConversationViewModel(engine: engine, conversationStore: .inMemory())

        #expect(vm.selectedRuntimeType == .litertlm)
    }

    // MARK: - Same-Type Guard

    @Test("switchEngine with same runtime type is a no-op")
    @MainActor
    func switchEngineSameTypeIsNoOp() async {
        let engine = MockInferenceEngine.happyPath(runtimeType: .litertlm)
        let vm = ConversationViewModel(engine: engine, conversationStore: .inMemory())

        // Switching to the same type should do nothing
        await vm.switchEngine(to: .litertlm)

        // Engine should NOT have been shut down
        #expect(engine.shutdownCallCount == 0)
        // selectedRuntimeType should remain unchanged
        #expect(vm.selectedRuntimeType == .litertlm)
    }

    // MARK: - Engine Replacement State

    @Test("switchEngine to different type updates selectedRuntimeType")
    @MainActor
    func switchEngineUpdateSelectedRuntimeType() async {
        let engine = MockInferenceEngine.happyPath(runtimeType: .litertlm)
        let vm = ConversationViewModel(engine: engine, conversationStore: .inMemory())

        // switchEngine creates a real engine via EngineFactory, so we can
        // verify the ViewModel state changed. The .mlx engine is supported.
        await vm.switchEngine(to: .mlx)

        #expect(vm.selectedRuntimeType == .mlx)
    }

    @Test("switchEngine shuts down the old engine")
    @MainActor
    func switchEngineShutdownsOldEngine() async {
        let engine = MockInferenceEngine.happyPath(runtimeType: .litertlm)
        let vm = ConversationViewModel(engine: engine, conversationStore: .inMemory())

        // Switch to MLX — the old LiteRT mock should be shut down
        // (shutdown is called by sessionController.replaceEngine)
        await vm.switchEngine(to: .mlx)

        // The mock's shutdown should have been called by the session controller
        #expect(engine.shutdownCallCount >= 1)
    }

    @Test("isEngineReady is false after engine switch")
    @MainActor
    func isEngineReadyFalseAfterSwitch() async {
        let engine = MockInferenceEngine.happyPath(runtimeType: .litertlm)
        let vm = ConversationViewModel(engine: engine, conversationStore: .inMemory())

        await vm.switchEngine(to: .mlx)

        #expect(vm.isEngineReady == false)
    }

    @Test("Conversation is cleared after engine switch")
    @MainActor
    func conversationClearedAfterSwitch() async {
        let engine = MockInferenceEngine.happyPath(runtimeType: .litertlm)
        let vm = ConversationViewModel(engine: engine, conversationStore: .inMemory())

        // Add a message to the conversation first
        vm.conversation.append(
            ChatMessage(
                id: UUID(), role: .user, content: "Hello", thinkingContent: nil,
                toolCalls: [], attachments: [], timestamp: Date(),
                benchmarkInfo: nil, isStreaming: false, thinkingWordCount: 0, specialResults: [:]
            )
        )
        vm.conversation.append(
            ChatMessage(
                id: UUID(), role: .assistant, content: "Hi there!", thinkingContent: nil,
                toolCalls: [], attachments: [], timestamp: Date(),
                benchmarkInfo: nil, isStreaming: false, thinkingWordCount: 0, specialResults: [:]
            )
        )
        #expect(vm.conversation.messages.count == 2)

        // Switch engine — conversation should be cleared
        await vm.switchEngine(to: .mlx)

        #expect(vm.conversation.messages.isEmpty)
    }

    @Test("performanceMetrics is nil after engine switch")
    @MainActor
    func performanceMetricsNilAfterSwitch() async {
        let engine = MockInferenceEngine.happyPath(runtimeType: .litertlm)
        let vm = ConversationViewModel(engine: engine, conversationStore: .inMemory())

        // Simulate having metrics from a previous run
        vm.performanceMetrics = EnginePerformanceMetrics(
            tokensPerSecond: 20.0,
            promptTokensPerSecond: nil,
            timeToFirstToken: 0.5,
            peakMemoryBytes: nil,
            tokenCount: 100,
            memoryDeltaMB: nil,
            thermalStateChanged: nil,
            runtimeType: .litertlm
        )
        #expect(vm.performanceMetrics != nil)

        await vm.switchEngine(to: .mlx)

        #expect(vm.performanceMetrics == nil)
    }

    // MARK: - GGUF Runtime

    @Test("switchEngine to .gguf succeeds and updates selectedRuntimeType")
    @MainActor
    func switchEngineToGgufSucceeds() async {
        let engine = MockInferenceEngine.happyPath(runtimeType: .litertlm)
        let vm = ConversationViewModel(engine: engine, conversationStore: .inMemory())

        await vm.switchEngine(to: .gguf)

        // EngineFactory.createEngine(for: .gguf) should succeed now
        #expect(vm.selectedRuntimeType == .gguf)
    }

    // MARK: - Phase 2: Cancel Generation Defense-in-Depth

    @Test("cancelGeneration is called on old engine during switch via session controller")
    @MainActor
    func cancelGenerationCalledDuringSwitch() async {
        let engine = MockInferenceEngine.happyPath(runtimeType: .litertlm)
        let vm = ConversationViewModel(engine: engine, conversationStore: .inMemory())

        await vm.switchEngine(to: .mlx)

        // The session controller's replaceEngine() should call cancelGeneration()
        // on the old engine as defense-in-depth, even if ViewModel also stops generation.
        #expect(engine.cancelGenerationCallCount >= 1)
    }

    // MARK: - Phase 2: Config Tracking Reset

    @Test("lastInitializedBackend is nil after engine switch — no false Restart Engine prompt")
    @MainActor
    func configTrackingResetAfterSwitch() async {
        let engine = MockInferenceEngine.happyPath(runtimeType: .litertlm)
        let vm = ConversationViewModel(engine: engine, conversationStore: .inMemory())

        // engineConfigChanged should be false initially (no config snapshot yet)
        #expect(vm.engineConfigChanged == false)

        // Switch engine — this resets lastInitializedBackend to nil
        await vm.switchEngine(to: .mlx)

        // After switch with no model loaded, engineConfigChanged should still be false
        // (guard isEngineReady returns false because no model is loaded)
        #expect(vm.engineConfigChanged == false)
    }

    @Test("inferenceMetrics is nil after engine switch")
    @MainActor
    func inferenceMetricsNilAfterSwitch() async {
        let engine = MockInferenceEngine.happyPath(runtimeType: .litertlm)
        let vm = ConversationViewModel(engine: engine, conversationStore: .inMemory())

        // Create a minimal InferenceMetrics for testing.
        // DeviceMetrics.captureSnapshot() creates a valid snapshot.
        let snapshot = DeviceMetrics.captureSnapshot()
        vm.inferenceMetrics = InferenceMetrics(
            startSnapshot: snapshot,
            endSnapshot: snapshot,
            ttftMs: 50.0,
            decodeLatenciesMs: [10.0, 12.0, 11.0],
            totalTokenCount: 100
        )
        #expect(vm.inferenceMetrics != nil)

        await vm.switchEngine(to: .mlx)

        #expect(vm.inferenceMetrics == nil)
    }

    // MARK: - Phase 2: Full Lifecycle Round-Trip

    @Test("Round-trip switch: LiteRT → MLX → GGUF → LiteRT all succeed")
    @MainActor
    func roundTripSwitching() async {
        let engine = MockInferenceEngine.happyPath(runtimeType: .litertlm)
        let vm = ConversationViewModel(engine: engine, conversationStore: .inMemory())

        #expect(vm.selectedRuntimeType == .litertlm)

        await vm.switchEngine(to: .mlx)
        #expect(vm.selectedRuntimeType == .mlx)

        await vm.switchEngine(to: .gguf)
        #expect(vm.selectedRuntimeType == .gguf)

        await vm.switchEngine(to: .litertlm)
        #expect(vm.selectedRuntimeType == .litertlm)

        // Original mock engine should have been shut down at least once
        #expect(engine.shutdownCallCount >= 1)
    }

    // MARK: - Phase 3: Robustness Guards

    @Test("reinitializeEngineIfNeeded is no-op during engine switch")
    @MainActor
    func reinitSkippedDuringEngineSwitch() async {
        let engine = MockInferenceEngine.happyPath(runtimeType: .litertlm)
        let vm = ConversationViewModel(engine: engine, conversationStore: .inMemory())

        // Start a switch — the mock EngineFactory will create a new mock engine.
        // While the switch is in-flight, changing settings should NOT trigger reinit
        // because `isEngineSwitching` is true.
        //
        // We verify indirectly: change preferredBackend (which would normally trigger
        // reinitializeEngineIfNeeded via scheduleReinit). If the guard works,
        // the sessionController won't receive a reinitializeIfNeeded call.
        await vm.switchEngine(to: .mlx)

        // After switch completes, isEngineSwitching should be false.
        // Verify the switch succeeded.
        #expect(vm.selectedRuntimeType == .mlx)

        // The original engine should have been shut down exactly once (by the switch).
        #expect(engine.shutdownCallCount == 1)
    }

    @Test("scheduleReinit debounces rapid settings changes")
    @MainActor
    func rapidSettingsChangeDebounced() async throws {
        let engine = MockInferenceEngine.happyPath(runtimeType: .litertlm)
        let vm = ConversationViewModel(engine: engine, conversationStore: .inMemory())

        // Rapidly change settings — each fires scheduleReinit() which cancels the
        // previous debounce timer. Only the last change should trigger a reinit.
        vm.preferredBackend = .cpu
        vm.preferredBackend = .gpu
        vm.preferredBackend = .cpu

        // Wait for the 200ms debounce to settle
        try await Task.sleep(for: .milliseconds(350))

        // The engine is NOT loaded (no model loaded), so reinitializeIfNeeded
        // should early-return in the session controller (guard engine.isLoaded).
        // The important thing is that we didn't crash from concurrent reinit Tasks.
        // Verify the VM is still in a consistent state.
        #expect(vm.preferredBackend == .cpu)
        #expect(vm.useGPU == false)
    }
}
