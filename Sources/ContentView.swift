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
/// Decomposed into focused child views:
/// - `ModelStripView` — Discovered + downloadable model cards
/// - `ConversationAreaView` — Chat bubbles and empty state
/// - `BenchmarkBarView` — Performance metrics bar
/// - `InputAreaView` — Prompt field, send button, attachments
/// - `StatusBarView` — macOS-only status bar
///
/// Accessibility: Every interactive element has `.accessibilityIdentifier`
/// for agent discoverability and UI testing.
struct ContentView: View {
    @Bindable private var viewModel = ConversationViewModel.shared
    @State private var showSettings = false
    @State private var showDashboard = false
    @State private var showcaseModel: ModelMetadata?
    @State private var showcaseModelURL: URL?

    var body: some View {
        ZStack {
            // Full-bleed vibrant animated background for premium feel
            VibrantBackgroundView()
                .ignoresSafeArea()
                .overlay(.black.opacity(0.2)) // Subtle dimming so glass cards pop
            VStack(spacing: 0) {
                #if os(iOS)
                // Header bar
                headerView
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.vertical, AppSpacing.sm)

                // Subtle separator
                Rectangle()
                    .fill(AppColors.border)
                    .frame(height: 0.5)
                #endif

                // Model card strip
                ModelStripView(
                    showcaseModel: $showcaseModel,
                    showcaseModelURL: $showcaseModelURL
                )

                Rectangle()
                    .fill(AppColors.border)
                    .frame(height: 0.5)

                // Conversation area — chat bubbles
                ConversationAreaView()
                    .frame(maxHeight: .infinity)

                // Benchmark bar (shown when data is available)
                if viewModel.experimentalFlags.enableBenchmark, let info = viewModel.benchmarkInfo {
                    Rectangle()
                        .fill(AppColors.border)
                        .frame(height: 0.5)
                    BenchmarkBarView(info: info)
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
                InputAreaView()
                    #if os(iOS)
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.vertical, AppSpacing.sm)
                    #else
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.vertical, AppSpacing.md)
                    #endif
                    
                #if os(macOS)
                Rectangle()
                    .fill(AppColors.border)
                    .frame(height: 0.5)
                StatusBarView()
                #endif
            }
        }
        .foregroundStyle(AppColors.textPrimary)
        #if os(iOS)
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                InferenceSettingsView(viewModel: viewModel)
                    .navigationTitle("Settings")
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showSettings = false }
                                .accessibilityIdentifier("button_doneSettings")
                        }
                    }
            }
        }
        #endif
        .sheet(isPresented: $showDashboard) {
            NavigationStack {
                PerformanceDashboardView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showDashboard = false }
                                .accessibilityIdentifier("button_doneDashboard")
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
        #if os(macOS)
        .navigationTitle(viewModel.activeModelMetadata?.name ?? "Edge AI Lab")
        .onReceive(NotificationCenter.default.publisher(for: .newChatRequested)) { _ in
            Task { await viewModel.newConversation() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showDashboardRequested)) { _ in
            showDashboard = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .refreshModelsRequested)) { _ in
            viewModel.refreshDiscoveredModels()
            viewModel.downloadManager.refreshStates()
        }
        .onReceive(NotificationCenter.default.publisher(for: .loadModelRequested)) { _ in
            viewModel.isFilePickerPresented = true
        }
        #endif
        #if os(macOS)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if #available(macOS 13.0, *) {
                    SettingsLink {
                        Image(systemName: "gearshape")
                    }
                    .help("Settings")
                    .accessibilityIdentifier("button_settings")
                }
                Button {
                    viewModel.refreshDiscoveredModels()
                    viewModel.downloadManager.refreshStates()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh discovered models")
                .accessibilityIdentifier("button_refresh")
                
                Button {
                    showDashboard = true
                } label: {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                }
                .help("Performance Dashboard")
                .accessibilityIdentifier("button_dashboard")
                
                Button {
                    viewModel.isFilePickerPresented = true
                } label: {
                    Image(systemName: "plus.square")
                    Text("Load Model")
                }
                .help("Load a custom model from disk")
                .accessibilityIdentifier("button_loadModel")
            }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url = url,
                      url.pathExtension == "litertlm" else { return }
                Task { @MainActor in
                    await viewModel.handleModelSelection(url)
                }
            }
            return true
        }
        #endif
    }

    // MARK: - Header (iOS)

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

                // Capability badges are now displayed directly on the model cards
                // inside the ModelStripView to ensure they are visible on both iOS and macOS.
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
            }
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
}

// MARK: - Reusable Views

struct ModelCapabilityBadges: View {
    let metadata: ModelMetadata
    let experimentalFlags: ExperimentalFlagsState
    
    var body: some View {
        HStack(spacing: AppSpacing.xs) {
            if metadata.supportsImage {
                Text("Vision")
                    .badge(AppColors.accentCyan)
                    .accessibilityIdentifier("badge_vision")
            }
            if metadata.supportsAudio {
                Text("Audio")
                    .badge(AppColors.accentTeal)
                    .accessibilityIdentifier("badge_audio")
            }
            if metadata.supportsMTP {
                Text("MTP")
                    .badge(AppColors.success)
                    .accessibilityIdentifier("badge_mtp")
            }
            if experimentalFlags.enableToolCalling {
                Text("Tools")
                    .badge(AppColors.toolCall)
                    .accessibilityIdentifier("badge_tools")
            }
            if experimentalFlags.enableThinking {
                Text("Thinking")
                    .badge(AppColors.thinking)
                    .accessibilityIdentifier("badge_thinking")
            }
        }
    }
}

// MARK: - Previews

#Preview {
    ContentView()
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
