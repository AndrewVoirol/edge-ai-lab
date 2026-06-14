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

// MARK: - Eval Benchmark Card
//
// MARK: Design System Exemption Policy
// This file renders image-export eval benchmark cards via ImageRenderer.
// Labels, badges, and section headers use AppTypography tokens.
// Hero display numbers (48pt pass rate, 32pt suite name) use fixed point
// sizes for pixel-perfect image export. These are marked with:
//   // design-system-exempt: image export requires fixed point sizes

/// Shareable eval result card, modeled after the existing `BenchmarkCardView`.
///
/// Renders a fixed-size card showing eval suite results for sharing
/// via screenshot, clipboard, or system share sheet.
///
/// Card Layout (1200×630, same as `BenchmarkCardView`):
/// - Top: Suite name + category badge
/// - Center: Pass rate ring + model name(s)
/// - Bottom: Speed metrics + device info + Edge AI Lab branding
struct EvalBenchmarkCard: View {

    // MARK: - Card Data

    let data: EvalBenchmarkCardData

    // MARK: - Constants

    static let cardWidth: CGFloat = 1200
    static let cardHeight: CGFloat = 630

    // MARK: - Body

    var body: some View {
        ZStack {
            // Background — same layered dark forest as BenchmarkCardView
            RoundedRectangle(cornerRadius: 24)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.04, green: 0.06, blue: 0.05),
                            Color(red: 0.08, green: 0.11, blue: 0.09),
                            Color(red: 0.05, green: 0.08, blue: 0.06),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            // Subtle gradient overlay
            RoundedRectangle(cornerRadius: 24)
                .fill(
                    RadialGradient(
                        colors: [
                            passRateColor(data.overallPassRate).opacity(0.08),
                            Color.clear,
                        ],
                        center: .center,
                        startRadius: 50,
                        endRadius: 400
                    )
                )

            // Card content
            VStack(spacing: 0) {
                topSection
                Spacer()
                centerSection
                Spacer()
                bottomSection
            }
            .padding(40)
        }
        .frame(width: Self.cardWidth, height: Self.cardHeight)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .accessibilityIdentifier("evalBenchmarkCard_root")
    }

    // MARK: - Top Section

    private var topSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 8) {
                // Suite name
                Text(data.suiteName)
                    .font(.system(size: 32, weight: .bold)) // design-system-exempt: image export requires fixed point sizes
                    .foregroundStyle(AppColors.textPrimary)

                // Category badge
                HStack(spacing: 8) {
                    Image(systemName: data.category.symbolName)
                        .font(.system(size: 14))
                    Text(data.category.displayName)
                        .font(AppTypography.badge)
                }
                .foregroundStyle(AppColors.accentCyan)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(AppColors.accentCyan.opacity(0.12))
                .clipShape(Capsule())
            }

            Spacer()

            // Date
            Text(
                data.date,
                format: .dateTime.month(.abbreviated).day().year()
            )
            .font(AppTypography.subtitle)
            .foregroundStyle(AppColors.textTertiary)
        }
    }

    // MARK: - Center Section

    private var centerSection: some View {
        HStack(spacing: 48) {
            // Pass rate ring
            passRateRing

            // Model results summary
            VStack(alignment: .leading, spacing: 16) {
                ForEach(data.modelSummaries) { summary in
                    modelSummaryRow(summary)
                }
            }
        }
    }

    private var passRateRing: some View {
        let color = passRateColor(data.overallPassRate)
        let percent = Int(data.overallPassRate * 100)

        return ZStack {
            Circle()
                .stroke(color.opacity(0.15), lineWidth: 10)
                .frame(width: 160, height: 160)

            Circle()
                .trim(from: 0, to: data.overallPassRate)
                .stroke(color, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 160, height: 160)

            VStack(spacing: 4) {
                Text("\(percent)")
                    .font(.system(size: 48, weight: .bold, design: .monospaced)) // design-system-exempt: image export requires fixed point sizes
                    .foregroundStyle(color)
                Text("PASS %")
                    .font(AppTypography.badge)
                    .foregroundStyle(AppColors.textTertiary)
            }
        }
        .accessibilityIdentifier("evalBenchmarkCard_passRateRing")
    }

    private func modelSummaryRow(_ summary: EvalBenchmarkCardData.ModelSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(summary.modelName)
                .font(AppTypography.cardTitle)
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(1)

            HStack(spacing: 20) {
                metricPill(
                    label: "Pass",
                    value: String(format: "%.0f%%", summary.passRate * 100),
                    color: passRateColor(summary.passRate)
                )
                metricPill(
                    label: "Speed",
                    value: String(format: "%.1f tok/s", summary.avgDecodeSpeed),
                    color: AppColors.accentCyan
                )
                metricPill(
                    label: "TTFT",
                    value: String(format: "%.2fs", summary.avgTTFT),
                    color: AppColors.accentGold
                )
            }
        }
    }

    private func metricPill(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(AppTypography.metricLarge)
                .foregroundStyle(color)
            Text(label)
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textTertiary)
        }
    }

    // MARK: - Bottom Section

    private var bottomSection: some View {
        HStack {
            // Device info
            HStack(spacing: 12) {
                Image(systemName: "desktopcomputer")
                    .font(.system(size: 14))
                    .foregroundStyle(AppColors.textTertiary)
                Text(data.deviceName)
                    .font(AppTypography.subtitle)
                    .foregroundStyle(AppColors.textTertiary)
                Text("·")
                    .foregroundStyle(AppColors.textTertiary)
                Text(data.platform)
                    .font(AppTypography.subtitle)
                    .foregroundStyle(AppColors.textTertiary)
            }

            Spacer()

            // Branding
            HStack(spacing: 8) {
                Image(systemName: "flask.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(AppColors.accentTeal)
                Text("Edge AI Lab")
                    .font(AppTypography.sectionHeader)
                    .foregroundStyle(AppColors.accentTeal)
            }
        }
    }

    // MARK: - Helpers

    private func passRateColor(_ rate: Double) -> Color {
        if rate > 0.8 { return AppColors.success }
        if rate > 0.5 { return AppColors.accentGold }
        return AppColors.danger
    }
}

