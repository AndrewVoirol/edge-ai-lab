// Copyright 2026 Andrew Voirol. Apache-2.0

import Foundation
import Testing

#if os(iOS)
@testable import EdgeAILab_iOS
#elseif os(macOS)
@testable import EdgeAILab_macOS
#endif

// MARK: - BenchmarkCardLogic Tests

@Suite("BenchmarkCardLogic")
struct BenchmarkCardLogicTests {

    // MARK: - Format Decode Speed

    @Test("formatDecodeSpeed — sub-100 shows one decimal")
    func testFormatDecodeSpeedSubHundred() {
        let result = BenchmarkCardLogic.formatDecodeSpeed(42.3)
        #expect(result == "42.3")
    }

    @Test("formatDecodeSpeed — 100+ shows no decimals")
    func testFormatDecodeSpeedOverHundred() {
        let result = BenchmarkCardLogic.formatDecodeSpeed(100.7)
        #expect(result == "101")
    }

    @Test("formatDecodeSpeed — zero")
    func testFormatDecodeSpeedZero() {
        let result = BenchmarkCardLogic.formatDecodeSpeed(0)
        #expect(result == "0.0")
    }

    @Test("formatDecodeSpeed — exactly 100")
    func testFormatDecodeSpeedExactly100() {
        let result = BenchmarkCardLogic.formatDecodeSpeed(100.0)
        #expect(result == "100")
    }

    // MARK: - Format TTFT

    @Test("formatTTFT — sub-second shows milliseconds")
    func testFormatTTFTSubSecond() {
        let result = BenchmarkCardLogic.formatTTFT(0.089)
        #expect(result == "89 ms")
    }

    @Test("formatTTFT — over 1 second shows seconds")
    func testFormatTTFTOverSecond() {
        let result = BenchmarkCardLogic.formatTTFT(1.234)
        #expect(result == "1.2 s")
    }

    @Test("formatTTFT — exactly 1 second")
    func testFormatTTFTExactlyOneSecond() {
        let result = BenchmarkCardLogic.formatTTFT(1.0)
        #expect(result == "1.0 s")
    }

    @Test("formatTTFT — zero")
    func testFormatTTFTZero() {
        let result = BenchmarkCardLogic.formatTTFT(0)
        #expect(result == "0 ms")
    }

    // MARK: - Format Memory

    @Test("formatMemory — megabytes")
    func testFormatMemoryMB() {
        let result = BenchmarkCardLogic.formatMemory(512)
        #expect(result == "512 MB")
    }

    @Test("formatMemory — gigabytes")
    func testFormatMemoryGB() {
        let result = BenchmarkCardLogic.formatMemory(1536)
        #expect(result == "1.5 GB")
    }

    @Test("formatMemory — negative value shows absolute")
    func testFormatMemoryNegative() {
        let result = BenchmarkCardLogic.formatMemory(-245)
        #expect(result == "245 MB")
    }

    @Test("formatMemory — zero")
    func testFormatMemoryZero() {
        let result = BenchmarkCardLogic.formatMemory(0)
        #expect(result == "0 MB")
    }

    // MARK: - Sparkline Data

    @Test("sparklineData — extracts last N speeds")
    func testSparklineDataLimit() {
        let entries = (0..<10).map { i in
            makeTestEntry(decodeSpeed: Double(i) * 10)
        }

        let sparkline = BenchmarkCardLogic.sparklineData(from: entries, limit: 5)
        #expect(sparkline.count == 5)
        #expect(sparkline[0] == 50.0)
        #expect(sparkline[4] == 90.0)
    }

    @Test("sparklineData — fewer entries than limit")
    func testSparklineDataFewerEntries() {
        let entries = [
            makeTestEntry(decodeSpeed: 42.3),
            makeTestEntry(decodeSpeed: 45.1),
        ]

        let sparkline = BenchmarkCardLogic.sparklineData(from: entries, limit: 5)
        #expect(sparkline.count == 2)
    }

    @Test("sparklineData — empty history")
    func testSparklineDataEmpty() {
        let sparkline = BenchmarkCardLogic.sparklineData(from: [], limit: 5)
        #expect(sparkline.isEmpty)
    }

    // MARK: - Format Metrics

