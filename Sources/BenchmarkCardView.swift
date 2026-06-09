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

// MARK: - Benchmark Card Data

/// All the data needed to render a shareable benchmark card.
/// Constructed from BenchmarkInfo + InferenceMetrics + model/device context.
struct BenchmarkCardData: Sendable {
    let modelName: String
    let modelArchitecture: String
    let backendLabel: String
    let deviceName: String
    let chipName: String
    let osVersion: String
    let ramGB: Int
    let decodeSpeed: Double
    let prefillSpeed: Double
    let ttft: Double
    let p95LatencyMs: Double
    let medianLatencyMs: Double
    let memoryDeltaMB: Double
    let thermalState: ThermalLevel
    let tokenCount: Int
    let timestamp: Date

    /// Performance tier derived from decode speed.
    var tier: PerformanceTier {
        PerformanceTier(decodeSpeed: decodeSpeed)
    }

    /// Create from live benchmark results.
    static func from(
        benchmarkInfo: BenchmarkInfo,
        inferenceMetrics: InferenceMetrics?,
        modelMetadata: ModelMetadata?,
        backendResult: BackendResult?
    ) -> BenchmarkCardData {
        let ramGB = Int(ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024))

        // Resolve chip name from utsname
        var systemInfo = utsname()
        uname(&systemInfo)
        let machine = withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }

        #if os(macOS)
        let deviceName = Host.current().localizedName ?? "Mac"
        let osLabel = "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)"
        #else
        let deviceName = UIDevice.current.name
        let osLabel = "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)"
        #endif

        return BenchmarkCardData(
            modelName: modelMetadata?.name ?? "Unknown Model",
            modelArchitecture: modelMetadata?.architectureType ?? "LiteRT-LM",
            backendLabel: backendResult?.activeBackend == .gpu ? "GPU (Metal)" : "CPU (XNNPACK)",
            deviceName: deviceName,
            chipName: machine,
            osVersion: osLabel,
            ramGB: ramGB,
            decodeSpeed: benchmarkInfo.lastDecodeTokensPerSecond,
            prefillSpeed: benchmarkInfo.lastPrefillTokensPerSecond,
            ttft: benchmarkInfo.timeToFirstTokenInSecond,
            p95LatencyMs: inferenceMetrics?.p95TokenLatencyMs ?? 0,
            medianLatencyMs: inferenceMetrics?.medianTokenLatencyMs ?? 0,
            memoryDeltaMB: inferenceMetrics?.memoryDeltaMB ?? 0,
            thermalState: inferenceMetrics?.endSnapshot.thermalLevel ?? .nominal,
            tokenCount: inferenceMetrics?.totalTokenCount ?? benchmarkInfo.lastDecodeTokenCount,
            timestamp: Date()
        )
    }
}

// MARK: - Benchmark Card View

/// A beautiful, branded benchmark result card designed for sharing.
/// Renders at 1200×630 (Open Graph standard) for optimal display when
/// pasted into X, Discord, Slack, Reddit, etc.
///
/// Design: Dark Forest theme with glass morphism, tier-colored hero metric,
/// and subtle branding. No watermarks — just clean, premium design.
struct BenchmarkCardView: View {
    let data: BenchmarkCardData

    /// Card dimensions — Open Graph standard for social media embeds.
    static let cardWidth: CGFloat = 1200
    static let cardHeight: CGFloat = 630

    var body: some View {
        ZStack {
            // Background — deep forest with radial gradient
            cardBackground

            // Content layout
            VStack(spacing: 0) {
                // Header — branding + model info
                cardHeader
                    .padding(.horizontal, 48)
                    .padding(.top, 40)

                Spacer()

                // Hero metric — decode speed (the number everyone cares about)
                heroMetric
                    .padding(.horizontal, 48)

                Spacer()

                // Secondary metrics grid
                metricsGrid
                    .padding(.horizontal, 48)

                Spacer()

                // Footer — device info + attribution
                cardFooter
                    .padding(.horizontal, 48)
                    .padding(.bottom, 36)
            }
        }
        .frame(width: Self.cardWidth, height: Self.cardHeight)
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }

    // MARK: - Background

