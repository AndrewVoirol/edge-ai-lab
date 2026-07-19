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

/// Pure formatting helpers for model detail display.
/// Extracted from `iOSModelDetailView` for cross-platform reuse and testability.
enum ModelDetailFormatters {

    /// Format a byte count for display (e.g. "4.2 GB").
    static func formattedSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    /// Format a context window size for display (e.g. "8K ctx", "1M ctx").
    static func formattedContextWindow(_ size: Int) -> String {
        if size >= 1_000_000 {
            return "\(size / 1_000_000)M ctx"
        } else if size >= 1_000 {
            return "\(size / 1_000)K ctx"
        } else {
            return "\(size) ctx"
        }
    }

    // MARK: - Capability Badges

    /// Builds an ordered array of capability badge labels from model flags.
    ///
    /// Always includes "Text Generation" as the first badge. Conditional badges
    /// are appended in display order: Vision, Audio, MTP/Speculative, Tool Calling, Thinking.
    ///
    /// - Parameters:
    ///   - supportsImage: Whether the model supports image input.
    ///   - supportsAudio: Whether the model supports audio input.
    ///   - supportsMTP: Whether the model supports Multi-Token Prediction.
    ///   - supportsToolCalling: Whether the model supports function calling.
    ///   - supportsThinking: Whether the model has thinking/reasoning capability.
    /// - Returns: An ordered array of badge label strings.
    static func capabilityBadges(
        supportsImage: Bool,
        supportsAudio: Bool,
        supportsMTP: Bool,
        supportsToolCalling: Bool,
        supportsThinking: Bool
    ) -> [String] {
        var badges = ["Text Generation"]
        if supportsImage { badges.append("Vision") }
        if supportsAudio { badges.append("Audio") }
        if supportsMTP { badges.append("Speculative Decoding") }
        if supportsToolCalling { badges.append("Tool Calling") }
        if supportsThinking { badges.append("Thinking") }
        return badges
    }

    // MARK: - Model Count Label

    /// Formats a model count with proper singular/plural phrasing.
    ///
    /// - Parameters:
    ///   - count: The number of models.
    ///   - noun: The noun to pluralize (default: "model").
    /// - Returns: A string like "1 model" or "3 models".
    static func modelCountLabel(_ count: Int, noun: String = "model") -> String {
        "\(count) \(noun)\(count == 1 ? "" : "s")"
    }

    // MARK: - Token Count Formatting

    /// Formats a token count with K/M suffixes (e.g., 128000 → "128K", 1000000 → "1M").
    ///
    /// Unlike `formattedContextWindow`, this does NOT append a " ctx" suffix.
    /// Used for raw count display in model detail panels.
    ///
    /// - Parameter count: The token count to format.
    /// - Returns: A compact string representation.
    static func formatTokenCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.0fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.0fK", Double(count) / 1_000)
        }
        return "\(count)"
    }

    // MARK: - Download Count Formatting

    /// Formats a download count with K/M suffixes (e.g., 12345 → "12.3K").
    ///
    /// - Parameter count: The download count.
    /// - Returns: A compact string representation.
    static func formatDownloadCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return "\(count)"
    }
    // MARK: - Model Name Normalization

    /// Normalize a model display name for consistent rendering.
    ///
    /// Replaces hyphens with spaces and title-cases known model families.
    /// Applied at display time so ALL sources (registry, catalog, synthesized) are covered.
    ///
    /// Examples:
    /// - `"gemma-4-e2b-it-Q4_K_M"` → `"Gemma 4 E2B IT Q4_K_M"`
    /// - `"mlx-community--phi-4-4bit"` → `"mlx community / Phi 4 4bit"`
    ///
    /// - Parameter name: The raw model name or filename stem.
    /// - Returns: A human-readable display name.
    static func normalizeDisplayName(_ name: String) -> String {
        // Skip names that already look well-formatted (contain " : " separator = MLX catalog)
        if name.contains(" : ") { return name }

        var result = name
            .replacingOccurrences(of: "--", with: " / ")
            .replacingOccurrences(of: "-", with: " ")

        // Title-case known model family prefixes
        result = result
            .replacingOccurrences(of: "gemma ", with: "Gemma ", options: .caseInsensitive)
            .replacingOccurrences(of: "llama ", with: "Llama ", options: .caseInsensitive)
            .replacingOccurrences(of: "mistral ", with: "Mistral ", options: .caseInsensitive)
            .replacingOccurrences(of: "phi ", with: "Phi ", options: .caseInsensitive)
            .replacingOccurrences(of: "qwen ", with: "Qwen ", options: .caseInsensitive)
            // Normalize common component casing
            .replacingOccurrences(of: " it ", with: " IT ", options: .caseInsensitive)
            .replacingOccurrences(of: " it$", with: " IT", options: [.caseInsensitive, .regularExpression])
            .replacingOccurrences(of: " e2b", with: " E2B", options: .caseInsensitive)
            .replacingOccurrences(of: " e4b", with: " E4B", options: .caseInsensitive)

        return result
    }

    /// Split a model display name into a family name and an optional quantization suffix.
    ///
    /// Examples:
    /// - `"Gemma 4 E2B IT Q4_K_M"` → `("Gemma 4 E2B IT", "Q4_K_M")`
    /// - `"Gemma 4 E2B IT"` → `("Gemma 4 E2B IT", nil)`
    ///
    /// - Parameter fullName: The display name to split.
    /// - Returns: A tuple of the primary name and optional quantization suffix.
    static func splitModelName(_ fullName: String) -> (primary: String, quantization: String?) {
        // Known quantization patterns to detect and split on
        let quantPatterns = [
            "UD-IQ", "UD-Q",
            "IQ4_", "IQ3_", "IQ2_",
            "Q3_K", "Q4_K", "Q5_K", "Q6_K", "Q8_",
            "Q4_0", "Q4_1", "Q5_0", "Q5_1",
            "BF16", "F16", "F32",
            // Common HuggingFace shorthand quantization names
            "4bit", "8bit", "2bit",
        ]
        for pattern in quantPatterns {
            if let range = fullName.range(of: pattern, options: .caseInsensitive) {
                let primary = String(fullName[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
                let secondary = String(fullName[range.lowerBound...])
                return (primary.isEmpty ? fullName : primary, secondary)
            }
        }
        return (fullName, nil)
    }
}