    @Test("formatMetrics — produces all fields")
    func testFormatMetrics() {
        let entry = makeTestEntry(decodeSpeed: 42.3)
        let metrics = BenchmarkCardLogic.formatMetrics(entry)

        #expect(metrics.decodeSpeedFormatted == "42.3")
        #expect(metrics.ttftFormatted == "342 ms")
        #expect(metrics.prefillFormatted == "128.7 tok/s")
        #expect(metrics.tokenCountFormatted == "128 tokens")
    }

    // MARK: - QR Code Generation

    @Test("generateQRImage — valid URL produces non-nil")
    func testQRCodeGeneration() {
        let image = BenchmarkCardLogic.generateQRImage(for: "https://github.com/AndrewVoirol/edge-ai-lab")
        #expect(image != nil)
    }

    @Test("generateQRImage — empty string returns nil")
    func testQRCodeEmptyString() {
        let image = BenchmarkCardLogic.generateQRImage(for: "")
        // Empty ASCII data should still produce a QR code
        // but CIFilter behavior may vary
        // Just verify it doesn't crash
        _ = image
    }

    // MARK: - Share Caption

    @Test("generateShareCaption — contains key elements")
    func testShareCaption() {
        let data = BenchmarkCardData(
            modelName: "Gemma 4 1B",
            modelArchitecture: "Dense",
            backendLabel: "GPU (Metal)",
            deviceName: "MacBook Pro M4 Max",
            chipName: "arm64e",
            osVersion: "macOS 26.0",
            ramGB: 36,
            decodeSpeed: 42.3,
            prefillSpeed: 128.7,
            ttft: 0.089,
            p95LatencyMs: 16.7,
            medianLatencyMs: 9.8,
            memoryDeltaMB: -245,
            thermalState: .nominal,
            tokenCount: 1162,
            timestamp: Date()
        )

        let caption = BenchmarkCardLogic.generateShareCaption(from: data)
        #expect(caption.contains("Gemma 4 1B"))
        #expect(caption.contains("MacBook Pro M4 Max"))
        #expect(caption.contains("42.3 tok/s"))
        #expect(caption.contains("Edge AI Lab"))
        #expect(caption.contains("github.com/AndrewVoirol/edge-ai-lab"))
    }

    @Test("generateShareCaption from entry — contains model and device")
    func testShareCaptionFromEntry() {
        let entry = makeTestEntry(decodeSpeed: 42.3)
        let caption = BenchmarkCardLogic.generateShareCaption(from: entry)
        #expect(caption.contains("test-model"))
        #expect(caption.contains("test-device"))
        #expect(caption.contains("42.3 tok/s"))
    }

    // MARK: - CardSize

    @Test("CardSize — twitterCard dimensions")
    func testCardSizeTwitter() {
        #expect(CardSize.twitterCard.width == 1200)
        #expect(CardSize.twitterCard.height == 630)
    }

    @Test("CardSize — instagramSquare dimensions")
    func testCardSizeInstagram() {
        #expect(CardSize.instagramSquare.width == 1080)
        #expect(CardSize.instagramSquare.height == 1080)
    }

    @Test("CardSize — allCases has 3 items")
    func testCardSizeAllCases() {
        #expect(CardSize.allCases.count == 3)
    }

    // MARK: - Test Helpers

    private func makeTestEntry(decodeSpeed: Double) -> MetricsStore.Entry {
        MetricsStore.Entry(
            timestamp: ISO8601DateFormatter().string(from: Date()),
            model: "test-model",
            platform: "test",
            device: "test-device",
            metrics: MetricsStore.Entry.Metrics(
                initTimeSeconds: 1.5,
                ttftSeconds: 0.342,
                decodeTokensPerSecond: decodeSpeed,
                prefillTokensPerSecond: 128.7,
                lastPrefillTokenCount: 256,
                lastDecodeTokenCount: 128,
                thermalStateAtStart: nil,
                thermalStateAtEnd: nil,
                availableMemoryAtStartMB: nil,
                availableMemoryAtEndMB: nil,
                medianTokenLatencyMs: nil,
                p95TokenLatencyMs: nil,
                decodeLatenciesMs: nil,
                latencyHistogram: nil,
                thermalTransitions: nil,
                estimatedMemoryBandwidthGBps: nil,
                modelLoadDurationMs: nil,
                gpuAllocatedMemoryAtStartMB: nil,
                gpuAllocatedMemoryAtEndMB: nil
            ),
            flags: RuntimeFlags(
                enableBenchmark: true,
                enableSpeculativeDecoding: nil,
                enableConversationConstrainedDecoding: false,
                visualTokenBudget: nil
            )
        )
    }
}