    private var cardBackground: some View {
        ZStack {
            // Base
            Color(red: 0.04, green: 0.05, blue: 0.04)

            // Radial gradient — forest depth
            RadialGradient(
                colors: [
                    AppColors.accentTeal.opacity(0.15),
                    Color.clear
                ],
                center: .topLeading,
                startRadius: 100,
                endRadius: 600
            )

            // Secondary glow — warm ambient
            RadialGradient(
                colors: [
                    data.tier.color.opacity(0.08),
                    Color.clear
                ],
                center: .center,
                startRadius: 50,
                endRadius: 400
            )

            // Subtle noise texture overlay
            RoundedRectangle(cornerRadius: 24)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.08),
                            Color.white.opacity(0.02),
                            Color.white.opacity(0.06)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
    }

    // MARK: - Header

    private var cardHeader: some View {
        HStack(alignment: .top) {
            // Logo + app name
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 12) {
                    // App icon placeholder — stylized terminal prompt
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(AppColors.accentTeal.opacity(0.2))
                            .frame(width: 40, height: 40)
                        Text("⚡")
                            .font(.system(size: 22))
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Edge AI Lab")
                            .font(.system(size: 20, weight: .bold, design: .default))
                            .foregroundStyle(AppColors.textPrimary)
                        Text("Benchmark Result")
                            .font(.system(size: 13, weight: .medium, design: .default))
                            .foregroundStyle(AppColors.textTertiary)
                    }
                }
            }

            Spacer()

            // Model info pill
            VStack(alignment: .trailing, spacing: 6) {
                Text(data.modelName)
                    .font(.system(size: 16, weight: .semibold, design: .default))
                    .foregroundStyle(AppColors.textPrimary)

                HStack(spacing: 8) {
                    Text(data.modelArchitecture)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(AppColors.accentTeal)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(AppColors.accentTeal.opacity(0.12))
                        .clipShape(Capsule())

                    Text(data.backendLabel)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(data.backendLabel.contains("GPU") ? AppColors.success : AppColors.warning)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            (data.backendLabel.contains("GPU") ? AppColors.success : AppColors.warning)
                                .opacity(0.12)
                        )
                        .clipShape(Capsule())
                }
            }
        }
    }

    // MARK: - Hero Metric

    private var heroMetric: some View {
        VStack(spacing: 8) {
            // Decode speed — the big number
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(String(format: "%.1f", data.decodeSpeed))
                    .font(.system(size: 96, weight: .bold, design: .monospaced))
                    .foregroundStyle(data.tier.color)
                    .shadow(color: data.tier.color.opacity(0.3), radius: 20, x: 0, y: 0)

                Text("tok/s")
                    .font(.system(size: 28, weight: .medium, design: .monospaced))
                    .foregroundStyle(data.tier.color.opacity(0.7))
            }

            // Tier badge
            HStack(spacing: 8) {
                Circle()
                    .fill(data.tier.color)
                    .frame(width: 8, height: 8)

                Text(data.tier.label.uppercased())
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(data.tier.color)
                    .tracking(2)

                Text("·")
                    .foregroundStyle(AppColors.textTertiary)

                Text("Decode Speed")
                    .font(.system(size: 14, weight: .medium, design: .default))
                    .foregroundStyle(AppColors.textTertiary)
            }
        }
    }

    // MARK: - Metrics Grid

    private var metricsGrid: some View {
        HStack(spacing: 0) {
            metricCell(
                label: "TTFT",
                value: String(format: "%.3fs", data.ttft),
                icon: "bolt.fill"
            )

            metricDivider

            metricCell(
                label: "Prefill",
                value: String(format: "%.1f tok/s", data.prefillSpeed),
                icon: "arrow.right.circle.fill"
            )

            metricDivider

            metricCell(
                label: "P95 Latency",
                value: String(format: "%.1f ms", data.p95LatencyMs),
                icon: "chart.bar.fill"
            )

            metricDivider

            metricCell(
                label: "Memory Δ",
                value: String(format: "%+.0f MB", data.memoryDeltaMB),
                icon: "memorychip.fill"
            )

            metricDivider

            metricCell(
                label: "Thermal",
                value: data.thermalState.label,
                icon: data.thermalState.symbolName
            )
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 24)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
                )
        )
    }

    private func metricCell(label: String, value: String, icon: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(AppColors.textTertiary)

            Text(value)
                .font(.system(size: 16, weight: .semibold, design: .monospaced))
                .foregroundStyle(AppColors.textPrimary)

            Text(label)
                .font(.system(size: 11, weight: .medium, design: .default))
                .foregroundStyle(AppColors.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private var metricDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.06))
            .frame(width: 0.5, height: 50)
    }

    // MARK: - Footer

    private var cardFooter: some View {
        HStack {
            // Device info
            HStack(spacing: 16) {
                deviceInfoPill(icon: "desktopcomputer", text: data.deviceName)
                deviceInfoPill(icon: "cpu", text: data.chipName)
                deviceInfoPill(icon: "memorychip", text: "\(data.ramGB) GB RAM")
                deviceInfoPill(icon: "gearshape", text: data.osVersion)
            }

            Spacer()

            // Attribution — repo URL + timestamp
            VStack(alignment: .trailing, spacing: 4) {
                Text("github.com/AndrewVoirol/edge-ai-lab")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(AppColors.accentTeal)

                Text(data.timestamp, format: .dateTime.year().month(.abbreviated).day().hour().minute())
                    .font(.system(size: 11, weight: .regular, design: .default))
                    .foregroundStyle(AppColors.textTertiary)
            }
        }
    }

    private func deviceInfoPill(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
            Text(text)
                .font(.system(size: 11, weight: .medium, design: .default))
        }
        .foregroundStyle(AppColors.textSecondary)
    }
}

