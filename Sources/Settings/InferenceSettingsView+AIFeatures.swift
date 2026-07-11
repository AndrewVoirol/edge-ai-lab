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

extension InferenceSettingsView {

    @ViewBuilder
    var thinkingModeSection: some View {
        Section {
            Toggle("Enable Thinking", isOn: $viewModel.runtimeFlags.enableThinking)
            .help("When enabled, the model's reasoning is displayed in a collapsible 'Thinking' section before the response. When disabled, thinking tags are stripped from the output.")
            .accessibilityIdentifier("toggle_enableThinking")

            Label(
                "The model may output reasoning in <think> blocks. When enabled, these are parsed and shown separately from the response.",
                systemImage: "brain.head.profile"
            )
            .font(AppTypography.caption)
            .foregroundStyle(AppColors.textSecondary)

            SettingsImpactLabel(
                descriptor: FlagRegistry.thinking,
                currentRuntime: viewModel.selectedRuntimeType
            )
        } header: {
            Label("Thinking Mode", systemImage: "brain.head.profile")
                .foregroundStyle(AppColors.sage)
        }
    }

    @ViewBuilder
    var visualTokenBudgetSection: some View {
        if let metadata = viewModel.activeModelMetadata, metadata.supportsImage {
            Section {
                Picker("Visual Token Budget", selection: Binding(
                    get: { viewModel.runtimeFlags.visualTokenBudget ?? 0 },
                    set: { viewModel.runtimeFlags.visualTokenBudget = $0 == 0 ? nil : $0 }
                )) {
                    Text("Auto (SDK Default)").tag(Int32(0))
                    Text("70 tokens (fastest)").tag(Int32(70))
                    Text("140 tokens").tag(Int32(140))
                    Text("280 tokens (balanced)").tag(Int32(280))
                    Text("560 tokens").tag(Int32(560))
                    Text("1120 tokens (highest quality)").tag(Int32(1120))
                }
                .accessibilityIdentifier("picker_visualTokenBudget")

                Label(
                    "Controls how many tokens the model uses to encode images. Higher values give better image understanding but slower inference.",
                    systemImage: "photo"
                )
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textSecondary)
            } header: {
                Label("Vision Settings", systemImage: "eye")
                    .foregroundStyle(AppColors.badgeVision)
            }
        }
    }

    @ViewBuilder
    var toolCallingSection: some View {
        Section {
            Toggle("Enable Tool Calling", isOn: $viewModel.runtimeFlags.enableToolCalling)
            .help("Allow the model to invoke built-in tools during inference.")
            .accessibilityIdentifier("toggle_enableToolCalling")

            if viewModel.runtimeFlags.enableToolCalling {
                Toggle(isOn: $viewModel.runtimeFlags.enableAgentSkills) {
                    HStack(spacing: AppSpacing.xs) {
                        Text("Enable Agent Skills")
                        Text("Beta")
                            .font(AppTypography.badge)
                            .foregroundStyle(AppColors.caution)
                            .padding(.horizontal, AppSpacing.xs)
                            .padding(.vertical, 1)
                            .background(AppColors.caution.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }
                .help("Enable built-in agent skills: Wikipedia search and Apple Maps rendering. Requires internet connection.")
                .accessibilityIdentifier("toggle_enableAgentSkills")

                VStack(alignment: .leading, spacing: 4) {
                    Text("Available Tools (\(toolDisplayItems.count))")
                        .font(AppTypography.caption)
                        .fontWeight(.semibold)

                    ForEach(toolDisplayItems, id: \.name) { item in
                        HStack(spacing: 6) {
                            Image(systemName: "wrench.fill")
                                .font(.caption2)
                                .foregroundStyle(AppColors.action)
                            Text(item.name)
                                .font(AppTypography.caption)
                                .fontDesign(.monospaced)
                            Text("— \(item.desc)")
                                .font(.caption2)
                                .foregroundStyle(AppColors.textSecondary)
                                .lineLimit(1)
                        }
                    }
                }

                Label(
                    "Tools are side-effect-free and work fully offline. The model can invoke tools to calculate, check time, analyze text, convert units, and introspect device health.",
                    systemImage: "checkmark.shield"
                )
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textSecondary)
                
                SettingsImpactLabel(
                    descriptor: FlagRegistry.toolCalling,
                    currentRuntime: viewModel.selectedRuntimeType
                )
            }
        } header: {
            Label("Tool Calling", systemImage: "wrench.and.screwdriver")
                .foregroundStyle(AppColors.action)
        }
    }

    @ViewBuilder
    var mcpServersSection: some View {
        #if os(macOS)
        if viewModel.runtimeFlags.enableToolCalling {
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
                                        .foregroundStyle(AppColors.textSecondary)
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
                                    .foregroundStyle(AppColors.textSecondary)
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
                                        .font(AppTypography.caption)
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
                                    .font(AppTypography.mono)
                                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(AppColors.textSecondary.opacity(0.5), lineWidth: 0.5))
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
                            .background(AppColors.textSecondary.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm))
                        } else {
                            // Tools list if connected
                            let tools = viewModel.getMCPTools(for: config.id)
                            if !tools.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Registered Tools:")
                                        .font(.caption2)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(AppColors.textSecondary)
                                    ForEach(tools, id: \.name) { tool in
                                        HStack(spacing: 4) {
                                            Image(systemName: "circle.grid.cross.fill")
                                                .font(.caption2)
                                                .foregroundStyle(AppColors.moss)
                                            Text(tool.name)
                                                .font(.caption2)
                                                .monospaced()
                                            Text("— \(tool.description)")
                                                .font(.caption2)
                                                .foregroundStyle(AppColors.textSecondary)
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
                                .foregroundStyle(AppColors.ember)
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
                    .foregroundStyle(AppColors.moss)
            }
        }
        #endif
    }
}
