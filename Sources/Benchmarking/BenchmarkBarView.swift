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

import LiteRTLM
import SwiftUI

// MARK: - Benchmark Bar View

/// Displays inference performance metrics in a compact bar with an expandable detail view.
///
/// All `accessibilityIdentifier` values are preserved from the original inline code
/// in `ContentView` so that agent discoverability and UI testing remain intact.
struct BenchmarkBarView: View {
    let info: BenchmarkInfo
    @Environment(ConversationViewModel.self) private var viewModel
    @State private var isBenchmarkExpanded = true
    @State private var isShowingBenchmarkCard = false

    var body: some View {
        benchmarkBar(info: info)
    }

    // MARK: - Benchmark Bar

    private func benchmarkBar(info: BenchmarkInfo) -> some View {
        let decodeTier = PerformanceTier(decodeSpeed: info.lastDecodeTokensPerSecond)

        return VStack(spacing: AppSpacing.xs) {
            // Compact bar (always visible)
            #if os(iOS)
            // iOS: Two-row wrapped grid to fit narrow screens
            iosBenchmarkCompactBar(info: info, decodeTier: decodeTier)
            #else
            HStack(spacing: AppSpacing.md) {
                // Backend indicator
                if let result = viewModel.backendResult {
                    HStack(spacing: AppSpacing.xs) {
                        Image(systemName: result.activeBackend == .gpu ? "bolt.fill" : "cpu")
                            .foregroundStyle(result.activeBackend == .gpu ? AppColors.success : AppColors.warning)
                        Text(result.activeBackend == .gpu ? "GPU" : "CPU")
                            .font(AppTypography.badge)
                            .foregroundStyle(result.activeBackend == .gpu ? AppColors.success : AppColors.warning)
                    }
                    .accessibilityIdentifier("badge_backend")

                    Rectangle()
                        .fill(AppColors.border)
                        .frame(width: 0.5, height: 18)
                }

                // Thermal state indicator
                thermalIndicator
                    .accessibilityIdentifier("indicator_thermal")

                Rectangle()
                    .fill(AppColors.border)
                    .frame(width: 0.5, height: 18)

                benchmarkItem(label: "TTFT", value: String(format: "%.3fs", info.timeToFirstTokenInSecond))
                    .accessibilityLabel("Time to first token: \(String(format: "%.3f", info.timeToFirstTokenInSecond)) seconds")
                Rectangle()
                    .fill(AppColors.border)
                    .frame(width: 0.5, height: 18)

                // Hero metric: decode speed with tier color
                VStack(alignment: .leading, spacing: 1) {
                    Text("Decode")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textTertiary)
                    Text(String(format: "%.1f tok/s", info.lastDecodeTokensPerSecond))
                        .font(AppTypography.metric)
                        .foregroundStyle(decodeTier.color)
                        .contentTransition(.numericText())
                        .accessibilityLabel("Decode speed: \(String(format: "%.1f", info.lastDecodeTokensPerSecond)) tokens per second")
                }

                Rectangle()
                    .fill(AppColors.border)
                    .frame(width: 0.5, height: 18)

                benchmarkItem(label: "Prefill", value: String(format: "%.1f tok/s", info.lastPrefillTokensPerSecond))
                    .accessibilityLabel("Prefill speed: \(String(format: "%.1f", info.lastPrefillTokensPerSecond)) tokens per second")

                // Memory indicator
                Rectangle()
                    .fill(AppColors.border)
                    .frame(width: 0.5, height: 18)
                memoryIndicator

                Spacer()

                // Share benchmark card button
                Button {
                    isShowingBenchmarkCard = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .foregroundStyle(AppColors.accentTeal)
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("button_benchmarkShare")
                .help("Share benchmark card")

                // Expand/collapse button
                Button {
                    withAnimation(AppAnimation.standard) {
                        isBenchmarkExpanded.toggle()
                    }
                } label: {
                    Image(systemName: isBenchmarkExpanded ? "chevron.down" : "chevron.up")
                        .foregroundStyle(AppColors.textTertiary)
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("button_benchmarkExpand")
            }
            #endif

            // Fallback warning
            if let result = viewModel.backendResult, result.didFallback, let reason = result.fallbackReason {
                HStack(spacing: AppSpacing.xs) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(AppColors.warning)
                    Text(reason)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textSecondary)
                    Spacer()
                }
                .padding(.vertical, AppSpacing.xs)
            }

            // Expanded detail view
            if isBenchmarkExpanded, let metrics = viewModel.inferenceMetrics {
                expandedMetricsView(metrics: metrics, info: info)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .font(AppTypography.caption)
        .sheet(isPresented: $isShowingBenchmarkCard) {
            BenchmarkCardShareSheet(
                cardData: BenchmarkCardData.from(
                    benchmarkInfo: info,
                    inferenceMetrics: viewModel.inferenceMetrics,
                    modelMetadata: viewModel.activeModelMetadata,
                    backendResult: viewModel.backendResult
                )
            )
        }
    }

    // MARK: - iOS Benchmark Compact Bar

    #if os(iOS)
    /// Two-row layout for the benchmark bar on narrow iPhone screens.
    private func iosBenchmarkCompactBar(info: BenchmarkInfo, decodeTier: PerformanceTier) -> some View {
        VStack(spacing: AppSpacing.xs) {
            // Row 1: Backend, Thermal, TTFT, Expand button
            HStack(spacing: AppSpacing.sm) {
                if let result = viewModel.backendResult {
                    HStack(spacing: AppSpacing.xs) {
                        Image(systemName: result.activeBackend == .gpu ? "bolt.fill" : "cpu")
                            .foregroundStyle(result.activeBackend == .gpu ? AppColors.success : AppColors.warning)
                        Text(result.activeBackend == .gpu ? "GPU" : "CPU")
                            .font(AppTypography.badge)
                            .foregroundStyle(result.activeBackend == .gpu ? AppColors.success : AppColors.warning)
                    }
                    .accessibilityIdentifier("badge_backend")
                }

                thermalIndicator
                    .accessibilityIdentifier("indicator_thermal")

                benchmarkItem(label: "TTFT", value: String(format: "%.3fs", info.timeToFirstTokenInSecond))

                Spacer()

                Button {
                    isShowingBenchmarkCard = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .foregroundStyle(AppColors.accentTeal)
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("button_benchmarkShare")

                Button {
                    withAnimation(AppAnimation.standard) {
                        isBenchmarkExpanded.toggle()
                    }
                } label: {
                    Image(systemName: isBenchmarkExpanded ? "chevron.down" : "chevron.up")
                        .foregroundStyle(AppColors.textTertiary)
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("button_benchmarkExpand")
            }

            // Row 2: Decode (hero), Prefill, Memory
            HStack(spacing: AppSpacing.sm) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Decode")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textTertiary)
                    Text(String(format: "%.1f tok/s", info.lastDecodeTokensPerSecond))
                        .font(AppTypography.metric)
                        .foregroundStyle(decodeTier.color)
                        .contentTransition(.numericText())
                        .accessibilityLabel("Decode speed: \(String(format: "%.1f", info.lastDecodeTokensPerSecond)) tokens per second")
                }

                benchmarkItem(label: "Prefill", value: String(format: "%.1f tok/s", info.lastPrefillTokensPerSecond))

                memoryIndicator

                Spacer()
            }
        }
    }
    #endif

    // MARK: - Thermal Indicator

    private var thermalIndicator: some View {
        let level = DeviceMetrics.currentThermalLevel
        return HStack(spacing: AppSpacing.xs) {
            Image(systemName: level.symbolName)
                .foregroundStyle(thermalColor(for: level))
            Text(level.label)
                .font(AppTypography.badge)
                .foregroundStyle(thermalColor(for: level))
        }
        .accessibilityElement(children: .combine)
    }

    private func thermalColor(for level: ThermalLevel) -> Color {
        switch level {
        case .nominal:  return AppColors.success
        case .fair:     return AppColors.warning
        case .serious:  return AppColors.toolCall
        case .critical: return AppColors.danger
        }
    }

    // MARK: - Memory Indicator

    private var memoryIndicator: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("Memory")
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textTertiary)
            Text(DeviceMetrics.formattedAvailableMemory)
                .font(AppTypography.metric)
                .foregroundStyle(AppColors.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Expanded Metrics Detail

    private func expandedMetricsView(metrics: InferenceMetrics, info: BenchmarkInfo) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Rectangle()
                .fill(AppColors.border)
                .frame(height: 0.5)

            #if os(iOS)
            // iOS: 2-column grid to avoid horizontal overflow on narrow screens
            let columns = [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)]

