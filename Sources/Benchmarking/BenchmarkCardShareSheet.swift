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

// MARK: - Benchmark Card Share Sheet

/// A modal sheet presenting a live preview of the benchmark card
/// with actions to copy, save, or share it.
/// Supports multiple card sizes for different social media platforms.
struct BenchmarkCardShareSheet: View {
    let cardData: BenchmarkCardData
    var metricsEntry: MetricsStore.Entry?

    @Environment(\.dismiss) private var dismiss
    @State private var renderedImage: PlatformImage?
    @State private var isCopied = false
    @State private var isSaved = false
    @State private var saveError: String?
    @State private var selectedSize: CardSize = .twitterCard
    @State private var showShareActions = false

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
                .accessibilityIdentifier("shareSheetDoneButton")
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.vertical, AppSpacing.lg)

            Divider().overlay(AppColors.border)

            ScrollView {
                VStack(spacing: AppSpacing.xl) {
                    // Card size picker
                    Picker("Card Size", selection: $selectedSize) {
                        ForEach(CardSize.allCases, id: \.self) { size in
                            Text(size.label).tag(size)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, AppSpacing.xl)
                    .padding(.top, AppSpacing.lg)
                    .accessibilityIdentifier("shareSheetSizePicker")

                    // Card preview (scaled to fit)
                    BenchmarkCardView(data: cardData, cardSize: selectedSize)
                        .scaleEffect(cardScale)
                        .frame(
                            width: selectedSize.width * cardScale,
                            height: selectedSize.height * cardScale
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(color: .black.opacity(0.4), radius: 20, y: 8)
                        .padding(.top, AppSpacing.md)

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
                        .accessibilityIdentifier("shareSheetCopyButton")

                        // Save to Downloads
                        actionButton(
                            icon: isSaved ? "checkmark.circle.fill" : "arrow.down.circle",
                            label: isSaved ? "Saved!" : "Save PNG",
                            color: isSaved ? AppColors.success : AppColors.accentGold
                        ) {
                            saveToDisk()
                        }
                        .accessibilityIdentifier("shareSheetSaveButton")
                        #endif

                        // Share via system share sheet
                        if let pngData = BenchmarkCardExporter.renderPNG(data: cardData, size: selectedSize) {
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
                            .accessibilityIdentifier("shareSheetShareButton")
                        }

                        // Copy Markdown
                        actionButton(
                            icon: "doc.text",
                            label: "Markdown",
                            color: AppColors.accentGold
                        ) {
                            copyMarkdown()
                        }
                        .accessibilityIdentifier("shareSheetMarkdownButton")
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
            renderedImage = BenchmarkCardExporter.renderImage(data: cardData, size: selectedSize)
        }
        .onChange(of: selectedSize) {
            renderedImage = BenchmarkCardExporter.renderImage(data: cardData, size: selectedSize)
        }
    }

    // MARK: - Scale Factor

    /// Scale the card to fit the sheet width.
    private var cardScale: CGFloat {
        #if os(macOS)
        return min(600 / selectedSize.width, 400 / selectedSize.height)
        #else
        return min(350 / selectedSize.width, 350 / selectedSize.height)
        #endif
    }

    // MARK: - Actions

    #if os(macOS)
    private func copyToClipboard() {
        guard let image = BenchmarkCardExporter.renderImage(data: cardData, size: selectedSize) else { return }
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
        guard let pngData = BenchmarkCardExporter.renderPNG(data: cardData, size: selectedSize) else {
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

    private func copyMarkdown() {
        let markdown: String
        if let entry = metricsEntry {
            markdown = MarkdownExporter.generateGitHubTemplate(entry: entry)
        } else {
            markdown = BenchmarkCardLogic.generateShareCaption(from: cardData)
        }

        #if os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(markdown, forType: .string)
        #else
        UIPasteboard.general.string = markdown
        #endif

        withAnimation(AppAnimation.standard) {
            isCopied = true
        }
        Task {
            try? await Task.sleep(for: .seconds(2))
            await MainActor.run {
                withAnimation(AppAnimation.standard) {
                    isCopied = false
                }
            }
        }
    }

    /// Generate a descriptive filename for the benchmark card.
    private var benchmarkFilename: String {
        let modelClean = cardData.modelName
            .replacingOccurrences(of: " · ", with: "-")
            .replacingOccurrences(of: " ", with: "_")
        let speed = String(format: "%.0f", cardData.decodeSpeed)
        let sizeLabel = selectedSize.rawValue
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmm"
        let dateStr = formatter.string(from: cardData.timestamp)
        return "EdgeAILab_\(modelClean)_\(speed)toks_\(sizeLabel)_\(dateStr).png"
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
