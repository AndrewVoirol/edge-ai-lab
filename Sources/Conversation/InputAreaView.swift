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
    #if os(iOS)
    @State private var showCamera = false
    #endif
    @FocusState private var isPromptFocused: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var isSendPressed = false

    var body: some View {
        @Bindable var viewModel = viewModel
        VStack(spacing: 0) { // design-system-exempt: zero spacing for tight packing
            // Archive mode banner
            if viewModel.isViewingArchivedConversation {
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: "archivebox.fill")
                        .foregroundStyle(AppColors.accentSecondary)
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
                        .foregroundStyle(AppColors.accentPrimary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("button_forkArchive")
                    .accessibilityLabel("Fork archived experiment")
                    .accessibilityHint("Double-tap to create a new experiment from this archive")
                }
                .padding(AppSpacing.sm)
                .background(AppColors.accentSecondary.opacity(0.08))
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

            // Active configuration badges — tappable pills showing enabled features.
            // Tap to toggle directly. Dimmed + ⚠️ if feature isn't supported on current engine.
            ActiveConfigBadges(viewModel: viewModel)
                .padding(.bottom, AppSpacing.xs)

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
                                    selectedPhotoItem != nil ? AppColors.accentPrimary : AppColors.textTertiary
                                )
                        }
                        .buttonStyle(.plain)
                        .help("Attach an image")
                        .accessibilityIdentifier("button_attachImage")

                        #if os(iOS)
                        // Camera button — iOS only, when device has a camera.
                        if UIImagePickerController.isSourceTypeAvailable(.camera) {
                            Button {
                                showCamera = true
                            } label: {
                                Image(systemName: "camera.fill")
                                    .foregroundStyle(AppColors.textTertiary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("button_captureCamera")
                            .accessibilityLabel("Take a photo")
                        }
                        #endif
                    }

                    if viewModel.supportsAudioInput {
                        Button {
                            showAudioPicker = true
                        } label: {
                            Image(systemName: "waveform.badge.plus")
                                .foregroundStyle(
                                    viewModel.selectedAudioData != nil ? AppColors.accentPrimary : AppColors.textTertiary
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
                    .font(AppTypography.body)
                    .lineLimit(1...8)
                    .focused($isPromptFocused)
                    #if os(iOS)
                    .submitLabel(.send)
                    .onSubmit {
                        submitPrompt()
                    }
                    // Backup send-on-return: TextField(axis: .vertical) with lineLimit(1...8)
                    // may not fire .onSubmit when the return key is pressed — it inserts a
                    // newline instead. Intercept the newline and trigger send if the prompt
                    // had content before the newline was inserted.
                    .onChange(of: viewModel.prompt) { oldValue, newValue in
                        guard newValue.hasSuffix("\n") else { return }
                        // Only intercept if there was real content before the newline
                        let trimmed = oldValue.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        // Remove the newline and send
                        viewModel.prompt = trimmed
                        submitPrompt()
                    }
                    #else
                    .onSubmit {
                        // Intentionally empty: suppress default Return key submission
                        // so Enter inserts a newline. Send is triggered by Cmd+Enter
                        // (via .keyboardShortcut on the Send button) or by clicking Send.
                    }
                    #endif
                    .padding(.horizontal, AppSpacing.sm)
                    .padding(.vertical, AppSpacing.sm)
                    .background {
                        if reduceTransparency {
                            AppColors.backgroundTertiary.opacity(0.85)
                        } else {
                            AppColors.backgroundTertiary.opacity(0.5).background(.ultraThinMaterial)
                        }
                    }
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
                            Text("New Experiment")
                                .font(AppTypography.caption)
                        }
                        .foregroundStyle(AppColors.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isGenerating)
                    .accessibilityIdentifier("button_newChat")
                }

                // Agent mode toggle
                Button {
                    viewModel.isAgentMode.toggle()
                } label: {
                    HStack(spacing: AppSpacing.xs) {
                        Image(systemName: viewModel.isAgentMode ? "cpu.fill" : "cpu")
                            .symbolEffect(
                                .pulse,
                                options: shouldAnimate ? .repeating : .default,
                                isActive: viewModel.agentHarness.isRunning
                            )
                        Text(viewModel.isAgentMode ? "Agent On" : "Agent")
                            .font(AppTypography.caption)
                    }
                    .foregroundStyle(
                        viewModel.isAgentMode ? AppColors.accentPrimary : AppColors.textTertiary
                    )
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isGenerating)
                .help(viewModel.isAgentMode
                    ? "Disable agent mode — single-turn inference"
                    : "Enable agent mode — multi-step autonomous reasoning")
                .accessibilityIdentifier("button_agentModeToggle")
                .accessibilityLabel(viewModel.isAgentMode ? "Agent mode enabled" : "Agent mode disabled")

                // Thinking mode indicator
                if viewModel.isThinking {
                    HStack(spacing: AppSpacing.xs) {
                        Image(systemName: "brain.head.profile")
                            .symbolEffect(.pulse)
                            .foregroundStyle(AppColors.reasoning)
                        Text("Reasoning...")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.reasoning)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Thinking mode enabled")
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
                .background {
                    if !reduceTransparency {
                        Rectangle().fill(.ultraThinMaterial)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.lg)
                .stroke(AppColors.border.opacity(0.3), lineWidth: AppLineWidth.hairline)
        )
        .shadow(color: AppColors.backgroundPrimary.opacity(0.5), radius: 8, y: -2)
        .onAppear {
            #if os(macOS)
            isPromptFocused = true
            #else
            // Prevent keyboard from auto-presenting when InputAreaView is inserted
            // into the view hierarchy (e.g., during empty→active state transition).
            // The user should explicitly tap the text field to bring up the keyboard.
            isPromptFocused = false
            #endif
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusPromptRequested)) { _ in
            isPromptFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .dismissKeyboardRequested)) { _ in
            isPromptFocused = false
        }
        .onReceive(NotificationCenter.default.publisher(for: .showPhotoPickerRequested)) { _ in
            showPhotoPicker = true
        }
        .photosPicker(
            isPresented: $showPhotoPicker,
            selection: $selectedPhotoItem,
            matching: .images,
            photoLibrary: .shared()
        )
        .onChange(of: selectedPhotoItem) { _, newItem in
            guard let newItem = newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self) {
                    viewModel.selectedImageData = data
                }
            }
        }
        #if os(iOS)
        .fullScreenCover(isPresented: $showCamera) {
            CameraImagePicker { data in
                viewModel.selectedImageData = data
            }
            .ignoresSafeArea()
        }
        #endif
    }

    // MARK: - Send Button

    private var canSubmitPrompt: Bool {
        viewModel.isGenerating || (
            viewModel.isEngineReady &&
            (!viewModel.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.hasMultimodalAttachment)
        )
    }

    private func submitPrompt() {
        if viewModel.isGenerating {
            viewModel.stopGenerating()
            return
        }
        guard viewModel.isEngineReady else {
            viewModel.statusMessage = "Please select or download a model first."
            return
        }
        guard !viewModel.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.hasMultimodalAttachment else {
            return
        }
        Task { await viewModel.generateText() }
    }

    private var sendButton: some View {
        Button {
            submitPrompt()
        } label: {
            Image(systemName: viewModel.isGenerating ? "stop.fill" : "arrow.up.circle.fill")
                .font(AppIconSize.lg)
                .foregroundStyle(sendButtonColor)
                .contentTransition(.symbolEffect(.replace))
                .scaleEffect(isSendPressed ? 0.85 : 1.0)
        }
        .buttonStyle(.plain)
        .frame(minWidth: 44, minHeight: 44) // HIG: 44pt minimum tap target
        .disabled(!canSubmitPrompt)
        .accessibilityLabel(viewModel.isGenerating ? "Stop generating" : "Send message")
        .accessibilityIdentifier("button_send")
        .accessibilityValue(sendButtonAccessibilityValue)
        .accessibilityHint(viewModel.isGenerating ? "Double-tap to stop generation" : "Double-tap to send message")
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
            color: AppColors.accentSecondary
        ))
    }

    /// Send button color adapts to state: gold when ready, muted when disabled/generating.
    private var sendButtonColor: Color {
        if viewModel.isGenerating {
            return AppColors.destructive
        }
        if viewModel.isEngineReady && !viewModel.prompt.isEmpty {
            return AppColors.accentSecondary
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
        if viewModel.runtimeFlags.enableThinking && viewModel.isThinking {
            return AppColors.reasoning
        }
        return AppColors.borderActive
    }

    /// Border width increases during thinking mode for visual emphasis.
    private var inputBorderWidth: CGFloat {
        if viewModel.runtimeFlags.enableThinking && viewModel.isThinking {
            return 1.5
        }
        return 0.5
    }

    // MARK: - Model Loading Indicator

    private var modelLoadingIndicator: some View {
        HStack(spacing: AppSpacing.sm) {
            ProgressView()
                .controlSize(.small)
                .tint(AppColors.accentPrimary)
            Text(viewModel.statusMessage)
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textSecondary)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, AppSpacing.sm)
        .transition(.opacity.combined(with: .move(edge: .top)))
        .accessibilityIdentifier("model_loading_indicator")
        .accessibilityLabel("Loading model")
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
                            .font(AppTypography.caption)
                    }
                    .buttonStyle(.plain)
                    .frame(minWidth: 44, minHeight: 44) // HIG: 44pt minimum tap target
                    .contentShape(Rectangle())
                    .accessibilityLabel("Remove attached image")
                    .accessibilityIdentifier("button_removeImage")
                }
                .padding(AppSpacing.xs)
                .glassCard(cornerRadius: AppRadius.sm)
            }

            if viewModel.selectedAudioData != nil {
                HStack(spacing: AppSpacing.xs) {
                    Image(systemName: "waveform")
                        .foregroundStyle(AppColors.accentPrimary)
                        .font(AppTypography.caption)
                    Text("Audio attached")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textSecondary)
                    Button {
                        viewModel.selectedAudioData = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(AppColors.textTertiary)
                            .font(AppTypography.caption)
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

    /// Guard for perpetual animations — disable in test environment.
    private var shouldAnimate: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
    }
}

// MARK: - Conditional Glow Modifier

/// Applies a pulsing gold glow when active (e.g., when prompt has text and engine is ready).
/// Separated as a ViewModifier to avoid SwiftUI conditional modifier issues.
/// Disables animation under XCTest to prevent runloop saturation.
private struct ConditionalGlowModifier: ViewModifier {
    let isActive: Bool
    let color: Color
    @State private var isGlowing = false

    /// Cached check: are we running inside an XCTest host?
    private static let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil || CommandLine.arguments.contains("-DisableAnimations")

    func body(content: Content) -> some View {
        if Self.isRunningTests {
            // Static shadow — no animation cycle to saturate the runloop
            content
                .shadow(
                    color: isActive ? color.opacity(0.3) : .clear,
                    radius: isActive ? 6 : 0
                )
        } else {
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
}
