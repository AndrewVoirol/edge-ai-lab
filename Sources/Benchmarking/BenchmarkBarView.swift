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

// MARK: - Benchmark Bar View

/// Displays inference performance metrics in a compact bar with an expandable detail view.
///
/// Consumes `EnginePerformanceMetrics` (the universal type populated by both LiteRT-LM
/// and MLX engines) instead of the LiteRT-specific `BenchmarkInfo`. This fixes the
/// SwiftUI observation bug where `viewModel.benchmarkInfo` (a computed property reading
/// from `@ObservationIgnored engine`) never triggered view updates.
///
/// All `accessibilityIdentifier` values are preserved from the original inline code
/// in `ContentView` so that agent discoverability and UI testing remain intact.
struct BenchmarkBarView: View {
    let metrics: EnginePerformanceMetrics
    @Environment(ConversationViewModel.self) private var viewModel
    @State private var isBenchmarkExpanded = true
    @State private var isShowingBenchmarkCard = false

    var body: some View {
        benchmarkBar(metrics: metrics)
    }

    // MARK: - Benchmark Bar

    private func benchmarkBar(metrics: EnginePerformanceMetrics) -> some View {
        let decodeTier = PerformanceTier(decodeSpeed: metrics.tokensPerSecond)

        return VStack(spacing: AppSpacing.xs) {
            // Compact bar (always visible)
            #if os(iOS)
            // iOS: Two-row wrapped grid to fit narrow screens
            iosBenchmarkCompactBar(metrics: metrics, decodeTier: decodeTier)
            #else
            HStack(spacing: AppSpacing.md) {
                // Runtime/Backend indicator
                runtimeBadge
                    .accessibilityIdentifier("badge_backend")

                Rectangle()
                    .fill(AppColors.border)
                    .frame(width: 0.5, height: 18)

                // Thermal state indicator
                thermalIndicator
                    .accessibilityIdentifier("indicator_thermal")

                Rectangle()
                    .fill(AppColors.border)
                    .frame(width: 0.5, height: 18)

                benchmarkItem(label: "TTFT", value: String(format: "%.3fs", metrics.timeToFirstToken ?? 0))
                    .accessibilityLabel("Time to first token: \(String(format: "%.3f", metrics.timeToFirstToken ?? 0)) seconds")
                Rectangle()
                    .fill(AppColors.border)
                    .frame(width: 0.5, height: 18)

                // Hero metric: decode speed with tier color
                VStack(alignment: .leading, spacing: 1) {
                    Text("Decode")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textTertiary)
                    Text(String(format: "%.1f tok/s", metrics.tokensPerSecond))
                        .font(AppTypography.metric)
                        .foregroundStyle(decodeTier.color)
                        .contentTransition(.numericText())
                        .accessibilityLabel("Decode speed: \(String(format: "%.1f", metrics.tokensPerSecond)) tokens per second")
                }

                Rectangle()
                    .fill(AppColors.border)
                    .frame(width: 0.5, height: 18)

                benchmarkItem(label: "Prefill", value: String(format: "%.1f tok/s", metrics.promptTokensPerSecond ?? 0))
                    .accessibilityLabel("Prefill speed: \(String(format: "%.1f", metrics.promptTokensPerSecond ?? 0)) tokens per second")

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
                        .foregroundStyle(AppColors.moss)
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
                        .foregroundStyle(AppColors.caution)
                    Text(reason)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textSecondary)
                    Spacer()
                }
                .padding(.vertical, AppSpacing.xs)
            }

            // Expanded detail view
            if isBenchmarkExpanded {
                expandedMetricsView(metrics: metrics)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .font(AppTypography.caption)
        .sheet(isPresented: $isShowingBenchmarkCard) {
            BenchmarkCardShareSheet(
                cardData: BenchmarkCardData.from(
                    performanceMetrics: metrics,
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
    private func iosBenchmarkCompactBar(metrics: EnginePerformanceMetrics, decodeTier: PerformanceTier) -> some View {
        VStack(spacing: AppSpacing.xs) {
            // Row 1: Backend, Thermal, TTFT, Expand button
            HStack(spacing: AppSpacing.sm) {
                runtimeBadge
                    .accessibilityIdentifier("badge_backend")

                thermalIndicator
                    .accessibilityIdentifier("indicator_thermal")

                benchmarkItem(label: "TTFT", value: String(format: "%.3fs", metrics.timeToFirstToken ?? 0))

                Spacer()

                Button {
                    isShowingBenchmarkCard = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .foregroundStyle(AppColors.moss)
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
                    Text(String(format: "%.1f tok/s", metrics.tokensPerSecond))
                        .font(AppTypography.metric)
                        .foregroundStyle(decodeTier.color)
                        .contentTransition(.numericText())
                        .accessibilityLabel("Decode speed: \(String(format: "%.1f", metrics.tokensPerSecond)) tokens per second")
                }

                benchmarkItem(label: "Prefill", value: String(format: "%.1f tok/s", metrics.promptTokensPerSecond ?? 0))

                memoryIndicator

                Spacer()
            }
        }
    }
    #endif

    // MARK: - Runtime Badge

    /// Shows the runtime type (MLX / LiteRT) and backend (GPU/CPU) as a colored badge.
    private var runtimeBadge: some View {
        HStack(spacing: AppSpacing.xs) {
            if metrics.runtimeType == .mlx {
                Image(systemName: "bolt.fill")
                    .foregroundStyle(AppColors.moss)
                Text("MLX")
                    .font(AppTypography.badge)
                    .foregroundStyle(AppColors.moss)
            } else if let result = viewModel.backendResult {
                Image(systemName: result.activeBackend == .gpu ? "bolt.fill" : "cpu")
                    .foregroundStyle(result.activeBackend == .gpu ? AppColors.sprout : AppColors.caution)
                Text(result.activeBackend == .gpu ? "GPU" : "CPU")
                    .font(AppTypography.badge)
                    .foregroundStyle(result.activeBackend == .gpu ? AppColors.sprout : AppColors.caution)
            } else {
                Image(systemName: "cpu")
                    .foregroundStyle(AppColors.textSecondary)
                Text("LiteRT")
                    .font(AppTypography.badge)
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
    }

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
        case .nominal:  return AppColors.sprout
        case .fair:     return AppColors.caution
        case .serious:  return AppColors.action
        case .critical: return AppColors.ember
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

    private func expandedMetricsView(metrics: EnginePerformanceMetrics) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Rectangle()
                .fill(AppColors.border)
                .frame(height: 0.5)

            #if os(iOS)
            // iOS: 2-column grid to avoid horizontal overflow on narrow screens
            let columns = [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)]

            // Token latency statistics (from InferenceMetrics if available)
            if let inferenceMetrics = viewModel.inferenceMetrics,
               !inferenceMetrics.decodeLatenciesMs.isEmpty {
                expandedSection(title: "LATENCY") {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: AppSpacing.sm) {
                        coloredStatItem(label: "Median", value: String(format: "%.1f ms", inferenceMetrics.medianTokenLatencyMs), color: AppColors.moss)
                        coloredStatItem(label: "P95", value: String(format: "%.1f ms", inferenceMetrics.p95TokenLatencyMs), color: AppColors.moss)
                        coloredStatItem(label: "Min", value: String(format: "%.1f ms", inferenceMetrics.minTokenLatencyMs), color: AppColors.moss)
                        coloredStatItem(label: "Max", value: String(format: "%.1f ms", inferenceMetrics.maxTokenLatencyMs), color: AppColors.moss)
                    }
                }
            }

            // Memory delta (from InferenceMetrics)
            if let inferenceMetrics = viewModel.inferenceMetrics {
                expandedSection(title: "MEMORY") {
                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        LazyVGrid(columns: columns, alignment: .leading, spacing: AppSpacing.sm) {
                            coloredStatItem(label: "Start", value: String(format: "%.0f MB", inferenceMetrics.startSnapshot.availableMemoryMB), color: AppColors.moss)
                            coloredStatItem(label: "End", value: String(format: "%.0f MB", inferenceMetrics.endSnapshot.availableMemoryMB), color: AppColors.moss)
                            coloredStatItem(label: "Δ Memory", value: String(format: "%+.0f MB", inferenceMetrics.memoryDeltaMB), color: inferenceMetrics.memoryDeltaMB < -500 ? AppColors.caution : AppColors.moss)
                        }

                        // Thermal transition
                        if inferenceMetrics.thermalStateChanged {
                            HStack(spacing: AppSpacing.xs) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(AppColors.caution)
                                Text("Thermal: \(inferenceMetrics.startSnapshot.thermalLevel.label) → \(inferenceMetrics.endSnapshot.thermalLevel.label)")
                                    .foregroundStyle(AppColors.textSecondary)
                            }
                        }
                    }
                }
            }

            // Token counts and timing
            expandedSection(title: "TOKENS") {
                LazyVGrid(columns: columns, alignment: .leading, spacing: AppSpacing.sm) {
                    coloredStatItem(label: "Decode", value: "\(metrics.tokenCount ?? 0) tok", color: AppColors.amber)
                    if let initTime = metrics.initTimeSeconds {
                        coloredStatItem(label: "Init", value: String(format: "%.2fs", initTime), color: AppColors.amber)
                    }
                    if let prefillCount = metrics.promptTokenCount {
                        coloredStatItem(label: "Prefill", value: "\(prefillCount) tok", color: AppColors.amber)
                    }
                }
            }

            // MTP Speculation stats (MLX only)
            if let acceptance = metrics.draftAcceptanceRate {
                expandedSection(title: "MTP SPECULATION") {
                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        LazyVGrid(columns: columns, alignment: .leading, spacing: AppSpacing.sm) {
                            coloredStatItem(label: "Accept", value: String(format: "%.1f%%", acceptance * 100), color: AppColors.caution)
                            coloredStatItem(label: "Draft", value: "\(metrics.proposedDraftTokens ?? 0) tok", color: AppColors.caution)
                            coloredStatItem(label: "Accepted", value: "\(metrics.acceptedDraftTokens ?? 0) tok", color: AppColors.caution)
                        }
                        if let reason = metrics.passthroughReason {
                            HStack(spacing: AppSpacing.xs) {
                                Image(systemName: "info.circle")
                                    .foregroundStyle(AppColors.textTertiary)
                                Text("Passthrough: \(reason)")
                                    .font(AppTypography.caption)
                                    .foregroundStyle(AppColors.textSecondary)
                            }
                        }
                    }
                }
            }

            // Timing breakdown
            if let promptTime = metrics.promptTimeSeconds, let genTime = metrics.generateTimeSeconds {
                expandedSection(title: "TIMING") {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: AppSpacing.sm) {
                        coloredStatItem(label: "Prefill", value: String(format: "%.3fs", promptTime), color: AppColors.textSecondary)
                        coloredStatItem(label: "Generate", value: String(format: "%.3fs", genTime), color: AppColors.textSecondary)
                    }
                }
            }

            #else
            // macOS: horizontal layout with section headers

            // Token latency statistics (from InferenceMetrics if available)
            if let inferenceMetrics = viewModel.inferenceMetrics,
               !inferenceMetrics.decodeLatenciesMs.isEmpty {
                expandedSection(title: "LATENCY") {
                    HStack(spacing: AppSpacing.lg) {
                        coloredStatItem(label: "Median", value: String(format: "%.1f ms", inferenceMetrics.medianTokenLatencyMs), color: AppColors.moss)
                        coloredStatItem(label: "P95", value: String(format: "%.1f ms", inferenceMetrics.p95TokenLatencyMs), color: AppColors.moss)
                        coloredStatItem(label: "Min", value: String(format: "%.1f ms", inferenceMetrics.minTokenLatencyMs), color: AppColors.moss)
                        coloredStatItem(label: "Max", value: String(format: "%.1f ms", inferenceMetrics.maxTokenLatencyMs), color: AppColors.moss)
                        Spacer()
                    }
                }
            }

            // Memory delta (from InferenceMetrics)
            if let inferenceMetrics = viewModel.inferenceMetrics {
                expandedSection(title: "MEMORY") {
                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        HStack(spacing: AppSpacing.lg) {
                            coloredStatItem(label: "Start", value: String(format: "%.0f MB", inferenceMetrics.startSnapshot.availableMemoryMB), color: AppColors.moss)
                            coloredStatItem(label: "End", value: String(format: "%.0f MB", inferenceMetrics.endSnapshot.availableMemoryMB), color: AppColors.moss)
                            coloredStatItem(label: "Δ Memory", value: String(format: "%+.0f MB", inferenceMetrics.memoryDeltaMB), color: inferenceMetrics.memoryDeltaMB < -500 ? AppColors.caution : AppColors.moss)
                            Spacer()
                        }

                        // Thermal transition
                        if inferenceMetrics.thermalStateChanged {
                            HStack(spacing: AppSpacing.xs) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(AppColors.caution)
                                Text("Thermal: \(inferenceMetrics.startSnapshot.thermalLevel.label) → \(inferenceMetrics.endSnapshot.thermalLevel.label)")
                                    .foregroundStyle(AppColors.textSecondary)
                            }
                        }
                    }
                }
            }

            // Token counts and timing
            expandedSection(title: "TOKENS") {
                HStack(spacing: AppSpacing.lg) {
                    coloredStatItem(label: "Decode", value: "\(metrics.tokenCount ?? 0) tok", color: AppColors.amber)
                    if let initTime = metrics.initTimeSeconds {
                        coloredStatItem(label: "Init", value: String(format: "%.2fs", initTime), color: AppColors.amber)
                    }
                    if let prefillCount = metrics.promptTokenCount {
                        coloredStatItem(label: "Prefill", value: "\(prefillCount) tok", color: AppColors.amber)
                    }
                    Spacer()
                }
            }

            // MTP Speculation stats (MLX only)
            if let acceptance = metrics.draftAcceptanceRate {
                expandedSection(title: "MTP SPECULATION") {
                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        HStack(spacing: AppSpacing.lg) {
                            coloredStatItem(label: "Accept", value: String(format: "%.1f%%", acceptance * 100), color: AppColors.caution)
                            coloredStatItem(label: "Draft", value: "\(metrics.proposedDraftTokens ?? 0) tok", color: AppColors.caution)
                            coloredStatItem(label: "Accepted", value: "\(metrics.acceptedDraftTokens ?? 0) tok", color: AppColors.caution)
                            if let reason = metrics.passthroughReason {
                                coloredStatItem(label: "Passthrough", value: reason, color: AppColors.caution)
                            }
                            Spacer()
                        }
                    }
                }
            }

            // Timing breakdown
            if let promptTime = metrics.promptTimeSeconds, let genTime = metrics.generateTimeSeconds {
                expandedSection(title: "TIMING") {
                    HStack(spacing: AppSpacing.lg) {
                        coloredStatItem(label: "Prefill", value: String(format: "%.3fs", promptTime), color: AppColors.textSecondary)
                        coloredStatItem(label: "Generate", value: String(format: "%.3fs", genTime), color: AppColors.textSecondary)
                        Spacer()
                    }
                }
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

    // MARK: - Visual Polish Helpers

    /// Section wrapper with uppercase header label and subtle background.
    private func expandedSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(title)
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textTertiary)
                .tracking(1)
            content()
        }
        .padding(AppSpacing.sm)
        .background(AppColors.backgroundTertiary.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm))
    }

    /// Stat item with custom value color for visual category grouping.
    private func coloredStatItem(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textTertiary)
            Text(value)
                .font(AppTypography.metric)
                .foregroundStyle(color)
        }
    }
}
