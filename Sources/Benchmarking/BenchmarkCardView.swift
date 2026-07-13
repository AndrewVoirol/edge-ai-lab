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

import Charts
import LiteRTLM
import SwiftUI

// MARK: - Benchmark Card Data

// MARK: Design System Notes
// This file renders image-export benchmark cards via ImageRenderer.
// Colors use AppColors tokens. Corner radii use AppRadius tokens.
// Font sizes remain fixed (not AppTypography) because ImageRenderer
// requires deterministic point sizes for pixel-perfect export.
// Fixed sizes are marked: // design-system-exempt: image export requires fixed point sizes

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

    /// Optional sparkline history for trend display.
    var sparklineHistory: [Double] = []

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

    /// Create from universal `EnginePerformanceMetrics` — works for all engine types.
    static func from(
        performanceMetrics: EnginePerformanceMetrics,
        inferenceMetrics: InferenceMetrics?,
        modelMetadata: ModelMetadata?,
        backendResult: BackendResult?
    ) -> BenchmarkCardData {
        let ramGB = Int(ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024))

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

        let runtimeLabel: String
        switch performanceMetrics.runtimeType {
        case .mlx:
            runtimeLabel = "MLX (Metal)"
        case .litertlm:
            runtimeLabel = backendResult?.activeBackend == .gpu ? "GPU (Metal)" : "CPU (XNNPACK)"
        case .gguf:
            runtimeLabel = "GGUF (llama.cpp)"
        }

        return BenchmarkCardData(
            modelName: modelMetadata?.name ?? "Unknown Model",
            modelArchitecture: modelMetadata?.architectureType ?? runtimeLabel,
            backendLabel: runtimeLabel,
            deviceName: deviceName,
            chipName: machine,
            osVersion: osLabel,
            ramGB: ramGB,
            decodeSpeed: performanceMetrics.tokensPerSecond,
            prefillSpeed: performanceMetrics.promptTokensPerSecond ?? 0,
            ttft: performanceMetrics.timeToFirstToken ?? 0,
            p95LatencyMs: inferenceMetrics?.p95TokenLatencyMs ?? 0,
            medianLatencyMs: inferenceMetrics?.medianTokenLatencyMs ?? 0,
            memoryDeltaMB: inferenceMetrics?.memoryDeltaMB ?? 0,
            thermalState: inferenceMetrics?.endSnapshot.thermalLevel ?? .nominal,
            tokenCount: inferenceMetrics?.totalTokenCount ?? performanceMetrics.tokenCount ?? 0,
            timestamp: Date()
        )
    }
}



// MARK: - Benchmark Card View

/// A premium, dark/sleek benchmark result card designed for sharing.
/// Renders at configurable sizes for optimal display when pasted into
/// X, Discord, Slack, Reddit, Instagram, etc.
///
/// Design: Dark tech aesthetic with neon accents, glow effects,
/// and SF Mono hero metrics.
struct BenchmarkCardView: View {
    let data: BenchmarkCardData
    var cardSize: CardSize

    /// Default to Twitter card for backward compatibility.
    init(data: BenchmarkCardData, cardSize: CardSize = .twitterCard) {
        self.data = data
        self.cardSize = cardSize
    }

