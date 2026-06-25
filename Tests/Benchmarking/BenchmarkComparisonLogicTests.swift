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

import Testing
import Foundation
#if os(iOS)
@testable import EdgeAILab_iOS
#elseif os(macOS)
@testable import EdgeAILab_macOS
#endif

// MARK: - Test Helpers

/// Creates a minimal `MetricsStore.Entry` for testing.
/// Only the fields used by `buildSummaries` need realistic values;
/// everything else uses safe defaults.
private func makeEntry(
    model: String,
    decodeSpeed: Double,
    ttft: Double,
    decodeTokens: Int = 100,
    prefillTokens: Int = 50
) -> MetricsStore.Entry {
    MetricsStore.Entry(
        timestamp: "2026-01-01T00:00:00Z",
        model: model,
        platform: "macOS",
        device: "TestMac",
        metrics: MetricsStore.Entry.Metrics(
            initTimeSeconds: 0,
            ttftSeconds: ttft,
            decodeTokensPerSecond: decodeSpeed,
            prefillTokensPerSecond: 0,
            lastPrefillTokenCount: prefillTokens,
            lastDecodeTokenCount: decodeTokens,
            thermalStateAtStart: nil,
            thermalStateAtEnd: nil,
            availableMemoryAtStartMB: nil,
            availableMemoryAtEndMB: nil,
            medianTokenLatencyMs: nil,
            p95TokenLatencyMs: nil,
            decodeLatenciesMs: nil
        ),
        flags: ExperimentalFlagsState(
            enableBenchmark: false,
            enableSpeculativeDecoding: nil,
            enableConversationConstrainedDecoding: false,
            visualTokenBudget: nil
        )
    )
}

// MARK: - Tests

@Suite("BenchmarkComparisonLogic")
struct BenchmarkComparisonLogicTests {

    // MARK: - buildSummaries

    @Suite("buildSummaries")
    struct BuildSummariesTests {

        @Test("Returns empty array when given no entries")
        func emptyEntries() {
            let result = BenchmarkComparisonLogic.buildSummaries(from: [])
            #expect(result.isEmpty)
        }

        @Test("Single model with one entry produces correct summary")
        func singleModelSingleEntry() {
            let entries = [
                makeEntry(model: "Gemma-3n", decodeSpeed: 42.5, ttft: 0.15,
                          decodeTokens: 200, prefillTokens: 80)
            ]

            let result = BenchmarkComparisonLogic.buildSummaries(from: entries)

            #expect(result.count == 1)
            let summary = result[0]
            #expect(summary.modelName == "Gemma-3n")
            #expect(summary.runCount == 1)
            #expect(summary.bestDecodeSpeed == 42.5)
            #expect(summary.bestTTFT == 0.15)
            #expect(summary.averageDecodeTokens == 200.0)
            #expect(summary.averagePrefillTokens == 80.0)
        }

        @Test("Single model with multiple entries picks best values and averages correctly")
        func singleModelMultipleEntries() {
            let entries = [
                makeEntry(model: "Gemma-3n", decodeSpeed: 30.0, ttft: 0.20,
                          decodeTokens: 100, prefillTokens: 40),
                makeEntry(model: "Gemma-3n", decodeSpeed: 50.0, ttft: 0.10,
                          decodeTokens: 200, prefillTokens: 60),
                makeEntry(model: "Gemma-3n", decodeSpeed: 40.0, ttft: 0.15,
                          decodeTokens: 300, prefillTokens: 80),
            ]

            let result = BenchmarkComparisonLogic.buildSummaries(from: entries)

            #expect(result.count == 1)
            let summary = result[0]
            #expect(summary.bestDecodeSpeed == 50.0)  // max
            #expect(summary.bestTTFT == 0.10)          // min
            #expect(summary.runCount == 3)
            #expect(summary.averageDecodeTokens == 200.0)   // (100+200+300)/3
            #expect(summary.averagePrefillTokens == 60.0)   // (40+60+80)/3
        }