// MARK: - Card Data Model

/// Data model for the eval benchmark card, similar to `BenchmarkCardData`.
struct EvalBenchmarkCardData {
    let suiteName: String
    let category: EvalCategory
    let overallPassRate: Double
    let modelSummaries: [ModelSummary]
    let deviceName: String
    let platform: String
    let date: Date

    struct ModelSummary: Identifiable {
        let id = UUID()
        let modelName: String
        let passRate: Double
        let avgDecodeSpeed: Double
        let avgTTFT: Double
    }

    /// Create card data from a completed eval run.
    static func from(_ run: EvalRun) -> EvalBenchmarkCardData {
        let summaries = run.modelResults.map { result in
            ModelSummary(
                modelName: result.modelName,
                passRate: result.passRate,
                avgDecodeSpeed: result.avgDecodeSpeed,
                avgTTFT: result.avgTTFT
            )
        }

        return EvalBenchmarkCardData(
            suiteName: run.suiteName,
            category: run.suiteCategory,
            overallPassRate: run.overallPassRate,
            modelSummaries: summaries,
            deviceName: run.deviceName,
            platform: run.platform,
            date: run.startedAt
        )
    }
}

// MARK: - Share Sheet

/// Modal sheet presenting the eval benchmark card with share/export actions.
struct EvalBenchmarkCardShareSheet: View {
    let evalRun: EvalRun

    @Environment(\.dismiss) private var dismiss
    @State private var isCopied = false
    @State private var isSaved = false

