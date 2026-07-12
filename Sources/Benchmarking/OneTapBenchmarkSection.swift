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

// MARK: - One-Tap Benchmark Section

/// UI component for the one-tap "Run Benchmark" button and result display.
///
/// Integrates with `OneTapBenchmarkRunner` to provide a complete
/// benchmark experience:
/// - Idle: Shows a prominent "Run Benchmark" button
/// - Running: Shows progress indicator with current run count
/// - Completed: Shows median results card
/// - Failed: Shows error message with retry option
///
/// Used in both macOS `DetailColumnView` and iOS `iOSModelDetailView`.
struct OneTapBenchmarkSection: View {
    var viewModel: ConversationViewModel
    @State private var runner: OneTapBenchmarkRunner?

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text("Benchmark")
                .font(AppTypography.sectionHeader)
                .foregroundStyle(AppColors.textSecondary)

            if let runner = runner {
                benchmarkContent(runner)
            } else {
                startButton
            }
        }
        .accessibilityIdentifier("section_oneTapBenchmark")
    }

    // MARK: - Start Button

    private var startButton: some View {
        Button {
            startBenchmark()
        } label: {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: "gauge.with.dots.needle.33percent")
                    .font(AppIconSize.lg)
                Text("Run Benchmark")
                    .font(AppTypography.subtitle)
            }
            .frame(maxWidth: .infinity)
            .padding(AppSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.lg)
                    .fill(AppColors.accentPrimary.opacity(0.15))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppRadius.lg)
                            .strokeBorder(AppColors.accentPrimary.opacity(0.3), lineWidth: AppLineWidth.regular)
                    )
            )
            .foregroundStyle(AppColors.accentPrimary)
        }
        .buttonStyle(.plain)
        .disabled(!viewModel.isEngineReady)
        .opacity(viewModel.isEngineReady ? 1.0 : 0.5)
        .accessibilityIdentifier("button_runBenchmark")
        .accessibilityLabel("Run benchmark")
        .accessibilityHint(viewModel.isEngineReady
            ? "Runs a standardized 3-run benchmark on the loaded model"
            : "Load a model first to run benchmarks")
    }

    // MARK: - Benchmark Content

    @ViewBuilder
    private func benchmarkContent(_ runner: OneTapBenchmarkRunner) -> some View {
        switch runner.state {
        case .idle:
            startButton

        case .warmingUp:
            progressCard(label: "Warming up…", detail: "Priming the engine")

        case .running(let currentRun, let totalRuns):
            progressCard(
                label: "Running benchmark…",
                detail: "Run \(currentRun) of \(totalRuns)"
            )

        case .completed(let result):
            resultCard(result)
            retryButton

        case .failed(let error):
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(AppColors.destructive)
                    Text("Benchmark failed")
                        .font(AppTypography.subtitle)
                        .foregroundStyle(AppColors.textPrimary)
                }
                Text(error)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
                    .lineLimit(3)
            }
            .padding(AppSpacing.md)
            .glassCard()
            .accessibilityIdentifier("benchmark_error")

            retryButton
        }
    }

    // MARK: - Progress Card

    private func progressCard(label: String, detail: String) -> some View {
        HStack(spacing: AppSpacing.md) {
            ProgressView()
                .controlSize(.small)
                .tint(AppColors.accentPrimary)
            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text(label)
                    .font(AppTypography.subtitle)
                    .foregroundStyle(AppColors.textPrimary)
                Text(detail)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }
            Spacer()
        }
        .padding(AppSpacing.md)
        .glassCard()
        .accessibilityIdentifier("benchmark_progress")
    }

    // MARK: - Result Card

    private func resultCard(_ result: BenchmarkResult) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(AppColors.success)
                Text("Benchmark Complete")
                    .font(AppTypography.subtitle)
                    .foregroundStyle(AppColors.textPrimary)
            }

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: AppSpacing.sm) {
                metricCell(
                    label: "Decode",
                    value: String(format: "%.1f", result.medianDecodeTokensPerSecond),
                    unit: "tok/s",
                    color: PerformanceTier(decodeSpeed: result.medianDecodeTokensPerSecond).color
                )
                metricCell(
                    label: "TTFT",
                    value: String(format: "%.3f", result.medianTTFTSeconds),
                    unit: "sec",
                    color: AppColors.accentPrimary
                )
                metricCell(
                    label: "Prefill",
                    value: String(format: "%.1f", result.medianPrefillTokensPerSecond),
                    unit: "tok/s",
                    color: AppColors.accentPrimary
                )
            }

            Text("Median of \(result.runCount) runs")
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textTertiary)
        }
        .padding(AppSpacing.md)
        .glassCard()
        .accessibilityIdentifier("benchmark_result")
    }

    private func metricCell(label: String, value: String, unit: String, color: Color) -> some View {
        VStack(spacing: AppSpacing.xxs) {
            Text(label)
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textTertiary)
            Text(value)
                .font(AppTypography.metricLarge)
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(unit)
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textTertiary)
        }
    }

    // MARK: - Retry Button

    private var retryButton: some View {
        Button {
            runner?.reset()
            startBenchmark()
        } label: {
            HStack(spacing: AppSpacing.xs) {
                Image(systemName: "arrow.counterclockwise")
                Text("Run Again")
                    .font(AppTypography.caption)
            }
            .foregroundStyle(AppColors.accentPrimary)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("button_rerunBenchmark")
    }

    // MARK: - Actions

    private func startBenchmark() {
        let newRunner = OneTapBenchmarkRunner(
            engine: viewModel.engine,
            metricsStore: MetricsStore(),
            modelName: viewModel.activeModelMetadata?.name ?? "Unknown",
            runtimeFlags: viewModel.runtimeFlags
        )
        runner = newRunner
        Task {
            await newRunner.run()
        }
    }
}