    var body: some View {
        ZStack {
            // Background — deep dark with subtle gradient
            cardBackground

            // Content layout
            VStack(spacing: 0) {
                // Header — device name + model info
                cardHeader
                    .padding(.horizontal, horizontalPadding)
                    .padding(.top, topPadding)

                // Gradient divider
                gradientDivider
                    .padding(.horizontal, horizontalPadding)
                    .padding(.top, sectionSpacing)

                Spacer()

                // Hero metrics — 3 columns
                heroMetrics
                    .padding(.horizontal, horizontalPadding)

                // Sparkline (if data available)
                if !data.sparklineHistory.isEmpty {
                    sparklineView
                        .padding(.horizontal, horizontalPadding)
                        .padding(.top, sectionSpacing)
                }

                Spacer()

                // Secondary metrics bar
                secondaryMetrics
                    .padding(.horizontal, horizontalPadding)

                Spacer()

                // Footer — branding + QR/graphic
                cardFooter
                    .padding(.horizontal, horizontalPadding)
                    .padding(.bottom, bottomPadding)
            }
        }
        .frame(width: cardSize.width, height: cardSize.height)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.card))
    }

    // MARK: - Adaptive Sizing

    // design-system-exempt: image export requires fixed point sizes
    private var horizontalPadding: CGFloat {
        cardSize == .instagramSquare ? 56 : 48
    }

    // design-system-exempt: image export requires fixed point sizes
    private var topPadding: CGFloat {
        cardSize == .instagramSquare ? 56 : 40
    }

    // design-system-exempt: image export requires fixed point sizes
    private var bottomPadding: CGFloat {
        cardSize == .instagramSquare ? 48 : 36
    }

    // design-system-exempt: image export requires fixed point sizes
    private var sectionSpacing: CGFloat {
        cardSize == .instagramSquare ? 20 : 12
    }

    // design-system-exempt: image export requires fixed point sizes
    private var heroFontSize: CGFloat {
        switch cardSize {
        case .twitterCard:     return 96
        case .instagramSquare: return 108
        case .default:         return 48
        }
    }

    // design-system-exempt: image export requires fixed point sizes
    private var heroUnitSize: CGFloat {
        switch cardSize {
        case .twitterCard:     return 28
        case .instagramSquare: return 32
        case .default:         return 16
        }
    }

    // design-system-exempt: image export requires fixed point sizes
    private var secondaryMetricSize: CGFloat {
        switch cardSize {
        case .twitterCard:     return 36
        case .instagramSquare: return 42
        case .default:         return 20
        }
    }

    // design-system-exempt: image export requires fixed point sizes
    private var labelSize: CGFloat {
        switch cardSize {
        case .twitterCard:     return 13
        case .instagramSquare: return 15
        case .default:         return 10
        }
    }

    // MARK: - Background

    private var cardBackground: some View {
        ZStack {
            // Base dark gradient
            LinearGradient(
                colors: [AppColors.backgroundPrimary, AppColors.backgroundSecondary],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Neon blue glow — top right
            RadialGradient(
                colors: [
                    AppColors.accentPrimary.opacity(0.12),
                    Color.clear
                ],
                center: .topTrailing,
                startRadius: 50,
                endRadius: 400
            )

            // Neon green glow — bottom left (subtle)
            RadialGradient(
                colors: [
                    AppColors.success.opacity(0.06),
                    Color.clear
                ],
                center: .bottomLeading,
                startRadius: 30,
                endRadius: 350
            )

            // 1px border
            RoundedRectangle(cornerRadius: AppRadius.card)
                .stroke(AppColors.border, lineWidth: 1)
        }
    }

    // MARK: - Gradient Divider

    private var gradientDivider: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [
                        Color.clear,
                        AppColors.accentPrimary.opacity(0.3),
                        AppColors.success.opacity(0.3),
                        Color.clear
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(height: 1)
    }

    // MARK: - Header

    private var cardHeader: some View {
        HStack(alignment: .top) {
            // Device icon + name
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Image(systemName: "cpu")
                        .font(.system(size: labelSize + 6, weight: .medium)) // design-system-exempt: image export requires fixed point sizes
                        .foregroundStyle(AppColors.accentPrimary)

                    Text(data.deviceName)
                        .font(.system(size: labelSize + 7, weight: .semibold, design: .default)) // design-system-exempt: image export requires fixed point sizes
                        .foregroundStyle(AppColors.textPrimary)
                }

                // Model info
                Text(data.modelName)
                    .font(.system(size: labelSize + 2, weight: .medium, design: .default)) // design-system-exempt: image export requires fixed point sizes
                    .foregroundStyle(AppColors.textSecondary)
            }

            Spacer()

            // Architecture + backend badges
            VStack(alignment: .trailing, spacing: 6) {
                HStack(spacing: 8) {
                    Text(data.modelArchitecture)
                        .font(.system(size: labelSize, weight: .medium, design: .rounded)) // design-system-exempt: image export requires fixed point sizes
                        .foregroundStyle(AppColors.accentPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(AppColors.accentPrimary.opacity(0.12))
                        .clipShape(Capsule())

                    Text(data.backendLabel)
                        .font(.system(size: labelSize, weight: .medium, design: .rounded)) // design-system-exempt: image export requires fixed point sizes
                        .foregroundStyle(
                            data.backendLabel.contains("GPU") ? AppColors.success : AppColors.textSecondary
                        )
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            (data.backendLabel.contains("GPU") ? AppColors.success : AppColors.textSecondary)
                                .opacity(0.12)
                        )
                        .clipShape(Capsule())
                }
            }
        }
    }

    // MARK: - Hero Metrics (3 Columns)

    private var heroMetrics: some View {
        HStack(spacing: 0) {
            // Decode Speed — primary hero (neon blue)
            heroMetricColumn(
                value: BenchmarkCardLogic.formatDecodeSpeed(data.decodeSpeed),
                unit: "tok/s",
                label: "DECODE",
                color: AppColors.accentPrimary,
                isHero: true
            )

            // Vertical divider
            heroColumnDivider

            // TTFT — secondary (neon green)
            heroMetricColumn(
                value: BenchmarkCardLogic.formatTTFT(data.ttft),
                unit: "",
                label: "TTFT",
                color: AppColors.success,
                isHero: false
            )

            // Vertical divider
            heroColumnDivider

            // Memory — secondary (neon green)
            heroMetricColumn(
                value: BenchmarkCardLogic.formatMemory(abs(data.memoryDeltaMB)),
                unit: "",
                label: "MEMORY",
                color: AppColors.success,
                isHero: false
            )
        }
    }

    private func heroMetricColumn(
        value: String,
        unit: String,
        label: String,
        color: Color,
        isHero: Bool
    ) -> some View {
        VStack(spacing: 4) {
            if isHero {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value)
                        .font(.system(size: heroFontSize, weight: .bold, design: .monospaced)) // design-system-exempt: image export requires fixed point sizes
                        .foregroundStyle(color)
                        .shadow(color: color.opacity(0.4), radius: 20, x: 0, y: 0) // design-system-exempt: image-export pixel-exact rendering

                    Text(unit)
                        .font(.system(size: heroUnitSize, weight: .medium, design: .monospaced)) // design-system-exempt: image export requires fixed point sizes
                        .foregroundStyle(color.opacity(0.6))
                }
            } else {
                Text(value)
                    .font(.system(size: secondaryMetricSize, weight: .bold, design: .monospaced)) // design-system-exempt: image export requires fixed point sizes
                    .foregroundStyle(color)
                    .shadow(color: color.opacity(0.25), radius: 12, x: 0, y: 0) // design-system-exempt: image-export pixel-exact rendering
            }

            Text(label)
                .font(.system(size: labelSize, weight: .semibold, design: .default)) // design-system-exempt: image export requires fixed point sizes
                .foregroundStyle(AppColors.textTertiary)
                .tracking(2)
        }
        .frame(maxWidth: .infinity)
    }

    private var heroColumnDivider: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [Color.clear, AppColors.border, Color.clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: 1, height: heroFontSize * 0.8)
    }

    // MARK: - Sparkline

    private var sparklineView: some View {
        VStack(spacing: 4) {
            Chart {
                ForEach(Array(data.sparklineHistory.enumerated()), id: \.offset) { index, speed in
                    LineMark(
                        x: .value("Run", index),
                        y: .value("Speed", speed)
                    )
                    .foregroundStyle(AppColors.accentPrimary.opacity(0.8))
                    .lineStyle(StrokeStyle(lineWidth: 2))

                    AreaMark(
                        x: .value("Run", index),
                        y: .value("Speed", speed)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [AppColors.accentPrimary.opacity(0.2), Color.clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(height: cardSize == .instagramSquare ? 60 : 40)

            Text("PERFORMANCE TREND · LAST \(data.sparklineHistory.count) RUNS")
                .font(.system(size: labelSize - 2, weight: .medium, design: .default)) // design-system-exempt: image export requires fixed point sizes
                .foregroundStyle(AppColors.textTertiary)
                .tracking(1)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.02))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(AppColors.border.opacity(0.5), lineWidth: 0.5)
                )
        )
    }

    // MARK: - Secondary Metrics

    private var secondaryMetrics: some View {
        HStack(spacing: 0) {
            secondaryMetricCell(
                label: "PREFILL",
                value: String(format: "%.1f tok/s", data.prefillSpeed),
                icon: "arrow.right.circle.fill"
            )

            secondaryDivider

            secondaryMetricCell(
                label: "P95 LATENCY",
                value: String(format: "%.1f ms", data.p95LatencyMs),
                icon: "chart.bar.fill"
            )

            secondaryDivider

            secondaryMetricCell(
                label: "THERMAL",
                value: data.thermalState.label,
                icon: data.thermalState.symbolName
            )

            secondaryDivider

            secondaryMetricCell(
                label: "TOKENS",
                value: "\(data.tokenCount)",
                icon: "text.word.spacing"
            )
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 20)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(AppColors.border.opacity(0.5), lineWidth: 0.5)
                )
        )
    }

    private func secondaryMetricCell(label: String, value: String, icon: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: labelSize, weight: .medium)) // design-system-exempt: image export requires fixed point sizes
                .foregroundStyle(AppColors.textTertiary)

            Text(value)
                .font(.system(size: labelSize + 2, weight: .semibold, design: .monospaced)) // design-system-exempt: image export requires fixed point sizes
                .foregroundStyle(AppColors.textPrimary)

            Text(label)
                .font(.system(size: labelSize - 2, weight: .medium, design: .default)) // design-system-exempt: image export requires fixed point sizes
                .foregroundStyle(AppColors.textTertiary)
                .tracking(1)
        }
        .frame(maxWidth: .infinity)
    }

    private var secondaryDivider: some View {
        Rectangle()
            .fill(AppColors.border.opacity(0.5))
            .frame(width: 0.5, height: 40)
    }

    // MARK: - Footer

    private var cardFooter: some View {
        HStack {
            // Device info pills
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 12) {
                    deviceInfoPill(icon: "cpu", text: data.chipName)
                    deviceInfoPill(icon: "memorychip", text: "\(data.ramGB) GB RAM")
                    deviceInfoPill(icon: "gearshape", text: data.osVersion)
                }

                // Tier badge
                HStack(spacing: 6) {
                    Circle()
                        .fill(data.tier.color)
                        .frame(width: AppSize.dotMd, height: AppSize.dotMd)
                    Text(data.tier.label.uppercased())
                        .font(.system(size: labelSize - 1, weight: .bold, design: .default)) // design-system-exempt: image export requires fixed point sizes
                        .foregroundStyle(data.tier.color)
                        .tracking(2)
                }
            }

            Spacer()

            // Branding + QR or mini chart
            VStack(alignment: .trailing, spacing: 6) {
                HStack(spacing: 8) {
                    Text("⚡")
                        .font(.system(size: labelSize + 4)) // design-system-exempt: image export requires fixed point sizes
                    Text("Edge AI Lab")
                        .font(.system(size: labelSize + 2, weight: .semibold, design: .default)) // design-system-exempt: image export requires fixed point sizes
                        .foregroundStyle(AppColors.textPrimary)
                }

                Text("github.com/AndrewVoirol/edge-ai-lab")
                    .font(.system(size: labelSize, weight: .medium, design: .monospaced)) // design-system-exempt: image export requires fixed point sizes
                    .foregroundStyle(AppColors.accentPrimary.opacity(0.7))

                Text(data.timestamp, format: .dateTime.year().month(.abbreviated).day().hour().minute())
                    .font(.system(size: labelSize - 1, weight: .regular, design: .default)) // design-system-exempt: image export requires fixed point sizes
                    .foregroundStyle(AppColors.textTertiary)
            }
        }
    }

    private func deviceInfoPill(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: labelSize - 2, weight: .medium)) // design-system-exempt: image export requires fixed point sizes
            Text(text)
                .font(.system(size: labelSize - 1, weight: .regular, design: .default)) // design-system-exempt: image export requires fixed point sizes
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
#Preview("Benchmark Card — Premium Dark") {
    BenchmarkCardView(data: BenchmarkCardData(
        modelName: "Gemma 4 E2B · Desktop GPU+CPU",
        modelArchitecture: "MoE Edge (2B effective)",
        backendLabel: "GPU (Metal)",
        deviceName: "MacBook Pro M4 Max",
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
        timestamp: Date(),
        sparklineHistory: [85.2, 92.1, 98.4, 95.7, 100.7]
    ))
    .padding()
    .background(Color.black)
}

#Preview("Benchmark Card — Instagram Square") {
    BenchmarkCardView(data: BenchmarkCardData(
        modelName: "Gemma 4 1B · Text Only",
        modelArchitecture: "Dense 1B",
        backendLabel: "CPU (XNNPACK)",
        deviceName: "iPhone 16 Pro Max",
        chipName: "iPhone17,2",
        osVersion: "iOS 19.0",
        ramGB: 8,
        decodeSpeed: 42.3,
        prefillSpeed: 128.7,
        ttft: 0.089,
        p95LatencyMs: 32.1,
        medianLatencyMs: 23.4,
        memoryDeltaMB: -512,
        thermalState: .fair,
        tokenCount: 512,
        timestamp: Date(),
        sparklineHistory: [38.1, 40.2, 41.5, 39.8, 42.3]
    ), cardSize: .instagramSquare)
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
