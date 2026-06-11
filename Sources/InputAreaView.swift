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
import PhotosUI
import UniformTypeIdentifiers

// MARK: - Input Area View

/// The prompt input area with multimodal attachments, send/stop button, and action bar.
///
/// Accessibility: Every interactive element has `.accessibilityIdentifier`
/// for agent discoverability and UI testing.
struct InputAreaView: View {
    @Environment(ConversationViewModel.self) private var viewModel
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showAudioPicker = false
    @State private var showPhotoPicker = false
    @FocusState private var isPromptFocused: Bool
    @State private var isSendPressed = false

    var body: some View {
        @Bindable var viewModel = viewModel
        VStack(spacing: 0) {
            // Archive mode banner
            if viewModel.isViewingArchivedConversation {
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: "archivebox.fill")
                        .foregroundStyle(AppColors.accentGold)
                    Text("Viewing archived experiment")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textSecondary)
                    Spacer()
                    Button {
                        if let id = viewModel.activeConversationId {
                            viewModel.forkConversation(id: id)
                        }
                    } label: {
                        HStack(spacing: AppSpacing.xs) {
                            Image(systemName: "arrow.triangle.branch")
                            Text("Fork")
                                .font(AppTypography.caption)
                        }
                        .foregroundStyle(AppColors.accentTeal)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("button_forkArchive")
                }
                .padding(AppSpacing.sm)
                .background(AppColors.accentGold.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm))
                .padding(.bottom, AppSpacing.sm)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Multimodal attachment preview
            if viewModel.hasMultimodalAttachment {
                multimodalAttachmentStrip
                    .padding(.bottom, AppSpacing.sm)
            }

            // Model loading indicator
            if viewModel.isLoadingModel {
                modelLoadingIndicator
                    .padding(.bottom, AppSpacing.sm)
            }

            // Main input row
            HStack(spacing: AppSpacing.sm) {
                // Attachment buttons
                HStack(spacing: AppSpacing.xs) {
                    if viewModel.supportsImageInput {
                        PhotosPicker(
                            selection: $selectedPhotoItem,
                            matching: .images,
                            photoLibrary: .shared()
                        ) {
                            Image(systemName: "photo.badge.plus")
                                .foregroundStyle(
                                    selectedPhotoItem != nil ? AppColors.accentCyan : AppColors.textTertiary
                                )
                        }
                        .buttonStyle(.plain)
                        .help("Attach an image")
                        .accessibilityIdentifier("button_attachImage")
                    }

                    if viewModel.supportsAudioInput {
                        Button {
                            showAudioPicker = true
                        } label: {
                            Image(systemName: "waveform.badge.plus")
                                .foregroundStyle(
                                    viewModel.selectedAudioData != nil ? AppColors.accentTeal : AppColors.textTertiary
                                )
                        }
                        .buttonStyle(.plain)
                        .help("Attach an audio file")
                        .accessibilityIdentifier("button_attachAudio")
                        .fileImporter(
                            isPresented: $showAudioPicker,
                            allowedContentTypes: [UTType.audio],
                            allowsMultipleSelection: false
                        ) { result in
                            if let url = try? result.get().first {
                                viewModel.selectedAudioData = try? Data(contentsOf: url)
                            }
                        }
                    }
                }

                // Text input
                #if os(macOS)
                let placeholder = "Ask Gemma anything... (Cmd+Enter to send)"
                #else
                let placeholder = "Ask Gemma anything..."
                #endif
                TextField(placeholder, text: $viewModel.prompt, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .lineLimit(1...8)
                    .focused($isPromptFocused)
                    .onSubmit {
                        // Intentionally empty: suppress default Return key submission
                        // so Enter inserts a newline. Send is triggered by Cmd+Enter
                        // (via .keyboardShortcut on the Send button) or by clicking Send.
                    }
                    .padding(.horizontal, AppSpacing.sm)
                    .padding(.vertical, AppSpacing.sm)
                    .background(AppColors.backgroundTertiary.opacity(0.5).background(.ultraThinMaterial))
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppRadius.md)
                            .stroke(inputBorderColor, lineWidth: inputBorderWidth)
                    )
                    .accessibilityIdentifier("textField_prompt")

