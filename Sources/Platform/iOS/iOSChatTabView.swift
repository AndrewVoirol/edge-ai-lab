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

#if os(iOS)
import SwiftUI

// MARK: - iOS Chat Tab View

/// Wraps the shared chat column with iOS-specific status indicator and toolbar.
///
/// Architecture:
/// - Reuses the existing `chatColumn` content (ConversationAreaView, InputAreaView)
/// - Adds the `iOSStatusIndicatorView` above the input area
/// - Provides iOS-specific toolbar buttons (New Experiment, History, Models)
/// - Shows a premium empty state when no model is loaded, guiding users
///   to the Models tab to select and load a model.
///
/// Navigation fix:
/// - The trailing toolbar button provides an always-visible escape hatch
///   from the Chat tab to the Models tab (per Apple HIG: every screen
///   should have a clear path to other destinations).
/// - The empty state CTA provides a contextual, prominent path to Models
///   when the user has no model loaded.
///
/// This view is the root of the Chat tab in the iOS TabView.
///
/// Accessibility: Every interactive element has `.accessibilityIdentifier`.
struct iOSChatTabView: View {
    @Environment(ConversationViewModel.self) private var viewModel
    @Environment(iOSNavigationRouter.self) private var router
    @State private var showConversationPicker = false

    /// Whether the chat has an active model ready for inference.
    private var hasActiveModel: Bool {
        viewModel.isEngineReady
    }

    var body: some View {
        ZStack {
            AppColors.backgroundPrimary
                .ignoresSafeArea()
                .accessibilityHidden(true)

            if hasActiveModel || viewModel.isLoadingModel {
                // Active chat interface
                activeChatContent
            } else {
                // Empty state — no model loaded
                chatEmptyState
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                HStack(spacing: AppSpacing.md) {
                    Button {
                        Task { await viewModel.newConversation() }
                    } label: {
                        Image(systemName: "plus.bubble")
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    .accessibilityLabel("New experiment")
                    .accessibilityIdentifier("chatTab_newChat")

                    Button {
                        showConversationPicker = true
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    .accessibilityLabel("Experiment history")
                    .accessibilityIdentifier("chatTab_conversationHistory")
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    router.navigateToModels()
                } label: {
                    Image(systemName: "cpu")
                        .foregroundStyle(AppColors.textSecondary)
                }
                .accessibilityLabel("Switch to Models")
                .accessibilityIdentifier("chatTab_goToModels")
            }
        }
        .sheet(isPresented: $showConversationPicker) {
            iOSConversationPickerSheet()
                .environment(viewModel)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("chatTab_root")
        .onAppear {
            // Dismiss any stale keyboard state when entering the chat tab.
            // Prevents keyboard auto-presenting during the empty→active view
            // transition when isEngineReady changes (SwiftUI recreates InputAreaView,
            // and on iOS the TextField can auto-focus during insertion).
            NotificationCenter.default.post(name: .dismissKeyboardRequested, object: nil)
        }
        .onDisappear {
            // Dismiss the keyboard when leaving the chat tab so it doesn't
            // persist across tab switches (iOS keeps view state in TabView).
            NotificationCenter.default.post(name: .dismissKeyboardRequested, object: nil)
        }
    }

    // MARK: - Active Chat Content

    /// The full chat interface shown when a model is loaded or loading.
    private var activeChatContent: some View {
        VStack(spacing: 0) { // design-system-exempt: zero spacing for tight packing
            // Conversation area — chat bubbles
            ConversationAreaView()
                .frame(maxHeight: .infinity)

            // Benchmark bar (shown when data is available)
            if viewModel.runtimeFlags.enableBenchmark, let metrics = viewModel.performanceMetrics {
                Rectangle()
                    .fill(AppColors.border)
                    .frame(height: 0.5)
                BenchmarkBarView(metrics: metrics)
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.vertical, AppSpacing.xs)
            }

            // Status indicator — iOS-specific content-layer status row
            iOSStatusIndicatorView()

            Rectangle()
                .fill(AppColors.border)
                .frame(height: 0.5)

            // Agent status banner (visible when agent mode is active)
            if viewModel.isAgentMode,
               viewModel.agentHarness.isRunning
                || viewModel.agentHarness.status != .idle {
                AgentStatusView(harness: viewModel.agentHarness)
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.vertical, AppSpacing.xs)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.easeInOut(duration: 0.3), value: viewModel.agentHarness.isRunning)
            }

            // Input area with multimodal attachments
            InputAreaView()
                .padding(.horizontal, AppSpacing.md)
                .padding(.vertical, AppSpacing.sm)
        }
        .accessibilityElement(children: .contain)
        // Agent approval sheet — presented when harness awaits user decision
        .sheet(isPresented: Binding<Bool>(
            get: {
                if case .waitingForApproval = viewModel.agentHarness.status { return true }
                return false
            },
            set: { newValue in
                if !newValue {
                    viewModel.agentHarness.denyAction()
                }
            }
        )) {
            if case .waitingForApproval(let tool, let args) = viewModel.agentHarness.status {
                AgentApprovalView(
                    toolName: tool,
                    arguments: args,
                    onApprove: { viewModel.agentHarness.approveAction() },
                    onDeny: { viewModel.agentHarness.denyAction() },
                    autoApproveAll: Binding(
                        get: { viewModel.agentHarness.autoApproveAll },
                        set: { viewModel.agentHarness.autoApproveAll = $0 }
                    )
                )
            }
        }
    }

    // MARK: - Empty State

    /// Premium empty state shown when no model is loaded.
    ///
    /// Design: A visually rich, animated prompt that guides the user
    /// to the Models tab. Uses the Dark Forest palette with layered
    /// radial gradients and a prominent CTA button.
    private var chatEmptyState: some View {
        VStack(spacing: AppSpacing.xl) {
            Spacer()

            // Hero icon — animated glow
            ZStack {
                // Ambient glow ring
                Circle()
                    .fill(
                        RadialGradient(
                            gradient: Gradient(colors: [
                                AppColors.accentPrimaryTint,
                                AppColors.accentPrimary.opacity(0.02),
                                .clear
                            ]),
                            center: .center,
                            startRadius: 30,
                            endRadius: 120
                        )
                    )
                    .frame(width: 240, height: 240)

                // Inner glass circle
                Circle()
                    .fill(AppColors.backgroundTertiary.opacity(0.6))
                    .frame(width: 100, height: 100)
                    .overlay(
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [AppColors.accentPrimary.opacity(0.4), AppColors.accentPrimary.opacity(0.1)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: AppLineWidth.regular
                            )
                    )
                    .shadow(color: AppColors.accentPrimary.opacity(0.2), radius: 20, x: 0, y: 4)

                // CPU icon
                Image(systemName: "cpu")
                    .font(AppIconSize.xxl)
                    .foregroundStyle(AppColors.accentPrimary)
            }
            .accessibilityHidden(true)

            // Text content
            VStack(spacing: AppSpacing.sm) {
                Text("No Model Loaded")
                    .font(AppTypography.pageTitle)
                    .foregroundStyle(AppColors.textPrimary)

                Text("Load a model from the Model Hub to start\nchatting, running benchmarks, or evaluations.")
                    .font(AppTypography.subtitle)
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }

            // Primary CTA
            Button {
                withAnimation(AppAnimation.spring) {
                    router.navigateToModels()
                }
            } label: {
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: "cpu")
                        .font(AppIconSize.md)
                    Text("Browse Models")
                        .font(AppTypography.subtitle)
                }
                .foregroundStyle(AppColors.textPrimary)
                .padding(.horizontal, AppSpacing.xl)
                .padding(.vertical, AppSpacing.md)
                .background(AppColors.accentPrimary)
                .clipShape(Capsule())
                .shadow(color: AppColors.accentPrimaryBorder, radius: 12, x: 0, y: 4)
            }
            .sensoryFeedback(.impact(weight: .light), trigger: router.selectedTab)
            .accessibilityLabel("Browse models to load one for chat")
            .accessibilityIdentifier("chatTab_browseModels")

            Spacer()
            Spacer()
        }
        .padding(.horizontal, AppSpacing.xl)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("chatTab_emptyState")
    }
}
#endif
