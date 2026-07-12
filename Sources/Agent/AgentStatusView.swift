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
        VStack(alignment: .leading, spacing: AppSpacing.md) {
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
        .padding(AppSpacing.lg)
        .background(AppColors.backgroundSecondary.opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.standard))
        .accessibilityIdentifier("agentStatusView")
    }

    // MARK: - Status Header

    @ViewBuilder
    private var statusHeader: some View {
        HStack(spacing: AppSpacing.sm) {
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
                .foregroundStyle(AppColors.reasoning)
                .symbolEffect(.pulse, options: shouldAnimate ? .repeating : .default)
                .accessibilityIdentifier("agentStatusIcon_thinking")
        case .executingTool(let name):
            Image(systemName: "hammer.fill")
                .foregroundStyle(AppColors.toolAction)
                .accessibilityIdentifier("agentStatusIcon_executing_\(name)")
        case .waitingForApproval:
            Image(systemName: "exclamationmark.shield.fill")
                .foregroundStyle(AppColors.warning)
                .accessibilityIdentifier("agentStatusIcon_approval")
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(AppColors.success)
                .accessibilityIdentifier("agentStatusIcon_completed")
        case .forceStopped:
            Image(systemName: "stop.circle.fill")
                .foregroundStyle(AppColors.warning)
                .accessibilityIdentifier("agentStatusIcon_stopped")
        case .cancelled:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(AppColors.destructive)
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
                .foregroundStyle(AppColors.reasoning)
        case .executingTool(let name):
            Text("Executing: \(name)")
                .foregroundStyle(AppColors.toolAction)
        case .waitingForApproval(let tool, _):
            Text("Approval needed: \(tool)")
                .foregroundStyle(AppColors.warning)
        case .completed:
            Text("Completed")
                .foregroundStyle(AppColors.success)
        case .forceStopped:
            Text("Stopped after \(harness.steps.count) steps")
                .foregroundStyle(AppColors.warning)
        case .cancelled:
            Text("Cancelled")
                .foregroundStyle(AppColors.destructive)
        }
    }

    // MARK: - Step Counter

    private var stepCounter: some View {
        Text("Step \(harness.currentIteration + 1) of \(harness.maxIterations)")
            .font(AppTypography.caption)
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
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                ForEach(harness.steps) { step in
                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        HStack {
                            Text("Step \(step.iteration + 1)")
                                .font(AppTypography.sectionHeader)
                            if let tool = step.toolCall {
                                Text("→ \(tool.toolName)")
                                    .font(AppTypography.caption)
                                    .foregroundStyle(AppColors.toolAction)
                            }
                        }
                        if let reasoning = step.reasoning {
                            Text(reasoning)
                                .font(AppTypography.caption)
                                .foregroundStyle(AppColors.textSecondary)
                                .lineLimit(3)
                        }
                    }
                    .padding(.vertical, AppSpacing.xxs)
                }
            }
        }
        .font(AppTypography.caption)
        .foregroundStyle(AppColors.textSecondary)
        .accessibilityIdentifier("agentReasoningTrace")
    }

    // MARK: - Cancel Button

    private var cancelButton: some View {
        Button(action: { harness.cancel() }) {
            Label("Cancel Agent", systemImage: "stop.fill")
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.destructive)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("agentCancelButton")
    }

    /// Guard for perpetual animations — disable in test environment.
    private var shouldAnimate: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
    }
}
