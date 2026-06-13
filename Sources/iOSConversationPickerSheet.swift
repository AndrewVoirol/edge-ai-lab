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

#if os(iOS)
import os
import SwiftUI

// MARK: - iOS Conversation Picker Sheet

/// A sheet presenting the user's saved conversation history on iOS.
///
/// Provides parity with the macOS sidebar's Conversations section:
/// - Lists all saved conversations sorted by last modified date
/// - Tap to load a conversation
/// - Swipe to delete
/// - Long-press context menu for rename, fork, export, delete
///
/// Design: Dark Forest / Moss palette with glass cards and consistent design tokens.
///
/// Accessibility: Every interactive element has `.accessibilityIdentifier`.
struct iOSConversationPickerSheet: View {
    private static let logger = Logger(
        subsystem: "com.andrewvoirol.GemmaEdgeGallery",
        category: "iOSConversationPickerSheet"
    )

    @Environment(ConversationViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss

    @State private var showRenameAlert = false
    @State private var renameText = ""
    @State private var renameTarget: ConversationIndexEntry?
    @State private var showDeleteConfirmation = false
    @State private var deleteTarget: ConversationIndexEntry?
    @State private var exportData: Data?
    @State private var showShareSheet = false

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                VibrantBackgroundView()
                    .ignoresSafeArea()
                    .accessibilityHidden(true)

                if viewModel.conversationStore.indexEntries.isEmpty {
                    emptyState
                } else {
                    conversationList
                }
            }
            .navigationTitle("Conversations")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(AppColors.accentCyan)
                        .accessibilityIdentifier("conversationPicker_done")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await viewModel.newConversation() }
                        dismiss()
                    } label: {
                        Image(systemName: "plus.bubble")
                            .foregroundStyle(AppColors.accentTeal)
                    }
                    .accessibilityIdentifier("conversationPicker_newChat")
                }
            }
        }
        .alert("Rename Conversation", isPresented: $showRenameAlert) {
            TextField("Title", text: $renameText)
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                if let target = renameTarget {
                    viewModel.renameConversation(id: target.id, newTitle: renameText)
                }
            }
        }
        .alert("Delete Conversation?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { deleteTarget = nil }
            Button("Delete", role: .destructive) {
                if let target = deleteTarget {
                    viewModel.deleteConversation(id: target.id)
                }
            }
        } message: {
            if let target = deleteTarget {
                Text("\"\(target.title)\" will be permanently deleted.")
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let data = exportData {
                ShareSheet(activityItems: [data])
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: AppSpacing.lg) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 48))
                .foregroundStyle(AppColors.textTertiary)

            Text("No saved conversations")
                .font(AppTypography.listTitle)
                .foregroundStyle(AppColors.textSecondary)

            Text("Start a chat and it will be saved here automatically.")
                .font(AppTypography.listSubtitle)
                .foregroundStyle(AppColors.textTertiary)
                .multilineTextAlignment(.center)
        }
        .padding(AppSpacing.xl)
        .accessibilityIdentifier("conversationPicker_emptyState")
    }

    // MARK: - Conversation List

    private var conversationList: some View {
        List {
            ForEach(viewModel.conversationStore.indexEntries) { entry in
                conversationRow(entry)
                    .accessibilityIdentifier("conversationPicker_row_\(entry.id.uuidString.prefix(8))")
            }
            .onDelete { indexSet in
                for index in indexSet {
                    let entry = viewModel.conversationStore.indexEntries[index]
                    viewModel.deleteConversation(id: entry.id)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    // MARK: - Conversation Row

    private func conversationRow(_ entry: ConversationIndexEntry) -> some View {
        let isActive = viewModel.activeConversationId == entry.id

        Button {
            viewModel.loadConversation(id: entry.id)
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                // Title
                HStack {
                    Text(entry.title)
                        .font(.system(.body, weight: isActive ? .semibold : .regular))
                        .foregroundStyle(isActive ? AppColors.accentCyan : AppColors.textPrimary)
                        .lineLimit(2)

                    Spacer()

                    if entry.forkedFrom != nil {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.caption)
                            .foregroundStyle(AppColors.accentTeal)
                    }
                }

                // Model badge + timestamp
                HStack(spacing: AppSpacing.xs) {
                    Text(entry.modelShortName)
                        .font(AppTypography.badge)
                        .foregroundStyle(AppColors.accentCyan)
                        .padding(.horizontal, AppSpacing.xs)
                        .padding(.vertical, 2)
                        .background(AppColors.accentCyan.opacity(0.1))
                        .clipShape(Capsule())

                    ForEach(entry.activeFeatureBadges, id: \.self) { badge in
                        Text(badge)
                            .font(AppTypography.badge)
                            .foregroundStyle(AppColors.accentTeal)
                            .padding(.horizontal, AppSpacing.xs)
                            .padding(.vertical, 2)
                            .background(AppColors.accentTeal.opacity(0.1))
                            .clipShape(Capsule())
                    }

                    Spacer()

                    Text(relativeTimestamp(entry.lastModifiedAt))
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textTertiary)
                }

                // Stats row
                if entry.messageCount > 0 {
                    HStack(spacing: AppSpacing.xs) {
                        Image(systemName: "bubble.left.and.text.bubble.right")
                            .font(.caption2)
                            .foregroundStyle(AppColors.textTertiary)
                        Text("\(entry.messageCount) messages")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textTertiary)

                        if let speed = entry.averageDecodeSpeed, speed > 0 {
                            Text("·")
                                .foregroundStyle(AppColors.textTertiary)
                            Text(String(format: "%.1f tok/s", speed))
                                .font(AppTypography.caption)
                                .foregroundStyle(AppColors.textTertiary)
                        }
                    }
                }
            }
            .padding(.vertical, AppSpacing.xs)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                renameTarget = entry
                renameText = entry.title
                showRenameAlert = true
            } label: {
                Label("Rename", systemImage: "pencil")
            }

            Button {
                viewModel.forkConversation(id: entry.id)
                dismiss()
            } label: {
                Label("Fork Experiment", systemImage: "arrow.triangle.branch")
            }

            Button {
                exportConversation(entry.id)
            } label: {
                Label("Export JSON", systemImage: "square.and.arrow.up")
            }

            Divider()

            Button(role: .destructive) {
                deleteTarget = entry
                showDeleteConfirmation = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Helpers

    private func relativeTimestamp(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func exportConversation(_ id: UUID) {
        do {
            exportData = try viewModel.conversationStore.exportJSON(id: id)
            showShareSheet = true
        } catch {
            Self.logger.error("Export failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

// MARK: - Share Sheet (UIKit Bridge)

/// UIKit activity view controller wrapper for iOS sharing.
private struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif
