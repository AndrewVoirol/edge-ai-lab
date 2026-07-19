// Copyright 2026 Andrew Voirol. Apache-2.0
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0

import SwiftUI

// MARK: - Config Proof View

/// Expandable inline disclosure showing what engine config produced an assistant response.
///
/// **Design philosophy**: This is the "instruments panel" for each response.
/// The collapsed state is a subtle capsule badge that doesn't clutter the chat.
/// The expanded state is a structured, glanceable config table.
///
/// Follows the same disclosure pattern as `thinkingSection` in ChatBubbleView:
/// tinted background + chevron + animated expand/collapse.
///
/// **Trust guarantee**: Values come from `InferenceConfigSnapshot` captured at
/// inference *start* — not reconstructed after the fact.
struct ConfigProofView: View {
    let snapshot: InferenceConfigSnapshot
    let messageId: UUID

    @State private var isExpanded = false

    // MARK: - Color Identity

    /// Config proof uses a muted instrument-panel tone — distinct from
    /// thinking (sage), tools (orange), benchmark (tier-based).
    private let proofColor = AppColors.accentPrimary

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            collapsedBadge
            if isExpanded {
                expandedDetail
                    .transition(.contentReveal)
            }
        }
    }

    // MARK: - Collapsed Badge

    /// One-line tappable capsule showing the config summary.
    /// Visual weight deliberately lower than the benchmark badge —
    /// this is supporting context, not the hero metric.
    private var collapsedBadge: some View {
        Button {
            withAnimation(AppAnimation.standard) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: "gearshape.2.fill")
                    .font(AppIconSize.xxs)
                    .foregroundStyle(proofColor.opacity(AppOpacity.strong))

                // Feature pills — compact visual summary
                featurePills

                Spacer()

                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textTertiary)
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, AppSpacing.sm)
            .background(proofColor.opacity(AppOpacity.mist))
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm))
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.sm)
                    .stroke(proofColor.opacity(AppOpacity.faint), lineWidth: AppLineWidth.hairline)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("configProof_\(messageId)")
        .accessibilityLabel("Inference configuration")
        .accessibilityHint("Shows what settings produced this response")
        .accessibilityValue(isExpanded ? "expanded" : "collapsed")
    }

    /// Compact feature pills — only shows what's ON, keeping visual noise minimal.
    @ViewBuilder
    private var featurePills: some View {
        HStack(spacing: AppSpacing.xs) {
            if let engine = snapshot.runtimeType {
                configChip(engine, color: AppColors.textTertiary)
            }
            if snapshot.thinkingEnabled == true {
                configChip("Think", color: AppColors.capabilityThinking)
            }
            if snapshot.mtpEnabled == true {
                configChip("Spec. Dec", color: AppColors.capabilityMTP)
            }
            if snapshot.constrainedDecodingEnabled == true {
                configChip("Struct. Out", color: AppColors.capabilityCD)
            }
            if snapshot.toolCallingEnabled == true {
                configChip("Tools", color: AppColors.toolAction)
            }
        }
    }

    private func configChip(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold, design: .rounded)) // design-system-exempt: fixed for compact config chips
            .foregroundStyle(color)
            .padding(.horizontal, AppSpacing.xs)
            .padding(.vertical, AppSpacing.xxs)
            .background(color.opacity(AppOpacity.faint))
            .clipShape(Capsule())
    }

    // MARK: - Expanded Detail

    /// Structured config table — grouped by category for scannability.
    /// Uses the same background treatment as the thinking section expansion.
    private var expandedDetail: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            // Model & Engine
            if snapshot.modelName != nil || snapshot.runtimeType != nil || snapshot.computeBackend != nil {
                configSection("Engine") {
                    if let name = snapshot.modelName {
                        configRow("Model", value: name)
                    }
                    if let runtime = snapshot.runtimeType {
                        configRow("Runtime", value: runtime)
                    }
                    if let compute = snapshot.computeBackend {
                        configRow("Compute", value: compute)
                    }
                }
            }

            // Feature Flags
            configSection("Features") {
                configRow("Thinking", value: snapshot.thinkingEnabled == true ? "On" : "Off",
                         color: snapshot.thinkingEnabled == true ? AppColors.capabilityThinking : nil)
                configRow("Speculative Decoding", value: snapshot.mtpEnabled == true ? "On" : "Off",
                         color: snapshot.mtpEnabled == true ? AppColors.capabilityMTP : nil)
                configRow("Constrained Decoding", value: snapshot.constrainedDecodingEnabled == true ? "On" : "Off",
                         color: snapshot.constrainedDecodingEnabled == true ? AppColors.capabilityCD : nil)
                configRow("Tool Calling", value: snapshot.toolCallingEnabled == true ? "On" : "Off",
                         color: snapshot.toolCallingEnabled == true ? AppColors.toolAction : nil)
            }

            // Sampler
            if snapshot.temperature != nil || snapshot.topK != nil {
                configSection("Sampler") {
                    if let t = snapshot.temperature {
                        configRow("Temperature", value: String(format: "%.2f", t))
                    }
                    if let k = snapshot.topK {
                        configRow("Top-K", value: "\(k)")
                    }
                    if let p = snapshot.topP {
                        configRow("Top-P", value: String(format: "%.2f", p))
                    }
                    if let s = snapshot.seed {
                        configRow("Seed", value: s == 0 ? "Random" : "\(s)")
                    }
                }
            }
        }
        .padding(AppSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(proofColor.opacity(AppOpacity.whisper))
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm))
        .accessibilityIdentifier("configProofDetail_\(messageId)")
    }

    // MARK: - Helpers

    @ViewBuilder
    private func configSection(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .bold, design: .rounded)) // design-system-exempt: fixed for compact section headers
                .foregroundStyle(proofColor.opacity(AppOpacity.half))
                .tracking(0.8)

            content()
        }
    }

    @ViewBuilder
    private func configRow(_ label: String, value: String, color: Color? = nil) -> some View {
        HStack {
            Text(label)
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textTertiary)
            Spacer()
            Text(value)
                .font(AppTypography.metric)
                .foregroundStyle(color ?? AppColors.textSecondary)
        }
    }
}
