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

/// GemmaEdgeGallery — Edge AI Lab for iOS & macOS.
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
struct GemmaEdgeGalleryApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #endif

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
        #if os(macOS)
        .windowStyle(.titleBar)
        .defaultSize(width: 1200, height: 800)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Chat") {
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
                    Button("⌘N  New Chat") {}
                        .disabled(true)
                    Button("⌘O  Load Model") {}
                        .disabled(true)
                    Button("⌘⏎  Send Message") {}
                        .disabled(true)
                    Button("⌘D  Performance Dashboard") {}
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
    static let refreshModelsRequested = Notification.Name("refreshModelsRequested")
    static let loadModelRequested = Notification.Name("loadModelRequested")
    static let showSettingsRequested = Notification.Name("showSettingsRequested")
}
