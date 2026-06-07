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

                Text("On-device Gemma inference")
                    .font(.subheadline)
                    .foregroundStyle(AppColors.textSecondary)

                // Model readiness hint
                if !viewModel.isEngineReady {
                    HStack(spacing: AppSpacing.xs) {
                        Image(systemName: "arrow.up")
                            .font(.caption)
                        Text("Load a model above to get started")
                            .font(.caption)
                    }
                    .foregroundStyle(AppColors.textTertiary)
                    .padding(.top, AppSpacing.xs)
                }
            }

            // Quick action hints — now actionable
            VStack(spacing: AppSpacing.md) {
                quickActionHint(
                    icon: "text.bubble",
                    text: "Start a conversation",
                    color: AppColors.accentCyan,
                    id: "hint_chat"
                ) {
                    NotificationCenter.default.post(name: .focusPromptRequested, object: nil)
                }

                quickActionHint(
                    icon: "photo",
                    text: "Analyze an image",
                    color: AppColors.accentGold,
                    id: "hint_image"
                ) {
                    NotificationCenter.default.post(name: .showPhotoPickerRequested, object: nil)
                }

                quickActionHint(
                    icon: "wrench.and.screwdriver",
                    text: "Use built-in tools",
                    color: AppColors.toolCall,
                    id: "hint_tools"
                ) {
                    viewModel.experimentalFlags.enableToolCalling = true
                    viewModel.prompt = "What time is it in Tokyo?"
                    NotificationCenter.default.post(name: .focusPromptRequested, object: nil)
                }

                quickActionHint(
                    icon: "brain.head.profile",
                    text: "Watch the model think",
                    color: AppColors.thinking,
                    id: "hint_thinking"
                ) {
                    viewModel.experimentalFlags.enableThinking = true
                    viewModel.prompt = "Explain step by step: Why does 0.1 + 0.2 ≠ 0.3 in floating point?"
                    NotificationCenter.default.post(name: .focusPromptRequested, object: nil)
                }
            }
            .padding(.horizontal, AppSpacing.xxl)

            Spacer()
        }
    }

    private func quickActionHint(
        icon: String,
        text: String,
        color: Color,
        id: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.md) {
                Image(systemName: icon)
                    .font(.body)
                    .foregroundStyle(color)
                    .frame(width: 28)
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(AppColors.textSecondary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(AppColors.textTertiary)
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.md)
            .glassCard(cornerRadius: AppRadius.md)
            .interactiveHover()
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(id)
    }
}
