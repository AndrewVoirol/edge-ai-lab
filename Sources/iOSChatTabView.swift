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
/// - Provides iOS-specific toolbar buttons (New Chat, Settings)
///
/// This view is the root of the Chat tab in the iOS TabView.
///
/// Accessibility: Every interactive element has `.accessibilityIdentifier`.
struct iOSChatTabView: View {
    @Environment(ConversationViewModel.self) private var viewModel
    @State private var showConversationPicker = false

    var body: some View {
        ZStack {
            VibrantBackgroundView()
                .ignoresSafeArea()
                .accessibilityHidden(true)

            VStack(spacing: 0) {
                // Conversation area — chat bubbles
                ConversationAreaView()
                    .frame(maxHeight: .infinity)

                // Benchmark bar (shown when data is available)
                if viewModel.experimentalFlags.enableBenchmark, let info = viewModel.benchmarkInfo {
                    Rectangle()
                        .fill(AppColors.border)
                        .frame(height: 0.5)
                    BenchmarkBarView(info: info)
                        .padding(.horizontal, AppSpacing.md)
                        .padding(.vertical, AppSpacing.xs)
                }

                // Status indicator — iOS-specific content-layer status row
                iOSStatusIndicatorView()

                Rectangle()
                    .fill(AppColors.border)
                    .frame(height: 0.5)

                // Input area with multimodal attachments
                InputAreaView()
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.vertical, AppSpacing.sm)
            }
            .accessibilityElement(children: .contain)
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
                    .accessibilityIdentifier("chatTab_newChat")

                    Button {
                        showConversationPicker = true
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    .accessibilityIdentifier("chatTab_conversationHistory")
                }
            }
        }
        .sheet(isPresented: $showConversationPicker) {
            iOSConversationPickerSheet()
                .environment(viewModel)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("chatTab_root")
    }
}
#endif
