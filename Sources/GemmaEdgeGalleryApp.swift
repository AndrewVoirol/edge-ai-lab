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
        }
        #endif
        
        #if os(macOS)
        Settings {
            // macOS native Settings (Preferences) window
            SettingsWrapper()
                .preferredColorScheme(.dark)
        }
        #endif
    }
}

#if os(macOS)
struct SettingsWrapper: View {
    // A standalone instance for settings if needed, or pass environment.
    // In SwiftUI, Settings gets its own separate view tree.
    // For simplicity, we create a fresh ViewModel, or we can use a shared state.
    // Since ConversationViewModel manages inference state, ideally we inject it or use an EnvironmentObject.
    // However, if we instantiate a new one, settings might be desynced.
    // Let's use a standard new model for settings assuming it syncs via UserDefaults/HFTokenStorage, 
    // or we can pass the shared one. But App struct doesn't have it.
    // Wait, let's just instantiate it, as settings like experimental flags 
    // might need to be global. Currently they are in ConversationViewModel.
    @State private var viewModel = ConversationViewModel.shared
    
    var body: some View {
        InferenceSettingsView(viewModel: viewModel)
            .frame(width: 550, height: 650)
    }
}
#endif

extension Notification.Name {
    static let newChatRequested = Notification.Name("newChatRequested")
    static let showDashboardRequested = Notification.Name("showDashboardRequested")
    static let refreshModelsRequested = Notification.Name("refreshModelsRequested")
    static let loadModelRequested = Notification.Name("loadModelRequested")
}