    private var cardData: EvalBenchmarkCardData {
        EvalBenchmarkCardData.from(evalRun)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                Text("Share Eval Results")
                    .font(AppTypography.cardTitle)
                    .foregroundStyle(AppColors.textPrimary)

                Spacer()

                Button("Done") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppColors.accentTeal)
                    .accessibilityIdentifier("evalBenchmarkCard_doneButton")
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.vertical, AppSpacing.lg)

            Divider().overlay(AppColors.border)

            ScrollView {
                VStack(spacing: AppSpacing.xl) {
                    // Card preview (scaled)
                    EvalBenchmarkCard(data: cardData)
                        .scaleEffect(0.5)
                        .frame(
                            width: EvalBenchmarkCard.cardWidth * 0.5,
                            height: EvalBenchmarkCard.cardHeight * 0.5
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(color: .black.opacity(0.4), radius: 20, y: 8)
                        .padding(.top, AppSpacing.xl)

                    // Action buttons
                    HStack(spacing: AppSpacing.lg) {
                        #if os(macOS)
                        actionButton(
                            icon: isCopied ? "checkmark.circle.fill" : "doc.on.doc",
                            label: isCopied ? "Copied!" : "Copy Image",
                            color: isCopied ? AppColors.success : AppColors.accentCyan
                        ) {
                            copyToClipboard()
                        }

                        actionButton(
                            icon: isSaved ? "checkmark.circle.fill" : "arrow.down.circle",
                            label: isSaved ? "Saved!" : "Save PNG",
                            color: isSaved ? AppColors.success : AppColors.accentGold
                        ) {
                            saveToDisk()
                        }
                        #endif
                    }
                    .padding(.horizontal, AppSpacing.xl)

                    // Attribution
                    HStack(spacing: AppSpacing.sm) {
                        Image(systemName: "info.circle")
                            .foregroundStyle(AppColors.textTertiary)
                        Text("Card includes device info, model names, and eval pass rates.")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textTertiary)
                    }
                    .padding(.horizontal, AppSpacing.xl)
                    .padding(.bottom, AppSpacing.xl)
                }
            }
        }
        .background(AppColors.backgroundPrimary)
        .frame(minWidth: 700, idealWidth: 750, minHeight: 500, idealHeight: 600)
        .accessibilityIdentifier("evalBenchmarkCard_shareSheet")
    }

    // MARK: - Action Button

    private func actionButton(
        icon: String,
        label: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: AppSpacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundStyle(color)
                Text(label)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }
            .frame(width: 90, height: 70)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.md)
                    .fill(color.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppRadius.md)
                            .stroke(color.opacity(0.15), lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    #if os(macOS)
    private func copyToClipboard() {
        // Render the card to an image using ImageRenderer
        let renderer = ImageRenderer(content: EvalBenchmarkCard(data: cardData))
        renderer.scale = 2.0
        guard let nsImage = renderer.nsImage else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([nsImage])
        withAnimation(AppAnimation.standard) { isCopied = true }
        Task {
            try? await Task.sleep(for: .seconds(2))
            await MainActor.run {
                withAnimation(AppAnimation.standard) { isCopied = false }
            }
        }
    }

    private func saveToDisk() {
        let renderer = ImageRenderer(content: EvalBenchmarkCard(data: cardData))
        renderer.scale = 2.0
        guard let nsImage = renderer.nsImage,
              let tiffData = nsImage.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapRep.representation(using: .png, properties: [:]) else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "EvalCard_\(cardData.suiteName.replacingOccurrences(of: " ", with: "_")).png"
        panel.canCreateDirectories = true
        panel.begin { response in
            if response == .OK, let url = panel.url {
                try? pngData.write(to: url)
                Task { @MainActor in
                    withAnimation(AppAnimation.standard) { isSaved = true }
                    try? await Task.sleep(for: .seconds(2))
                    withAnimation(AppAnimation.standard) { isSaved = false }
                }
            }
        }
    }
    #endif
}

// MARK: - Preview

#if DEBUG
#Preview("Eval Benchmark Card") {
    EvalBenchmarkCard(data: EvalBenchmarkCardData(
        suiteName: "Math Accuracy",
        category: .math,
        overallPassRate: 0.87,
        modelSummaries: [
            .init(modelName: "Gemma 4 E2B", passRate: 0.9, avgDecodeSpeed: 42.5, avgTTFT: 0.87),
            .init(modelName: "Gemma 4 E4B", passRate: 0.84, avgDecodeSpeed: 28.1, avgTTFT: 1.23),
        ],
        deviceName: "MacBook Pro (M4 Max)",
        platform: "macOS",
        date: Date()
    ))
    .preferredColorScheme(.dark)
    .frame(width: 700, height: 400)
}
#endif
