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

// MARK: - Canvas Panel View

/// Side panel that renders HTML artifacts from model output in a sandboxed WKWebView.
///
/// Layout:
/// - **macOS**: Trailing panel alongside the chat column, resizable via drag handle.
///   Width persisted in `@AppStorage("canvasPanelWidth")`.
/// - **iOS**: Presented as a sheet over the chat view.
///
/// Features:
/// - Header with title, "Copy HTML" button, and close button.
/// - Dark mode CSS injection matching the Dark Forest theme.
/// - Keyboard shortcut ⌘⇧K to toggle (handled via notification in EdgeAILabApp).
struct CanvasPanelView: View {
    @Environment(ConversationViewModel.self) private var viewModel

    /// Persisted panel width (macOS only).
    @AppStorage("canvasPanelWidth") private var panelWidth: Double = 480

    /// State for the "Copied!" feedback indicator.
    @State private var copied = false

    /// Reported content height from the WKWebView's ResizeObserver.
    @State private var contentHeight: CGFloat = 400

    #if os(macOS)
    /// Whether the panel is being resized via the drag handle.
    @GestureState private var isDragging = false
    #endif

    var body: some View {
        if let content = viewModel.activeCanvasContent {
            panelContent(content)
        }
    }

    // MARK: - Panel Content

    @ViewBuilder
    private func panelContent(_ content: CanvasContent) -> some View {
        VStack(spacing: 0) { // design-system-exempt: zero spacing for tight packing
            // Header
            headerBar(content)

            Rectangle()
                .fill(AppColors.border)
                .frame(height: 0.5)

            // Web view
            CanvasWebView(
                htmlContent: content.htmlContent,
                onHeightChange: { height in
                    contentHeight = height
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("canvasWebView")
        }
        .background(AppColors.backgroundPrimary)
        #if os(macOS)
        .frame(width: panelWidth)
        .overlay(alignment: .leading) {
            // Drag handle for resizing
            resizeDragHandle
        }
        #endif
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("canvasPanel")
    }

    // MARK: - Header Bar

    private func headerBar(_ content: CanvasContent) -> some View {
        HStack(spacing: AppSpacing.sm) {
            // Language badge
            if let lang = content.language {
                Text(lang.uppercased())
                    .font(AppTypography.badge)
                    .foregroundStyle(AppColors.accentSecondary)
                    .padding(.horizontal, AppSpacing.sm)
                    .padding(.vertical, AppSpacing.xxs)
                    .background(AppColors.accentSecondary.opacity(0.12))
                    .clipShape(Capsule())
            }

            Text("Canvas")
                .font(AppTypography.subtitle)
                .foregroundStyle(AppColors.textPrimary)

            Spacer()

            // Copy HTML button
            Button {
                #if os(macOS)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(content.htmlContent, forType: .string)
                #else
                UIPasteboard.general.string = content.htmlContent
                #endif
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    copied = false
                }
            } label: {
                HStack(spacing: AppSpacing.xs) {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(AppIconSize.xxs)
                    Text(copied ? "Copied" : "Copy HTML")
                        .font(AppTypography.caption)
                }
                .foregroundStyle(copied ? AppColors.success : AppColors.textSecondary)
            }
            .buttonStyle(.plain)
            .animation(.easeInOut(duration: 0.2), value: copied)
            .accessibilityIdentifier("button_copyCanvasHTML")
            .accessibilityLabel(copied ? "HTML copied" : "Copy HTML to clipboard")

            // Close button
            Button {
                viewModel.activeCanvasContent = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(AppIconSize.xs)
                    .foregroundStyle(AppColors.textTertiary)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("button_closeCanvas")
            .accessibilityLabel("Close canvas panel")
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, AppSpacing.sm)
        .background(AppColors.backgroundSecondary)
    }

    // MARK: - Resize Drag Handle (macOS)

    #if os(macOS)
    private var resizeDragHandle: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: 6)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        // Dragging left increases width, dragging right decreases
                        let newWidth = panelWidth - value.translation.width
                        panelWidth = max(300, min(newWidth, 900))
                    }
            )
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
            .accessibilityIdentifier("canvasResizeHandle")
            .accessibilityLabel("Resize canvas panel")
    }
    #endif
}
