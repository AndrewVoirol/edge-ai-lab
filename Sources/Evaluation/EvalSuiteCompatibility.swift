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

// MARK: - Eval Suite Compatibility Status

/// Represents the compatibility of an eval suite with a loaded model.
enum EvalSuiteCompatibilityStatus: Sendable, Equatable {
    /// Suite is fully compatible — all requirements are met.
    case compatible
    /// Suite is partially compatible — some prompts will be skipped.
    case partiallyCompatible(reasons: [String])
    /// Suite is incompatible — cannot run at all.
    case incompatible(reasons: [String])
    /// Compatibility cannot be determined — no profile available.
    case unknown

    /// Whether the suite can be launched (compatible or partially compatible).
    var canRun: Bool {
        switch self {
        case .compatible, .partiallyCompatible: return true
        case .incompatible, .unknown: return false
        }
    }

    /// Human-readable summary of the compatibility status.
    var displaySummary: String {
        switch self {
        case .compatible:
            return "Compatible"
        case .partiallyCompatible(let reasons):
            return "Partial: \(reasons.joined(separator: "; "))"
        case .incompatible(let reasons):
            return "Incompatible: \(reasons.joined(separator: "; "))"
        case .unknown:
            return "Compatibility unknown"
        }
    }

    /// SF Symbol name for the status.
    var symbolName: String {
        switch self {
        case .compatible: return "checkmark.seal.fill"
        case .partiallyCompatible: return "exclamationmark.triangle.fill"
        case .incompatible: return "xmark.seal.fill"
        case .unknown: return "questionmark.circle"
        }
    }
}

// MARK: - Eval Suite Compatibility Checker

/// Pure-function namespace for checking eval suite compatibility against a model's capabilities.
///
/// Uses the suite's existing computed properties (hasMultimodalPrompts, requiresToolCalling)
/// plus the EvalCategory to infer requirements, then checks against ModelCapabilityProfile.
enum EvalSuiteCompatibility {

    /// Check the compatibility of a suite with the given model capability profile.
    static func check(suite: EvalSuite, profile: ModelCapabilityProfile?) -> EvalSuiteCompatibilityStatus {
        guard let profile = profile else { return .unknown }

        var incompatibleReasons: [String] = []
        var partialReasons: [String] = []

        // Check multimodal requirements
        if suite.hasMultimodalPrompts || suite.category == .multimodal {
            let hasVision = profile.supportsVision?.value ?? false
            let hasAudio = profile.supportsAudio?.value ?? false
            if !hasVision && !hasAudio {
                if suite.category == .multimodal {
                    incompatibleReasons.append("Model lacks multimodal support")
                } else {
                    partialReasons.append("Multimodal prompts will be skipped")
                }
            }
        }

        // Check tool calling requirements
        if suite.requiresToolCalling {
            let hasToolCalling = profile.supportsToolCalling?.value ?? false
            if !hasToolCalling {
                incompatibleReasons.append("Model may not support tool calling")
            }
        } else if suite.hasToolCallingPrompts {
            let hasToolCalling = profile.supportsToolCalling?.value ?? false
            if !hasToolCalling {
                partialReasons.append("Tool calling prompts will be skipped")
            }
        }

        // Check thinking requirements for reasoning suites
        if suite.category == .reasoning {
            let hasThinking = profile.supportsThinking?.value ?? false
            if !hasThinking {
                partialReasons.append("Model may not support explicit thinking mode")
            }
        }

        // Return the most severe status
        if !incompatibleReasons.isEmpty {
            return .incompatible(reasons: incompatibleReasons)
        } else if !partialReasons.isEmpty {
            return .partiallyCompatible(reasons: partialReasons)
        } else {
            return .compatible
        }
    }

    /// Filter a list of suites to only those compatible with the given profile.
    ///
    /// Returns all suites that are `.compatible` or `.partiallyCompatible`.
    /// If no profile is available, returns all suites (fail-open).
    static func filterCompatible(suites: [EvalSuite], profile: ModelCapabilityProfile?) -> [EvalSuite] {
        guard let profile = profile else { return suites }
        return suites.filter { suite in
            let status = check(suite: suite, profile: profile)
            return status.canRun
        }
    }

    /// Annotate suites with their compatibility status.
    ///
    /// Returns tuples of (suite, status) for UI display.
    static func annotate(suites: [EvalSuite], profile: ModelCapabilityProfile?) -> [(suite: EvalSuite, status: EvalSuiteCompatibilityStatus)] {
        suites.map { suite in
            (suite: suite, status: check(suite: suite, profile: profile))
        }
    }
}
