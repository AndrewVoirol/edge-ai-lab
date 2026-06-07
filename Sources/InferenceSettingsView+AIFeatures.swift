import SwiftUI
import LiteRTLM

extension InferenceSettingsView {

    @ViewBuilder
    var thinkingModeSection: some View {
        Section {
            Toggle("Enable Thinking", isOn: $viewModel.experimentalFlags.enableThinking)
            .help("When enabled, the model's reasoning is displayed in a collapsible 'Thinking' section before the response.")
            .accessibilityIdentifier("toggle_enableThinking")

            Label(
                "The model may output reasoning in <think> blocks. When enabled, these are parsed and shown separately from the response.",
                systemImage: "brain.head.profile"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        } header: {
            Label("Thinking Mode", systemImage: "brain.head.profile")
                .foregroundStyle(AppColors.thinking)
        }
    }

    @ViewBuilder
    var toolCallingSection: some View {
        Section {
            Toggle("Enable Tool Calling", isOn: $viewModel.experimentalFlags.enableToolCalling)
            .help("Allow the model to invoke built-in tools during inference.")
            .accessibilityIdentifier("toggle_enableToolCalling")

            if viewModel.experimentalFlags.enableToolCalling {
                Toggle("Enable Agent Skills", isOn: $viewModel.experimentalFlags.enableAgentSkills)
                .help("Enable built-in agent skills: Wikipedia search and Apple Maps rendering.")
                .accessibilityIdentifier("toggle_enableAgentSkills")

                VStack(alignment: .leading, spacing: 4) {
                    Text("Available Tools (\(toolDisplayItems.count))")
                        .font(.caption)
                        .fontWeight(.semibold)

                    ForEach(toolDisplayItems, id: \.name) { item in
                        HStack(spacing: 6) {
                            Image(systemName: "wrench.fill")
                                .font(.caption2)
                                .foregroundStyle(AppColors.toolCall)
                            Text(item.name)
                                .font(.caption)
                                .fontDesign(.monospaced)
                            Text("— \(item.desc)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }

                Label(
                    "Tools are side-effect-free and work fully offline. The model can invoke tools to calculate, check time, analyze text, convert units, and introspect device health.",
                    systemImage: "checkmark.shield"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                
                Text("⚠️ Tool Calling changes take effect on next model load.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Label("Tool Calling", systemImage: "wrench.and.screwdriver")
                .foregroundStyle(AppColors.toolCall)
        }
    }

    @ViewBuilder
    var mcpServersSection: some View {
        #if os(macOS)
        if viewModel.experimentalFlags.enableToolCalling {
            Section {
                ForEach(viewModel.mcpServers) { config in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(config.name)
                                    .fontWeight(.medium)
                                if expandedServerID != config.id {
                                    Text("\(config.command) \(config.args.joined(separator: " "))")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }

                            Spacer()

                            // State Indicator
                            let state = viewModel.getMCPClientState(for: config.id)
                            HStack(spacing: 4) {
                                Circle()
                                    .frame(width: 8, height: 8)
                                    .foregroundStyle(statusColor(for: state))
                                Text(statusText(for: state))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            Toggle("", isOn: Binding(
                                get: { config.enabled },
                                set: { newValue in
                                    var updated = config
                                    updated.enabled = newValue
                                    viewModel.updateMCPServerConfig(updated)
                                }
                            ))
                            .labelsHidden()
                            .accessibilityIdentifier("toggle_mcp_\(config.name)")
                        }

                        if expandedServerID == config.id {
                            // Inline Editor
                            VStack(alignment: .leading, spacing: 8) {
                                TextField("Name", text: Binding(
                                    get: { config.name },
                                    set: { var new = config; new.name = $0; viewModel.updateMCPServerConfig(new) }
                                ))
                                .textFieldStyle(.roundedBorder)
                                .accessibilityIdentifier("textField_mcp_name_\(config.id)")

                                TextField("Executable/Interpreter (e.g. /usr/local/bin/node)", text: Binding(
                                    get: { config.command },
                                    set: { var new = config; new.command = $0; viewModel.updateMCPServerConfig(new) }
                                ))
                                .textFieldStyle(.roundedBorder)
                                .accessibilityIdentifier("textField_mcp_command_\(config.id)")

                                TextField("Arguments (space-separated)", text: Binding(
                                    get: { config.args.joined(separator: " ") },
                                    set: { var new = config; new.args = $0.split(separator: " ").map(String.init); viewModel.updateMCPServerConfig(new) }
                                ))
                                .textFieldStyle(.roundedBorder)
                                .accessibilityIdentifier("textField_mcp_args_\(config.id)")

                                VStack(alignment: .leading) {
                                    Text("Environment Variables (One per line: KEY=VALUE)")
                                        .font(.caption)
                                    TextEditor(text: Binding(
                                        get: { config.env.map { "\($0.key)=\($0.value)" }.joined(separator: "\n") },
                                        set: { newEnv in
                                            var new = config
                                            var envDict: [String: String] = [:]
                                            for line in newEnv.split(separator: "\n") {
                                                let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
                                                if parts.count == 2 { envDict[parts[0]] = parts[1] }
                                            }
                                            new.env = envDict
                                            viewModel.updateMCPServerConfig(new)
                                        }
                                    ))
                                    .frame(minHeight: 60)
                                    .font(.system(.body, design: .monospaced))
                                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.5), lineWidth: 0.5))
                                }

                                HStack {
                                    Spacer()
                                    Button("Close") {
                                        expandedServerID = nil
                                    }
                                    .controlSize(.small)
                                    .accessibilityIdentifier("button_close_mcp_\(config.name)")
                                }
                            }
                            .padding()
                            .background(Color.secondary.opacity(0.05))
                            .cornerRadius(8)
                        } else {
                            // Tools list if connected
                            let tools = viewModel.getMCPTools(for: config.id)
                            if !tools.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Registered Tools:")
                                        .font(.caption2)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.secondary)
                                    ForEach(tools, id: \.name) { tool in
                                        HStack(spacing: 4) {
                                            Image(systemName: "circle.grid.cross.fill")
                                                .font(.caption2)
                                                .foregroundStyle(AppColors.accentTeal)
                                            Text(tool.name)
                                                .font(.caption2)
                                                .monospaced()
                                            Text("— \(tool.description)")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                    }
                                }
                                .padding(.leading, 8)
                            }

                            // Edit & Delete button
                            HStack {
                                Button("Edit") {
                                    expandedServerID = config.id
                                }
                                .buttonStyle(.borderless)
                                .font(.caption2)
                                .accessibilityIdentifier("button_edit_mcp_\(config.name)")

                                Spacer()

                                Button("Delete", role: .destructive) {
                                    viewModel.deleteMCPServerConfig(id: config.id)
                                }
                                .buttonStyle(.borderless)
                                .font(.caption2)
                                .foregroundStyle(AppColors.danger)
                                .accessibilityIdentifier("button_delete_mcp_\(config.name)")
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                Button(action: {
                    let newConfig = MCPServerConfig(
                        name: "New Server",
                        enabled: false,
                        command: "",
                        args: [],
                        env: [:]
                    )
                    viewModel.addMCPServerConfig(newConfig)
                    expandedServerID = newConfig.id
                }) {
                    Label("Add MCP Server", systemImage: "plus")
                }
                .accessibilityIdentifier("button_addMCP")
            } header: {
                Label("MCP Servers (macOS Only)", systemImage: "server.rack")
                    .foregroundStyle(AppColors.accentTeal)
            }
        }
        #endif
    }
}
