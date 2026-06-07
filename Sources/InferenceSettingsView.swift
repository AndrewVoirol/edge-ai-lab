import SwiftUI
import LiteRTLM

/// Settings view for configuring ExperimentalFlags, inference parameters,
/// and HuggingFace token management.
/// Flags are user-toggleable with benchmarking defaulting to ON.
struct InferenceSettingsView: View {
    @Bindable var viewModel: ConversationViewModel
    @State var hfTokenInput = ""
    @State var hfTokenSaved = HFTokenStorage.hasToken
    @State var hfTokenMessage = ""

    @State var expandedServerID: UUID? = nil

    /// Helper for displaying tool information in a ForEach.
    /// Tool protocol has static properties, so we need to extract them at build time.
    struct ToolDisplayItem {
        let name: String
        let desc: String
    }

    var toolDisplayItems: [ToolDisplayItem] {
        var items = [
            ToolDisplayItem(name: CalculatorTool.name, desc: CalculatorTool.description),
            ToolDisplayItem(name: DateTimeTool.name, desc: DateTimeTool.description),
            ToolDisplayItem(name: DeviceInfoTool.name, desc: DeviceInfoTool.description),
            ToolDisplayItem(name: UnitConverterTool.name, desc: UnitConverterTool.description),
            ToolDisplayItem(name: TextAnalyzerTool.name, desc: TextAnalyzerTool.description),
            ToolDisplayItem(name: SystemHealthTool.name, desc: SystemHealthTool.description),
        ]
        if viewModel.experimentalFlags.enableAgentSkills {
            items.append(ToolDisplayItem(name: WikipediaSkillTool.name, desc: WikipediaSkillTool.description))
            items.append(ToolDisplayItem(name: MapSkillTool.name, desc: MapSkillTool.description))
        }
        return items
    }

    // MARK: - Body

    var body: some View {
        #if os(macOS)
        TabView {
            Form {
                backendSection
                experimentalFlagsSection
            }
            .formStyle(.grouped)
            .tag("tab_general")
            .tabItem { Label("General", systemImage: "gearshape") }
            .accessibilityIdentifier("tab_general")

            Form {
                thinkingModeSection
                toolCallingSection
                mcpServersSection
            }
            .formStyle(.grouped)
            .tag("tab_aiFeatures")
            .tabItem { Label("AI Features", systemImage: "brain.head.profile") }
            .accessibilityIdentifier("tab_aiFeatures")

            Form {
                samplerSection
                systemMessageSection
            }
            .formStyle(.grouped)
            .tag("tab_sampler")
            .tabItem { Label("Sampler", systemImage: "slider.horizontal.3") }
            .accessibilityIdentifier("tab_sampler")

            Form {
                modelInfoSection
                performanceSection
                hfTokenSection
            }
            .formStyle(.grouped)
            .tag("tab_data")
            .tabItem { Label("Data", systemImage: "chart.bar") }
            .accessibilityIdentifier("tab_data")
        }
        .frame(minWidth: 480, minHeight: 400)
        #else
        Form {
            backendSection
            experimentalFlagsSection
            thinkingModeSection
            toolCallingSection
            samplerSection
            systemMessageSection
            modelInfoSection
            performanceSection
            hfTokenSection
        }
        .formStyle(.grouped)
        #endif
    }

    // MARK: - Helpers

    func statusColor(for state: MCPClientState) -> Color {
        switch state {
        case .stopped: return AppColors.textTertiary
        case .starting: return AppColors.warning
        case .connected: return AppColors.success
        case .failed: return AppColors.danger
        }
    }

    func statusText(for state: MCPClientState) -> String {
        switch state {
        case .stopped: return "Stopped"
        case .starting: return "Connecting"
        case .connected: return "Connected"
        case .failed(let err): return "Error: \(err.prefix(30))..."
        }
    }
}
