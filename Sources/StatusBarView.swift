import SwiftUI

// MARK: - Status Bar View (macOS)

/// The macOS-only status bar at the bottom of the window showing model status
/// and capability badges.
///
/// Accessibility: Every interactive element has `.accessibilityIdentifier`
/// for agent discoverability and UI testing.
#if os(macOS)
struct StatusBarView: View {
    @Bindable private var viewModel = ConversationViewModel.shared

    var body: some View {
        HStack {
            if viewModel.isLoadingModel {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityIdentifier("progress_loading")
            }
            Text(viewModel.statusMessage)
                .font(.system(.caption, design: .default, weight: .semibold))
                .foregroundStyle(AppColors.textSecondary)
                
            if let metadata = viewModel.activeModelMetadata, viewModel.isEngineReady {
                HStack(spacing: 4) {
                    if metadata.supportsMTP { Text("MTP").badge(AppColors.accentTeal) }
                    if metadata.supportsImage { Text("Vision").badge(AppColors.accentCyan) }
                    if metadata.supportsAudio { Text("Audio").badge(AppColors.accentGold) }
                    if metadata.supportsToolCalling { Text("Tools").badge(AppColors.toolCall) }
                }
                .padding(.leading, AppSpacing.sm)
            }
            Spacer()
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, AppSpacing.xs)
        .background(AppColors.backgroundTertiary)
    }
}
#endif