                // Send/Stop button with glow effect
                sendButton
            }

            // Action bar below input
            HStack(spacing: AppSpacing.md) {
                if !viewModel.conversation.isEmpty {
                    Button {
                        Task { await viewModel.newConversation() }
                    } label: {
                        HStack(spacing: AppSpacing.xs) {
                            Image(systemName: "plus.bubble")
                            Text("New Chat")
                                .font(AppTypography.caption)
                        }
                        .foregroundStyle(AppColors.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isGenerating)
                    .accessibilityIdentifier("button_newChat")
                }

                // Thinking mode indicator
                if viewModel.isThinking {
                    HStack(spacing: AppSpacing.xs) {
                        Image(systemName: "brain.head.profile")
                            .symbolEffect(.pulse)
                            .foregroundStyle(AppColors.thinking)
                        Text("Reasoning...")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.thinking)
                    }
                    .transition(.opacity)
                }

                Spacer()
            }
            .padding(.top, AppSpacing.xs)
        }
        .padding(AppSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.lg)
                .fill(AppColors.backgroundSecondary.opacity(0.6))
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.lg)
                .stroke(AppColors.border.opacity(0.3), lineWidth: 0.5)
        )
        .shadow(color: AppColors.backgroundPrimary.opacity(0.5), radius: 8, y: -2)
        .onAppear {
            isPromptFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusPromptRequested)) { _ in
            isPromptFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .showPhotoPickerRequested)) { _ in
            showPhotoPicker = true
        }
        .onChange(of: selectedPhotoItem) { _, newItem in
            guard let newItem = newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self) {
                    viewModel.selectedImageData = data
                }
            }
        }
    }

    // MARK: - Send Button

    private var sendButton: some View {
        Button {
            if viewModel.isGenerating {
                viewModel.stopGenerating()
                return
            }
            guard viewModel.isEngineReady else {
                viewModel.statusMessage = "Please select or download a model first."
                return
            }
            Task { await viewModel.generateText() }
        } label: {
            Image(systemName: viewModel.isGenerating ? "stop.fill" : "arrow.up.circle.fill")
                .font(.title2)
                .foregroundStyle(sendButtonColor)
                .contentTransition(.symbolEffect(.replace))
                .scaleEffect(isSendPressed ? 0.85 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(!viewModel.isEngineReady)
        .accessibilityIdentifier("button_send")
        .accessibilityValue(sendButtonAccessibilityValue)
        .keyboardShortcut(.return, modifiers: .command)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    withAnimation(AppAnimation.spring) { isSendPressed = true }
                }
                .onEnded { _ in
                    withAnimation(AppAnimation.spring) { isSendPressed = false }
                }
        )
        .modifier(ConditionalGlowModifier(
            isActive: !viewModel.prompt.isEmpty && viewModel.isEngineReady,
            color: AppColors.accentGold
        ))
    }

    /// Send button color adapts to state: gold when ready, muted when disabled/generating.
    private var sendButtonColor: Color {
        if viewModel.isGenerating {
            return AppColors.danger
        }
        if viewModel.isEngineReady && !viewModel.prompt.isEmpty {
            return AppColors.accentGold
        }
        return AppColors.textTertiary
    }

    /// Accessibility value for the send button state.
    private var sendButtonAccessibilityValue: String {
        if viewModel.isGenerating { return "stop" }
        if !viewModel.isEngineReady { return "disabled" }
        if !viewModel.prompt.isEmpty { return "ready" }
        return "idle"
    }

    // MARK: - Input Border

    /// Border color changes when thinking mode is active.
    private var inputBorderColor: Color {
        if viewModel.experimentalFlags.enableThinking && viewModel.isThinking {
            return AppColors.thinking
        }
        return AppColors.borderActive
    }

    /// Border width increases during thinking mode for visual emphasis.
    private var inputBorderWidth: CGFloat {
        if viewModel.experimentalFlags.enableThinking && viewModel.isThinking {
            return 1.5
        }
        return 0.5
    }

    // MARK: - Model Loading Indicator

    private var modelLoadingIndicator: some View {
        HStack(spacing: AppSpacing.sm) {
            ProgressView()
                .controlSize(.small)
                .tint(AppColors.accentTeal)
            Text(viewModel.statusMessage)
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textSecondary)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, AppSpacing.sm)
        .transition(.opacity.combined(with: .move(edge: .top)))
        .accessibilityIdentifier("model_loading_indicator")
    }

    // MARK: - Multimodal Attachment Strip

    private var multimodalAttachmentStrip: some View {
        HStack(spacing: AppSpacing.sm) {
            if let imageData = viewModel.selectedImageData {
                HStack(spacing: AppSpacing.xs) {
                    #if os(iOS)
                    if let uiImage = UIImage(data: imageData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 36, height: 36)
                            .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm))
                    }
                    #elseif os(macOS)
                    if let nsImage = NSImage(data: imageData) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 36, height: 36)
                            .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm))
                    }
                    #endif
                    Text("Image attached")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textSecondary)
                    Button {
                        viewModel.selectedImageData = nil
                        selectedPhotoItem = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(AppColors.textTertiary)
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("button_removeImage")
                }
                .padding(AppSpacing.xs)
                .glassCard(cornerRadius: AppRadius.sm)
            }

            if viewModel.selectedAudioData != nil {
                HStack(spacing: AppSpacing.xs) {
                    Image(systemName: "waveform")
                        .foregroundStyle(AppColors.accentTeal)
                        .font(.caption)
                    Text("Audio attached")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textSecondary)
                    Button {
                        viewModel.selectedAudioData = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(AppColors.textTertiary)
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("button_removeAudio")
                }
                .padding(AppSpacing.xs)
                .glassCard(cornerRadius: AppRadius.sm)
            }

            Spacer()
        }
    }
}

// MARK: - Conditional Glow Modifier

/// Applies a pulsing gold glow when active (e.g., when prompt has text and engine is ready).
/// Separated as a ViewModifier to avoid SwiftUI conditional modifier issues.
private struct ConditionalGlowModifier: ViewModifier {
    let isActive: Bool
    let color: Color
    @State private var isGlowing = false

    func body(content: Content) -> some View {
        content
            .shadow(
                color: isActive ? color.opacity(isGlowing ? 0.6 : 0.2) : .clear,
                radius: isActive ? (isGlowing ? 8 : 4) : 0
            )
            .animation(
                isActive ? .easeInOut(duration: 1.2).repeatForever(autoreverses: true) : .default,
                value: isGlowing
            )
            .onChange(of: isActive) { _, newValue in
                isGlowing = newValue
            }
            .onAppear {
                isGlowing = isActive
            }
    }
}
