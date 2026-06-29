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

import CoreImage
import Foundation
import SwiftUI

// MARK: - Card Metrics

/// Formatted metrics ready for display on the benchmark card.
struct CardMetrics: Sendable, Equatable {
    let decodeSpeedFormatted: String
    let ttftFormatted: String
    let memoryFormatted: String
    let prefillFormatted: String
    let p95LatencyFormatted: String
    let thermalLabel: String
    let tokenCountFormatted: String
}

// MARK: - Card Size

/// Predefined export sizes for the benchmark card.
enum CardSize: String, CaseIterable, Sendable {
    case twitterCard     // 1200×630  — Open Graph / Twitter
    case instagramSquare // 1080×1080 — Instagram
    case `default`       // Adaptive  — in-app display

    // design-system-exempt: image export requires fixed point sizes
    var width: CGFloat {
        switch self {
        case .twitterCard:     return 1200
        case .instagramSquare: return 1080
        case .default:         return 600
        }
    }

    // design-system-exempt: image export requires fixed point sizes
    var height: CGFloat {
        switch self {
        case .twitterCard:     return 630
        case .instagramSquare: return 1080
        case .default:         return 340
        }
    }

    var label: String {
        switch self {
        case .twitterCard:     return "Twitter / Open Graph"
        case .instagramSquare: return "Instagram Square"
        case .default:         return "Default"
        }
    }
}

// MARK: - Benchmark Card Logic

/// Pure-function logic for benchmark card formatting and data preparation.
/// Extracted into an enum namespace for testability.
enum BenchmarkCardLogic {

    /// Format the device name for display on the card.
    static func formatDeviceName() -> String {
        #if os(macOS)
        return Host.current().localizedName ?? "Mac"
        #else
        return UIDevice.current.name
        #endif
    }

    /// Format a MetricsStore.Entry into display-ready CardMetrics.
    static func formatMetrics(_ entry: MetricsStore.Entry) -> CardMetrics {
        let decode = entry.metrics.decodeTokensPerSecond
        let ttft = entry.metrics.ttftSeconds
        let memory = (entry.metrics.availableMemoryAtStartMB ?? 0) - (entry.metrics.availableMemoryAtEndMB ?? 0)
        let prefill = entry.metrics.prefillTokensPerSecond
        let p95 = entry.metrics.p95TokenLatencyMs ?? 0
        let thermal = entry.metrics.thermalStateAtEnd ?? "nominal"
        let tokens = entry.metrics.lastDecodeTokenCount

        return CardMetrics(
            decodeSpeedFormatted: formatDecodeSpeed(decode),
            ttftFormatted: formatTTFT(ttft),
            memoryFormatted: formatMemory(memory),
            prefillFormatted: String(format: "%.1f tok/s", prefill),
            p95LatencyFormatted: String(format: "%.1f ms", p95),
            thermalLabel: thermal.capitalized,
            tokenCountFormatted: "\(tokens) tokens"
        )
    }

    /// Format decode speed for display (e.g., "42.3" or "101").
    static func formatDecodeSpeed(_ speed: Double) -> String {
        if speed >= 100 {
            return String(format: "%.0f", speed)
        }
        return String(format: "%.1f", speed)
    }

    /// Format TTFT for display in milliseconds (e.g., "89 ms" or "1.2 s").
    static func formatTTFT(_ seconds: Double) -> String {
        let ms = seconds * 1000
        if ms < 1000 {
            return String(format: "%.0f ms", ms)
        }
        return String(format: "%.1f s", seconds)
    }

    /// Format memory delta for display (e.g., "1.2 GB" or "512 MB").
    static func formatMemory(_ deltaMB: Double) -> String {
        let absMB = abs(deltaMB)
        if absMB >= 1024 {
            return String(format: "%.1f GB", absMB / 1024.0)
        }
        return String(format: "%.0f MB", absMB)
    }

    /// Extract sparkline data from metrics history.
    /// Returns the last `limit` decode speeds as an array of Doubles.
    static func sparklineData(
        from history: [MetricsStore.Entry],
        limit: Int = 5
    ) -> [Double] {
        let recent = Array(history.suffix(limit))
        return recent.map { $0.metrics.decodeTokensPerSecond }
    }

    /// Generate a QR code image from a URL string.
    /// Returns nil if generation fails.
    static func generateQRImage(for urlString: String) -> CGImage? {
        guard let data = urlString.data(using: .ascii) else { return nil }
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")

        guard let outputImage = filter.outputImage else { return nil }

        // Scale up the QR code (it starts very small)
        let scale = CGAffineTransform(scaleX: 10, y: 10)
        let scaledImage = outputImage.transformed(by: scale)

        let context = CIContext()
        return context.createCGImage(scaledImage, from: scaledImage.extent)
    }

    /// Generate a social media caption for sharing.
    static func generateShareCaption(from data: BenchmarkCardData) -> String {
        let speed = formatDecodeSpeed(data.decodeSpeed)
        let ttft = formatTTFT(data.ttft)
        let memory = formatMemory(abs(data.memoryDeltaMB))

        return """
        🚀 \(data.modelName) on \(data.deviceName)
        📊 \(speed) tok/s decode · \(ttft) TTFT · \(memory) memory
        🔬 Benchmarked with Edge AI Lab
        github.com/AndrewVoirol/edge-ai-lab
        """
    }

    /// Generate a social media caption from a MetricsStore.Entry.
    static func generateShareCaption(from entry: MetricsStore.Entry) -> String {
        let speed = formatDecodeSpeed(entry.metrics.decodeTokensPerSecond)
        let ttft = formatTTFT(entry.metrics.ttftSeconds)
        let memory: String
        if let startMB = entry.metrics.availableMemoryAtStartMB,
           let endMB = entry.metrics.availableMemoryAtEndMB {
            memory = formatMemory(abs(startMB - endMB))
        } else {
            memory = "N/A"
        }

        return """
        🚀 \(entry.model) on \(entry.device)
        📊 \(speed) tok/s decode · \(ttft) TTFT · \(memory) memory
        🔬 Benchmarked with Edge AI Lab
        github.com/AndrewVoirol/edge-ai-lab
        """
    }
}