        @Test("Multiple models are sorted by best decode speed descending")
        func multipleModelsSortedBySpeed() {
            let entries = [
                makeEntry(model: "SlowModel", decodeSpeed: 10.0, ttft: 0.50),
                makeEntry(model: "FastModel", decodeSpeed: 90.0, ttft: 0.05),
                makeEntry(model: "MedModel", decodeSpeed: 45.0, ttft: 0.20),
            ]

            let result = BenchmarkComparisonLogic.buildSummaries(from: entries)

            #expect(result.count == 3)
            #expect(result[0].modelName == "FastModel")
            #expect(result[1].modelName == "MedModel")
            #expect(result[2].modelName == "SlowModel")
        }

        @Test("Multiple entries per model with correct averages across models")
        func multipleModelsMultipleEntriesAverages() {
            let entries = [
                // ModelA: two runs
                makeEntry(model: "ModelA", decodeSpeed: 20.0, ttft: 0.30,
                          decodeTokens: 100, prefillTokens: 50),
                makeEntry(model: "ModelA", decodeSpeed: 40.0, ttft: 0.10,
                          decodeTokens: 300, prefillTokens: 150),
                // ModelB: one run
                makeEntry(model: "ModelB", decodeSpeed: 60.0, ttft: 0.05,
                          decodeTokens: 500, prefillTokens: 200),
            ]

            let result = BenchmarkComparisonLogic.buildSummaries(from: entries)

            // ModelB (60) should come first, then ModelA (40)
            #expect(result.count == 2)
            #expect(result[0].modelName == "ModelB")
            #expect(result[1].modelName == "ModelA")

            // ModelA averages: (100+300)/2 = 200, (50+150)/2 = 100
            let modelA = result[1]
            #expect(modelA.runCount == 2)
            #expect(modelA.bestDecodeSpeed == 40.0)
            #expect(modelA.bestTTFT == 0.10)
            #expect(modelA.averageDecodeTokens == 200.0)
            #expect(modelA.averagePrefillTokens == 100.0)

            // ModelB single run
            let modelB = result[0]
            #expect(modelB.runCount == 1)
            #expect(modelB.averageDecodeTokens == 500.0)
            #expect(modelB.averagePrefillTokens == 200.0)
        }
    }

    // MARK: - formatSpeed

    @Suite("formatSpeed")
    struct FormatSpeedTests {

        @Test("Zero speed formats as 0.0")
        func zero() {
            #expect(BenchmarkComparisonLogic.formatSpeed(0) == "0.0")
        }

        @Test("Rounds to one decimal place", arguments: [
            (12.3456, "12.3"),
            (12.36, "12.4"),
            (99.99, "100.0"),
        ])
        func roundsCorrectly(input: Double, expected: String) {
            #expect(BenchmarkComparisonLogic.formatSpeed(input) == expected)
        }

        @Test("Whole number gets .0 suffix")
        func wholeNumber() {
            #expect(BenchmarkComparisonLogic.formatSpeed(100.0) == "100.0")
        }
    }

    // MARK: - formatTTFT

    @Suite("formatTTFT")
    struct FormatTTFTTests {

        @Test("Zero TTFT formats as 0.00")
        func zero() {
            #expect(BenchmarkComparisonLogic.formatTTFT(0) == "0.00")
        }

        @Test("Rounds to two decimal places", arguments: [
            (0.12345, "0.12"),
            (0.125, "0.12"),  // banker's rounding
            (0.126, "0.13"),
        ])
        func roundsCorrectly(input: Double, expected: String) {
            #expect(BenchmarkComparisonLogic.formatTTFT(input) == expected)
        }

        @Test("Whole number gets .00 suffix")
        func wholeNumber() {
            #expect(BenchmarkComparisonLogic.formatTTFT(1.5) == "1.50")
        }
    }

    // MARK: - formatTokens

    @Suite("formatTokens")
    struct FormatTokensTests {

        @Test("Zero formats as 0")
        func zero() {
            #expect(BenchmarkComparisonLogic.formatTokens(0) == "0")
        }

        @Test("Fractional value rounds to nearest integer", arguments: [
            (42.7, "43"),
            (42.3, "42"),
            (42.5, "42"),  // banker's rounding toward even
        ])
        func roundsCorrectly(input: Double, expected: String) {
            #expect(BenchmarkComparisonLogic.formatTokens(input) == expected)
        }

        @Test("Large whole number has no decimal")
        func largeWholeNumber() {
            #expect(BenchmarkComparisonLogic.formatTokens(1000.0) == "1000")
        }
    }
}
