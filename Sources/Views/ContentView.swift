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

import LiteRTLM
import SwiftUI
import UniformTypeIdentifiers
import PhotosUI

// MARK: - Content View

/// The main application view — Edge AI Lab, a premium on-device inference research instrument.
///
/// Architecture:
/// - **macOS**: 2-column `NavigationSplitView` —
///   Sidebar (models/benchmarks/conversations) → Detail (model lab/dashboard + chat panel).
///   The sidebar collapses via the built-in `NavigationSplitView` mechanism.
///   The chat panel collapses independently via a custom `isChatCollapsed` toggle.
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
    #if os(macOS)
    /// Whether the chat panel (right column) is collapsed.
    @State private var isChatCollapsed = false
    /// Persisted chat panel width (macOS only).
    @AppStorage("chatPanelWidth") private var chatPanelWidth: Double = 420
    /// Width snapshot at drag start for computing absolute position from gesture deltas.
    @State private var chatWidthAtDragStart: Double = 420
    #endif


    var body: some View {
        @Bindable var viewModel = viewModel
        #if os(macOS)
        macOSLayout
        #else
        iOSLayout
        #endif
    }

    // MARK: - macOS 2-Column Layout (Sidebar + Detail/Chat)

    #if os(macOS)
    private var macOSLayout: some View {
        appliedSharedModifiers(
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // Left column: Sidebar (collapse handled by built-in NavigationSplitView toggle)
            SidebarView(
                selectedSection: $selectedSection,
                selectedModelId: $selectedModelId,
                showcaseModel: $showcaseModel,
                showcaseModelURL: $showcaseModelURL
            )
        } detail: {
            // Detail area: middle panel + chat panel side-by-side
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    // Middle: Detail (model info / dashboard / comparison)
                    DetailColumnView(
                        selectedSection: $selectedSection,
                        selectedModelId: $selectedModelId
                    )
                    .frame(minWidth: 300)

                    // Right: Chat panel (collapsible independently)
                    if !isChatCollapsed {
                        PanelResizeHandle(
                            onDragStart: {
                                chatWidthAtDragStart = chatPanelWidth
                            },
                            onDragChanged: { delta in
                                let availableWidth = geometry.size.width
                                let minChat: CGFloat = 300
                                let minDetail: CGFloat = 300
                                let maxChat = availableWidth - minDetail - 8
                                // Dragging left (negative delta) grows the chat panel
                                let newWidth = chatWidthAtDragStart - delta
                                chatPanelWidth = max(minChat, min(newWidth, maxChat))
                            }
                        )

                        HStack(spacing: 0) {
                            chatColumn
                            // Canvas side panel — trailing, only visible when content is active
                            if viewModel.activeCanvasContent != nil {
                                Rectangle()
                                    .fill(AppColors.border)
                                    .frame(width: 0.5)
                                CanvasPanelView()
                            }
                        }
                        .frame(width: chatPanelWidth)
                    }
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .navigationTitle(viewModel.activeModelMetadata?.name ?? "Edge AI Lab")
        .toolbar {
            // Settings — isolated on the left of the primary action area
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .help("Settings")
                .accessibilityIdentifier("button_settings")
                .accessibilityLabel("Settings")
            }

            ToolbarSpacer(.fixed)

            // Model actions — grouped together under a shared glass capsule
            ToolbarItemGroup(placement: .primaryAction) {
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
                }
                .help("Load a custom model from disk")
                .accessibilityIdentifier("button_loadModel")
                .accessibilityLabel("Load Model")
            }

            ToolbarSpacer(.fixed)

            // Chat panel toggle — isolated on the right
            ToolbarItem(placement: .primaryAction) {
                Button {
                    withAnimation(AppAnimation.standard) {
                        isChatCollapsed.toggle()
                    }
                } label: {
                    Image(systemName: "sidebar.right")
                }
                .help(isChatCollapsed ? "Show chat panel" : "Hide chat panel")
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .accessibilityIdentifier("button_toggleChatPanel")
                .accessibilityLabel(isChatCollapsed ? "Show chat panel" : "Hide chat panel")
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
        .onReceive(NotificationCenter.default.publisher(for: .toggleCanvasRequested)) { _ in
            withAnimation(AppAnimation.standard) {
                if viewModel.activeCanvasContent != nil {
                    viewModel.activeCanvasContent = nil
                }
            }
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

            // Tab 4: Lab (Benchmarks / Performance Dashboard)
            iOSLabTabView()
            .tabItem {
                Label("Lab", systemImage: "chart.line.uptrend.xyaxis")
            }
            .tag(AppTab.lab)

            // Tab 5: Settings
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
        .tint(AppColors.accentCyan)
        .sheet(item: Binding(
            get: { viewModel.activeCanvasContent },
            set: { viewModel.activeCanvasContent = $0 }
        )) { _ in
            NavigationStack {
                CanvasPanelView()
                    .navigationTitle("Canvas")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .presentationDetents([.medium, .large])
        }
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
                if viewModel.runtimeFlags.enableBenchmark, let metrics = viewModel.performanceMetrics {
                    Rectangle()
                        .fill(AppColors.border)
                        .frame(height: 0.5)
                    BenchmarkBarView(metrics: metrics)
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

                // Agent status banner (visible when agent mode is active)
                if viewModel.isAgentMode,
                   viewModel.agentHarness.isRunning
                    || viewModel.agentHarness.status != .idle {
                    AgentStatusView(harness: viewModel.agentHarness)
                        #if os(iOS)
                        .padding(.horizontal, AppSpacing.md)
                        .padding(.vertical, AppSpacing.xs)
                        #else
                        .padding(.horizontal, AppSpacing.lg)
                        .padding(.vertical, AppSpacing.sm)
                        #endif
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .animation(.easeInOut(duration: 0.3), value: viewModel.agentHarness.isRunning)
                }

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
            // Agent approval sheet — presented when harness awaits user decision
            .sheet(isPresented: Binding<Bool>(
                get: {
                    if case .waitingForApproval = viewModel.agentHarness.status { return true }
                    return false
                },
                set: { newValue in
                    if !newValue {
                        viewModel.agentHarness.denyAction()
                    }
                }
            )) {
                if case .waitingForApproval(let tool, let args) = viewModel.agentHarness.status {
                    AgentApprovalView(
                        toolName: tool,
                        arguments: args,
                        onApprove: { viewModel.agentHarness.approveAction() },
                        onDeny: { viewModel.agentHarness.denyAction() },
                        autoApproveAll: Binding(
                            get: { viewModel.agentHarness.autoApproveAll },
                            set: { viewModel.agentHarness.autoApproveAll = $0 }
                        )
                    )
                }
            }
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
                .accessibilityIdentifier("button_alertOpenSettings")
                Button("Cancel", role: .cancel) {
                    viewModel.downloadManager.showTokenPrompt = false
                }
                .accessibilityIdentifier("button_alertTokenCancel")
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
    let runtimeFlags: RuntimeFlags
    
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
            if runtimeFlags.enableToolCalling {
                Text("Tools")
                    .badge(AppColors.toolCall)
                    .accessibilityIdentifier("badge_tools")
                    .accessibilityLabel("Tool calling capability")
            }
            if runtimeFlags.enableThinking {
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

/// Atmospheric background for content areas (chat, lab, onboarding).
///
/// ## Liquid Glass Compatibility
/// Uses the system background as the base layer instead of an opaque custom color.
/// This lets navigation chrome (sidebar, toolbar, tab bar) render glass effects
/// correctly while preserving the forest/moss atmospheric gradient overlays.
///
/// In dark mode: visually similar to the original (system dark bg ≈ near-black).
/// In light mode: gradients tint the system background subtly.
struct VibrantBackgroundView: View {
    var body: some View {
        ZStack {
            // System background — respects light/dark mode, glass-compatible
            #if os(iOS)
            Color(.systemBackground)
            #else
            Color(.windowBackgroundColor)
            #endif

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
