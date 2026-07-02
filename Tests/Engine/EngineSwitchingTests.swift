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
        let vm = ConversationViewModel(engine: mlxEngine)

        #expect(vm.selectedRuntimeType == .mlx)
    }

    @Test("selectedRuntimeType defaults to .litertlm for LiteRT engine")
    @MainActor
    func selectedRuntimeTypeDefaultsToLitertlm() {
        let engine = MockInferenceEngine(runtimeType: .litertlm)
        let vm = ConversationViewModel(engine: engine)

        #expect(vm.selectedRuntimeType == .litertlm)
    }

    // MARK: - Same-Type Guard

    @Test("switchEngine with same runtime type is a no-op")
    @MainActor
    func switchEngineSameTypeIsNoOp() async {
        let engine = MockInferenceEngine.happyPath(runtimeType: .litertlm)
        let vm = ConversationViewModel(engine: engine)

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
        let vm = ConversationViewModel(engine: engine)

        // switchEngine creates a real engine via EngineFactory, so we can
        // verify the ViewModel state changed. The .mlx engine is supported.
        await vm.switchEngine(to: .mlx)

        #expect(vm.selectedRuntimeType == .mlx)
    }

    @Test("switchEngine shuts down the old engine")
    @MainActor
    func switchEngineShutdownsOldEngine() async {
        let engine = MockInferenceEngine.happyPath(runtimeType: .litertlm)
        let vm = ConversationViewModel(engine: engine)

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
        let vm = ConversationViewModel(engine: engine)

        await vm.switchEngine(to: .mlx)

        #expect(vm.isEngineReady == false)
    }

    @Test("Conversation is cleared after engine switch")
    @MainActor
    func conversationClearedAfterSwitch() async {
        let engine = MockInferenceEngine.happyPath(runtimeType: .litertlm)
        let vm = ConversationViewModel(engine: engine)

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
        let vm = ConversationViewModel(engine: engine)

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

    // MARK: - Unsupported Runtime

    @Test("switchEngine to unsupported .gguf sets error status message")
    @MainActor
    func switchEngineToUnsupportedRuntimeSetsError() async {
        let engine = MockInferenceEngine.happyPath(runtimeType: .litertlm)
        let vm = ConversationViewModel(engine: engine)

        await vm.switchEngine(to: .gguf)

        // EngineFactory.createEngine(for: .gguf) throws runtimeNotYetAvailable,
        // which should be caught and set as statusMessage
        #expect(vm.statusMessage.contains("GGUF") || vm.statusMessage.contains("Failed"))
        // selectedRuntimeType should NOT have changed since the switch failed
        #expect(vm.selectedRuntimeType == .litertlm)
    }
}
