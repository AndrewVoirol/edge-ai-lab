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

import SwiftUI

// MARK: - Capability Gate Status

/// Represents the resolved state of a capability gate.
///
/// Used by settings views to determine whether a toggle should be enabled,
/// disabled, or hidden — and to show provenance labels like "(from config.json)".
enum CapabilityGateStatus: Sendable {
    /// Capability is supported — show and enable the UI.
    case supported(source: CapabilitySource)
    /// Capability is not supported — show but disable the UI with explanation.
    case unsupported(source: CapabilitySource, reason: String)
    /// Capability status is unknown — no profile or no data. Show with a caution badge.
    case unknown
    /// Capability is not applicable for this runtime type. Hide the UI entirely.
    case notApplicable(reason: String)

    /// Whether the UI element should be enabled/interactive.
    var isEnabled: Bool {
        if case .supported = self { return true }
        return false
    }

    /// Whether the UI element should be visible at all.
    var isVisible: Bool {
        if case .notApplicable = self { return false }
        return true
    }

    /// Source label for inline display (e.g., "from config.json").
    var sourceLabel: String? {
        switch self {
        case .supported(let source): return source.displayLabel
        case .unsupported(let source, _): return source.displayLabel
        default: return nil
        }
    }

    /// Reason text for disabled states.
    var disabledReason: String? {
        switch self {
        case .unsupported(_, let reason): return reason
        case .notApplicable(let reason): return reason
        default: return nil
        }
    }
}

// MARK: - Capability Gating Logic

/// Pure-function namespace for resolving capability gates.
///
/// All methods are static and side-effect-free. This makes them testable
/// without needing a view hierarchy or @Observable state.
enum CapabilityGating {

    /// Resolve the gate status for vision/image support.
    static func vision(profile: ModelCapabilityProfile?) -> CapabilityGateStatus {
        guard let profile = profile else { return .unknown }
        guard let sv = profile.supportsVision else { return .unknown }
        if sv.value {
            return .supported(source: sv.source)
        } else {
            return .unsupported(source: sv.source, reason: "This model does not support image input.")
        }
    }

    /// Resolve the gate status for audio support.
    static func audio(profile: ModelCapabilityProfile?) -> CapabilityGateStatus {
        guard let profile = profile else { return .unknown }
        guard let sv = profile.supportsAudio else { return .unknown }
        if sv.value {
            return .supported(source: sv.source)
        } else {
            return .unsupported(source: sv.source, reason: "This model does not support audio input.")
        }
    }

    /// Resolve the gate status for thinking/reasoning mode.
    static func thinking(profile: ModelCapabilityProfile?) -> CapabilityGateStatus {
        guard let profile = profile else { return .unknown }
        guard let sv = profile.supportsThinking else { return .unknown }
        if sv.value {
            return .supported(source: sv.source)
        } else {
            return .unsupported(source: sv.source, reason: "This model does not support thinking mode.")
        }
    }

    /// Resolve the gate status for tool calling.
    static func toolCalling(profile: ModelCapabilityProfile?) -> CapabilityGateStatus {
        guard let profile = profile else { return .unknown }
        guard let sv = profile.supportsToolCalling else { return .unknown }
        if sv.value {
            return .supported(source: sv.source)
        } else {
            return .unsupported(
                source: sv.source,
                reason: "This model may not reliably follow tool-calling instructions."
            )
        }
    }

    /// Resolve the gate status for MTP/speculative decoding.
    ///
    /// MTP requires both model support AND runtime support (currently LiteRT-LM only).
    static func mtp(profile: ModelCapabilityProfile?, runtimeType: RuntimeType) -> CapabilityGateStatus {
        // MTP only works on LiteRT-LM
        guard runtimeType == .litertlm else {
            return .notApplicable(reason: "MTP is only available on LiteRT-LM backend.")
        }
        guard let profile = profile else { return .unknown }
        guard let sv = profile.supportsMTP else { return .unknown }
        if sv.value {
            return .supported(source: sv.source)
        } else {
            return .unsupported(source: sv.source, reason: "This model does not include MTP draft heads.")
        }
    }

    /// Resolve the gate status for constrained decoding.
    static func constrainedDecoding(profile: ModelCapabilityProfile?, runtimeType: RuntimeType) -> CapabilityGateStatus {
        guard runtimeType == .litertlm else {
            return .notApplicable(reason: "Constrained decoding is only available on LiteRT-LM backend.")
        }
        guard let profile = profile else { return .unknown }
        guard let sv = profile.supportsConstrainedDecoding else { return .unknown }
        if sv.value {
            return .supported(source: sv.source)
        } else {
            return .unsupported(source: sv.source, reason: "This model does not support constrained decoding.")
        }
    }
}

// MARK: - Sourced Capability Badge View

/// A small inline badge that shows a capability's status and provenance.
///
/// Example display:
/// - ✓ Vision (from config.json)
/// - ✗ Audio (estimated)
/// - ? Thinking
struct SourcedCapabilityBadge: View {
    let label: String
    let status: CapabilityGateStatus

    var body: some View {
        HStack(spacing: AppSpacing.xs) {
            Image(systemName: symbolName)
                .foregroundStyle(symbolColor)
            Text(label)
                .font(AppTypography.caption)
            if let sourceLabel = status.sourceLabel {
                Text("(\(sourceLabel))")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textTertiary)
            }
        }
        .accessibilityLabel("\(label): \(accessibilityDescription)")
    }

    private var symbolName: String {
        switch status {
        case .supported: return "checkmark.circle.fill"
        case .unsupported: return "xmark.circle.fill"
        case .unknown: return "questionmark.circle"
        case .notApplicable: return "minus.circle"
        }
    }

    private var symbolColor: Color {
        switch status {
        case .supported: return AppColors.success
        case .unsupported: return AppColors.destructive
        case .unknown: return AppColors.textSecondary
        case .notApplicable: return AppColors.textTertiary
        }
    }

    private var accessibilityDescription: String {
        switch status {
        case .supported(let source):
            return "Supported (\(source.displayLabel))"
        case .unsupported(_, let reason):
            return "Not supported. \(reason)"
        case .unknown:
            return "Unknown"
        case .notApplicable(let reason):
            return "Not applicable. \(reason)"
        }
    }
}
