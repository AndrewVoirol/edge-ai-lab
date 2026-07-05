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

// MARK: - KVCacheConfigLogic

/// Pure-function logic for KV-cache (maxNumTokens) configuration.
/// Extracted from view code for testability per project conventions.
/// Views call these static methods; no instance state.
enum KVCacheConfigLogic {

    // MARK: - Constants

    /// Minimum allowed KV-cache token count.
    static let minimumTokenCount = 256

    /// Default upper bound when model context length is unknown.
    static let defaultMaxTokenCount = 8192

    // MARK: - Validation

    /// Result of validating a token count configuration.
    struct ValidationResult: Sendable, Equatable {
        let isValid: Bool
        let errorMessage: String?

        static func valid() -> ValidationResult {
            ValidationResult(isValid: true, errorMessage: nil)
        }

        static func invalid(_ message: String) -> ValidationResult {
            ValidationResult(isValid: false, errorMessage: message)
        }
    }

    /// Validates a maxNumTokens configuration value.
    ///
    /// - Parameter tokenCount: The token count to validate. `nil` means auto (always valid).
    /// - Returns: A `ValidationResult` indicating whether the value is acceptable.
    static func validate(tokenCount: Int?) -> ValidationResult {
        guard let count = tokenCount else {
            // nil = auto mode, always valid
            return .valid()
        }

        if count <= 0 {
            return .invalid("Token count must be a positive number")
        }

        return .valid()
    }

    // MARK: - Stepper Range

    /// Returns the valid range for the KV-cache token count stepper.
    ///
    /// - Parameter modelContextLength: The model's native context window size, or `nil` if unknown.
    /// - Returns: A closed range from `minimumTokenCount` to the model's context length (or default).
    static func stepperRange(modelContextLength: Int?) -> ClosedRange<Int> {
        let upper = modelContextLength ?? defaultMaxTokenCount
        return minimumTokenCount...upper
    }

    /// Returns preset step values for the KV-cache stepper.
    /// Powers of 2 that fit within the model's context length.
    ///
    /// - Parameter modelContextLength: The model's native context window size, or `nil` if unknown.
    /// - Returns: Sorted array of preset token counts.
    static func presetSteps(modelContextLength: Int?) -> [Int] {
        let maxLength = modelContextLength ?? defaultMaxTokenCount
        let allPresets = [256, 512, 1024, 2048, 4096, 8192, 16384, 32768, 65536, 131072, 262144]
        return allPresets.filter { $0 <= maxLength }
    }

    // MARK: - Display Label

    /// Formats a display label for the current KV-cache configuration.
    ///
    /// - Parameters:
    ///   - tokenCount: Current token count setting. `nil` means auto.
    ///   - modelDefault: The model's default/native context length, or `nil` if unknown.
    /// - Returns: Human-readable label string.
    static func formatDisplayLabel(tokenCount: Int?, modelDefault: Int?) -> String {
        if let count = tokenCount {
            if let modelDefault {
                return "\(count) tokens (model default: \(modelDefault))"
            } else {
                return "\(count) tokens"
            }
        } else {
            if let modelDefault {
                return "Auto (\(modelDefault) tokens)"
            } else {
                return "Auto"
            }
        }
    }

    // MARK: - Restart Detection

    /// Whether changing the KV-cache setting requires engine re-initialization.
    ///
    /// - Parameters:
    ///   - current: The currently active token count (nil = auto).
    ///   - proposed: The newly selected token count (nil = auto).
    /// - Returns: `true` if the engine must be restarted.
    static func requiresRestart(current: Int?, proposed: Int?) -> Bool {
        current != proposed
    }
}
