// Copyright 2026 Andrew Voirol. Apache-2.0
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

// MARK: - Eval Suite

/// A collection of evaluation prompts grouped into a named test suite.
///
/// Suites define a repeatable battery of tests that can be run against one or more
/// models. Built-in suites ship with the app (see `BuiltInEvalSuites`); custom
/// suites can be created by users.
struct EvalSuite: Codable, Sendable, Identifiable {
    /// Unique identifier for this suite.
    let id: UUID

    /// Human-readable suite name (e.g., "Math Accuracy").
    let name: String

    /// Longer description of what this suite tests.
    let description: String

    /// Broad category for grouping suites in the UI.
    let category: EvalCategory

    /// Ordered list of prompts to evaluate.
    let prompts: [EvalPrompt]

    /// Whether this suite ships with the app (true) or was user-created (false).
    let isBuiltIn: Bool

    /// When this suite was created.
    let createdAt: Date

    // MARK: - Init

    /// Memberwise initializer with sensible defaults.
    init(
        id: UUID = UUID(),
        name: String,
        description: String,
        category: EvalCategory,
        prompts: [EvalPrompt],
        isBuiltIn: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.category = category
        self.prompts = prompts
        self.isBuiltIn = isBuiltIn
        self.createdAt = createdAt
    }

    // MARK: - Computed Properties

    /// Number of prompts in this suite.
    var promptCount: Int { prompts.count }

    /// Whether this suite contains any multimodal prompts (image or audio data).
    var hasMultimodalPrompts: Bool {
        prompts.contains { $0.imageData != nil || $0.audioData != nil }
    }

    /// Short summary for display (e.g., "10 prompts · Math").
    var displaySummary: String {
        "\(promptCount) prompt\(promptCount == 1 ? "" : "s") · \(category.displayName)"
    }

    /// Estimated total timeout for running this suite against a single model.
    var estimatedDurationSeconds: Int {
        prompts.reduce(0) { $0 + $1.timeoutSeconds }
    }
}

// MARK: - Eval Category

/// Broad categories for grouping evaluation suites.
enum EvalCategory: String, Codable, Sendable, CaseIterable {
    case math
    case toolCalling
    case reasoning
    case multimodal
    case general
    case custom

    /// Human-readable display name.
    var displayName: String {
        switch self {
        case .math:         return "Math"
        case .toolCalling:  return "Tool Calling"
        case .reasoning:    return "Reasoning"
        case .multimodal:   return "Multimodal"
        case .general:      return "General"
        case .custom:       return "Custom"
        }
    }

    /// SF Symbol name for this category.
    var symbolName: String {
        switch self {
        case .math:         return "function"
        case .toolCalling:  return "wrench.and.screwdriver"
        case .reasoning:    return "brain"
        case .multimodal:   return "photo.on.rectangle"
        case .general:      return "text.bubble"
        case .custom:       return "slider.horizontal.3"
        }
    }
}

// MARK: - Eval Prompt

/// A single evaluation prompt with expected behavior for automated scoring.
struct EvalPrompt: Codable, Sendable, Identifiable {
    /// Unique identifier for this prompt.
    let id: UUID

    /// The prompt text to send to the model.
    let prompt: String

    /// What the model's response should satisfy for a "pass" score.
    let expectedBehavior: ExpectedBehavior

    /// Optional image data for multimodal prompts (JPEG/PNG).
    let imageData: Data?

    /// Optional audio data for multimodal prompts.
    let audioData: Data?

    /// Maximum seconds to wait for a response before marking as timeout.
    let timeoutSeconds: Int

    // MARK: - Init

    /// Memberwise initializer with sensible defaults.
    init(
        id: UUID = UUID(),
        prompt: String,
        expectedBehavior: ExpectedBehavior,
        imageData: Data? = nil,
        audioData: Data? = nil,
        timeoutSeconds: Int = 60
    ) {
        self.id = id
        self.prompt = prompt
        self.expectedBehavior = expectedBehavior
        self.imageData = imageData
        self.audioData = audioData
        self.timeoutSeconds = timeoutSeconds
    }

    // MARK: - Computed Properties

    /// Whether this prompt includes image data.
    var isImagePrompt: Bool { imageData != nil }

    /// Whether this prompt includes audio data.
    var isAudioPrompt: Bool { audioData != nil }

    /// Whether this prompt is multimodal (includes image or audio).
    var isMultimodal: Bool { isImagePrompt || isAudioPrompt }

    /// Truncated prompt text for compact display (max 80 characters).
    var truncatedPrompt: String {
        if prompt.count <= 80 { return prompt }
        return String(prompt.prefix(77)) + "..."
    }
}

// MARK: - Expected Behavior

/// Defines the expected behavior of a model's response for automated scoring.
///
/// Each case represents a different type of assertion that the eval runner
/// checks against the model's output and tool call events.
enum ExpectedBehavior: Codable, Sendable {
    /// Response must contain the specified text (case-insensitive).
    case containsText(String)

    /// Response must contain ANY of the specified texts (case-insensitive).
    ///
    /// Useful for multimodal eval where the model may use synonyms for the same
    /// concept (e.g., "bicycle" vs "bike" vs "cycle"). Passes if at least one
    /// of the provided strings is found in the response.
    case containsAny([String])

    /// Response must contain ALL of the specified texts (case-insensitive).
    ///
    /// Useful for multi-aspect queries (e.g., "What is this and what color?").
    /// Passes only if every string in the array is found in the response.
    case containsAll([String])

    /// Model must invoke a tool with the given name.
    case toolCall(toolName: String)

    /// Model must invoke a tool with specific argument key-value pair.
    case toolCallWithArgs(toolName: String, key: String, expectedValue: String)

    /// Model must invoke a chain of tools in the specified order.
    case toolCallChain([String])

    /// Response must be non-empty (at least some text generated).
    case nonEmpty

    /// Response must match the given regular expression pattern.
    case matchesRegex(String)

    /// Custom description for manual review — cannot be auto-scored.
    case custom(description: String)

    // MARK: - Display Helpers

    /// Human-readable description of what this expectation checks.
    var displayDescription: String {
        switch self {
        case .containsText(let text):
            return "Contains: \"\(text)\""
        case .containsAny(let alternatives):
            let joined = alternatives.map { "\"\($0)\"" }.joined(separator: ", ")
            return "Contains any of: [\(joined)]"
        case .containsAll(let required):
            let joined = required.map { "\"\($0)\"" }.joined(separator: ", ")
            return "Contains all of: [\(joined)]"
        case .toolCall(toolName: let name):
            return "Calls tool: \(name)"
        case .toolCallWithArgs(toolName: let name, key: let key, expectedValue: let value):
            return "Calls \(name) with \(key)=\"\(value)\""
        case .toolCallChain(let tools):
            return "Tool chain: \(tools.joined(separator: " → "))"
        case .nonEmpty:
            return "Non-empty response"
        case .matchesRegex(let pattern):
            return "Matches regex: /\(pattern)/"
        case .custom(description: let desc):
            return "Manual: \(desc)"
        }
    }

    /// Whether this expectation can be automatically scored (vs. manual review).
    var isAutoScorable: Bool {
        switch self {
        case .custom:
            return false
        default:
            return true
        }
    }

    /// Whether this expectation involves tool calling.
    var involvesToolCalling: Bool {
        switch self {
        case .toolCall, .toolCallWithArgs, .toolCallChain:
            return true
        default:
            return false
        }
    }
}
