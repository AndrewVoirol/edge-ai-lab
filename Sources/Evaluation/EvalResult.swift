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

// MARK: - Eval Run

/// A complete evaluation run capturing results for one or more models against a suite.
///
/// Each run is persisted as a single JSON file by `EvalStore`. A run is created
/// when the user starts an evaluation, and progressively updated as each model
/// completes its prompts.
struct EvalRun: Codable, Sendable, Identifiable {
    /// Unique identifier for this run.
    let id: UUID

    /// The suite that was evaluated (by ID reference).
    let suiteId: UUID

    /// Suite name cached for display without needing to resolve the suite.
    let suiteName: String

    /// The category of the suite that was evaluated.
    let suiteCategory: EvalCategory

    /// When this run was started.
    let startedAt: Date

    /// When this run completed (nil if still in progress).
    var completedAt: Date?

    /// Platform identifier (e.g., "macOS", "iOS").
    let platform: String

    /// Device name (e.g., "MacBook Pro (M4 Max)", "iPhone 16 Pro Max").
    let deviceName: String

    /// Results for each model evaluated in this run.
    var modelResults: [ModelEvalResult]

    // MARK: - Init

    /// Memberwise initializer with sensible defaults.
    init(
        id: UUID = UUID(),
        suiteId: UUID,
        suiteName: String,
        suiteCategory: EvalCategory = .general,
        startedAt: Date = Date(),
        completedAt: Date? = nil,
        platform: String = EvalRun.currentPlatform,
        deviceName: String = EvalRun.currentDeviceName,
        modelResults: [ModelEvalResult] = []
    ) {
        self.id = id
        self.suiteId = suiteId
        self.suiteName = suiteName
        self.suiteCategory = suiteCategory
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.platform = platform
        self.deviceName = deviceName
        self.modelResults = modelResults
    }

    // MARK: - Computed Properties

    /// Whether this run has completed (all models evaluated).
    var isComplete: Bool { completedAt != nil }

    /// Total wall-clock duration of the run.
    var duration: TimeInterval? {
        guard let end = completedAt else { return nil }
        return end.timeIntervalSince(startedAt)
    }

    /// Formatted duration string (e.g., "2m 34s").
    var formattedDuration: String {
        guard let dur = duration else { return "In progress…" }
        let minutes = Int(dur) / 60
        let seconds = Int(dur) % 60
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }
        return "\(seconds)s"
    }

    /// Number of models evaluated.
    var modelCount: Int { modelResults.count }

    /// Overall pass rate across all models (computed from actual counts, not averaged rates).
    var overallPassRate: Double {
        guard !modelResults.isEmpty else { return 0 }
        let totalPassed = modelResults.reduce(0) { $0 + $1.promptResults.filter(\.passed).count }
        let totalPrompts = modelResults.reduce(0) { $0 + $1.promptResults.count }
        guard totalPrompts > 0 else { return 0 }
        return Double(totalPassed) / Double(totalPrompts)
    }

    /// Short display summary (e.g., "3 models · 87% pass rate").
    var displaySummary: String {
        let passPercent = Int(overallPassRate * 100)
        return "\(modelCount) model\(modelCount == 1 ? "" : "s") · \(passPercent)% pass rate"
    }

    // MARK: - Platform Detection

    /// Current platform identifier.
    static var currentPlatform: String {
        #if os(iOS)
        return "iOS"
        #elseif os(macOS)
        return "macOS"
        #else
        return "Unknown"
        #endif
    }

    /// Current device name.
    static var currentDeviceName: String {
        #if os(macOS)
        return Host.current().localizedName ?? "Mac"
        #else
        return DeviceMetrics.deviceModel
        #endif
    }
}

// MARK: - Model Eval Result

/// Evaluation results for a single model within an eval run.
///
/// Aggregates speed metrics, accuracy metrics, and resource metrics
/// from individual prompt results.
struct ModelEvalResult: Codable, Sendable, Identifiable {
    /// Unique identifier for this model result.
    let id: UUID

    /// Human-readable model name (e.g., "Gemma 4 E2B · Desktop GPU+CPU").
    let modelName: String

    /// Model filename on disk (e.g., "gemma-4-E2B-it.litertlm").
    let modelFile: String

    // MARK: - Speed Metrics (Aggregated)

    /// Average decode speed in tokens per second across all prompts.
    let avgDecodeSpeed: Double

    /// Average time to first token in seconds across all prompts.
    let avgTTFT: Double

    /// 95th percentile token latency in milliseconds across all prompts.
    let p95Latency: Double

