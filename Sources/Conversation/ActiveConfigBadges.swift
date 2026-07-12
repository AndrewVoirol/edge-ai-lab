// Copyright 2026 Andrew Voirol. Apache-2.0
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0

import SwiftUI

// MARK: - Active Configuration Badges

/// Contextual pills above the input field showing active inference features.
///
/// Each badge represents a feature flag with three possible states:
/// - **Active** (solid color): Feature is enabled AND supported by the current engine
/// - **Unsupported** (dimmed + ⚠️): Feature is enabled but NOT supported by the current engine
/// - **Hidden**: Feature is disabled
///
/// Tapping a badge toggles the feature directly (saves a settings detour).
///
/// Badge data is sourced from `FlagRegistry` (Phase 2A.2), which is itself
/// sourced from Phase 1/1.5 empirical testing.
struct ActiveConfigBadges: View {
    @Bindable var viewModel: ConversationViewModel

    var body: some View {
        let badges = Self.visibleBadges(
            flags: viewModel.runtimeFlags,
            runtime: viewModel.selectedRuntimeType
        )

        if !badges.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppSpacing.xs) {
                    ForEach(badges) { badge in
                        BadgePill(
                            badge: badge,
                            onTap: { toggleFlag(badge.flagId) }
                        )
                    }
                }
                .padding(.horizontal, AppSpacing.sm)
            }
            .accessibilityIdentifier("active_config_badges")
        }
    }

    // MARK: - Toggle Logic

    private func toggleFlag(_ flagId: String) {
        switch flagId {
        case "thinking":
            viewModel.runtimeFlags.enableThinking.toggle()
        case "mtp":
            if let current = viewModel.runtimeFlags.enableSpeculativeDecoding {
                viewModel.runtimeFlags.enableSpeculativeDecoding = !current
            } else {
                viewModel.runtimeFlags.enableSpeculativeDecoding = true
            }
        case "cd":
            viewModel.runtimeFlags.enableConversationConstrainedDecoding.toggle()
        case "tools":
            viewModel.runtimeFlags.enableToolCalling.toggle()
        default:
            break
        }
    }

    // MARK: - Badge Computation (Static for Testability)

    /// Compute which badges should be visible given current flags and runtime.
    ///
    /// Rules (from plan):
    /// - **Visible** if feature is enabled AND model supports it
    /// - **Dimmed + ⚠️** if enabled but model doesn't support it
    /// - **Hidden** if disabled
    static func visibleBadges(
        flags: RuntimeFlags,
        runtime: RuntimeType
    ) -> [BadgeItem] {
        var badges: [BadgeItem] = []

        // Thinking
        if flags.enableThinking {
            let desc = FlagRegistry.thinking
            let supported = desc.isSupported(on: runtime)
            badges.append(BadgeItem(
                flagId: "thinking",
                label: "Think",
                symbol: "brain.head.profile",
                color: AppColors.capabilityThinking,
                isSupported: supported
            ))
        }

        // MTP / Speculative Decoding
        if flags.enableSpeculativeDecoding == true {
            let desc = FlagRegistry.speculative
            let supported = desc.isSupported(on: runtime)
            badges.append(BadgeItem(
                flagId: "mtp",
                label: "MTP",
                symbol: "bolt.fill",
                color: AppColors.capabilityMTP,
                isSupported: supported
            ))
        }

        // Constrained Decoding
        if flags.enableConversationConstrainedDecoding {
            let desc = FlagRegistry.constrainedDecoding
            let supported = desc.isSupported(on: runtime)
            badges.append(BadgeItem(
                flagId: "cd",
                label: "CD",
                symbol: "doc.text.magnifyingglass",
                color: AppColors.capabilityCD,
                isSupported: supported
            ))
        }

        // Tool Calling
        if flags.enableToolCalling {
            let desc = FlagRegistry.toolCalling
            let supported = desc.isSupported(on: runtime)
            badges.append(BadgeItem(
                flagId: "tools",
                label: "Tools",
                symbol: "wrench.fill",
                color: AppColors.toolAction,
                isSupported: supported
            ))
        }

        return badges
    }
}

// MARK: - Badge Item

/// Data model for a single badge pill.
struct BadgeItem: Identifiable {
    let flagId: String
    let label: String
    let symbol: String
    let color: Color
    /// Whether the current engine supports this feature.
    /// When false, badge shows dimmed with ⚠️.
    let isSupported: Bool

    var id: String { flagId }
}

// MARK: - Badge Pill View

/// A single tappable badge pill.
private struct BadgePill: View {
    let badge: BadgeItem
    let onTap: () -> Void
    @State private var isPressed = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: AppSpacing.xxs) {
                if !badge.isSupported {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(AppIconSize.xxs)
                        .foregroundStyle(AppColors.warning)
                }
                Image(systemName: badge.symbol)
                    .font(AppIconSize.xs)
                Text(badge.label)
                    .font(AppTypography.badge)
            }
            .foregroundStyle(badge.isSupported ? badge.color : badge.color.opacity(0.4))
            .padding(.horizontal, AppSpacing.sm)
            .padding(.vertical, AppSpacing.xxs + 1)
            .background(
                Capsule()
                    .fill(badge.isSupported
                        ? badge.color.opacity(0.12)
                        : badge.color.opacity(0.05))
            )
            .overlay(
                Capsule()
                    .strokeBorder(
                        badge.isSupported
                            ? badge.color.opacity(0.3)
                            : badge.color.opacity(0.1),
                        lineWidth: 0.5
                    )
            )
            .scaleEffect(isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: isPressed)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("badge_\(badge.flagId)")
        .accessibilityLabel("\(badge.label) \(badge.isSupported ? "active" : "unsupported on this engine")")
        .accessibilityHint("Double-tap to toggle \(badge.label)")
        .accessibilityAddTraits(.isButton)
        .onLongPressGesture(minimumDuration: 0, pressing: { pressing in
            isPressed = pressing
        }, perform: {})
    }
}
