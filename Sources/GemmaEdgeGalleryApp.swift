import SwiftUI

/// GemmaEdgeGallery — On-device Gemma 4 inference lab for iOS & macOS.
///
/// Powered by LiteRT-LM v0.13. Runs Gemma 4 E2B, E4B, and 12B models
/// entirely on-device with Metal GPU acceleration. Features tool calling,
/// thinking mode, multimodal input, and deep performance instrumentation.
@main
struct GemmaEdgeGalleryApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
        #if os(macOS)
        .windowStyle(.titleBar)
        .defaultSize(width: 900, height: 700)
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
                Text("Keyboard Shortcuts")
                    .font(.headline)
                Divider()
                Text("⌘N  New Chat")
                Text("⌘O  Load Model")
                Text("⌘⏎  Send Message")
                Text("⌘D  Performance Dashboard")
                Text("⌘R  Refresh Models")
                Text("⌘,  Settings")
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