    /// Total number of tokens generated across all prompts.
    let totalTokensGenerated: Int

    /// Total wall-clock duration for evaluating this model.
    let totalDuration: TimeInterval

    // MARK: - Accuracy Metrics

    /// Per-prompt detailed results.
    let promptResults: [PromptEvalResult]

    /// Fraction of prompts that passed (0.0–1.0).
    var passRate: Double

    /// Tool call accuracy for tool-calling prompts (nil if no tool prompts).
    var toolCallAccuracy: Double?

    // MARK: - Resource Metrics

    /// Peak memory delta in MB during this model's evaluation (nil if unavailable).
    let peakMemoryDeltaMB: Double?

    /// Number of thermal state transitions during evaluation.
    let thermalTransitions: Int

    // MARK: - Init

    /// Memberwise initializer.
    init(
        id: UUID = UUID(),
        modelName: String,
        modelFile: String,
        avgDecodeSpeed: Double,
        avgTTFT: Double,
        p95Latency: Double,
        totalTokensGenerated: Int,
        totalDuration: TimeInterval,
        promptResults: [PromptEvalResult],
        passRate: Double? = nil,
        toolCallAccuracy: Double? = nil,
        peakMemoryDeltaMB: Double? = nil,
        thermalTransitions: Int = 0
    ) {
        self.id = id
        self.modelName = modelName
        self.modelFile = modelFile
        self.avgDecodeSpeed = avgDecodeSpeed
        self.avgTTFT = avgTTFT
        self.p95Latency = p95Latency
        self.totalTokensGenerated = totalTokensGenerated
        self.totalDuration = totalDuration
        self.promptResults = promptResults
        // Auto-compute pass rate if not provided
        if let rate = passRate {
            self.passRate = rate
        } else {
            let passCount = promptResults.filter(\.passed).count
            self.passRate = promptResults.isEmpty ? 0 : Double(passCount) / Double(promptResults.count)
        }
        self.toolCallAccuracy = toolCallAccuracy
        self.peakMemoryDeltaMB = peakMemoryDeltaMB
        self.thermalTransitions = thermalTransitions
    }

    // MARK: - Computed Properties

    /// Number of prompts that passed.
    var passCount: Int { promptResults.filter(\.passed).count }

    /// Number of prompts that failed.
    var failCount: Int { promptResults.count - passCount }

    /// Number of prompts that timed out.
    var timeoutCount: Int {
        promptResults.filter { if case .timeout = $0.score { return true }; return false }.count
    }

    /// Number of prompts that errored.
    var errorCount: Int {
        promptResults.filter { if case .error = $0.score { return true }; return false }.count
    }

    /// Formatted pass rate as percentage string (e.g., "87%").
    var passRatePercent: String {
        "\(Int(passRate * 100))%"
    }

    /// Formatted decode speed (e.g., "43.1 tok/s").
    var formattedDecodeSpeed: String {
        String(format: "%.1f tok/s", avgDecodeSpeed)
    }

    /// Formatted TTFT (e.g., "0.87s").
    var formattedTTFT: String {
        String(format: "%.2fs", avgTTFT)
    }

    /// Formatted total duration (e.g., "1m 23s").
    var formattedDuration: String {
        let minutes = Int(totalDuration) / 60
        let seconds = Int(totalDuration) % 60
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }
        return "\(seconds)s"
    }

    /// Short display summary for list views.
    var displaySummary: String {
        "\(passRatePercent) pass · \(formattedDecodeSpeed) · \(formattedTTFT) TTFT"
    }
}

// MARK: - Prompt Eval Result

/// Evaluation result for a single prompt within a model's evaluation.
struct PromptEvalResult: Codable, Sendable, Identifiable {
    /// Unique identifier for this prompt result.
    let id: UUID

    /// The prompt ID from the source EvalPrompt.
    let promptId: UUID

    /// The prompt text that was sent.
    let promptText: String

    /// The model's full response text.
    let response: String

    /// Whether this prompt passed its expected behavior check.
    let passed: Bool

    /// Detailed score with pass/fail reason.
    let score: EvalScore

    /// Decode speed for this specific prompt (tokens/second), nil if unavailable.
    let decodeSpeed: Double?

    /// Time to first token for this prompt (seconds), nil if unavailable.
    let ttft: Double?

    /// Tool call events that occurred during this prompt's inference.
    let toolCallEvents: [ToolCallEvent]

    /// Wall-clock duration for this prompt's evaluation.
    let duration: TimeInterval

    // MARK: - Init

