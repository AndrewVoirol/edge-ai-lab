// Copyright 2026 Andrew Voirol. Apache-2.0
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0

import SwiftUI

// MARK: - Settings Impact Label

/// A compact inline label showing a flag's impact areas, reload requirement,
/// and engine compatibility.
///
/// Used below settings toggles to give the user immediate context about what
/// a flag affects and whether it needs a restart.
///
/// Data sourced from `FlagRegistry` (empirically verified in Phase 1/1.5).
struct SettingsImpactLabel: View {
    let descriptor: FlagDescriptor
    let currentRuntime: RuntimeType

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            // Impact pills
            ForEach(descriptor.impactAreas, id: \.rawValue) { area in
                ImpactPill(area: area)
            }

            // Engine support indicator
            if !descriptor.supportedEngines.isEmpty {
                engineSupportLabel
            }

            Spacer()

            // Reload indicator
            if descriptor.reloadRequirement.requiresReload(for: currentRuntime) {
                HStack(spacing: AppSpacing.xxs) {
                    Image(systemName: "arrow.clockwise")
                        .font(AppIconSize.xxs)
                    Text("Reload")
                        .font(AppTypography.badge)
                }
                .foregroundStyle(AppColors.warning.opacity(0.8))
                .accessibilityLabel("Requires engine reload")
            }
        }
        .accessibilityIdentifier("impact_label_\(descriptor.id)")
    }

    @ViewBuilder
    private var engineSupportLabel: some View {
        let supported = descriptor.isSupported(on: currentRuntime)
        HStack(spacing: AppSpacing.xxs) {
            if !supported {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(AppIconSize.xxs)
                    .foregroundStyle(.orange)
            }
            Text(engineNames)
                .font(AppTypography.badge)
                .foregroundStyle(supported ? AppColors.textTertiary : .orange.opacity(0.8))
        }
        .accessibilityLabel(supported
            ? "Supported on \(engineNames)"
            : "Not supported on \(currentRuntime.displayName)")
    }

    private var engineNames: String {
        descriptor.supportedEngines
            .map(\.displayName)
            .sorted()
            .joined(separator: " · ")
    }
}

// MARK: - Impact Pill

/// A tiny colored pill showing an impact area (Speed, Quality, Memory, Compatibility).
private struct ImpactPill: View {
    let area: ImpactArea

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: area.symbolName)
                .font(AppIconSize.xxs)
            Text(area.rawValue)
                .font(AppTypography.badge)
        }
        .foregroundStyle(pillColor)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(
            Capsule()
                .fill(pillColor.opacity(0.1))
        )
        .accessibilityLabel("\(area.rawValue) impact")
    }

    private var pillColor: Color {
        switch area {
        case .speed: return AppColors.capabilityMTP
        case .quality: return AppColors.capabilityThinking
        case .memory: return AppColors.warning
        case .compatibility: return AppColors.capabilityCD
        }
    }
}
