import LiteRTLM
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var viewModel = ConversationViewModel()
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
                .padding()

            Divider()

            // Discovered models (shown when models are available)
            if !viewModel.discoveredModels.isEmpty {
                discoveredModelsSection
                Divider()
            }

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
        .onAppear {
            // Skip auto-loading when running under the test harness —
            // tests manage their own engine lifecycle.
            guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
                return
            }
            viewModel.checkForLocalModels()
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

    // MARK: - Discovered Models

    private var discoveredModelsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Available Models")
                .font(.subheadline)
                .fontWeight(.semibold)
                .padding(.horizontal)
                .padding(.top, 8)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(viewModel.discoveredModels) { model in
                        modelCard(model)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
        }
    }

    private func modelCard(_ model: DiscoveredModel) -> some View {
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
                Text(model.formattedSize)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.quaternary.opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Benchmark Bar

    private func benchmarkBar(info: BenchmarkInfo) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 16) {
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

                benchmarkItem(label: "TTFT", value: String(format: "%.3fs", info.timeToFirstTokenInSecond))
                Divider().frame(height: 20)
                benchmarkItem(label: "Decode", value: String(format: "%.1f tok/s", info.lastDecodeTokensPerSecond))
                Divider().frame(height: 20)
                benchmarkItem(label: "Prefill", value: String(format: "%.1f tok/s", info.lastPrefillTokensPerSecond))
                Spacer()
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
        }
        .font(.caption)
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
