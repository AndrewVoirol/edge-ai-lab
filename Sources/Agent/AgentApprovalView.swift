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

/// Modal view presented when the agent encounters a risky tool call.
/// Shows tool details and lets the user approve or deny the action.
struct AgentApprovalView: View {
    let toolName: String
    let arguments: [String: String]
    let onApprove: () -> Void
    let onDeny: () -> Void
    @Binding var autoApproveAll: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.title2)
                    .foregroundStyle(AppColors.warning)
                Text("Tool Approval Required")
                    .font(.headline)
                    .foregroundStyle(AppColors.textPrimary)
            }
            .accessibilityIdentifier("approvalHeader")

            Divider()

            // Tool info
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Tool:")
                        .font(.subheadline.bold())
                        .foregroundStyle(AppColors.textSecondary)
                    Text(toolName)
                        .font(.subheadline.monospaced())
                        .foregroundStyle(AppColors.toolCall)
                }
                .accessibilityIdentifier("approvalToolName")

                Text("Arguments:")
                    .font(.subheadline.bold())
                    .foregroundStyle(AppColors.textSecondary)

                ForEach(arguments.keys.sorted(), id: \.self) { key in
                    HStack(alignment: .top) {
                        Text("\(key):")
                            .font(.caption.monospaced())
                            .foregroundStyle(AppColors.textTertiary)
                        Text(arguments[key] ?? "")
                            .font(.caption.monospaced())
                            .foregroundStyle(AppColors.textPrimary)
                    }
                    .padding(.leading, 8)
                }
            }
            .accessibilityIdentifier("approvalToolDetails")

            // Risk explanation
            Text("This tool may access sensitive device data. The agent needs your permission to proceed.")
                .font(.caption)
                .foregroundStyle(AppColors.textSecondary)
                .padding(.vertical, 4)

            // Auto-approve toggle
            Toggle(isOn: $autoApproveAll) {
                Text("Approve all remaining tools")
                    .font(.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }
            #if os(macOS)
            .toggleStyle(.checkbox)
            #endif
            .accessibilityIdentifier("approvalAutoApproveToggle")

            Divider()

            // Action buttons
            HStack(spacing: 12) {
                Button(action: onDeny) {
                    Text("Deny")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
                .tint(AppColors.danger)
                .accessibilityIdentifier("approvalDenyButton")

                Button(action: onApprove) {
                    Text("Approve")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppColors.success)
                .accessibilityIdentifier("approvalApproveButton")
            }
        }
        .padding(20)
        .frame(minWidth: 320)
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .accessibilityIdentifier("agentApprovalView")
    }
}
