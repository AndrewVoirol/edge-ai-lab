import LiteRTLM
import SwiftUI
import UniformTypeIdentifiers
import PhotosUI

struct ContentView: View {
    @State private var viewModel = ConversationViewModel()
    @State private var showSettings = false
    @State private var isBenchmarkExpanded = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showAudioPicker = false
    @State private var scrollProxy: ScrollViewProxy?
    @Namespace private var bottomAnchor

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
                .padding()

            Divider()

            // Model management section (discovered + downloadable)
            modelManagementSection
            Divider()

            // Prompt input with multimodal attachment strip
            VStack(spacing: 8) {
                // Multimodal attachment preview
                if viewModel.hasMultimodalAttachment {
                    multimodalAttachmentStrip
                }

                HStack(spacing: 8) {
                    // Image attachment button (only for image-capable models)
                    if viewModel.supportsImageInput {
                        PhotosPicker(
                            selection: $selectedPhotoItem,
                            matching: .images,
                            photoLibrary: .shared()
                        ) {
                            Image(systemName: "photo.badge.plus")
                                .foregroundStyle(selectedPhotoItem != nil ? .blue : .secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Attach an image")
                    }

                    // Audio attachment button (only for audio-capable models)
                    if viewModel.supportsAudioInput {
                        Button {
                            showAudioPicker = true
                        } label: {
                            Image(systemName: "waveform.badge.plus")
                                .foregroundStyle(viewModel.selectedAudioData != nil ? .blue : .secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Attach an audio file")
                    }

                    TextField("Enter your prompt here", text: $viewModel.prompt)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            guard viewModel.isEngineReady && !viewModel.isGenerating else { return }
                            Task { await viewModel.generateText() }
                        }
                }
            }
            .padding()

            // Action bar: Generate + New Conversation
            HStack(spacing: 12) {
                Button {
                    Task { await viewModel.generateText() }
                } label: {
                    HStack(spacing: 4) {
                        if viewModel.isGenerating {
                            ProgressView()
                                .controlSize(.small)
                            Text("Generating...")
                        } else {
                            Image(systemName: "paperplane.fill")
                            Text("Send")
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.isEngineReady || viewModel.isGenerating)

                if !viewModel.conversation.isEmpty {
                    Button {
                        Task { await viewModel.newConversation() }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus.bubble")
                            Text("New Chat")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.isGenerating)
                }

                // Thinking mode indicator
                if viewModel.isThinking {
                    HStack(spacing: 4) {
                        Image(systemName: "brain.head.profile")
                            .symbolEffect(.pulse)
                            .foregroundStyle(.purple)
                        Text("Thinking...")
                            .font(.caption)
                            .foregroundStyle(.purple)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 4)

            // Conversation area — chat bubbles
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
                    .padding(.vertical, 8)
                }
                .frame(maxHeight: .infinity)
                .onChange(of: viewModel.conversation.messages.count) { _, _ in
                    withAnimation(.easeOut(duration: 0.3)) {
                        proxy.scrollTo("conversationBottom", anchor: .bottom)
                    }
                }
                .onChange(of: viewModel.responseText) { _, _ in
                    // Scroll during streaming too
                    proxy.scrollTo("conversationBottom", anchor: .bottom)
                }
                .onAppear { scrollProxy = proxy }
            }

            // Benchmark bar (shown when data is available)
            if viewModel.experimentalFlags.enableBenchmark, let info = viewModel.benchmarkInfo {
                Divider()
                benchmarkBar(info: info)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
            }
        }
        .padding()
        .fileImporter(
            isPresented: $viewModel.isFilePickerPresented,
            allowedContentTypes: [UTType.data],
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
        .fileImporter(
            isPresented: $showAudioPicker,
            allowedContentTypes: [UTType.audio],
            allowsMultipleSelection: false
        ) { result in
            if let url = try? result.get().first {
                viewModel.selectedAudioData = try? Data(contentsOf: url)
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
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            Text(viewModel.statusMessage)
                .font(.headline)

            // Capability badges for loaded model
            if let metadata = viewModel.activeModelMetadata {
                HStack(spacing: 4) {
                    if metadata.supportsImage {
                        Image(systemName: "photo")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                            .help("Image input supported")
                    }
                    if metadata.supportsAudio {
                        Image(systemName: "waveform")
                            .font(.caption2)
                            .foregroundStyle(.purple)
                            .help("Audio input supported")
                    }
                    if metadata.supportsMTP {
                        Image(systemName: "hare")
                            .font(.caption2)
                            .foregroundStyle(.green)
                            .help("Multi-Token Prediction supported")
                    }
                    if viewModel.experimentalFlags.enableToolCalling {
                        Image(systemName: "wrench.and.screwdriver")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                            .help("Tool calling enabled (\(ToolRegistry.defaultTools.count) tools)")
                    }
                    if viewModel.experimentalFlags.enableThinking {
                        Image(systemName: "brain.head.profile")
                            .font(.caption2)
                            .foregroundStyle(.purple)
                            .help("Thinking mode enabled")
                    }
                }
            }

            Spacer()
            Button {
                viewModel.refreshDiscoveredModels()
                viewModel.downloadManager.refreshStates()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Refresh discovered models")
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
            .help("Inference Settings")
            Button("Load Model") {
                viewModel.isFilePickerPresented = true
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Model Management (Discovered + Downloadable)

    private var modelManagementSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Models")
                .font(.subheadline)
                .fontWeight(.semibold)
                .padding(.horizontal)
                .padding(.top, 8)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    // On-disk discovered models
                    ForEach(viewModel.discoveredModels) { model in
                        discoveredModelCard(model)
                    }

                    // Registry models not yet on disk (downloadable)
                    ForEach(downloadableModels) { model in
                        downloadableModelCard(model)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
        }
    }

    /// Registry models that are not yet discovered on disk.
    private var downloadableModels: [ModelMetadata] {
        let discoveredFilenames = Set(viewModel.discoveredModels.map(\.filename))
        return ModelRegistry.knownModels.filter { !discoveredFilenames.contains($0.modelFile) }
    }

    // MARK: - Model Cards

    private func discoveredModelCard(_ model: DiscoveredModel) -> some View {
        Button {
            Task {
                await viewModel.handleModelSelection(model.url)
            }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(model.metadata?.name ?? model.filename)
                        .font(.caption)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    if model.source == .edgeGallery {
                        Text("Gallery")
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(.blue.opacity(0.15))
                            .foregroundStyle(.blue)
                            .clipShape(Capsule())
                    }
                }
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption2)
                    Text(model.formattedSize)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.quaternary.opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private func downloadableModelCard(_ model: ModelMetadata) -> some View {
        let state = viewModel.downloadManager.downloadStates[model.modelFile] ?? .notDownloaded

        return VStack(alignment: .leading, spacing: 4) {
            Text(model.name)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(1)

            switch state {
            case .notDownloaded:
                Button {
                    viewModel.downloadManager.download(model)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.circle")
                        Text(ByteCountFormatter.string(fromByteCount: model.sizeInBytes, countStyle: .file))
                            .font(.caption2)
                    }
                    .font(.caption2)
                    .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)

            case .downloading(let progress):
                VStack(alignment: .leading, spacing: 2) {
                    ProgressView(value: progress)
                        .frame(width: 80)
                    HStack {
                        Text("\(Int(progress * 100))%")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            viewModel.downloadManager.cancelDownload(model)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }

            case .downloaded:
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption2)
                    Text("Ready")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

            case .failed(let message):
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.caption2)
                    Text(message)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .lineLimit(1)
                }

            case .authRequired:
                Button {
                    viewModel.downloadManager.showTokenPrompt = true
                    viewModel.downloadManager.pendingAuthModel = model
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "lock.fill")
                        Text("Auth required")
                    }
                    .font(.caption2)
                    .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.quaternary.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(.quaternary, lineWidth: 1)
        )
    }

    // MARK: - Multimodal Attachment Strip

    private var multimodalAttachmentStrip: some View {
        HStack(spacing: 8) {
            if let imageData = viewModel.selectedImageData {
                HStack(spacing: 4) {
                    #if os(iOS)
                    if let uiImage = UIImage(data: imageData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 32, height: 32)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    #elseif os(macOS)
                    if let nsImage = NSImage(data: imageData) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 32, height: 32)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    #endif
                    Text("Image attached")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Button {
                        viewModel.selectedImageData = nil
                        selectedPhotoItem = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
                .padding(4)
                .background(.quaternary.opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            if viewModel.selectedAudioData != nil {
                HStack(spacing: 4) {
                    Image(systemName: "waveform")
                        .foregroundStyle(.purple)
                        .font(.caption)
                    Text("Audio attached")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Button {
                        viewModel.selectedAudioData = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
                .padding(4)
                .background(.quaternary.opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: 6))
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
        VStack(spacing: 4) {
            // Compact bar (always visible)
            HStack(spacing: 12) {
                // Backend indicator
                if let result = viewModel.backendResult {
                    HStack(spacing: 4) {
                        Image(systemName: result.activeBackend == .gpu ? "bolt.fill" : "cpu")
                            .foregroundStyle(result.activeBackend == .gpu ? .green : .orange)
                        Text(result.activeBackend == .gpu ? "GPU" : "CPU")
                            .fontWeight(.semibold)
                    }
                    Divider().frame(height: 20)
                }

                // Thermal state indicator
                thermalIndicator

                Divider().frame(height: 20)

                benchmarkItem(label: "TTFT", value: String(format: "%.3fs", info.timeToFirstTokenInSecond))
                Divider().frame(height: 20)
                benchmarkItem(label: "Decode", value: String(format: "%.1f tok/s", info.lastDecodeTokensPerSecond))
                Divider().frame(height: 20)
                benchmarkItem(label: "Prefill", value: String(format: "%.1f tok/s", info.lastPrefillTokensPerSecond))

                // Memory indicator
                Divider().frame(height: 20)
                memoryIndicator

                Spacer()

                // Expand/collapse button
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isBenchmarkExpanded.toggle()
                    }
                } label: {
                    Image(systemName: isBenchmarkExpanded ? "chevron.down" : "chevron.up")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            // Fallback warning
            if let result = viewModel.backendResult, result.didFallback, let reason = result.fallbackReason {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                    Text(reason)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }

            // Expanded detail view
            if isBenchmarkExpanded, let metrics = viewModel.inferenceMetrics {
                expandedMetricsView(metrics: metrics, info: info)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .font(.caption)
    }

    // MARK: - Thermal Indicator

    private var thermalIndicator: some View {
        let level = DeviceMetrics.currentThermalLevel
        return HStack(spacing: 4) {
            Image(systemName: level.symbolName)
                .foregroundStyle(thermalColor(for: level))
            Text(level.label)
                .fontWeight(.medium)
        }
    }

    private func thermalColor(for level: ThermalLevel) -> Color {
        switch level {
        case .nominal:  return .green
        case .fair:     return .yellow
        case .serious:  return .orange
        case .critical: return .red
        }
    }

    // MARK: - Memory Indicator

    private var memoryIndicator: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Memory")
                .foregroundStyle(.secondary)
            Text(DeviceMetrics.formattedAvailableMemory)
                .monospacedDigit()
                .fontWeight(.medium)
        }
    }

    // MARK: - Expanded Metrics Detail

    private func expandedMetricsView(metrics: InferenceMetrics, info: BenchmarkInfo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()

            // Token latency statistics
            if !metrics.tokenLatenciesMs.isEmpty {
                HStack(spacing: 16) {
                    statItem(label: "Median", value: String(format: "%.1f ms", metrics.medianTokenLatencyMs))
                    statItem(label: "P95", value: String(format: "%.1f ms", metrics.p95TokenLatencyMs))
                    statItem(label: "Min", value: String(format: "%.1f ms", metrics.minTokenLatencyMs))
                    statItem(label: "Max", value: String(format: "%.1f ms", metrics.maxTokenLatencyMs))
                    Spacer()
                }
            }

            // Memory delta
            HStack(spacing: 16) {
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
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Thermal: \(metrics.startSnapshot.thermalLevel.label) → \(metrics.endSnapshot.thermalLevel.label)")
                }
            }

            // Token counts
            HStack(spacing: 16) {
                statItem(label: "Tokens", value: "\(metrics.totalTokenCount)")
                statItem(label: "Init", value: String(format: "%.2fs", info.initTimeInSecond))
                statItem(label: "Prefill", value: "\(info.lastPrefillTokenCount) tok")
                statItem(label: "Decode", value: "\(info.lastDecodeTokenCount) tok")
                Spacer()
            }
        }
        .font(.caption2)
        .padding(.top, 4)
    }

    private func statItem(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .monospacedDigit()
                .fontWeight(.medium)
        }
    }

    private func benchmarkItem(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .monospacedDigit()
                .fontWeight(.medium)
        }
    }
}
