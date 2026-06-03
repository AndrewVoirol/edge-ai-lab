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
        .windowStyle(.automatic)
        .defaultSize(width: 900, height: 700)
        .commands {
            // Remove the default "New Window" command to keep single-window
            CommandGroup(replacing: .newItem) { }
        }
        #endif
    }
}
