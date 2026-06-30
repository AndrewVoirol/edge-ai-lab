// Copyright 2026 Andrew Voirol. Apache-2.0

import Foundation
import Testing

#if os(iOS)
@testable import EdgeAILab_iOS
#elseif os(macOS)
@testable import EdgeAILab_macOS
#endif

// MARK: - MarkdownExporter Tests

@Suite("MarkdownExporter")
struct MarkdownExporterTests {

    // MARK: - Benchmark Table

    @Test("generateBenchmarkTable — single entry")
    func testBenchmarkTableSingleEntry() {
        let entry = makeTestEntry(model: "Gemma 4 1B", decodeSpeed: 42.3)
        let table = MarkdownExporter.generateBenchmarkTable(entries: [entry])

        #expect(table.contains("| Model |"))
        #expect(table.contains("|-------|"))
        #expect(table.contains("Gemma 4 1B"))
        #expect(table.contains("42.3"))
    }

    @Test("generateBenchmarkTable — multiple entries")
    func testBenchmarkTableMultipleEntries() {
        let entries = [
            makeTestEntry(model: "Gemma 4 1B", decodeSpeed: 42.3),
            makeTestEntry(model: "Gemma 4 E2B", decodeSpeed: 100.7),
        ]
        let table = MarkdownExporter.generateBenchmarkTable(entries: entries)

        let lines = table.components(separatedBy: "\n")
        // Header + separator + 2 data rows = 4 lines
        #expect(lines.count == 4)
        #expect(table.contains("Gemma 4 1B"))
        #expect(table.contains("Gemma 4 E2B"))
    }

    @Test("generateBenchmarkTable — empty entries")
    func testBenchmarkTableEmpty() {
        let table = MarkdownExporter.generateBenchmarkTable(entries: [])
        #expect(table == "_No benchmark data available._")
    }

    @Test("generateBenchmarkTable — special characters in model name")
    func testBenchmarkTableSpecialCharacters() {
        let entry = makeTestEntry(model: "Model|With|Pipes", decodeSpeed: 10.0)
        let table = MarkdownExporter.generateBenchmarkTable(entries: [entry])

        // Pipes should be escaped
        #expect(table.contains("Model\\|With\\|Pipes"))
    }

    // MARK: - GitHub Template

    @Test("generateGitHubTemplate — contains all sections")
    func testGitHubTemplate() {
        let entry = makeTestEntry(model: "Gemma 4 1B", decodeSpeed: 42.3)
        let template = MarkdownExporter.generateGitHubTemplate(entry: entry)

        #expect(template.contains("## Benchmark Result: Gemma 4 1B"))
        #expect(template.contains("### Device"))
        #expect(template.contains("### Performance Metrics"))
        #expect(template.contains("### Configuration"))
        #expect(template.contains("Edge AI Lab"))
        #expect(template.contains("42.3"))
    }

    @Test("generateGitHubTemplate — includes optional metrics when present")
    func testGitHubTemplateWithOptionalMetrics() {
        let entry = makeTestEntryWithOptionalMetrics()
        let template = MarkdownExporter.generateGitHubTemplate(entry: entry)

        #expect(template.contains("P95 Latency"))
        #expect(template.contains("Median Latency"))
        #expect(template.contains("Memory Δ"))
    }

    @Test("generateGitHubTemplate — benchmark flag shows checkmark")
    func testGitHubTemplateBenchmarkFlag() {
        let entry = makeTestEntry(model: "Test", decodeSpeed: 10.0)
        let template = MarkdownExporter.generateGitHubTemplate(entry: entry)
        #expect(template.contains("✅"))
    }

    // MARK: - Escape Pipes

    @Test("escapePipes — replaces pipe characters")
    func testEscapePipes() {
        let result = MarkdownExporter.escapePipes("hello|world|test")
        #expect(result == "hello\\|world\\|test")
    }

    @Test("escapePipes — no pipes unchanged")
    func testEscapePipesNoPipes() {
        let result = MarkdownExporter.escapePipes("hello world")
        #expect(result == "hello world")
    }

    @Test("escapePipes — empty string")
    func testEscapePipesEmpty() {
        let result = MarkdownExporter.escapePipes("")
        #expect(result == "")
    }

    // MARK: - Table Formatting

    @Test("generateBenchmarkTable — proper column alignment")
    func testTableColumnAlignment() {
        let entry = makeTestEntry(model: "Test", decodeSpeed: 42.3)
        let table = MarkdownExporter.generateBenchmarkTable(entries: [entry])

        let lines = table.components(separatedBy: "\n")
        // All lines should start and end with |
        for line in lines {
            #expect(line.hasPrefix("|"))
            #expect(line.hasSuffix("|"))
        }
    }

    @Test("generateBenchmarkTable — TTFT formatted to 3 decimal places")
    func testTableTTFTFormatting() {
        let entry = makeTestEntry(model: "Test", decodeSpeed: 42.3)
        let table = MarkdownExporter.generateBenchmarkTable(entries: [entry])
        #expect(table.contains("0.342"))
    }

    // MARK: - Test Helpers

    private func makeTestEntry(model: String, decodeSpeed: Double) -> MetricsStore.Entry {
        MetricsStore.Entry(
            timestamp: "2026-06-28T12:00:00Z",
            model: model,
            platform: "macOS",
            device: "MacBook Pro",
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

    private func makeTestEntryWithOptionalMetrics() -> MetricsStore.Entry {
        MetricsStore.Entry(
            timestamp: "2026-06-28T12:00:00Z",
            model: "Gemma 4 1B",
            platform: "macOS",
            device: "MacBook Pro",
            metrics: MetricsStore.Entry.Metrics(
                initTimeSeconds: 1.5,
                ttftSeconds: 0.342,
                decodeTokensPerSecond: 42.3,
                prefillTokensPerSecond: 128.7,
                lastPrefillTokenCount: 256,
                lastDecodeTokenCount: 128,
                thermalStateAtStart: "nominal",
                thermalStateAtEnd: "fair",
                availableMemoryAtStartMB: 8192,
                availableMemoryAtEndMB: 7680,
                medianTokenLatencyMs: 23.4,
                p95TokenLatencyMs: 32.1,
                decodeLatenciesMs: [20.0, 25.0, 30.0],
                latencyHistogram: ["0-10ms": 0, "10-20ms": 0, "20-50ms": 3],
                thermalTransitions: nil,
                estimatedMemoryBandwidthGBps: 12.5,
                modelLoadDurationMs: 1500,
                gpuAllocatedMemoryAtStartMB: 256,
                gpuAllocatedMemoryAtEndMB: 512
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
