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

import LiteRTLM
import SwiftUI
import UniformTypeIdentifiers
import PhotosUI

// MARK: - Content View

/// The main application view — Edge AI Lab, a premium on-device inference research instrument.
///
/// Architecture:
/// - **macOS**: 3-column `NavigationSplitView` —
///   Sidebar (models/benchmarks/conversations) → Detail (model lab/dashboard) → Content (chat).
/// - **iOS**: `TabView` with 3 tabs (Chat, Models, Lab) — adapting the same components
///   for a mobile-first layout.
///
/// Dark Forest / Moss palette. "A cabin with a terminal."
///
/// Decomposed into focused child views:
/// - `SidebarView` — Model list, benchmarks, conversations sidebar
/// - `DetailColumnView` — Model detail panel / performance dashboard
/// - `ConversationAreaView` — Chat bubbles and empty state
/// - `BenchmarkBarView` — Performance metrics bar
/// - `InputAreaView` — Prompt field, send button, attachments
/// - `StatusBarView` — macOS-only status bar
///
/// Accessibility: Every interactive element has `.accessibilityIdentifier`
/// for agent discoverability and UI testing.
struct ContentView: View {
    @Environment(ConversationViewModel.self) private var viewModel
    #if os(iOS)
    @Environment(iOSNavigationRouter.self) private var navigationRouter
    #endif
    @State private var showSettings = false
    @State private var showDashboard = false
    @State private var showcaseModel: ModelMetadata?
    @State private var showcaseModelURL: URL?

    // NavigationSplitView state
    @State private var selectedSection: SidebarSection?
    @State private var selectedModelId: String?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all


    var body: some View {
        @Bindable var viewModel = viewModel
        #if os(macOS)
        macOSLayout
        #else
        iOSLayout
        #endif
    }

    // MARK: - macOS 3-Column Layout

    #if os(macOS)
    private var macOSLayout: some View {
        appliedSharedModifiers(
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // Left column: Sidebar
            SidebarView(
                selectedSection: $selectedSection,
                selectedModelId: $selectedModelId,
                showcaseModel: $showcaseModel,
                showcaseModelURL: $showcaseModelURL
            )
        } content: {
            // Middle column: Detail (model info / dashboard / comparison)
            DetailColumnView(
                selectedSection: $selectedSection,
                selectedModelId: $selectedModelId
            )
        } detail: {
            // Right column: Chat area — the instrument
            chatColumn
        }
        .navigationSplitViewStyle(.balanced)
        .foregroundStyle(AppColors.textPrimary)
        .preferredColorScheme(.dark)
        .navigationTitle(viewModel.activeModelMetadata?.name ?? "Edge AI Lab")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .help("Settings")
                .accessibilityIdentifier("button_settings")
                .accessibilityLabel("Settings")

                Button {
                    viewModel.refreshDiscoveredModels()
                    viewModel.downloadManager.refreshStates()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh discovered models")
                .accessibilityIdentifier("button_refresh")
                .accessibilityLabel("Refresh models")

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
        .onReceive(NotificationCenter.default.publisher(for: .newChatRequested)) { _ in
            Task { await viewModel.newConversation() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showDashboardRequested)) { _ in
            selectedSection = .benchmarks
        }
        .onReceive(NotificationCenter.default.publisher(for: .showEvaluationsRequested)) { _ in
            selectedSection = .evaluations
        }
        .onReceive(NotificationCenter.default.publisher(for: .refreshModelsRequested)) { _ in
            viewModel.refreshDiscoveredModels()
            viewModel.downloadManager.refreshStates()
        }
        .onReceive(NotificationCenter.default.publisher(for: .loadModelRequested)) { _ in
            viewModel.isFilePickerPresented = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .showSettingsRequested)) { _ in
            showSettings = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .importModelRequested)) { _ in
            viewModel.showURLImportSheet = true
        }
        )
    }
    #endif

    // MARK: - iOS Tab Layout

    #if os(iOS)
    private var iOSLayout: some View {
        @Bindable var router = navigationRouter
        return appliedSharedModifiers(
        TabView(selection: $router.selectedTab) {
            // Tab 1: Models (primary — the Model Hub)
            NavigationStack(path: $router.modelsPath) {
                iOSModelHubView()
                    .navigationTitle("Models")
                    .navigationBarTitleDisplayMode(.large)
            }
            .tabItem {
                Label("Models", systemImage: "cpu")
            }
            .tag(AppTab.models)

            // Tab 2: Chat (inference)
            NavigationStack {
                iOSChatTabView()
                    .navigationTitle("Chat")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem {
                Label("Chat", systemImage: "bubble.left.and.bubble.right")
            }
            .tag(AppTab.chat)

            // Tab 3: Evaluations
            NavigationStack {
                iOSEvalTabView()
                    .navigationTitle("Evaluations")
                    .navigationBarTitleDisplayMode(.large)
            }
            .tabItem {
                Label("Evals", systemImage: "testtube.2")
            }
            .tag(AppTab.evaluations)

            // Tab 4: Settings
            NavigationStack {
                InferenceSettingsView(viewModel: viewModel)
                    .navigationTitle("Settings")
                    .navigationBarTitleDisplayMode(.large)
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
            .tag(AppTab.settings)
        }
        .foregroundStyle(AppColors.textPrimary)
        .preferredColorScheme(.dark)
        .tint(AppColors.accentCyan)
        )
    }
    #endif

    // MARK: - Chat Column (Shared)

    /// The chat column — used as the right column on macOS and the first tab on iOS.
    /// Contains the conversation area, benchmark bar, input area, and status bar.
    private var chatColumn: some View {
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
            .accessibilityElement(children: .contain)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("chatColumn_root")
    }
}


// MARK: - Shared Modifiers (applied via extension)

extension ContentView {
    /// Applies shared modifiers (sheets, alerts, onAppear, file importer) to the layout view.
    @ViewBuilder
    func appliedSharedModifiers<V: View>(_ base: V) -> some View {
        @Bindable var viewModel = viewModel
        base
            .sheet(isPresented: $showSettings) {
                NavigationStack {
                    InferenceSettingsView(viewModel: viewModel)
                        .navigationTitle("Settings")
                        #if os(macOS)
                        .frame(minWidth: 550, minHeight: 600)
                        #endif
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { showSettings = false }
                                    .accessibilityIdentifier("button_doneSettings")
                            }
                        }
                }
            }
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
                Button("Open Settings") {
                    viewModel.downloadManager.showTokenPrompt = false
                    showSettings = true
                }
                Button("Cancel", role: .cancel) {
                    viewModel.downloadManager.showTokenPrompt = false
                }
            }
            #if os(macOS)
            .sheet(isPresented: Binding(
                get: { viewModel.showURLImportSheet },
                set: { viewModel.showURLImportSheet = $0 }
            )) {
                macOSURLImportSheet()
                    .environment(viewModel)
            }
            #endif
            .task {
                // Skip auto-loading when running under the test harness or developer automation —
                // tests manage their own engine lifecycle.
                guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil,
                      !CommandLine.arguments.contains("-DisableAnimations"),
                      !CommandLine.arguments.contains("-RunAutomationHarness"),
                      !CommandLine.arguments.contains("-RunAllTests"),
                      !CommandLine.arguments.contains("-RunMatrixBenchmark"),
                      !CommandLine.arguments.contains("-RunEvalPipeline"),
                      !CommandLine.arguments.contains("-RunBenchmarkPipeline"),
                      !CommandLine.arguments.contains("-RunValidation"),
                      !CommandLine.arguments.contains("-RunFlow"),
                      !CommandLine.arguments.contains("-RunAllFlows") else {
                    viewModel.downloadManager.refreshStates()
                    DeveloperAutomationHarness.runIfRequested(viewModel: viewModel)
                    return
                }
                viewModel.checkForLocalModels()
                viewModel.downloadManager.refreshStates()
            }
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

