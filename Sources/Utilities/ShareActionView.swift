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

// MARK: - Share Action View

/// A compact share action panel with options to share image, copy markdown, or copy link.
/// Designed to be presented as a popover or sheet from the benchmark card area.
struct ShareActionView: View {
    let cardData: BenchmarkCardData
    let metricsEntry: MetricsStore.Entry?

    @State private var copiedItem: CopiedItem?

    private enum CopiedItem: String {
        case markdown
        case link
        case caption
    }

    var body: some View {
        VStack(spacing: AppSpacing.md) {
            // Title
            HStack {
                Image(systemName: "square.and.arrow.up")
                    .font(AppIconSize.md)
                    .foregroundStyle(AppColors.moss)
                Text("Share Benchmark")
                    .font(AppTypography.cardTitle)
                    .foregroundStyle(AppColors.textPrimary)
                Spacer()
            }
            .accessibilityIdentifier("shareActionTitle")

            Divider().overlay(AppColors.border)

            // Share Image button
            shareImageButton

            // Copy Markdown
            actionRow(
                icon: "doc.text",
                label: "Copy Markdown Table",
                sublabel: "GitHub-ready benchmark table",
                copiedKey: .markdown
            ) {
                copyMarkdown()
            }
            .accessibilityIdentifier("shareActionCopyMarkdown")

            // Copy Link
            actionRow(
                icon: "link",
                label: "Copy Link",
                sublabel: "github.com/AndrewVoirol/edge-ai-lab",
                copiedKey: .link
            ) {
                copyLink()
            }
            .accessibilityIdentifier("shareActionCopyLink")

            // Copy Caption
            actionRow(
                icon: "text.bubble",
                label: "Copy Caption",
                sublabel: "Social media-ready text",
                copiedKey: .caption
            ) {
                copyCaption()
            }
            .accessibilityIdentifier("shareActionCopyCaption")
        }
        .padding(AppSpacing.lg)
        .frame(width: 300)
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))
    }

    // MARK: - Share Image

    private var shareImageButton: some View {
        Group {
            if let pngData = BenchmarkCardRenderer.renderPNG(data: cardData) {
                ShareLink(
                    item: BenchmarkCardTransferable(imageData: pngData),
                    preview: SharePreview(
                        "Edge AI Lab Benchmark",
                        image: Image(systemName: "bolt.fill")
                    )
                ) {
                    HStack(spacing: AppSpacing.md) {
                        Image(systemName: "photo")
                            .font(AppIconSize.lg)
                            .foregroundStyle(AppColors.moss)
                            .frame(width: 32)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Share Image")
                                .font(AppTypography.subtitle)
                                .foregroundStyle(AppColors.textPrimary)
                            Text("Share card as PNG image")
                                .font(AppTypography.caption)
                                .foregroundStyle(AppColors.textTertiary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(AppIconSize.xs)
                            .foregroundStyle(AppColors.textTertiary)
                    }
                    .padding(.vertical, AppSpacing.sm)
                    .padding(.horizontal, AppSpacing.md)
                    .background(
                        RoundedRectangle(cornerRadius: AppRadius.md)
                            .fill(AppColors.moss.opacity(0.08))
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .accessibilityIdentifier("shareActionShareImage")
    }

    // MARK: - Action Row

    private func actionRow(
        icon: String,
        label: String,
        sublabel: String,
        copiedKey: CopiedItem,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: {
            action()
            withAnimation(AppAnimation.standard) {
                copiedItem = copiedKey
            }
            Task {
                try? await Task.sleep(for: .seconds(2))
                await MainActor.run {
                    withAnimation(AppAnimation.standard) {
                        if copiedItem == copiedKey {
                            copiedItem = nil
                        }
                    }
                }
            }
        }) {
            HStack(spacing: AppSpacing.md) {
                Image(systemName: copiedItem == copiedKey ? "checkmark.circle.fill" : icon)
                    .font(AppIconSize.lg)
                    .foregroundStyle(copiedItem == copiedKey ? AppColors.sprout : AppColors.textSecondary)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(copiedItem == copiedKey ? "Copied!" : label)
                        .font(AppTypography.subtitle)
                        .foregroundStyle(AppColors.textPrimary)
                    Text(sublabel)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textTertiary)
                }

                Spacer()
            }
            .padding(.vertical, AppSpacing.sm)
            .padding(.horizontal, AppSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.md)
                    .fill(Color.white.opacity(0.03))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func copyMarkdown() {
        let markdown: String
        if let entry = metricsEntry {
            markdown = MarkdownExporter.generateGitHubTemplate(entry: entry)
        } else {
            // Fallback: generate a simple caption-based markdown
            markdown = BenchmarkCardLogic.generateShareCaption(from: cardData)
        }
        copyToClipboard(markdown)
    }

    private func copyLink() {
        copyToClipboard("https://github.com/AndrewVoirol/edge-ai-lab")
    }

    private func copyCaption() {
        let caption = BenchmarkCardLogic.generateShareCaption(from: cardData)
        copyToClipboard(caption)
    }

    private func copyToClipboard(_ text: String) {
        #if os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }
}
