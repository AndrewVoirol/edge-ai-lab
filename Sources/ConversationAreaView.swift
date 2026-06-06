import SwiftUI

// MARK: - Conversation Area View

/// The scrollable chat area with message bubbles and empty state.
///
/// Accessibility: Every interactive element has `.accessibilityIdentifier`
/// for agent discoverability and UI testing.
struct ConversationAreaView: View {
    @Bindable private var viewModel = ConversationViewModel.shared

    var body: some View {
        Group {
            if viewModel.conversation.isEmpty {
                // Empty state
                emptyState
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(viewModel.conversation.messages) { message in
                                ChatBubbleView(
                                    message: message,
                                    enableThinking: viewModel.experimentalFlags.enableThinking
                                )
                            }

                            // Invisible anchor for auto-scroll
                            Color.clear
                                .frame(height: 1)
                                .id("conversationBottom")
                        }
                        .padding(.vertical, AppSpacing.sm)
                    }
                    .scrollContentBackground(.hidden)
                    .onChange(of: viewModel.conversation.messages.count) { _, _ in
                        withAnimation(AppAnimation.gentleSpring) {
                            proxy.scrollTo("conversationBottom", anchor: .bottom)
                        }
                    }
                    .onChange(of: viewModel.responseText) { _, _ in
                        // Scroll during streaming too
                        proxy.scrollTo("conversationBottom", anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: AppSpacing.xl) {
            Spacer()

            Image(systemName: "sparkles")
                .font(.system(size: 48))
                .foregroundStyle(
                    LinearGradient(
                        colors: [AppColors.accentGold, AppColors.accentTeal],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .pulsingGlow(AppColors.accentTeal)

            VStack(spacing: AppSpacing.sm) {
                Text("Edge AI Lab")
                    .font(.system(.title2, design: .default, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)

                Text("On-device Gemma 4 inference")
                    .font(.subheadline)
                    .foregroundStyle(AppColors.textSecondary)
            }

            // Quick action hints
            VStack(spacing: AppSpacing.md) {
                quickActionHint(icon: "text.bubble", text: "Start a conversation", color: AppColors.accentCyan, id: "hint_chat")
                quickActionHint(icon: "photo", text: "Analyze an image", color: AppColors.accentGold, id: "hint_image")
                quickActionHint(icon: "wrench.and.screwdriver", text: "Use built-in tools", color: AppColors.toolCall, id: "hint_tools")
                quickActionHint(icon: "brain.head.profile", text: "Watch the model think", color: AppColors.thinking, id: "hint_thinking")
            }
            .padding(.horizontal, AppSpacing.xxl)

            Spacer()
        }
    }

    private func quickActionHint(icon: String, text: String, color: Color, id: String) -> some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(color)
                .frame(width: 28)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(AppColors.textSecondary)
            Spacer()
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, AppSpacing.md)
        .glassCard(cornerRadius: AppRadius.md)
        .interactiveHover()
        .accessibilityIdentifier(id)
    }
}