// MARK: - Reusable Views

struct ModelCapabilityBadges: View {
    let metadata: ModelMetadata
    let experimentalFlags: ExperimentalFlagsState
    
    var body: some View {
        HStack(spacing: AppSpacing.xs) {
            if metadata.supportsImage {
                Text("Vision")
                    .badge(AppColors.badgeVision)
                    .accessibilityIdentifier("badge_vision")
                    .accessibilityLabel("Vision capability")
            }
            if metadata.supportsAudio {
                Text("Audio")
                    .badge(AppColors.badgeAudio)
                    .accessibilityIdentifier("badge_audio")
                    .accessibilityLabel("Audio capability")
            }
            if metadata.supportsMTP {
                Text("MTP")
                    .badge(AppColors.badgeMTP)
                    .accessibilityIdentifier("badge_mtp")
                    .accessibilityLabel("Multi-turn planning capability")
            }
            if experimentalFlags.enableToolCalling {
                Text("Tools")
                    .badge(AppColors.toolCall)
                    .accessibilityIdentifier("badge_tools")
                    .accessibilityLabel("Tool calling capability")
            }
            if experimentalFlags.enableThinking {
                Text("Thinking")
                    .badge(AppColors.badgeThinking)
                    .accessibilityIdentifier("badge_thinking")
                    .accessibilityLabel("Thinking mode capability")
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
            // Deep forest floor — the darkest layer
            AppColors.backgroundPrimary
            
            // Moonlight through canopy (top left) — subtle moss green
            RadialGradient(
                gradient: Gradient(colors: [AppColors.accentTeal.opacity(0.10), .clear]),
                center: .topLeading,
                startRadius: 0,
                endRadius: 800
            )
            
            // Distant firelight (bottom right) — warm amber glow
            RadialGradient(
                gradient: Gradient(colors: [AppColors.accentGold.opacity(0.06), .clear]),
                center: .bottomTrailing,
                startRadius: 0,
                endRadius: 800
            )
        }
    }
}
