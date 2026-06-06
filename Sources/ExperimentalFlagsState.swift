import Foundation
import LiteRTLM

/// Captures the current state of all ExperimentalFlags for metrics store persistence.
/// Each benchmark run records the active flags alongside the results, enabling
/// comparative analysis (e.g., "How does speculative decoding impact decode speed?").
struct ExperimentalFlagsState: Codable, Equatable, Sendable {
    var enableBenchmark: Bool
    var enableSpeculativeDecoding: Bool?
    var enableConversationConstrainedDecoding: Bool
    var visualTokenBudget: Int32?

    /// Whether thinking mode is enabled in the UI.
    /// When true, the model's `<think>...</think>` output is parsed and displayed
    /// separately from the response. This is a UI-level flag — the model may still
    /// emit thinking tokens even when disabled; we just don't surface them.
    var enableThinking: Bool = true

    /// Whether tool calling is enabled for the current session.
    /// When true, the engine is initialized with ToolManager and the model can
    /// invoke registered tools during inference.
    var enableToolCalling: Bool = false

    /// Whether Wikipedia search and Apple Maps grounding/rendering are enabled.
    var enableAgentSkills: Bool = false

    public init(
        enableBenchmark: Bool,
        enableSpeculativeDecoding: Bool?,
        enableConversationConstrainedDecoding: Bool,
        visualTokenBudget: Int32?,
        enableThinking: Bool = true,
        enableToolCalling: Bool = false,
        enableAgentSkills: Bool = false
    ) {
        self.enableBenchmark = enableBenchmark
        self.enableSpeculativeDecoding = enableSpeculativeDecoding
        self.enableConversationConstrainedDecoding = enableConversationConstrainedDecoding
        self.visualTokenBudget = visualTokenBudget
        self.enableThinking = enableThinking
        self.enableToolCalling = enableToolCalling
        self.enableAgentSkills = enableAgentSkills
    }

    /// Captures the current state from the global ExperimentalFlags statics.
    static func captureCurrentState() -> ExperimentalFlagsState {
        ExperimentalFlagsState(
            enableBenchmark: ExperimentalFlags.enableBenchmark,
            enableSpeculativeDecoding: ExperimentalFlags.enableSpeculativeDecoding,
            enableConversationConstrainedDecoding: ExperimentalFlags.enableConversationConstrainedDecoding,
            visualTokenBudget: ExperimentalFlags.visualTokenBudget,
            enableThinking: true,
            enableToolCalling: false,
            enableAgentSkills: false
        )
    }

    /// Applies this state to the global ExperimentalFlags.
    /// IMPORTANT: Caller must have already called ExperimentalFlags.optIntoExperimentalAPIs().
    func applyToGlobalFlags() {
        ExperimentalFlags.enableBenchmark = enableBenchmark
        ExperimentalFlags.enableSpeculativeDecoding = enableSpeculativeDecoding
        ExperimentalFlags.enableConversationConstrainedDecoding = enableConversationConstrainedDecoding
        ExperimentalFlags.visualTokenBudget = visualTokenBudget
    }
}
