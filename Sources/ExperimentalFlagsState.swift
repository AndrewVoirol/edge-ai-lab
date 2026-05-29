import Foundation
import LiteRTLM

/// Captures the current state of all ExperimentalFlags for metrics store persistence.
/// Each benchmark run records the active flags alongside the results, enabling
/// comparative analysis (e.g., "How does speculative decoding impact decode speed?").
struct ExperimentalFlagsState: Codable, Equatable, Sendable {
    let enableBenchmark: Bool
    let enableSpeculativeDecoding: Bool?
    let enableConversationConstrainedDecoding: Bool
    let visualTokenBudget: Int32?

    /// Captures the current state from the global ExperimentalFlags statics.
    static func captureCurrentState() -> ExperimentalFlagsState {
        ExperimentalFlagsState(
            enableBenchmark: ExperimentalFlags.enableBenchmark,
            enableSpeculativeDecoding: ExperimentalFlags.enableSpeculativeDecoding,
            enableConversationConstrainedDecoding: ExperimentalFlags.enableConversationConstrainedDecoding,
            visualTokenBudget: ExperimentalFlags.visualTokenBudget
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
