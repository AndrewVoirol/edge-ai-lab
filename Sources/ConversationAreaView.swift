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

    @State private var cardsAppeared = false

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

                if viewModel.isEngineReady, let metadata = viewModel.activeModelMetadata {
                    Text("\(metadata.name) loaded · on-device inference")
                        .font(.subheadline)
                        .foregroundStyle(AppColors.textSecondary)
                } else {
                    Text("On-device Gemma inference")
                        .font(.subheadline)
                        .foregroundStyle(AppColors.textSecondary)
                }

                // Model readiness hint
                if !viewModel.isEngineReady {
                    HStack(spacing: AppSpacing.xs) {
                        #if os(macOS)
                        Image(systemName: "arrow.left")
                            .font(.caption)
                        Text("Select a model from the sidebar to get started")
                            .font(.caption)
                        #else
                        Image(systemName: "arrow.up")
                            .font(.caption)
                        Text("Load a model above to get started")
                            .font(.caption)
                        #endif
                    }
                    .foregroundStyle(AppColors.textTertiary)
                    .padding(.top, AppSpacing.xs)
                }
            }

            // Actionable hint cards — contextual to engine state
            if viewModel.isEngineReady {
                VStack(spacing: AppSpacing.md) {
                    quickActionHint(
                        icon: "text.bubble",
                        title: "Start a conversation",
                        subtitle: "Ask anything — inference runs locally",
                        color: AppColors.accentCyan,
                        id: "hint_chat",
                        delay: 0.0
                    ) {
                        NotificationCenter.default.post(name: .focusPromptRequested, object: nil)
                    }

                    if viewModel.supportsImageInput {
                        quickActionHint(
                            icon: "photo",
                            title: "Analyze an image",
                            subtitle: "Attach a photo and ask about it",
                            color: AppColors.badgeVision,
                            id: "hint_image",
                            delay: 0.05
                        ) {
                            NotificationCenter.default.post(name: .showPhotoPickerRequested, object: nil)
                        }
                    }

                    quickActionHint(
                        icon: "wrench.and.screwdriver",
                        title: "Use built-in tools",
                        subtitle: "6 tools: calculator, datetime, device info, and more",
                        color: AppColors.toolCall,
                        id: "hint_tools",
                        delay: 0.1
                    ) {
                        viewModel.experimentalFlags.enableToolCalling = true
                        viewModel.prompt = "What time is it in Tokyo?"
                        NotificationCenter.default.post(name: .focusPromptRequested, object: nil)
                    }

                    quickActionHint(
                        icon: "brain.head.profile",
                        title: "Watch the model think",
                        subtitle: "See step-by-step reasoning in real-time",
                        color: AppColors.badgeThinking,
                        id: "hint_thinking",
                        delay: 0.15
                    ) {
                        viewModel.experimentalFlags.enableThinking = true
                        viewModel.prompt = "Explain step by step: Why does 0.1 + 0.2 ≠ 0.3 in floating point?"
                        NotificationCenter.default.post(name: .focusPromptRequested, object: nil)
                    }

                    quickActionHint(
                        icon: "speedometer",
                        title: "Benchmark performance",
                        subtitle: "Per-token latency, TTFT, P95, thermal tracking",
                        color: AppColors.accentGold,
                        id: "hint_benchmark",
                        delay: 0.2
                    ) {
                        viewModel.prompt = "Write a short poem about silicon and light."
                        NotificationCenter.default.post(name: .focusPromptRequested, object: nil)
                    }
                }
                .padding(.horizontal, AppSpacing.xxl)
                .onAppear {
                    withAnimation(AppAnimation.gentleSpring) {
                        cardsAppeared = true
                    }
                }
                .onDisappear {
                    cardsAppeared = false
                }
            }

            Spacer()
        }
    }

    private func quickActionHint(
        icon: String,
        title: String,
        subtitle: String,
        color: Color,
        id: String,
        delay: Double,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.md) {
                Image(systemName: icon)
                    .font(.body)
                    .foregroundStyle(color)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(.subheadline, weight: .medium))
                        .foregroundStyle(AppColors.textPrimary)
                    Text(subtitle)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textTertiary)
                }
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
        .opacity(cardsAppeared ? 1 : 0)
        .offset(y: cardsAppeared ? 0 : 12)
        .animation(AppAnimation.messageEntrance.delay(delay), value: cardsAppeared)
    }
}
