import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

// MARK: - Input Area View

/// The prompt input area with multimodal attachments, send/stop button, and action bar.
///
/// Accessibility: Every interactive element has `.accessibilityIdentifier`
/// for agent discoverability and UI testing.
struct InputAreaView: View {
    @Bindable private var viewModel = ConversationViewModel.shared
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showAudioPicker = false
    @FocusState private var isPromptFocused: Bool

    var body: some View {
        VStack(spacing: AppSpacing.sm) {
            // Multimodal attachment preview
            if viewModel.hasMultimodalAttachment {
                multimodalAttachmentStrip
            }

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
                            .stroke(AppColors.borderActive, lineWidth: 0.5)
                    )
                    .accessibilityIdentifier("textField_prompt")

                // Send/Stop button
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
                        .foregroundStyle(
                            viewModel.isEngineReady && !viewModel.isGenerating
                                ? AppColors.accentGold
                                : AppColors.textTertiary
                        )
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.isEngineReady)
                .accessibilityIdentifier("button_send")
                .keyboardShortcut(.return, modifiers: .command)
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
        }
        .onAppear {
            isPromptFocused = true
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