    /// Memberwise initializer.
    init(
        id: UUID = UUID(),
        promptId: UUID,
        promptText: String,
        response: String,
        passed: Bool,
        score: EvalScore,
        decodeSpeed: Double? = nil,
        ttft: Double? = nil,
        toolCallEvents: [ToolCallEvent] = [],
        duration: TimeInterval = 0
    ) {
        self.id = id
        self.promptId = promptId
        self.promptText = promptText
        self.response = response
        self.passed = passed
        self.score = score
        self.decodeSpeed = decodeSpeed
        self.ttft = ttft
        self.toolCallEvents = toolCallEvents
        self.duration = duration
    }

    // MARK: - Computed Properties

    /// Whether any tool calls occurred during this prompt.
    var hadToolCalls: Bool { !toolCallEvents.isEmpty }

    /// Names of tools that were called.
    var toolNamesUsed: [String] { toolCallEvents.map(\.toolName) }

    /// Formatted decode speed (e.g., "43.1 tok/s").
    var formattedDecodeSpeed: String {
        guard let speed = decodeSpeed else { return "N/A" }
        return String(format: "%.1f tok/s", speed)
    }

    /// Formatted TTFT (e.g., "0.87s").
    var formattedTTFT: String {
        guard let t = ttft else { return "N/A" }
        return String(format: "%.2fs", t)
    }

    /// Truncated response for compact display (max 120 characters).
    var truncatedResponse: String {
        if response.count <= 120 { return response }
        return String(response.prefix(117)) + "..."
    }
}

// MARK: - Eval Score

/// Outcome classification for a single prompt evaluation.
enum EvalScore: Codable, Sendable, Equatable {
    /// The response satisfied the expected behavior.
    case pass

    /// The response did not satisfy the expected behavior.
    case fail(reason: String)

    /// The prompt timed out before receiving a complete response.
    case timeout

    /// An error occurred during inference.
    case error(String)

    /// This prompt requires human review (e.g., custom expectations).
    case manualReviewNeeded

    // MARK: - Display Helpers

    /// Human-readable label for display.
    var displayLabel: String {
        switch self {
        case .pass:                     return "Pass"
        case .fail:                     return "Fail"
        case .timeout:                  return "Timeout"
        case .error:                    return "Error"
        case .manualReviewNeeded:       return "Needs Review"
        }
    }

    /// SF Symbol name for this score.
    var symbolName: String {
        switch self {
        case .pass:                     return "checkmark.circle.fill"
        case .fail:                     return "xmark.circle.fill"
        case .timeout:                  return "clock.badge.exclamationmark"
        case .error:                    return "exclamationmark.triangle.fill"
        case .manualReviewNeeded:       return "eye.circle"
        }
    }

    /// Whether this score represents a definitive pass.
    var isPass: Bool {
        if case .pass = self { return true }
        return false
    }

    /// Whether this score represents a definitive failure (fail, timeout, or error).
    var isFailure: Bool {
        switch self {
        case .fail, .timeout, .error:   return true
        default:                        return false
        }
    }

    /// Detailed reason string, or nil for pass/manualReview.
    var reason: String? {
        switch self {
        case .fail(reason: let r):      return r
        case .error(let e):             return e
        case .timeout:                  return "Inference timed out"
        default:                        return nil
        }
    }
}

// MARK: - Eval Run Index Entry

/// Lightweight index entry for fast listing of eval runs without loading full data.
///
/// Mirrors the pattern used by `ConversationIndexEntry` — just enough data
/// to render a run row in the sidebar.
struct EvalRunIndexEntry: Codable, Sendable, Identifiable {
    /// The eval run ID.
    let id: UUID

    /// Suite name for display.
    let suiteName: String

    /// Number of models evaluated.
    let modelCount: Int

    /// Overall pass rate across all models (0.0–1.0).
    let overallPassRate: Double

    /// Platform string (e.g., "macOS").
    let platform: String

    /// Device name.
    let deviceName: String

    /// When the run was started.
    let startedAt: Date

    /// When the run completed (nil if still in progress).
    let completedAt: Date?

    /// Whether this run completed.
    var isComplete: Bool { completedAt != nil }

    /// Initialize from a full EvalRun.
    init(from run: EvalRun) {
        self.id = run.id
        self.suiteName = run.suiteName
        self.modelCount = run.modelCount
        self.overallPassRate = run.overallPassRate
        self.platform = run.platform
        self.deviceName = run.deviceName
        self.startedAt = run.startedAt
        self.completedAt = run.completedAt
    }
}
