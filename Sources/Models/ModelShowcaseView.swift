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

// MARK: - Model Showcase View

/// Rich model detail card showing architecture, context window, capabilities,
/// memory requirements, and device-fitness indicator.
///
/// Accessed by tapping a model card in the model management section.
struct ModelShowcaseView: View {
    let metadata: ModelMetadata
    var fileURL: URL? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.xl) {
                // Hero section
                heroSection

                // Capabilities grid
                capabilitiesGrid

                // Technical specs
                technicalSpecs

                // Device fitness
                deviceFitness
            }
            .padding(AppSpacing.lg)
        }
        .background(
            AppGradients.showcaseBackground
            .ignoresSafeArea()
            .overlay(.ultraThinMaterial)
        )
        .navigationTitle(metadata.name)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
                    .accessibilityIdentifier("button_closeShowcase")
            }
        }
        .accessibilityIdentifier("view_modelShowcase")
    }

    // MARK: - Hero Section

    private var heroSection: some View {
        VStack(spacing: AppSpacing.md) {
            // Architecture badge
            Text(metadata.architectureType)
                .font(AppTypography.badge)
                .foregroundStyle(AppColors.accentPrimary)
                .padding(.horizontal, AppSpacing.md)
                .padding(.vertical, AppSpacing.xs)
                .background(AppColors.accentPrimaryFaint)
                .clipShape(Capsule())

            // Model name
            Text(metadata.name)
                .font(AppTypography.pageTitle)
                .foregroundStyle(AppColors.textPrimary)
                .multilineTextAlignment(.center)

            // Description
            Text(metadata.description)
                .font(AppTypography.subtitle)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(4)

            // Recommended for
            HStack(spacing: AppSpacing.xs) {
                Image(systemName: "star.fill")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.accentSecondary)
                Text(metadata.recommendedFor)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.accentSecondary)
            }
        }
        .padding(AppSpacing.xl)
        .frame(maxWidth: .infinity)
        .glassCard()
    }

    // MARK: - Capabilities Grid

    private var capabilitiesGrid: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("Capabilities")
                .font(AppTypography.sectionHeader)
                .foregroundStyle(AppColors.textSecondary)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: AppSpacing.md) {
                capabilityCard(icon: "text.bubble.fill", label: "Text", enabled: true, color: AppColors.accentPrimary)
                capabilityCard(icon: "eye.fill", label: "Vision", enabled: metadata.supportsImage, color: AppColors.accentSecondary)
                capabilityCard(icon: "waveform", label: "Audio", enabled: metadata.supportsAudio, color: AppColors.accentPrimary)
                capabilityCard(icon: "brain.head.profile", label: "Thinking", enabled: metadata.capabilities.contains("llm_thinking"), color: AppColors.reasoning)
                capabilityCard(icon: "hare.fill", label: "MTP", enabled: metadata.supportsMTP, color: AppColors.success)
                capabilityCard(icon: "wrench.and.screwdriver", label: "Tools", enabled: true, color: AppColors.toolAction)
            }
        }
    }

    private func capabilityCard(icon: String, label: String, enabled: Bool, color: Color) -> some View {
        VStack(spacing: AppSpacing.sm) {
            Image(systemName: icon)
                .font(AppIconSize.lg)
                .foregroundStyle(enabled ? color : AppColors.textTertiary)
            Text(label)
                .font(AppTypography.badge)
                .foregroundStyle(enabled ? AppColors.textPrimary : AppColors.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(AppSpacing.md)
        .glassCard(cornerRadius: AppRadius.md)
        .opacity(enabled ? 1.0 : 0.4)
        .accessibilityLabel("\(label): \(enabled ? "enabled" : "disabled")")
    }

    // MARK: - Technical Specs

    private var technicalSpecs: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("Technical Specifications")
                .font(AppTypography.sectionHeader)
                .foregroundStyle(AppColors.textSecondary)

            VStack(spacing: 0) { // design-system-exempt: zero spacing for tight packing
                if let url = fileURL {
                    specRow(label: "Location", value: url.path)
                }
                specRow(label: "Size", value: ByteCountFormatter.string(fromByteCount: metadata.sizeInBytes, countStyle: .file))
                specRow(label: "Context Window", value: formatTokenCount(metadata.contextWindowSize))
                specRow(label: "Max Output Tokens", value: formatTokenCount(metadata.defaultConfig.maxTokens))
                specRow(label: "Architecture", value: metadata.architectureType)
                specRow(label: "Accelerators", value: metadata.defaultConfig.accelerators.uppercased())
                specRow(label: "Default Top-K", value: "\(metadata.defaultConfig.topK)")
                specRow(label: "Default Top-P", value: String(format: "%.2f", metadata.defaultConfig.topP))
                specRow(label: "Default Temperature", value: String(format: "%.1f", metadata.defaultConfig.temperature))
            }
            .glassCard(cornerRadius: AppRadius.md)
        }
    }

    private func specRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textTertiary)
            Spacer()
            Text(value)
                .font(AppTypography.metric)
                .foregroundStyle(AppColors.textPrimary)
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, AppSpacing.sm)
    }

    // MARK: - Device Fitness

    private var deviceFitness: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("Device Compatibility")
                .font(AppTypography.sectionHeader)
                .foregroundStyle(AppColors.textSecondary)

            VStack(spacing: AppSpacing.sm) {
                let availableMB = DeviceMetrics.availableMemoryMB
                let requiredMB = Double(metadata.minDeviceMemoryGB) * 1024.0
                let fits = availableMB >= requiredMB * 0.5 // Some wiggle room — OS manages memory

                HStack(spacing: AppSpacing.md) {
                    Image(systemName: fits ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(AppIconSize.lg)
                        .foregroundStyle(fits ? AppColors.success : AppColors.warning)
                    VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                        Text(fits ? "This model should fit your device" : "This model may not fit — limited memory")
                            .font(AppTypography.subtitle)
                            .foregroundStyle(AppColors.textPrimary)
                        Text("Requires \(metadata.minDeviceMemoryGB) GB · Available: \(String(format: "%.0f", availableMB)) MB")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textTertiary)
                    }
                    Spacer()
                }
                .padding(AppSpacing.md)

                // Platform support
                HStack(spacing: AppSpacing.lg) {
                    platformBadge(label: "macOS", capability: metadata.platformSupport.macOS)
                    platformBadge(label: "iPhone", capability: metadata.platformSupport.iOSDevice)
                    platformBadge(label: "Simulator", capability: metadata.platformSupport.iOSSimulator)
                }
                .padding(.horizontal, AppSpacing.md)
                .padding(.bottom, AppSpacing.md)
            }
            .glassCard(cornerRadius: AppRadius.md)
        }
    }

    private func platformBadge(label: String, capability: BackendCapability) -> some View {
        VStack(spacing: AppSpacing.xs) {
            Circle()
                .fill(capabilityColor(capability))
                .frame(width: 10, height: 10)
            Text(label)
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textTertiary)
            Text(capabilityLabel(capability))
                .font(AppTypography.badge)
                .foregroundStyle(capabilityColor(capability))
        }
    }

    private func capabilityColor(_ capability: BackendCapability) -> Color {
        switch capability {
        case .gpuAndCpu: return AppColors.success
        case .gpuOnly:   return AppColors.accentPrimary
        case .cpuOnly:   return AppColors.warning
        case .unknown:   return AppColors.textTertiary
        }
    }

    private func capabilityLabel(_ capability: BackendCapability) -> String {
        switch capability {
        case .gpuAndCpu: return "GPU+CPU"
        case .gpuOnly:   return "GPU only"
        case .cpuOnly:   return "CPU only"
        case .unknown:   return "Unknown"
        }
    }

    private func formatTokenCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return "\(count / 1_000_000)M"
        } else if count >= 1_000 {
            return "\(count / 1_000)K"
        }
        return "\(count)"
    }
}