            // Token latency statistics
            if !metrics.decodeLatenciesMs.isEmpty {
                LazyVGrid(columns: columns, alignment: .leading, spacing: AppSpacing.sm) {
                    statItem(label: "Median", value: String(format: "%.1f ms", metrics.medianTokenLatencyMs))
                    statItem(label: "P95", value: String(format: "%.1f ms", metrics.p95TokenLatencyMs))
                    statItem(label: "Min", value: String(format: "%.1f ms", metrics.minTokenLatencyMs))
                    statItem(label: "Max", value: String(format: "%.1f ms", metrics.maxTokenLatencyMs))
                }
            }

            // Memory delta
            LazyVGrid(columns: columns, alignment: .leading, spacing: AppSpacing.sm) {
                statItem(
                    label: "Mem Start",
                    value: String(format: "%.0f MB", metrics.startSnapshot.availableMemoryMB)
                )
                statItem(
                    label: "Mem End",
                    value: String(format: "%.0f MB", metrics.endSnapshot.availableMemoryMB)
                )
                statItem(
                    label: "Δ Memory",
                    value: String(format: "%+.0f MB", metrics.memoryDeltaMB)
                )
            }

            // Thermal transition
            if metrics.thermalStateChanged {
                HStack(spacing: AppSpacing.xs) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(AppColors.warning)
                    Text("Thermal: \(metrics.startSnapshot.thermalLevel.label) → \(metrics.endSnapshot.thermalLevel.label)")
                        .foregroundStyle(AppColors.textSecondary)
                }
            }

            // Token counts
            LazyVGrid(columns: columns, alignment: .leading, spacing: AppSpacing.sm) {
                statItem(label: "Tokens", value: "\(metrics.totalTokenCount)")
                statItem(label: "Init", value: String(format: "%.2fs", info.initTimeInSecond))
                statItem(label: "Prefill", value: "\(info.lastPrefillTokenCount) tok")
                statItem(label: "Decode", value: "\(info.lastDecodeTokenCount) tok")
            }
            #else
            // Token latency statistics
            if !metrics.decodeLatenciesMs.isEmpty {
                HStack(spacing: AppSpacing.lg) {
                    statItem(label: "Median", value: String(format: "%.1f ms", metrics.medianTokenLatencyMs))
                    statItem(label: "P95", value: String(format: "%.1f ms", metrics.p95TokenLatencyMs))
                    statItem(label: "Min", value: String(format: "%.1f ms", metrics.minTokenLatencyMs))
                    statItem(label: "Max", value: String(format: "%.1f ms", metrics.maxTokenLatencyMs))
                    Spacer()
                }
            }

            // Memory delta
            HStack(spacing: AppSpacing.lg) {
                statItem(
                    label: "Mem Start",
                    value: String(format: "%.0f MB", metrics.startSnapshot.availableMemoryMB)
                )
                statItem(
                    label: "Mem End",
                    value: String(format: "%.0f MB", metrics.endSnapshot.availableMemoryMB)
                )
                statItem(
                    label: "Δ Memory",
                    value: String(format: "%+.0f MB", metrics.memoryDeltaMB)
                )
                Spacer()
            }

            // Thermal transition
            if metrics.thermalStateChanged {
                HStack(spacing: AppSpacing.xs) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(AppColors.warning)
                    Text("Thermal: \(metrics.startSnapshot.thermalLevel.label) → \(metrics.endSnapshot.thermalLevel.label)")
                        .foregroundStyle(AppColors.textSecondary)
                }
            }

            // Token counts
            HStack(spacing: AppSpacing.lg) {
                statItem(label: "Tokens", value: "\(metrics.totalTokenCount)")
                statItem(label: "Init", value: String(format: "%.2fs", info.initTimeInSecond))
                statItem(label: "Prefill", value: "\(info.lastPrefillTokenCount) tok")
                statItem(label: "Decode", value: "\(info.lastDecodeTokenCount) tok")
                Spacer()
            }
            #endif
        }
        .padding(.top, AppSpacing.xs)
    }

    private func statItem(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textTertiary)
            Text(value)
                .font(AppTypography.metric)
                .foregroundStyle(AppColors.textSecondary)
        }
    }

    private func benchmarkItem(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textTertiary)
            Text(value)
                .font(AppTypography.metric)
                .foregroundStyle(AppColors.textSecondary)
        }
    }
}
