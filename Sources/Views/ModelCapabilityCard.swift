// Copyright 2026 Andrew Voirol. Apache-2.0
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0

import SwiftUI

// MARK: - Model Capability Card

/// A contextual card shown in the conversation empty state after a model loads.
///
/// **Why this exists**: Before this card, loading a model gave you badges in the
/// status bar and nothing else. The user had no moment of "here's what this model
/// can do and what it can't." Missing buttons (no image attach for text-only models)
/// are invisible UX — you can't notice the absence of something you never saw.
///
/// **Design**: Follows the glass card pattern from the empty state quick-action hints.
/// Uses the same `glassCard` modifier and `messageEntrance` animation.
///
/// **Data source**: `ModelMetadata` + `RuntimeFlags` + `BackendResult` — all available
/// when `isEngineReady` transitions to `true`.
struct ModelCapabilityCard: View {
    let metadata: ModelMetadata
    let backendResult: BackendResult?
    let runtimeFlags: RuntimeFlags
    let runtimeType: RuntimeType

    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            // Header: Model identity
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: "cpu.fill")
                    .font(AppIconSize.md)
                    .foregroundStyle(AppColors.accentPrimary)
                    .symbolEffect(.pulse, isActive: !appeared)

                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    Text(metadata.name)
                        .font(AppTypography.cardTitle)
                        .foregroundStyle(AppColors.textPrimary)

                    HStack(spacing: AppSpacing.xs) {
                        if let backend = backendResult {
                            HStack(spacing: AppSpacing.xxs) {
                                Circle()
                                    .fill(backend.activeBackend == .gpu ? AppColors.success : AppColors.warning)
                                    .frame(width: AppSize.dotMd, height: AppSize.dotMd)
                                Text(backend.activeBackend == .gpu ? "GPU (Metal)" : "CPU")
                                    .font(AppTypography.metric)
                                    .foregroundStyle(AppColors.textSecondary)
                            }
                        }
                        Text("·")
                            .foregroundStyle(AppColors.textTertiary)
                        Text(runtimeType.displayName)
                            .font(AppTypography.metric)
                            .foregroundStyle(AppColors.textTertiary)
                    }
                }

                Spacer()
            }

            // Capability grid
            capabilityGrid

            // Negative capabilities — what this model CAN'T do
            if !negativeCapabilities.isEmpty {
                HStack(spacing: AppSpacing.xs) {
                    Image(systemName: "info.circle")
                        .font(AppIconSize.xxs)
                        .foregroundStyle(AppColors.textTertiary)
                    Text(negativeCapabilities.joined(separator: " · "))
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textTertiary)
                }
            }
        }
        .padding(AppSpacing.lg)
        .glassCard()
        .messageEntrance()
        .onAppear {
            withAnimation(AppAnimation.gentleSpring.delay(0.3)) {
                appeared = true
            }
        }
        .accessibilityIdentifier("modelCapabilityCard")
        .accessibilityLabel("Model capabilities for \(metadata.name)")
    }

    // MARK: - Capability Grid

    @ViewBuilder
    private var capabilityGrid: some View {
        // 2×3 grid of capability badges
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: AppSpacing.sm),
                GridItem(.flexible(), spacing: AppSpacing.sm),
                GridItem(.flexible(), spacing: AppSpacing.sm)
            ],
            spacing: AppSpacing.sm
        ) {
            capabilityBadge("Vision", icon: "eye.fill", supported: metadata.supportsImage, color: AppColors.capabilityVision)
            capabilityBadge("Audio", icon: "waveform", supported: metadata.supportsAudio, color: AppColors.capabilityAudio)
            capabilityBadge("MTP", icon: "hare.fill", supported: metadata.supportsMTP && runtimeType != .mlx, color: AppColors.capabilityMTP)
            capabilityBadge("Thinking", icon: "brain.head.profile", supported: true, color: AppColors.capabilityThinking)
            capabilityBadge("Tools", icon: "wrench.fill", supported: metadata.supportsToolCalling, color: AppColors.toolAction)
            contextWindowBadge
        }
    }

    @ViewBuilder
    private func capabilityBadge(_ label: String, icon: String, supported: Bool, color: Color) -> some View {
        HStack(spacing: AppSpacing.xs) {
            Image(systemName: icon)
                .font(AppIconSize.xxs)
                .foregroundStyle(supported ? color : AppColors.textQuaternary)
            Text(label)
                .font(AppTypography.badge)
                .foregroundStyle(supported ? AppColors.textSecondary : AppColors.textQuaternary)
            Spacer()
            Image(systemName: supported ? "checkmark.circle.fill" : "minus.circle")
                .font(AppIconSize.xxs)
                .foregroundStyle(supported ? color.opacity(0.6) : AppColors.textQuaternary)
        }
        .padding(.horizontal, AppSpacing.sm)
        .padding(.vertical, AppSpacing.xs)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.sm)
                .fill(supported ? color.opacity(0.06) : Color.clear)
        )
        .accessibilityLabel("\(label): \(supported ? "supported" : "not supported")")
    }

    @ViewBuilder
    private var contextWindowBadge: some View {
        HStack(spacing: AppSpacing.xs) {
            Image(systemName: "text.line.first.and.arrowtriangle.forward")
                .font(AppIconSize.xxs)
                .foregroundStyle(AppColors.accentSecondary)
            Text(Self.formatContextWindow(metadata.contextWindowSize))
                .font(AppTypography.badge)
                .foregroundStyle(AppColors.textSecondary)
            Spacer()
        }
        .padding(.horizontal, AppSpacing.sm)
        .padding(.vertical, AppSpacing.xs)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.sm)
                .fill(AppColors.accentSecondary.opacity(0.06))
        )
        .accessibilityLabel("Context window: \(metadata.contextWindowSize ?? 0) tokens")
    }

    // MARK: - Negative Capabilities

    /// What this model explicitly CANNOT do — surfaced as plain text so the user
    /// doesn't have to infer from missing badges.
    private var negativeCapabilities: [String] {
        var items: [String] = []
        if !metadata.supportsImage { items.append("No image input") }
        if !metadata.supportsAudio { items.append("No audio input") }
        if !metadata.supportsMTP || runtimeType == .mlx {
            items.append(runtimeType == .mlx ? "MTP unavailable on MLX" : "No MTP")
        }
        return items
    }

    // MARK: - Formatting

    static func formatContextWindow(_ size: Int?) -> String {
        guard let size = size, size > 0 else { return "—" }
        if size >= 1000 {
            return "\(size / 1000)K ctx"
        }
        return "\(size) ctx"
    }
}
