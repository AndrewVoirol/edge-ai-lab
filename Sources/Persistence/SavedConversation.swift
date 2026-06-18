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

// MARK: - Saved Conversation

/// A persisted experiment run — the top-level structure stored as a JSON file.
///
/// Contains the full message history, experiment configuration snapshot,
/// and aggregate benchmark summary. Designed for the "experiment as conversation"
/// paradigm where each conversation is a scientific artifact.
///
/// **Persistence**: Each `SavedConversation` maps to one JSON file at:
/// `~/Library/Application Support/EdgeAILab/Conversations/{id}.json`
///
/// **Lifecycle**:
/// 1. Created automatically when inference completes (auto-save)
/// 2. Viewed in read-only mode from the sidebar
/// 3. Forked to create a new editable experiment with the same config/history
/// 4. Deleted via context menu
struct SavedConversation: Codable, Identifiable, Sendable {

    /// Unique identifier for this experiment run.
    let id: UUID

    /// Smart title combining model name + first prompt snippet.
    /// Format: "E2B · Explain quantum..." — editable via context menu rename.
    var title: String

    /// Frozen configuration snapshot at the time of creation.
    let config: ExperimentConfig

    /// Full message history (text only — multimodal attachments stored as metadata).
    let messages: [ChatMessage]

    /// Aggregate benchmark summary for quick sidebar display.
    let summary: ExperimentSummary

    /// When the experiment was first created.
    let createdAt: Date

    /// When the experiment was last modified (last inference completion).
    let lastModifiedAt: Date

    /// The UUID of the original conversation this was forked from, if any.
    let forkedFrom: UUID?
}

// MARK: - Experiment Summary

/// Conversation-level aggregate metrics for quick sidebar rendering.
///
/// Computed from the per-message `BenchmarkSnapshot` data without needing
/// to deserialize the full message array.
struct ExperimentSummary: Codable, Sendable {

    /// Average decode speed across all assistant messages (tok/s).
    let averageDecodeSpeed: Double?

    /// Total tokens generated across all assistant messages.
    let totalTokens: Int

    /// Number of messages in the conversation (user + assistant + system).
    let messageCount: Int

    /// Timestamp of the last activity (last message or inference completion).
    let lastActivityDate: Date

    /// Total number of tool calls made during this experiment.
    let totalToolCalls: Int

    /// Duration of the experiment from first to last message.
    let experimentDuration: TimeInterval?

    // MARK: - Factory

    /// Compute a summary from a conversation's messages.
    static func compute(from messages: [ChatMessage]) -> ExperimentSummary {
        let assistantMessages = messages.filter { $0.role == .assistant }

        // Collect benchmark data from all assistant messages
        let benchmarks = assistantMessages.compactMap(\.benchmarkInfo)
        let avgSpeed: Double? = benchmarks.isEmpty ? nil : benchmarks.map(\.decodeTokensPerSecond).reduce(0, +) / Double(benchmarks.count)
        let totalToks = benchmarks.map(\.tokenCount).reduce(0, +)

        // Count tool calls
        let toolCallCount = messages.reduce(0) { $0 + $1.toolCalls.count }

        // Experiment duration
        let timestamps = messages.map(\.timestamp)
        let duration: TimeInterval?
        if let first = timestamps.first, let last = timestamps.last, first != last {
            duration = last.timeIntervalSince(first)
        } else {
            duration = nil
        }

        return ExperimentSummary(
            averageDecodeSpeed: avgSpeed,
            totalTokens: totalToks,
            messageCount: messages.count,
            lastActivityDate: timestamps.last ?? Date(),
            totalToolCalls: toolCallCount,
            experimentDuration: duration
        )
    }
}

// MARK: - Smart Title Generation

extension SavedConversation {

    /// Generate a smart title from the config and messages.
    /// Format: "E2B · Explain quantum entanglement and..."
    static func generateTitle(config: ExperimentConfig, messages: [ChatMessage]) -> String {
        let modelPart = config.modelShortName

        // Find the first user message for the prompt snippet
        guard let firstUserMessage = messages.first(where: { $0.role == .user }) else {
            return "\(modelPart) · New Experiment"
        }

        let prompt = firstUserMessage.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if prompt.isEmpty {
            return "\(modelPart) · New Experiment"
        }

        // Truncate to ~40 chars on word boundary
        let maxLength = 40
        let truncated: String
        if prompt.count <= maxLength {
            truncated = prompt
        } else {
            let prefixEnd = prompt.index(prompt.startIndex, offsetBy: maxLength)
            let prefix = String(prompt[..<prefixEnd])
            // Find the last space to avoid cutting mid-word
            if let lastSpace = prefix.lastIndex(of: " ") {
                truncated = String(prefix[..<lastSpace]) + "…"
            } else {
                truncated = prefix + "…"
            }
        }

        // Remove newlines for clean sidebar display
        let clean = truncated.replacingOccurrences(of: "\n", with: " ")
        return "\(modelPart) · \(clean)"
    }
}
