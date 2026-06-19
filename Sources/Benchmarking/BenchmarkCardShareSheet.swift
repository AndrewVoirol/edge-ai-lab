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

// MARK: - Benchmark Card Share Sheet

/// A modal sheet presenting a live preview of the benchmark card
/// with actions to copy, save, or share it.
struct BenchmarkCardShareSheet: View {
    let cardData: BenchmarkCardData

    @Environment(\.dismiss) private var dismiss
    @State private var renderedImage: PlatformImage?
    @State private var isCopied = false
    @State private var isSaved = false
    @State private var saveError: String?

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                Text("Share Benchmark")
                    .font(AppTypography.cardTitle)
                    .foregroundStyle(AppColors.textPrimary)

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppColors.accentTeal)
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.vertical, AppSpacing.lg)

            Divider().overlay(AppColors.border)

            ScrollView {
                VStack(spacing: AppSpacing.xl) {
                    // Card preview (scaled to fit)
                    BenchmarkCardView(data: cardData)
                        .scaleEffect(cardScale)
                        .frame(
                            width: BenchmarkCardView.cardWidth * cardScale,
                            height: BenchmarkCardView.cardHeight * cardScale
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(color: .black.opacity(0.4), radius: 20, y: 8)
                        .padding(.top, AppSpacing.xl)

                    // Action buttons
                    HStack(spacing: AppSpacing.lg) {
                        #if os(macOS)
                        // Copy to clipboard
                        actionButton(
                            icon: isCopied ? "checkmark.circle.fill" : "doc.on.doc",
                            label: isCopied ? "Copied!" : "Copy Image",
                            color: isCopied ? AppColors.success : AppColors.accentCyan
                        ) {
                            copyToClipboard()
                        }

                        // Save to Downloads
                        actionButton(
                            icon: isSaved ? "checkmark.circle.fill" : "arrow.down.circle",
                            label: isSaved ? "Saved!" : "Save PNG",
                            color: isSaved ? AppColors.success : AppColors.accentGold
                        ) {
                            saveToDisk()
                        }
                        #endif

                        // Share via system share sheet
                        if let pngData = BenchmarkCardRenderer.renderPNG(data: cardData) {
                            ShareLink(
                                item: BenchmarkCardTransferable(imageData: pngData),
                                preview: SharePreview(
                                    "Edge AI Lab Benchmark — \(String(format: "%.1f", cardData.decodeSpeed)) tok/s",
                                    image: Image(systemName: "bolt.fill")
                                )
                            ) {
                                actionButtonLabel(
                                    icon: "square.and.arrow.up",
                                    label: "Share",
                                    color: AppColors.accentTeal
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, AppSpacing.xl)

                    // Error message
                    if let error = saveError {
                        Text(error)
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.danger)
                            .padding(.horizontal, AppSpacing.xl)
                    }

                    // Attribution hint
                    HStack(spacing: AppSpacing.sm) {
                        Image(systemName: "info.circle")
                            .foregroundStyle(AppColors.textTertiary)
                        Text("Card includes your device info, model name, and a link to the Edge AI Lab repo.")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textTertiary)
                    }
                    .padding(.horizontal, AppSpacing.xl)
                    .padding(.bottom, AppSpacing.xl)
                }
            }
        }
        .background(AppColors.backgroundPrimary)
        .frame(minWidth: 600, idealWidth: 700, minHeight: 500, idealHeight: 600)
        .onAppear {
            renderedImage = BenchmarkCardRenderer.renderImage(data: cardData)
        }
    }

    // MARK: - Scale Factor

    /// Scale the 1200×630 card to fit the sheet width.
    private var cardScale: CGFloat {
        #if os(macOS)
        return 0.5
        #else
        return 0.28
        #endif
    }

    // MARK: - Actions

    #if os(macOS)
    private func copyToClipboard() {
        guard let image = renderedImage else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
        withAnimation(AppAnimation.standard) {
            isCopied = true
        }
        // Reset after 2 seconds
        Task {
            try? await Task.sleep(for: .seconds(2))
            await MainActor.run {
                withAnimation(AppAnimation.standard) {
                    isCopied = false
                }
            }
        }
    }

    private func saveToDisk() {
        guard let pngData = BenchmarkCardRenderer.renderPNG(data: cardData) else {
            saveError = "Failed to render image"
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = benchmarkFilename
        panel.canCreateDirectories = true

        panel.begin { response in
            if response == .OK, let url = panel.url {
                do {
                    try pngData.write(to: url)
                    Task { @MainActor in
                        withAnimation(AppAnimation.standard) {
                            isSaved = true
                        }
                        try? await Task.sleep(for: .seconds(2))
                        withAnimation(AppAnimation.standard) {
                            isSaved = false
                        }
                    }
                } catch {
                    Task { @MainActor in
                        saveError = "Save failed: \(error.localizedDescription)"
                    }
                }
            }
        }
    }
    #endif

    /// Generate a descriptive filename for the benchmark card.
    private var benchmarkFilename: String {
        let modelClean = cardData.modelName
            .replacingOccurrences(of: " · ", with: "-")
            .replacingOccurrences(of: " ", with: "_")
        let speed = String(format: "%.0f", cardData.decodeSpeed)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmm"
        let dateStr = formatter.string(from: cardData.timestamp)
        return "EdgeAILab_\(modelClean)_\(speed)toks_\(dateStr).png"
    }

    // MARK: - Button Helpers

    private func actionButton(
        icon: String,
        label: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            actionButtonLabel(icon: icon, label: label, color: color)
        }
        .buttonStyle(.plain)
    }

    private func actionButtonLabel(icon: String, label: String, color: Color) -> some View {
        VStack(spacing: AppSpacing.sm) {
            Image(systemName: icon)
                .font(AppIconSize.xl)
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
}
