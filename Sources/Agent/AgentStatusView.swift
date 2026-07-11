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

/// Displays the current agent status during a ReAct loop execution.
/// Shows thinking animation, tool execution info, approval buttons, and step counter.
struct AgentStatusView: View {
    let harness: AgentHarness

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            statusHeader

            if harness.isRunning {
                stepCounter
            }

            if !harness.steps.isEmpty {
                reasoningTrace
            }

            if harness.isRunning {
                cancelButton
            }
        }
        .padding(16)
        .background(AppColors.backgroundSecondary.opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityIdentifier("agentStatusView")
    }

    // MARK: - Status Header

    @ViewBuilder
    private var statusHeader: some View {
        HStack(spacing: 10) {
            statusIcon
            statusText
            Spacer()
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch harness.status {
        case .idle:
            Image(systemName: "circle")
                .foregroundStyle(AppColors.textSecondary)
                .accessibilityIdentifier("agentStatusIcon_idle")
        case .thinking:
            Image(systemName: "brain.head.profile")
                .foregroundStyle(AppColors.sage)
                .symbolEffect(.pulse, options: shouldAnimate ? .repeating : .default)
                .accessibilityIdentifier("agentStatusIcon_thinking")
        case .executingTool(let name):
            Image(systemName: "hammer.fill")
                .foregroundStyle(AppColors.action)
                .accessibilityIdentifier("agentStatusIcon_executing_\(name)")
        case .waitingForApproval:
            Image(systemName: "exclamationmark.shield.fill")
                .foregroundStyle(AppColors.caution)
                .accessibilityIdentifier("agentStatusIcon_approval")
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(AppColors.sprout)
                .accessibilityIdentifier("agentStatusIcon_completed")
        case .forceStopped:
            Image(systemName: "stop.circle.fill")
                .foregroundStyle(AppColors.caution)
                .accessibilityIdentifier("agentStatusIcon_stopped")
        case .cancelled:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(AppColors.ember)
                .accessibilityIdentifier("agentStatusIcon_cancelled")
        }
    }

    @ViewBuilder
    private var statusText: some View {
        switch harness.status {
        case .idle:
            Text("Agent idle")
                .foregroundStyle(AppColors.textSecondary)
        case .thinking:
            Text("Thinking...")
                .foregroundStyle(AppColors.sage)
        case .executingTool(let name):
            Text("Executing: \(name)")
                .foregroundStyle(AppColors.action)
        case .waitingForApproval(let tool, _):
            Text("Approval needed: \(tool)")
                .foregroundStyle(AppColors.caution)
        case .completed:
            Text("Completed")
                .foregroundStyle(AppColors.sprout)
        case .forceStopped:
            Text("Stopped after \(harness.steps.count) steps")
                .foregroundStyle(AppColors.caution)
        case .cancelled:
            Text("Cancelled")
                .foregroundStyle(AppColors.ember)
        }
    }

    // MARK: - Step Counter

    private var stepCounter: some View {
        Text("Step \(harness.currentIteration + 1) of \(harness.maxIterations)")
            .font(.caption)
            .foregroundStyle(AppColors.textTertiary)
            .accessibilityIdentifier("agentStepCounter")
    }

    // MARK: - Reasoning Trace

    @State private var isTraceExpanded = false

    private var reasoningTrace: some View {
        DisclosureGroup(
            "Reasoning trace (\(harness.steps.count) steps)",
            isExpanded: $isTraceExpanded
        ) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(harness.steps) { step in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Step \(step.iteration + 1)")
                                .font(.caption.bold())
                            if let tool = step.toolCall {
                                Text("→ \(tool.toolName)")
                                    .font(.caption)
                                    .foregroundStyle(AppColors.action)
                            }
                        }
                        if let reasoning = step.reasoning {
                            Text(reasoning)
                                .font(.caption2)
                                .foregroundStyle(AppColors.textSecondary)
                                .lineLimit(3)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .font(.caption)
        .foregroundStyle(AppColors.textSecondary)
        .accessibilityIdentifier("agentReasoningTrace")
    }

    // MARK: - Cancel Button

    private var cancelButton: some View {
        Button(action: { harness.cancel() }) {
            Label("Cancel Agent", systemImage: "stop.fill")
                .font(.caption)
                .foregroundStyle(AppColors.ember)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("agentCancelButton")
    }

    /// Guard for perpetual animations — disable in test environment.
    private var shouldAnimate: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
    }
}
