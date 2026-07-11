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

/// EdgeAILab — Edge AI Lab for iOS & macOS.
///
/// Powered by LiteRT-LM v0.13. Runs Gemma 4 E2B, E4B, and 12B models
/// entirely on-device with Metal GPU acceleration. Features tool calling,
/// thinking mode, multimodal input, and deep performance instrumentation.
///
/// Layout:
/// - macOS: 3-column NavigationSplitView (Sidebar → Model Lab → Chat)
/// - iOS: TabView (Models / Chat / Settings) with background download support
///
/// "A cabin with a terminal. Frosted glass in a forest."
@main
struct EdgeAILabApp: App {
    @State private var downloadManager: ModelDownloadManager
    @State private var viewModel: ConversationViewModel
    @State private var showOnboarding = false

    #if os(iOS)
    @State private var navigationRouter = iOSNavigationRouter()
    #endif

    /// Static reference for AppDelegate's background session callback.
    /// This is NOT a singleton — it's the App's owned dependency shared
    /// with UIKit-era code that can't participate in SwiftUI's environment.
    nonisolated(unsafe) static var activeDownloadManager: ModelDownloadManager?

    #if os(iOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #endif

    init() {
        let dm = ModelDownloadManager()
        let catalog = DynamicModelCatalog()
        _downloadManager = State(initialValue: dm)
        let vm = ConversationViewModel(
            downloadManager: dm,
            dynamicModelCatalog: catalog
        )
        _viewModel = State(initialValue: vm)
        Self.activeDownloadManager = dm
        
        // Trigger the automation harness during app init — before any views render.
        // This is critical for XCUITest: the SwiftUI .task/.onAppear modifiers
        // don't fire reliably under XCUITest's sandbox because the view render
        // cycle may not complete before the test checks for process exit.
        dm.refreshStates()
        DeveloperAutomationHarness.runIfRequested(viewModel: vm)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .accessibilityIdentifier("mainWindow")
                .environment(viewModel)
                .environment(downloadManager)
                #if os(iOS)
                .environment(navigationRouter)
                #endif
                .onAppear {
                    // Skip onboarding when running under test harness or automation
                    guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil,
                          !CommandLine.arguments.contains("-RunAutomationHarness"),
                          !CommandLine.arguments.contains("-SkipOnboarding"),
                          !CommandLine.arguments.contains("-DisableAnimations") else {
                        return
                    }
                    if !OnboardingManager().hasCompletedOnboarding {
                        showOnboarding = true
                    }
                }
                #if os(iOS)
                .fullScreenCover(isPresented: $showOnboarding) {
                    OnboardingView {
                        OnboardingManager().hasCompletedOnboarding = true
                        showOnboarding = false
                    }
                }
                #else
                .sheet(isPresented: $showOnboarding) {
                    OnboardingView {
                        OnboardingManager().hasCompletedOnboarding = true
                        showOnboarding = false
                    }
                    .frame(minWidth: 500, minHeight: 600)
                }
                #endif
        }
        #if os(macOS)
        .windowStyle(.titleBar)
        .defaultSize(width: 1200, height: 800)
        .windowResizability(.contentMinSize)
        .defaultLaunchBehavior(.presented)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Experiment") {
                    NotificationCenter.default.post(name: .newChatRequested, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)
                
                Button("Load Model...") {
                    NotificationCenter.default.post(name: .loadModelRequested, object: nil)
                }
                .keyboardShortcut("o", modifiers: .command)
            }
            
            CommandMenu("Dashboard") {
                Button("Show Performance Dashboard") {
                    NotificationCenter.default.post(name: .showDashboardRequested, object: nil)
                }
                .keyboardShortcut("d", modifiers: .command)
                
                Button("Run Evaluations") {
                    NotificationCenter.default.post(name: .showEvaluationsRequested, object: nil)
                }
                .keyboardShortcut("e", modifiers: .command)
                
                Divider()
                
                Button("Import Model from URL...") {
                    NotificationCenter.default.post(name: .importModelRequested, object: nil)
                }
                .keyboardShortcut("i", modifiers: .command)

                Divider()

                Button("Toggle Canvas Panel") {
                    NotificationCenter.default.post(name: .toggleCanvasRequested, object: nil)
                }
                .keyboardShortcut("k", modifiers: [.command, .shift])
            }
            
            CommandGroup(before: .windowSize) {
                Button("Refresh Discovered Models") {
                    NotificationCenter.default.post(name: .refreshModelsRequested, object: nil)
                }
                .keyboardShortcut("r", modifiers: .command)
                Divider()
            }
            
            CommandGroup(replacing: .help) {
                Section("Keyboard Shortcuts") {
                    Button("⌘N  New Experiment") {}
                        .disabled(true)
                    Button("⌘O  Load Model") {}
                        .disabled(true)
                    Button("⌘⏎  Send Message") {}
                        .disabled(true)
                    Button("⌘D  Performance Dashboard") {}
                        .disabled(true)
                    Button("⌘E  Run Evaluations") {}
                        .disabled(true)
                    Button("⌘I  Import from URL") {}
                        .disabled(true)
                    Button("⌘⇧K  Toggle Canvas") {}
                        .disabled(true)
                    Button("⌘R  Refresh Models") {}
                        .disabled(true)
                    Button("⌘,  Settings") {}
                        .disabled(true)
                }
            }
            
            CommandGroup(replacing: .appSettings) {
                Button("Settings...") {
                    NotificationCenter.default.post(name: .showSettingsRequested, object: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
        #endif
    }
}



extension Notification.Name {
    static let newChatRequested = Notification.Name("newChatRequested")
    static let showDashboardRequested = Notification.Name("showDashboardRequested")
    static let showEvaluationsRequested = Notification.Name("showEvaluationsRequested")
    static let refreshModelsRequested = Notification.Name("refreshModelsRequested")
    static let loadModelRequested = Notification.Name("loadModelRequested")
    static let showSettingsRequested = Notification.Name("showSettingsRequested")
    static let importModelRequested = Notification.Name("importModelRequested")
}
