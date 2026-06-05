import LiteRTLM
import SwiftUI
import UniformTypeIdentifiers
import PhotosUI

// MARK: - Content View

/// The main application view — a premium on-device AI inference lab.
///
/// Layout: Dark-mode-first with a top header bar, horizontal model card strip,
/// scrollable chat area with glass-effect bubbles, and a frosted input bar.
/// The benchmark bar at the bottom uses performance tier coloring.
///
/// Accessibility: Every interactive element has `.accessibilityIdentifier`
/// for agent discoverability and UI testing.
struct ContentView: View {
    @State private var viewModel = ConversationViewModel()
    @State private var showSettings = false
    @State private var showDashboard = false
    @State private var showcaseModel: ModelMetadata?
    @State private var showcaseModelURL: URL?
    @State private var isBenchmarkExpanded = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showAudioPicker = false
    @State private var scrollProxy: ScrollViewProxy?
    @Namespace private var bottomAnchor

    var body: some View {
        ZStack {
            // Full-bleed vibrant animated background for premium feel
            VibrantBackgroundView()
                .ignoresSafeArea()
                .overlay(.black.opacity(0.2)) // Subtle dimming so glass cards pop
            VStack(spacing: 0) {
                // Header bar
                headerView
                    #if os(iOS)
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.vertical, AppSpacing.sm)
                    #else
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.vertical, AppSpacing.md)
                    #endif

                // Subtle separator
                Rectangle()
                    .fill(AppColors.border)
                    .frame(height: 0.5)

                // Model card strip
                modelManagementSection

                Rectangle()
                    .fill(AppColors.border)
                    .frame(height: 0.5)

                // Conversation area — chat bubbles
                conversationArea
                    .frame(maxHeight: .infinity)

                // Benchmark bar (shown when data is available)
                if viewModel.experimentalFlags.enableBenchmark, let info = viewModel.benchmarkInfo {
                    Rectangle()
                        .fill(AppColors.border)
                        .frame(height: 0.5)
                    benchmarkBar(info: info)
                        #if os(iOS)
                        .padding(.horizontal, AppSpacing.md)
                        .padding(.vertical, AppSpacing.xs)
                        #else
                        .padding(.horizontal, AppSpacing.lg)
                        .padding(.vertical, AppSpacing.sm)
                        #endif
                }

                Rectangle()
                    .fill(AppColors.border)
                    .frame(height: 0.5)

                // Input area with multimodal attachments
                inputArea
                    #if os(iOS)
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.vertical, AppSpacing.sm)
                    #else
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.vertical, AppSpacing.md)
                    #endif
            }
        }
        .foregroundStyle(AppColors.textPrimary)
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                InferenceSettingsView(viewModel: viewModel)
                    .navigationTitle("Settings")
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showSettings = false }
                        }
                    }
            }
            #if os(macOS)
            .frame(minWidth: 400, minHeight: 500)
            #endif
        }
        .sheet(isPresented: $showDashboard) {
            NavigationStack {
                PerformanceDashboardView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showDashboard = false }
                        }
                    }
            }
            #if os(macOS)
            .frame(minWidth: 600, minHeight: 500)
            #endif
        }
        .sheet(item: $showcaseModel) { model in
            NavigationStack {
                ModelShowcaseView(metadata: model, fileURL: showcaseModelURL)
            }
            #if os(macOS)
            .frame(minWidth: 450, minHeight: 550)
            #endif
        }
        .alert("HuggingFace Token Required", isPresented: Binding(
            get: { viewModel.downloadManager.showTokenPrompt },
            set: { viewModel.downloadManager.showTokenPrompt = $0 }
        )) {
            hfTokenAlert
        }
        .onChange(of: selectedPhotoItem) { _, newItem in
            guard let newItem = newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self) {
                    viewModel.selectedImageData = data
                }
            }
        }
        .onAppear {
            // Skip auto-loading when running under the test harness or developer automation —
            // tests manage their own engine lifecycle.
            guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil,
                  !CommandLine.arguments.contains("-RunAutomationHarness"),
                  !CommandLine.arguments.contains("-RunAllTests"),
                  !CommandLine.arguments.contains("-RunMatrixBenchmark") else {
                viewModel.downloadManager.refreshStates()
                DeveloperAutomationHarness.runIfRequested(viewModel: viewModel)
                return
            }
            viewModel.checkForLocalModels()
            viewModel.downloadManager.refreshStates()
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: AppSpacing.sm) {
            // Status / model name
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: AppSpacing.sm) {
                    if viewModel.isLoadingModel {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityIdentifier("progress_loading")
                    }

                    Text(viewModel.statusMessage)
                        .font(.system(.headline, design: .default, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    if viewModel.isLoadingModel {
                        Button("Cancel") {
                            viewModel.cancelModelLoad()
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                        .controlSize(.small)
                        .accessibilityIdentifier("button_cancelLoad")
                    }
                }

                if let path = viewModel.activeModelURL?.path {
                    Text(path)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                // Capability badges for loaded model
                if let metadata = viewModel.activeModelMetadata {
                    HStack(spacing: AppSpacing.xs) {
                        if metadata.supportsImage {
                            Label("Vision", systemImage: "eye")
                                .badge(AppColors.accentCyan)
                                .accessibilityIdentifier("badge_vision")
                        }
                        if metadata.supportsAudio {
                            Label("Audio", systemImage: "waveform")
                                .badge(AppColors.accentTeal)
                                .accessibilityIdentifier("badge_audio")
                        }
                        if metadata.supportsMTP {
                            Label("MTP", systemImage: "hare")
                                .badge(AppColors.success)
                                .accessibilityIdentifier("badge_mtp")
                        }
                        if viewModel.experimentalFlags.enableToolCalling {
                            Label("Tools", systemImage: "wrench.and.screwdriver")
                                .badge(AppColors.toolCall)
                                .accessibilityIdentifier("badge_tools")
                        }
                        if viewModel.experimentalFlags.enableThinking {
                            Label("Thinking", systemImage: "brain.head.profile")
                                .badge(AppColors.thinking)
                                .accessibilityIdentifier("badge_thinking")
                        }
                    }
                }
            }

            Spacer()

            // Action buttons
            HStack(spacing: AppSpacing.sm) {
                Button {
                    viewModel.refreshDiscoveredModels()
                    viewModel.downloadManager.refreshStates()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .foregroundStyle(AppColors.textSecondary)
                }
                .buttonStyle(.plain)
                .help("Refresh discovered models")
                .accessibilityIdentifier("button_refresh")

                Button {
                    showDashboard = true
                } label: {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .foregroundStyle(AppColors.textSecondary)
                }
                .buttonStyle(.plain)
                .help("Performance Dashboard")
                .accessibilityIdentifier("button_dashboard")

                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .foregroundStyle(AppColors.textSecondary)
                }
                .buttonStyle(.plain)
                .help("Inference Settings")
                .accessibilityIdentifier("button_settings")

                Button {
                    viewModel.isFilePickerPresented = true
                } label: {
                    #if os(iOS)
                    // Icon-only capsule on iPhone to save horizontal space
                    Image(systemName: "plus.square")
                        .foregroundStyle(AppColors.accentGold)
                        .padding(AppSpacing.sm)
                        .background(AppColors.accentGold.opacity(0.12))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(AppColors.accentGold.opacity(0.2), lineWidth: 0.5))
                    #else
                    HStack(spacing: AppSpacing.xs) {
                        Image(systemName: "plus.square")
                        Text("Load Model")
                            .font(.system(.caption, weight: .semibold))
                    }
                    .foregroundStyle(AppColors.accentGold)
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.vertical, AppSpacing.sm)
                    .background(AppColors.accentGold.opacity(0.12))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(AppColors.accentGold.opacity(0.2), lineWidth: 0.5))
                    #endif
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("button_loadModel")
                .fileImporter(
                    isPresented: $viewModel.isFilePickerPresented,
                    allowedContentTypes: [.data],
                    allowsMultipleSelection: false
                ) { result in
                    do {
                        guard let selectedFile = try result.get().first else { return }
                        Task {
                            await viewModel.handleModelSelection(selectedFile)
                        }
                    } catch {
                        viewModel.statusMessage = "Error selecting file: \(error.localizedDescription)"
                    }
                }
            }
        }
    }

    // MARK: - Conversation Area

    private var conversationArea: some View {
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
                    .onAppear { scrollProxy = proxy }
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
                quickActionHint(icon: "text.bubble", text: "Start a conversation", color: AppColors.accentCyan)
                quickActionHint(icon: "photo", text: "Analyze an image", color: AppColors.accentGold)
                quickActionHint(icon: "wrench.and.screwdriver", text: "Use built-in tools", color: AppColors.toolCall)
                quickActionHint(icon: "brain.head.profile", text: "Watch the model think", color: AppColors.thinking)
            }
            .padding(.horizontal, AppSpacing.xxl)

            Spacer()
        }
    }

    private func quickActionHint(icon: String, text: String, color: Color) -> some View {
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
    }

    // MARK: - Input Area

    private var inputArea: some View {
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
                TextField("Ask Gemma anything...", text: $viewModel.prompt)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .padding(.horizontal, AppSpacing.sm)
                    .padding(.vertical, AppSpacing.sm)
                    .background(AppColors.backgroundTertiary.opacity(0.5).background(.ultraThinMaterial))
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppRadius.md)
                            .stroke(AppColors.borderActive, lineWidth: 0.5)
                    )
                    .onSubmit {
                        guard viewModel.isEngineReady else {
                            viewModel.statusMessage = "Please select or download a model first."
                            return
                        }
                        guard !viewModel.isGenerating else { return }
                        Task { await viewModel.generateText() }
                    }
                    .accessibilityIdentifier("textField_prompt")

                // Send button
                Button {
                    guard viewModel.isEngineReady else {
                        viewModel.statusMessage = "Please select or download a model first."
                        return
                    }
                    guard !viewModel.isGenerating else { return }
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
                .disabled(!viewModel.isEngineReady || viewModel.isGenerating)
                .accessibilityIdentifier("button_send")
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
    }

    // MARK: - Model Management (Discovered + Downloadable)

    private var modelManagementSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack {
                Text("Models")
                    .font(AppTypography.sectionHeader)
                    .foregroundStyle(AppColors.textSecondary)
                Spacer()
                Text(viewModel.downloadManager.documentsDirectory.path)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.top, AppSpacing.sm)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppSpacing.md) {
                    // On-disk discovered models
                    ForEach(viewModel.discoveredModels) { model in
                        discoveredModelCard(model)
                    }

                    // Registry models not yet on disk (downloadable)
                    ForEach(downloadableModels) { model in
                        downloadableModelCard(model)
                    }
                }
                .padding(.horizontal, AppSpacing.lg)
                .padding(.bottom, AppSpacing.sm)
            }
        }
        .accessibilityIdentifier("section_models")
    }

    /// Registry models that are not yet discovered on disk.
    private var downloadableModels: [ModelMetadata] {
        let discoveredFilenames = Set(viewModel.discoveredModels.map(\.filename))
        return ModelRegistry.knownModels.filter { !discoveredFilenames.contains($0.modelFile) }
    }

    // MARK: - Model Cards

    private func discoveredModelCard(_ model: DiscoveredModel) -> some View {
        let isActive = viewModel.activeModelURL == model.url
        return Button {
            Task {
                await viewModel.handleModelSelection(model.url)
            }
        } label: {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                HStack(spacing: AppSpacing.xs) {
                    Text(model.metadata?.name ?? model.filename)
                        .font(.system(.caption, weight: .semibold))
                        .foregroundStyle(isActive ? AppColors.accentCyan : AppColors.textPrimary)
                        .lineLimit(1)
                    if model.source == .edgeGallery {
                        Text("Gallery")
                            .font(AppTypography.badge)
                            .foregroundStyle(AppColors.accentCyan)
                            .padding(.horizontal, AppSpacing.xs)
                            .padding(.vertical, 1)
                            .background(AppColors.accentCyan.opacity(0.1))
                            .clipShape(Capsule())
                    }
                }
                HStack(spacing: AppSpacing.xs) {
                    Circle()
                        .fill(isActive ? AppColors.accentCyan : AppColors.success)
                        .frame(width: 5, height: 5)
                    Text(isActive ? "Loaded Engine" : "Click to Load Engine")
                        .font(AppTypography.caption)
                        .foregroundStyle(isActive ? AppColors.accentCyan : AppColors.textTertiary)
                }
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, AppSpacing.sm)
            .contentShape(Rectangle())
            .glassCard(cornerRadius: AppRadius.md)
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.md)
                    .stroke(isActive ? AppColors.accentCyan : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            if let metadata = model.metadata {
                Button {
                    showcaseModelURL = model.url
                    showcaseModel = metadata
                } label: {
                    Label("Model Info", systemImage: "info.circle")
                }
            }
        }
        .accessibilityIdentifier("modelCard_\(model.filename)")
    }

    private func downloadableModelCard(_ model: ModelMetadata) -> some View {
        let state = viewModel.downloadManager.downloadStates[model.modelFile] ?? .notDownloaded

        return VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(model.name)
                .font(.system(.caption, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(1)

            switch state {
            case .notDownloaded:
                Button {
                    viewModel.downloadManager.download(model)
                } label: {
                    HStack(spacing: AppSpacing.xs) {
                        Image(systemName: "arrow.down.circle")
                        Text(ByteCountFormatter.string(fromByteCount: model.sizeInBytes, countStyle: .file))
                            .font(AppTypography.caption)
                    }
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.accentCyan)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("download_\(model.modelFile)")

            case .downloading(let progress):
                VStack(alignment: .leading, spacing: 2) {
                    ProgressView(value: progress)
                        .tint(AppColors.accentTeal)
                        .frame(width: 80)
                    HStack {
                        Text("\(Int(progress * 100))%")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textTertiary)
                        Spacer()
                        Button {
                            viewModel.downloadManager.cancelDownload(model)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption2)
                                .foregroundStyle(AppColors.textTertiary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("cancelDownload_\(model.modelFile)")
                    }
                }

            case .downloaded:
                HStack(spacing: AppSpacing.xs) {
                    Circle()
                        .fill(AppColors.success)
                        .frame(width: 5, height: 5)
                    Text("Ready")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textTertiary)
                }

            case .failed(let message):
                HStack(spacing: AppSpacing.xs) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(AppColors.danger)
                        .font(.caption2)
                    Text(message)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.danger)
                        .lineLimit(1)
                }

            case .authRequired:
                Button {
                    viewModel.downloadManager.showTokenPrompt = true
                    viewModel.downloadManager.pendingAuthModel = model
                } label: {
                    HStack(spacing: AppSpacing.xs) {
                        Image(systemName: "lock.fill")
                        Text("Auth required")
                    }
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.warning)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("auth_\(model.modelFile)")
            }
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, AppSpacing.sm)
        .contentShape(Rectangle())
        .glassCard(cornerRadius: AppRadius.md)
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

    // MARK: - HF Token Alert

    @ViewBuilder
    private var hfTokenAlert: some View {
        // Note: iOS alerts don't support text fields natively in all cases.
        // For simplicity, we direct the user to Settings.
        Button("Open Settings") {
            viewModel.downloadManager.showTokenPrompt = false
            showSettings = true
        }
        Button("Cancel", role: .cancel) {
            viewModel.downloadManager.showTokenPrompt = false
        }
    }

    // MARK: - Benchmark Bar

    private func benchmarkBar(info: BenchmarkInfo) -> some View {
        let decodeTier = PerformanceTier(decodeSpeed: info.lastDecodeTokensPerSecond)

        return VStack(spacing: AppSpacing.xs) {
            // Compact bar (always visible)
            #if os(iOS)
            // iOS: Two-row wrapped grid to fit narrow screens
            iosBenchmarkCompactBar(info: info, decodeTier: decodeTier)
            #else
            HStack(spacing: AppSpacing.md) {
                // Backend indicator
                if let result = viewModel.backendResult {
                    HStack(spacing: AppSpacing.xs) {
                        Image(systemName: result.activeBackend == .gpu ? "bolt.fill" : "cpu")
                            .foregroundStyle(result.activeBackend == .gpu ? AppColors.success : AppColors.warning)
                        Text(result.activeBackend == .gpu ? "GPU" : "CPU")
                            .font(AppTypography.badge)
                            .foregroundStyle(result.activeBackend == .gpu ? AppColors.success : AppColors.warning)
                    }
                    .accessibilityIdentifier("badge_backend")

                    Rectangle()
                        .fill(AppColors.border)
                        .frame(width: 0.5, height: 18)
                }

                // Thermal state indicator
                thermalIndicator
                    .accessibilityIdentifier("indicator_thermal")

                Rectangle()
                    .fill(AppColors.border)
                    .frame(width: 0.5, height: 18)

                benchmarkItem(label: "TTFT", value: String(format: "%.3fs", info.timeToFirstTokenInSecond))
                Rectangle()
                    .fill(AppColors.border)
                    .frame(width: 0.5, height: 18)

                // Hero metric: decode speed with tier color
                VStack(alignment: .leading, spacing: 1) {
                    Text("Decode")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textTertiary)
                    Text(String(format: "%.1f tok/s", info.lastDecodeTokensPerSecond))
                        .font(AppTypography.metric)
                        .foregroundStyle(decodeTier.color)
                        .contentTransition(.numericText())
                }

                Rectangle()
                    .fill(AppColors.border)
                    .frame(width: 0.5, height: 18)

                benchmarkItem(label: "Prefill", value: String(format: "%.1f tok/s", info.lastPrefillTokensPerSecond))

                // Memory indicator
                Rectangle()
                    .fill(AppColors.border)
                    .frame(width: 0.5, height: 18)
                memoryIndicator

                Spacer()

                // Expand/collapse button
                Button {
                    withAnimation(AppAnimation.standard) {
                        isBenchmarkExpanded.toggle()
                    }
                } label: {
                    Image(systemName: isBenchmarkExpanded ? "chevron.down" : "chevron.up")
                        .foregroundStyle(AppColors.textTertiary)
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("button_benchmarkExpand")
            }
            #endif

            // Fallback warning
            if let result = viewModel.backendResult, result.didFallback, let reason = result.fallbackReason {
                HStack(spacing: AppSpacing.xs) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(AppColors.warning)
                    Text(reason)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textSecondary)
                    Spacer()
                }
                .padding(.vertical, AppSpacing.xs)
            }

            // Expanded detail view
            if isBenchmarkExpanded, let metrics = viewModel.inferenceMetrics {
                expandedMetricsView(metrics: metrics, info: info)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .font(AppTypography.caption)
    }

    // MARK: - iOS Benchmark Compact Bar

    #if os(iOS)
    /// Two-row layout for the benchmark bar on narrow iPhone screens.
    private func iosBenchmarkCompactBar(info: BenchmarkInfo, decodeTier: PerformanceTier) -> some View {
        VStack(spacing: AppSpacing.xs) {
            // Row 1: Backend, Thermal, TTFT, Expand button
            HStack(spacing: AppSpacing.sm) {
                if let result = viewModel.backendResult {
                    HStack(spacing: AppSpacing.xs) {
                        Image(systemName: result.activeBackend == .gpu ? "bolt.fill" : "cpu")
                            .foregroundStyle(result.activeBackend == .gpu ? AppColors.success : AppColors.warning)
                        Text(result.activeBackend == .gpu ? "GPU" : "CPU")
                            .font(AppTypography.badge)
                            .foregroundStyle(result.activeBackend == .gpu ? AppColors.success : AppColors.warning)
                    }
                    .accessibilityIdentifier("badge_backend")
                }

                thermalIndicator
                    .accessibilityIdentifier("indicator_thermal")

                benchmarkItem(label: "TTFT", value: String(format: "%.3fs", info.timeToFirstTokenInSecond))

                Spacer()

                Button {
                    withAnimation(AppAnimation.standard) {
                        isBenchmarkExpanded.toggle()
                    }
                } label: {
                    Image(systemName: isBenchmarkExpanded ? "chevron.down" : "chevron.up")
                        .foregroundStyle(AppColors.textTertiary)
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("button_benchmarkExpand")
            }

            // Row 2: Decode (hero), Prefill, Memory
            HStack(spacing: AppSpacing.sm) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Decode")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textTertiary)
                    Text(String(format: "%.1f tok/s", info.lastDecodeTokensPerSecond))
                        .font(AppTypography.metric)
                        .foregroundStyle(decodeTier.color)
                        .contentTransition(.numericText())
                }

                benchmarkItem(label: "Prefill", value: String(format: "%.1f tok/s", info.lastPrefillTokensPerSecond))

                memoryIndicator

                Spacer()
            }
        }
    }
    #endif

    // MARK: - Thermal Indicator

    private var thermalIndicator: some View {
        let level = DeviceMetrics.currentThermalLevel
        return HStack(spacing: AppSpacing.xs) {
            Image(systemName: level.symbolName)
                .foregroundStyle(thermalColor(for: level))
            Text(level.label)
                .font(AppTypography.badge)
                .foregroundStyle(thermalColor(for: level))
        }
    }

    private func thermalColor(for level: ThermalLevel) -> Color {
        switch level {
        case .nominal:  return AppColors.success
        case .fair:     return AppColors.warning
        case .serious:  return AppColors.toolCall
        case .critical: return AppColors.danger
        }
    }

    // MARK: - Memory Indicator

    private var memoryIndicator: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("Memory")
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textTertiary)
            Text(DeviceMetrics.formattedAvailableMemory)
                .font(AppTypography.metric)
                .foregroundStyle(AppColors.textSecondary)
        }
    }

    // MARK: - Expanded Metrics Detail

    private func expandedMetricsView(metrics: InferenceMetrics, info: BenchmarkInfo) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Rectangle()
                .fill(AppColors.border)
                .frame(height: 0.5)

            #if os(iOS)
            // iOS: 2-column grid to avoid horizontal overflow on narrow screens
            let columns = [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)]

            // Token latency statistics
            if !metrics.tokenLatenciesMs.isEmpty {
                LazyVGrid(columns: columns, alignment: .leading, spacing: AppSpacing.sm) {
                    statItem(label: "Median", value: String(format: "%.1f ms", metrics.medianTokenLatencyMs))
                    statItem(label: "P95", value: String(format: "%.1f ms", metrics.p95TokenLatencyMs))
                    statItem(label: "Min", value: String(format: "%.1f ms", metrics.minTokenLatencyMs))
                    statItem(label: "Max", value: String(format: "%.1f ms", metrics.maxTokenLatencyMs))
                }
            }

            // Memory delta
            LazyVGrid(columns: columns, alignment: .leading, spacing: AppSpacing.sm) {
                statItem(
                    label: "Mem Start",
                    value: String(format: "%.0f MB", metrics.startSnapshot.availableMemoryMB)
                )
                statItem(
                    label: "Mem End",
                    value: String(format: "%.0f MB", metrics.endSnapshot.availableMemoryMB)
                )
                statItem(
                    label: "Δ Memory",
                    value: String(format: "%+.0f MB", metrics.memoryDeltaMB)
                )
            }

            // Thermal transition
            if metrics.thermalStateChanged {
                HStack(spacing: AppSpacing.xs) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(AppColors.warning)
                    Text("Thermal: \(metrics.startSnapshot.thermalLevel.label) → \(metrics.endSnapshot.thermalLevel.label)")
                        .foregroundStyle(AppColors.textSecondary)
                }
            }

            // Token counts
            LazyVGrid(columns: columns, alignment: .leading, spacing: AppSpacing.sm) {
                statItem(label: "Tokens", value: "\(metrics.totalTokenCount)")
                statItem(label: "Init", value: String(format: "%.2fs", info.initTimeInSecond))
                statItem(label: "Prefill", value: "\(info.lastPrefillTokenCount) tok")
                statItem(label: "Decode", value: "\(info.lastDecodeTokenCount) tok")
            }
            #else
            // Token latency statistics
            if !metrics.tokenLatenciesMs.isEmpty {
                HStack(spacing: AppSpacing.lg) {
                    statItem(label: "Median", value: String(format: "%.1f ms", metrics.medianTokenLatencyMs))
                    statItem(label: "P95", value: String(format: "%.1f ms", metrics.p95TokenLatencyMs))
                    statItem(label: "Min", value: String(format: "%.1f ms", metrics.minTokenLatencyMs))
                    statItem(label: "Max", value: String(format: "%.1f ms", metrics.maxTokenLatencyMs))
                    Spacer()
                }
            }

            // Memory delta
            HStack(spacing: AppSpacing.lg) {
                statItem(
                    label: "Mem Start",
                    value: String(format: "%.0f MB", metrics.startSnapshot.availableMemoryMB)
                )
                statItem(
                    label: "Mem End",
                    value: String(format: "%.0f MB", metrics.endSnapshot.availableMemoryMB)
                )
                statItem(
                    label: "Δ Memory",
                    value: String(format: "%+.0f MB", metrics.memoryDeltaMB)
                )
                Spacer()
            }

            // Thermal transition
            if metrics.thermalStateChanged {
                HStack(spacing: AppSpacing.xs) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(AppColors.warning)
                    Text("Thermal: \(metrics.startSnapshot.thermalLevel.label) → \(metrics.endSnapshot.thermalLevel.label)")
                        .foregroundStyle(AppColors.textSecondary)
                }
            }

            // Token counts
            HStack(spacing: AppSpacing.lg) {
                statItem(label: "Tokens", value: "\(metrics.totalTokenCount)")
                statItem(label: "Init", value: String(format: "%.2fs", info.initTimeInSecond))
                statItem(label: "Prefill", value: "\(info.lastPrefillTokenCount) tok")
                statItem(label: "Decode", value: "\(info.lastDecodeTokenCount) tok")
                Spacer()
            }
            #endif
        }
        .padding(.top, AppSpacing.xs)
    }

    private func statItem(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textTertiary)
            Text(value)
                .font(AppTypography.metric)
                .foregroundStyle(AppColors.textSecondary)
        }
    }

    private func benchmarkItem(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textTertiary)
            Text(value)
                .font(AppTypography.metric)
                .foregroundStyle(AppColors.textSecondary)
        }
    }
}

// MARK: - Vibrant Background

struct VibrantBackgroundView: View {
    var body: some View {
        ZStack {
            // Elegant dark base
            Color(red: 0.03, green: 0.03, blue: 0.05)
            
            // Subtle premium glow (top left)
            RadialGradient(
                gradient: Gradient(colors: [Color.indigo.opacity(0.15), .clear]),
                center: .topLeading,
                startRadius: 0,
                endRadius: 800
            )
            
            // Subtle premium glow (bottom right)
            RadialGradient(
                gradient: Gradient(colors: [Color.teal.opacity(0.1), .clear]),
                center: .bottomTrailing,
                startRadius: 0,
                endRadius: 800
            )
        }
    }
}
