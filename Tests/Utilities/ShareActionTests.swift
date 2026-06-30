// Copyright 2026 Andrew Voirol. Apache-2.0

import Foundation
import Testing

#if os(iOS)
@testable import EdgeAILab_iOS
#elseif os(macOS)
@testable import EdgeAILab_macOS
#endif

// MARK: - ShareAction Tests

@Suite("ShareAction")
struct ShareActionTests {

    // MARK: - Caption Generation

    @Test("generateShareCaption — contains all key elements")
    func testCaptionContainsKeyElements() {
        let data = makeTestCardData()
        let caption = BenchmarkCardLogic.generateShareCaption(from: data)

        #expect(caption.contains("Gemma 4 1B"))
        #expect(caption.contains("MacBook Pro"))
        #expect(caption.contains("tok/s"))
        #expect(caption.contains("Edge AI Lab"))
        #expect(caption.contains("github.com/AndrewVoirol/edge-ai-lab"))
    }

    @Test("generateShareCaption — contains emoji markers")
    func testCaptionContainsEmoji() {
        let data = makeTestCardData()
        let caption = BenchmarkCardLogic.generateShareCaption(from: data)

        #expect(caption.contains("🚀"))
        #expect(caption.contains("📊"))
        #expect(caption.contains("🔬"))
    }

    @Test("generateShareCaption — formats speed correctly")
    func testCaptionSpeedFormatting() {
        let data = makeTestCardData(decodeSpeed: 42.3)
        let caption = BenchmarkCardLogic.generateShareCaption(from: data)
        #expect(caption.contains("42.3 tok/s"))
    }

    @Test("generateShareCaption — high speed uses no decimal")
    func testCaptionHighSpeedFormatting() {
        let data = makeTestCardData(decodeSpeed: 150.7)
        let caption = BenchmarkCardLogic.generateShareCaption(from: data)
        #expect(caption.contains("151 tok/s"))
    }

    // MARK: - Caption from Entry

    @Test("generateShareCaption from entry — works with MetricsStore.Entry")
    func testCaptionFromEntry() {
        let entry = makeTestEntry()
        let caption = BenchmarkCardLogic.generateShareCaption(from: entry)

        #expect(caption.contains("test-model"))
        #expect(caption.contains("test-device"))
        #expect(caption.contains("tok/s"))
        #expect(caption.contains("Edge AI Lab"))
    }

    @Test("generateShareCaption from entry — handles missing memory")
    func testCaptionFromEntryMissingMemory() {
        let entry = makeTestEntry()
        let caption = BenchmarkCardLogic.generateShareCaption(from: entry)
        #expect(caption.contains("N/A"))
    }

    @Test("generateShareCaption from entry — shows memory when available")
    func testCaptionFromEntryWithMemory() {
        let entry = makeTestEntryWithMemory()
        let caption = BenchmarkCardLogic.generateShareCaption(from: entry)
        // Should not contain N/A when memory data is present
        #expect(!caption.contains("N/A"))
        #expect(caption.contains("memory"))
    }

    // MARK: - Markdown Output

    @Test("markdown table output — valid for single entry")
    func testMarkdownTableOutput() {
        let entry = makeTestEntry()
        let table = MarkdownExporter.generateBenchmarkTable(entries: [entry])

        // Should be valid markdown table
        #expect(table.contains("|"))
        #expect(table.contains("Decode (tok/s)"))
    }

    @Test("markdown template — includes version info")
    func testMarkdownTemplateVersion() {
        let entry = makeTestEntry()
        let template = MarkdownExporter.generateGitHubTemplate(entry: entry)

        // Should reference Edge AI Lab
        #expect(template.contains("Edge AI Lab"))
    }

    // MARK: - Test Helpers

    private func makeTestCardData(decodeSpeed: Double = 42.3) -> BenchmarkCardData {
        BenchmarkCardData(
            modelName: "Gemma 4 1B",
            modelArchitecture: "Dense 1B",
            backendLabel: "GPU (Metal)",
            deviceName: "MacBook Pro",
            chipName: "arm64e",
            osVersion: "macOS 26.0",
            ramGB: 36,
            decodeSpeed: decodeSpeed,
            prefillSpeed: 128.7,
            ttft: 0.089,
            p95LatencyMs: 16.7,
            medianLatencyMs: 9.8,
            memoryDeltaMB: -245,
            thermalState: .nominal,
            tokenCount: 512,
            timestamp: Date()
        )
    }

    private func makeTestEntry() -> MetricsStore.Entry {
        MetricsStore.Entry(
            timestamp: "2026-06-28T12:00:00Z",
            model: "test-model",
            platform: "macOS",
            device: "test-device",
            metrics: MetricsStore.Entry.Metrics(
                initTimeSeconds: 1.5,
                ttftSeconds: 0.342,
                decodeTokensPerSecond: 42.3,
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

    private func makeTestEntryWithMemory() -> MetricsStore.Entry {
        MetricsStore.Entry(
            timestamp: "2026-06-28T12:00:00Z",
            model: "test-model",
            platform: "macOS",
            device: "test-device",
            metrics: MetricsStore.Entry.Metrics(
                initTimeSeconds: 1.5,
                ttftSeconds: 0.342,
                decodeTokensPerSecond: 42.3,
                prefillTokensPerSecond: 128.7,
                lastPrefillTokenCount: 256,
                lastDecodeTokenCount: 128,
                thermalStateAtStart: nil,
                thermalStateAtEnd: nil,
                availableMemoryAtStartMB: 8192,
                availableMemoryAtEndMB: 7680,
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
