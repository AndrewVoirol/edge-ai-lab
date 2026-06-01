import LiteRTLM
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var viewModel = ConversationViewModel()
    @State private var showSettings = false
    @State private var isBenchmarkExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
                .padding()

            Divider()

            // Model management section (discovered + downloadable)
            modelManagementSection
            Divider()

            // Prompt input
            TextField("Enter your prompt here", text: $viewModel.prompt)
                .textFieldStyle(.roundedBorder)
                .padding()

            // Generate button
            Button(viewModel.isGenerating ? "Generating..." : "Generate Response") {
                Task {
                    await viewModel.generateText()
                }
            }
            .buttonStyle(.bordered)
            .disabled(!viewModel.isEngineReady || viewModel.isGenerating)

            // Response area
            ScrollView {
                Text(viewModel.responseText)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: .infinity)

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
        .onAppear {
            // Skip auto-loading when running under the test harness —
            // tests manage their own engine lifecycle.
            guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
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
        let state = viewModel.downloadManager.checkState(for: model)

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