// MARK: - Image Renderer

/// Renders a BenchmarkCardView to a platform-native image for sharing.
enum BenchmarkCardRenderer {

    /// Render the benchmark card to a platform image at 2x scale for Retina.
    @MainActor
    static func renderImage(data: BenchmarkCardData) -> PlatformImage? {
        let view = BenchmarkCardView(data: data)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2.0  // Retina — final image will be 2400×1260

        #if os(macOS)
        return renderer.nsImage
        #else
        return renderer.uiImage
        #endif
    }

    /// Render the benchmark card to PNG data.
    @MainActor
    static func renderPNG(data: BenchmarkCardData) -> Data? {
        #if os(macOS)
        guard let image = renderImage(data: data),
              let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
        #else
        guard let image = renderImage(data: data) else { return nil }
        return image.pngData()
        #endif
    }
}

// MARK: - Platform Image Typealias

#if os(macOS)
typealias PlatformImage = NSImage
#else
typealias PlatformImage = UIImage
#endif

// MARK: - Share Sheet Integration

/// A transferable wrapper for the benchmark card image,
/// enabling ShareLink integration in SwiftUI.
struct BenchmarkCardTransferable: Transferable {
    let imageData: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { card in
            card.imageData
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Benchmark Card — Excellent") {
    BenchmarkCardView(data: BenchmarkCardData(
        modelName: "Gemma 4 E2B · Desktop GPU+CPU",
        modelArchitecture: "MoE Edge (2B effective)",
        backendLabel: "GPU (Metal)",
        deviceName: "MacBook Pro",
        chipName: "arm64e",
        osVersion: "macOS 26.0",
        ramGB: 36,
        decodeSpeed: 100.7,
        prefillSpeed: 217.3,
        ttft: 0.143,
        p95LatencyMs: 16.7,
        medianLatencyMs: 9.8,
        memoryDeltaMB: -245,
        thermalState: .nominal,
        tokenCount: 1162,
        timestamp: Date()
    ))
    .padding()
    .background(Color.black)
}

#Preview("Benchmark Card — Fair") {
    BenchmarkCardView(data: BenchmarkCardData(
        modelName: "Gemma 4 12B · Dense Multimodal",
        modelArchitecture: "Dense Multimodal",
        backendLabel: "CPU (XNNPACK)",
        deviceName: "MacBook Pro",
        chipName: "arm64e",
        osVersion: "macOS 26.0",
        ramGB: 36,
        decodeSpeed: 0.57,
        prefillSpeed: 1.3,
        ttft: 9.351,
        p95LatencyMs: 1716.7,
        medianLatencyMs: 1500.2,
        memoryDeltaMB: -1024,
        thermalState: .serious,
        tokenCount: 256,
        timestamp: Date()
    ))
    .padding()
    .background(Color.black)
}
#endif
