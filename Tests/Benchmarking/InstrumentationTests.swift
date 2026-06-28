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

// MARK: - Instrumentation Tests

/// Tests for the enhanced instrumentation system:
/// - Token latency histogram (Tier 1: Always-On)
/// - ThermalTransition Codable (Tier 1: Always-On)
/// - ThermalMonitor lifecycle (Tier 1: Always-On)
/// - Memory bandwidth estimation (Tier 2: Benchmark-Only)
/// - Model load duration storage (Tier 2: Benchmark-Only)
/// - JSON backward compatibility (Critical)
@Suite("Instrumentation")
struct InstrumentationTests {

    // MARK: - Test Helpers

    /// Creates an InferenceMetrics with configurable fields.
    private static func makeMetrics(
        startMemoryMB: Double = 4096.0,
        endMemoryMB: Double = 3584.0,
        startTimestamp: Date = Date(timeIntervalSinceReferenceDate: 750_000_000),
        endTimestamp: Date = Date(timeIntervalSinceReferenceDate: 750_000_005),
        decodeLatenciesMs: [Double] = [10.0, 20.0, 30.0],
        totalTokenCount: Int = 3
    ) -> InferenceMetrics {
        let start = DeviceMetricsSnapshot(
            timestamp: startTimestamp,
            thermalLevel: .nominal,
            availableMemoryMB: startMemoryMB,
            deviceModel: "TestDevice1,1"
        )
        let end = DeviceMetricsSnapshot(
            timestamp: endTimestamp,
            thermalLevel: .nominal,
            availableMemoryMB: endMemoryMB,
            deviceModel: "TestDevice1,1"
        )
        return InferenceMetrics(
            startSnapshot: start,
            endSnapshot: end,
            ttftMs: nil,
            decodeLatenciesMs: decodeLatenciesMs,
            totalTokenCount: totalTokenCount
        )
    }

    // MARK: - Latency Histogram Tests (Tier 1)

    @Suite("Latency Histogram")
    struct LatencyHistogramTests {

        @Test("All buckets are present even with empty latencies")
        func emptyLatencies() {
            let histogram = InstrumentationLogic.computeLatencyHistogram(from: [])
            #expect(histogram.count == 6)
            #expect(histogram["0-10ms"] == 0)
            #expect(histogram["10-20ms"] == 0)
            #expect(histogram["20-50ms"] == 0)
            #expect(histogram["50-100ms"] == 0)
            #expect(histogram["100-200ms"] == 0)
            #expect(histogram["200ms+"] == 0)
        }

        @Test("Single latency in first bucket")
        func singleFirstBucket() {
            let histogram = InstrumentationLogic.computeLatencyHistogram(from: [5.0])
            #expect(histogram["0-10ms"] == 1)
            #expect(histogram["10-20ms"] == 0)
        }

        @Test("Latencies distributed across all buckets")
        func allBuckets() {
            let latencies = [5.0, 15.0, 35.0, 75.0, 150.0, 250.0]
            let histogram = InstrumentationLogic.computeLatencyHistogram(from: latencies)
            #expect(histogram["0-10ms"] == 1)
            #expect(histogram["10-20ms"] == 1)
            #expect(histogram["20-50ms"] == 1)
            #expect(histogram["50-100ms"] == 1)
            #expect(histogram["100-200ms"] == 1)
            #expect(histogram["200ms+"] == 1)
        }

        @Test("Boundary value 10.0ms goes to 10-20ms bucket (upper bound exclusive)")
        func boundaryAt10() {
            let histogram = InstrumentationLogic.computeLatencyHistogram(from: [10.0])
            #expect(histogram["0-10ms"] == 0)
            #expect(histogram["10-20ms"] == 1)
        }

        @Test("Boundary value 20.0ms goes to 20-50ms bucket")
        func boundaryAt20() {
            let histogram = InstrumentationLogic.computeLatencyHistogram(from: [20.0])
            #expect(histogram["20-50ms"] == 1)
        }

        @Test("Boundary value 50.0ms goes to 50-100ms bucket")
        func boundaryAt50() {
            let histogram = InstrumentationLogic.computeLatencyHistogram(from: [50.0])
            #expect(histogram["50-100ms"] == 1)
        }

        @Test("Boundary value 100.0ms goes to 100-200ms bucket")
        func boundaryAt100() {
            let histogram = InstrumentationLogic.computeLatencyHistogram(from: [100.0])
            #expect(histogram["100-200ms"] == 1)
        }

        @Test("Boundary value 200.0ms goes to 200ms+ bucket")
        func boundaryAt200() {
            let histogram = InstrumentationLogic.computeLatencyHistogram(from: [200.0])
            #expect(histogram["200ms+"] == 1)
        }

        @Test("Multiple values in same bucket are counted correctly")
        func multipleSameBucket() {
            let latencies = [1.0, 3.0, 5.0, 7.0, 9.0]
            let histogram = InstrumentationLogic.computeLatencyHistogram(from: latencies)
            #expect(histogram["0-10ms"] == 5)
            #expect(histogram["10-20ms"] == 0)
        }

        @Test("Very small latencies (sub-millisecond) go to first bucket")
        func subMillisecond() {
            let histogram = InstrumentationLogic.computeLatencyHistogram(from: [0.001, 0.5])
            #expect(histogram["0-10ms"] == 2)
        }

        @Test("Very large latencies go to 200ms+ bucket")
        func veryLarge() {
            let histogram = InstrumentationLogic.computeLatencyHistogram(from: [1000.0, 5000.0])
            #expect(histogram["200ms+"] == 2)
        }

        @Test("Negative latencies go to first bucket")
        func negativeLanency() {
            // Edge case: negative values (shouldn't happen but shouldn't crash)
            let histogram = InstrumentationLogic.computeLatencyHistogram(from: [-5.0])
            #expect(histogram["0-10ms"] == 1)
        }

        @Test("InferenceMetrics.latencyHistogram uses existing decodeLatenciesMs")
        func computedPropertyIntegration() {
            let metrics = InstrumentationTests.makeMetrics(
                decodeLatenciesMs: [5.0, 15.0, 35.0],
                totalTokenCount: 3
            )
            let histogram = metrics.latencyHistogram
            #expect(histogram["0-10ms"] == 1)
            #expect(histogram["10-20ms"] == 1)
            #expect(histogram["20-50ms"] == 1)
            #expect(histogram["50-100ms"] == 0)
            #expect(histogram["100-200ms"] == 0)
            #expect(histogram["200ms+"] == 0)
        }
    }

    // MARK: - ThermalTransition Tests

    @Suite("ThermalTransition")
    struct ThermalTransitionTests {

        @Test("Codable round-trip preserves all fields")
        func codableRoundTrip() throws {
            let transition = ThermalTransition(
                from: .nominal,
                to: .serious,
                timestamp: Date(timeIntervalSinceReferenceDate: 750_000_000)
            )

            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            let data = try encoder.encode(transition)
            let decoded = try decoder.decode(ThermalTransition.self, from: data)

            #expect(decoded.from == transition.from)
            #expect(decoded.to == transition.to)
            #expect(decoded.timestamp == transition.timestamp)
        }

        @Test("All thermal level transitions encode correctly")
        func allLevelCombinations() throws {
            let levels: [ThermalLevel] = [.nominal, .fair, .serious, .critical]
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            for from in levels {
                for to in levels where from != to {
                    let transition = ThermalTransition(from: from, to: to, timestamp: Date())
                    let data = try encoder.encode(transition)
                    let decoded = try decoder.decode(ThermalTransition.self, from: data)
                    #expect(decoded.from == from)
                    #expect(decoded.to == to)
                }
            }
        }
    }

    // MARK: - ThermalMonitor Tests

    @Suite("ThermalMonitor")
    struct ThermalMonitorTests {

        @Test("Initial state: no transitions, not monitoring")
        func initialState() {
            let monitor = ThermalMonitor()
            #expect(monitor.transitions.isEmpty)
            #expect(!monitor.isMonitoring)
        }

        @Test("startMonitoring activates monitoring")
        func startActivates() {
            let monitor = ThermalMonitor()
            monitor.startMonitoring()
            #expect(monitor.isMonitoring)
            monitor.stopMonitoring()
        }

        @Test("stopMonitoring deactivates monitoring")
        func stopDeactivates() {
            let monitor = ThermalMonitor()
            monitor.startMonitoring()
            monitor.stopMonitoring()
            #expect(!monitor.isMonitoring)
        }

        @Test("No transitions when thermal state doesn't change")
        func noTransitionsWhenStable() {
            let monitor = ThermalMonitor()
            monitor.startMonitoring()
            // In a test environment, thermal state won't change spontaneously
            monitor.stopMonitoring()
            #expect(monitor.transitions.isEmpty)
        }

        @Test("Restarting monitoring clears previous transitions")
        func restartClearsPrevious() {
            let monitor = ThermalMonitor()
            monitor.startMonitoring()
            monitor.stopMonitoring()

            // Start a new session
            monitor.startMonitoring()
            #expect(monitor.transitions.isEmpty)
            monitor.stopMonitoring()
        }

        @Test("Multiple start/stop cycles are safe")
        func multipleCycles() {
            let monitor = ThermalMonitor()
            for _ in 0..<5 {
                monitor.startMonitoring()
                monitor.stopMonitoring()
            }
            #expect(!monitor.isMonitoring)
            #expect(monitor.transitions.isEmpty)
        }
    }

    // MARK: - Memory Bandwidth Estimation Tests (Tier 2)

    @Suite("Memory Bandwidth")
    struct MemoryBandwidthTests {

        @Test("Returns nil when duration is zero")
        func zeroDuration() {
            let now = Date()
            let result = InstrumentationLogic.computeMemoryBandwidth(
                startMemoryMB: 4096.0,
                endMemoryMB: 3584.0,
                startTimestamp: now,
                endTimestamp: now
            )
            #expect(result == nil)
        }

        @Test("Returns nil when end is before start")
        func negativeDuration() {
            let now = Date()
            let result = InstrumentationLogic.computeMemoryBandwidth(
                startMemoryMB: 4096.0,
                endMemoryMB: 3584.0,
                startTimestamp: now,
                endTimestamp: now.addingTimeInterval(-1)
            )
            #expect(result == nil)
        }

        @Test("Computes correct bandwidth for known values")
        func knownValues() {
            // 512 MB delta over 5 seconds
            // 512 * 1_048_576 bytes = 536_870_912 bytes
            // 536_870_912 / 5 / 1_000_000_000 ≈ 0.1074 GB/s
            let start = Date(timeIntervalSinceReferenceDate: 0)
            let end = Date(timeIntervalSinceReferenceDate: 5)
            let result = InstrumentationLogic.computeMemoryBandwidth(
                startMemoryMB: 4096.0,
                endMemoryMB: 3584.0,
                startTimestamp: start,
                endTimestamp: end
            )
            #expect(result != nil)
            let expected = 512.0 * 1_048_576.0 / 5.0 / 1_000_000_000.0
            #expect(abs(result! - expected) < 0.0001)
        }

        @Test("Uses absolute value of memory delta")
        func absoluteValue() {
            let start = Date(timeIntervalSinceReferenceDate: 0)
            let end = Date(timeIntervalSinceReferenceDate: 5)

            // Positive delta (memory freed)
            let pos = InstrumentationLogic.computeMemoryBandwidth(
                startMemoryMB: 3584.0,
                endMemoryMB: 4096.0,
                startTimestamp: start,
                endTimestamp: end
            )
            // Negative delta (memory consumed)
            let neg = InstrumentationLogic.computeMemoryBandwidth(
                startMemoryMB: 4096.0,
                endMemoryMB: 3584.0,
                startTimestamp: start,
                endTimestamp: end
            )
            #expect(pos == neg)
        }

        @Test("Returns zero bandwidth when no memory change")
        func zeroMemoryDelta() {
            let start = Date(timeIntervalSinceReferenceDate: 0)
            let end = Date(timeIntervalSinceReferenceDate: 5)
            let result = InstrumentationLogic.computeMemoryBandwidth(
                startMemoryMB: 4096.0,
                endMemoryMB: 4096.0,
                startTimestamp: start,
                endTimestamp: end
            )
            #expect(result == 0.0)
        }

        @Test("InferenceMetrics computed property integration")
        func computedPropertyIntegration() {
            let metrics = InstrumentationTests.makeMetrics(
                startMemoryMB: 4096.0,
                endMemoryMB: 3584.0,
                startTimestamp: Date(timeIntervalSinceReferenceDate: 0),
                endTimestamp: Date(timeIntervalSinceReferenceDate: 5)
            )
            #expect(metrics.estimatedMemoryBandwidthGBps != nil)
            let expected = 512.0 * 1_048_576.0 / 5.0 / 1_000_000_000.0
            #expect(abs(metrics.estimatedMemoryBandwidthGBps! - expected) < 0.0001)
        }
    }

    // MARK: - MetricsStore Backward Compatibility Tests (Critical)

    @Suite("JSON Backward Compatibility")
    struct JSONBackwardCompatibilityTests {

        @Test("Old-format JSON (without new fields) decodes successfully")
        func oldFormatDecodes() throws {
            // This JSON represents the OLD format before instrumentation fields were added.
            // It must decode without error to preserve backward compatibility.
            let oldFormatJSON = """
            [{
                "timestamp": "2026-06-19T12:00:00.000Z",
                "model": "gemma-2b",
                "platform": "macOS",
                "device": "Test Mac",
                "metrics": {
                    "initTimeSeconds": 2.5,
                    "ttftSeconds": 0.15,
                    "decodeTokensPerSecond": 100.0,
                    "prefillTokensPerSecond": 200.0,
                    "lastPrefillTokenCount": 10,
                    "lastDecodeTokenCount": 256
                },
                "flags": {
                    "enableBenchmark": true,
                    "enableConversationConstrainedDecoding": false,
                    "enableThinking": true,
                    "enableToolCalling": false,
                    "enableAgentSkills": false
                }
            }]
            """

            let data = try #require(oldFormatJSON.data(using: .utf8))
            let entries = try JSONDecoder().decode([MetricsStore.Entry].self, from: data)

            #expect(entries.count == 1)
            let entry = entries[0]
            #expect(entry.model == "gemma-2b")
            #expect(entry.metrics.decodeTokensPerSecond == 100.0)

            // All optional fields should be nil
            #expect(entry.metrics.thermalStateAtStart == nil)
            #expect(entry.metrics.thermalStateAtEnd == nil)
            #expect(entry.metrics.availableMemoryAtStartMB == nil)
            #expect(entry.metrics.availableMemoryAtEndMB == nil)
            #expect(entry.metrics.medianTokenLatencyMs == nil)
            #expect(entry.metrics.p95TokenLatencyMs == nil)
            #expect(entry.metrics.decodeLatenciesMs == nil)
            // New instrumentation fields should also be nil
            #expect(entry.metrics.latencyHistogram == nil)
            #expect(entry.metrics.thermalTransitions == nil)
            #expect(entry.metrics.estimatedMemoryBandwidthGBps == nil)
            #expect(entry.metrics.modelLoadDurationMs == nil)
        }

        @Test("JSON with only original optional fields (no new instrumentation) decodes")
        func partialOptionalFieldsDecodes() throws {
            let partialJSON = """
            [{
                "timestamp": "2026-06-19T12:00:00.000Z",
                "model": "gemma-2b",
                "platform": "macOS",
                "device": "Test Mac",
                "metrics": {
                    "initTimeSeconds": 2.5,
                    "ttftSeconds": 0.15,
                    "decodeTokensPerSecond": 100.0,
                    "prefillTokensPerSecond": 200.0,
                    "lastPrefillTokenCount": 10,
                    "lastDecodeTokenCount": 256,
                    "thermalStateAtStart": "nominal",
                    "thermalStateAtEnd": "fair",
                    "availableMemoryAtStartMB": 4096.0,
                    "availableMemoryAtEndMB": 3584.0,
                    "medianTokenLatencyMs": 6.5,
                    "p95TokenLatencyMs": 12.3,
                    "decodeLatenciesMs": [5.0, 6.0, 7.0]
                },
                "flags": {
                    "enableBenchmark": true,
                    "enableConversationConstrainedDecoding": false,
                    "enableThinking": true,
                    "enableToolCalling": false,
                    "enableAgentSkills": false
                }
            }]
            """

            let data = try #require(partialJSON.data(using: .utf8))
            let entries = try JSONDecoder().decode([MetricsStore.Entry].self, from: data)

            #expect(entries.count == 1)
            let entry = entries[0]
            #expect(entry.metrics.thermalStateAtStart == "nominal")
            #expect(entry.metrics.medianTokenLatencyMs == 6.5)
            // New fields should be nil since they're not in the JSON
            #expect(entry.metrics.latencyHistogram == nil)
            #expect(entry.metrics.thermalTransitions == nil)
            #expect(entry.metrics.estimatedMemoryBandwidthGBps == nil)
            #expect(entry.metrics.modelLoadDurationMs == nil)
            #expect(entry.metrics.gpuAllocatedMemoryAtStartMB == nil)
            #expect(entry.metrics.gpuAllocatedMemoryAtEndMB == nil)
        }

        @Test("Full JSON with all new instrumentation fields decodes and round-trips")
        func fullFormatRoundTrip() throws {
            let fullJSON = """
            [{
                "timestamp": "2026-06-19T12:00:00.000Z",
                "model": "gemma-2b",
                "platform": "macOS",
                "device": "Test Mac",
                "metrics": {
                    "initTimeSeconds": 2.5,
                    "ttftSeconds": 0.15,
                    "decodeTokensPerSecond": 100.0,
                    "prefillTokensPerSecond": 200.0,
                    "lastPrefillTokenCount": 10,
                    "lastDecodeTokenCount": 256,
                    "thermalStateAtStart": "nominal",
                    "thermalStateAtEnd": "fair",
                    "availableMemoryAtStartMB": 4096.0,
                    "availableMemoryAtEndMB": 3584.0,
                    "medianTokenLatencyMs": 6.5,
                    "p95TokenLatencyMs": 12.3,
                    "decodeLatenciesMs": [5.0, 6.0, 7.0],
                    "latencyHistogram": {"0-10ms": 3, "10-20ms": 0, "20-50ms": 0, "50-100ms": 0, "100-200ms": 0, "200ms+": 0},
                    "thermalTransitions": [{"from": "nominal", "to": "fair", "timestamp": "2026-06-19T12:00:01.000Z"}],
                    "estimatedMemoryBandwidthGBps": 0.107,
                    "modelLoadDurationMs": 2500.0,
                    "gpuAllocatedMemoryAtStartMB": 128.5,
                    "gpuAllocatedMemoryAtEndMB": 384.0
                },
                "flags": {
                    "enableBenchmark": true,
                    "enableConversationConstrainedDecoding": false,
                    "enableThinking": true,
                    "enableToolCalling": false,
                    "enableAgentSkills": false
                }
            }]
            """

            let data = try #require(fullJSON.data(using: .utf8))
            let entries = try JSONDecoder().decode([MetricsStore.Entry].self, from: data)

            #expect(entries.count == 1)
            let entry = entries[0]
            #expect(entry.metrics.latencyHistogram?["0-10ms"] == 3)
            #expect(entry.metrics.thermalTransitions?.count == 1)
            #expect(entry.metrics.thermalTransitions?[0].from == "nominal")
            #expect(entry.metrics.thermalTransitions?[0].to == "fair")
            #expect(entry.metrics.estimatedMemoryBandwidthGBps == 0.107)
            #expect(entry.metrics.modelLoadDurationMs == 2500.0)
            #expect(entry.metrics.gpuAllocatedMemoryAtStartMB == 128.5)
            #expect(entry.metrics.gpuAllocatedMemoryAtEndMB == 384.0)

            // Verify round-trip: encode and decode again
            let encoder = JSONEncoder()
            let reEncoded = try encoder.encode(entries)
            let reDecoded = try JSONDecoder().decode([MetricsStore.Entry].self, from: reEncoded)
            #expect(reDecoded[0].metrics.latencyHistogram == entry.metrics.latencyHistogram)
            #expect(reDecoded[0].metrics.estimatedMemoryBandwidthGBps == entry.metrics.estimatedMemoryBandwidthGBps)
            #expect(reDecoded[0].metrics.modelLoadDurationMs == entry.metrics.modelLoadDurationMs)
            #expect(reDecoded[0].metrics.gpuAllocatedMemoryAtStartMB == 128.5)
            #expect(reDecoded[0].metrics.gpuAllocatedMemoryAtEndMB == 384.0)
        }

        @Test("MetricsStore file persistence with new fields round-trips correctly")
        func storeRoundTrip() throws {
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("InstrumentationTests-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: tempDir) }

            let fileURL = tempDir
                .appendingPathComponent("metrics")
                .appendingPathComponent("history.json")
            let store = MetricsStore(fileURL: fileURL)

            let entry = MetricsStore.Entry(
                timestamp: "2026-06-19T12:00:00.000Z",
                model: "test-instrumented",
                platform: "macOS",
                device: "Test Mac",
                metrics: MetricsStore.Entry.Metrics(
                    initTimeSeconds: 2.5,
                    ttftSeconds: 0.15,
                    decodeTokensPerSecond: 100.0,
                    prefillTokensPerSecond: 200.0,
                    lastPrefillTokenCount: 10,
                    lastDecodeTokenCount: 256,
                    thermalStateAtStart: "nominal",
                    thermalStateAtEnd: "fair",
                    availableMemoryAtStartMB: 4096.0,
                    availableMemoryAtEndMB: 3584.0,
                    medianTokenLatencyMs: 6.5,
                    p95TokenLatencyMs: 12.3,
                    decodeLatenciesMs: [5.0, 6.0, 7.0],
                    latencyHistogram: ["0-10ms": 3, "10-20ms": 0, "20-50ms": 0, "50-100ms": 0, "100-200ms": 0, "200ms+": 0],
                    thermalTransitions: [
                        MetricsStore.ThermalTransitionRecord(from: "nominal", to: "fair", timestamp: "2026-06-19T12:00:01.000Z")
                    ],
                    estimatedMemoryBandwidthGBps: 0.107,
                    modelLoadDurationMs: 2500.0,
                    gpuAllocatedMemoryAtStartMB: 128.5,
                    gpuAllocatedMemoryAtEndMB: 384.0
                ),
                flags: ExperimentalFlagsState(
                    enableBenchmark: true,
                    enableSpeculativeDecoding: nil,
                    enableConversationConstrainedDecoding: false,
                    visualTokenBudget: nil
                )
            )

            try store.append(entry: entry)
            let loaded = try store.loadEntries()
            #expect(loaded.count == 1)
            #expect(loaded[0].metrics.latencyHistogram?["0-10ms"] == 3)
            #expect(loaded[0].metrics.thermalTransitions?.count == 1)
            #expect(loaded[0].metrics.estimatedMemoryBandwidthGBps == 0.107)
            #expect(loaded[0].metrics.modelLoadDurationMs == 2500.0)
        }
    }

    // MARK: - ThermalTransitionRecord Tests

    @Suite("ThermalTransitionRecord")
    struct ThermalTransitionRecordTests {

        @Test("Codable round-trip preserves all fields")
        func codableRoundTrip() throws {
            let record = MetricsStore.ThermalTransitionRecord(
                from: "nominal",
                to: "serious",
                timestamp: "2026-06-19T12:00:01.000Z"
            )

            let data = try JSONEncoder().encode(record)
            let decoded = try JSONDecoder().decode(MetricsStore.ThermalTransitionRecord.self, from: data)

            #expect(decoded.from == "nominal")
            #expect(decoded.to == "serious")
            #expect(decoded.timestamp == "2026-06-19T12:00:01.000Z")
        }
    }

    // MARK: - InstrumentationLogic Tests

    @Suite("InstrumentationLogic")
    struct InstrumentationLogicTests {

        @Test("histogramBuckets has 5 defined ranges")
        func bucketCount() {
            #expect(InstrumentationLogic.histogramBuckets.count == 5)
        }

        @Test("Histogram total equals input count")
        func histogramTotalMatchesInput() {
            let latencies = [1.0, 5.0, 15.0, 25.0, 55.0, 120.0, 250.0, 300.0]
            let histogram = InstrumentationLogic.computeLatencyHistogram(from: latencies)
            let total = histogram.values.reduce(0, +)
            #expect(total == latencies.count)
        }
    }

    // MARK: - GPU Metrics Tests

    @Suite("GPU Metrics")
    struct GPUMetricsTests {

        @Test("DeviceMetrics.gpuAllocatedMemoryMB returns non-negative value on Metal-capable device")
        func gpuAllocatedMemoryIsNonNegative() {
            // On macOS test runners (Apple Silicon), Metal is always available.
            // On CI without GPU, this gracefully returns nil.
            if let gpuMemory = DeviceMetrics.gpuAllocatedMemoryMB {
                #expect(gpuMemory >= 0)
            }
        }

        @Test("DeviceMetrics.metalDevice is non-nil on Apple Silicon")
        func metalDeviceExists() {
            // Apple Silicon always has Metal — this test validates the lazy caching works
            #if arch(arm64)
            #expect(DeviceMetrics.metalDevice != nil)
            #endif
        }

        @Test("captureSnapshot includes gpuAllocatedMemoryMB")
        func snapshotIncludesGPU() {
            let snapshot = DeviceMetrics.captureSnapshot()
            // On Metal-capable hardware, this should be populated
            if DeviceMetrics.metalDevice != nil {
                #expect(snapshot.gpuAllocatedMemoryMB != nil)
                #expect(snapshot.gpuAllocatedMemoryMB! >= 0)
            }
        }

        @Test("DeviceMetricsSnapshot init with gpuAllocatedMemoryMB preserves value")
        func snapshotPreservesGPUMemory() {
            let snapshot = DeviceMetricsSnapshot(
                timestamp: Date(),
                thermalLevel: .nominal,
                availableMemoryMB: 4096.0,
                deviceModel: "TestDevice1,1",
                gpuAllocatedMemoryMB: 256.5
            )
            #expect(snapshot.gpuAllocatedMemoryMB == 256.5)
        }

        @Test("DeviceMetricsSnapshot init without gpuAllocatedMemoryMB defaults to nil")
        func snapshotDefaultsToNil() {
            let snapshot = DeviceMetricsSnapshot(
                timestamp: Date(),
                thermalLevel: .nominal,
                availableMemoryMB: 4096.0,
                deviceModel: "TestDevice1,1"
            )
            #expect(snapshot.gpuAllocatedMemoryMB == nil)
        }

        @Test("DeviceMetricsSnapshot Codable round-trip preserves gpuAllocatedMemoryMB")
        func codableRoundTripPreservesGPU() throws {
            let original = DeviceMetricsSnapshot(
                timestamp: Date(timeIntervalSinceReferenceDate: 750_000_000),
                thermalLevel: .fair,
                availableMemoryMB: 2048.0,
                deviceModel: "TestDevice1,1",
                gpuAllocatedMemoryMB: 512.75
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(original)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let decoded = try decoder.decode(DeviceMetricsSnapshot.self, from: data)
            #expect(decoded.gpuAllocatedMemoryMB == 512.75)
            #expect(decoded.thermalLevel == .fair)
            #expect(decoded.availableMemoryMB == 2048.0)
        }

        @Test("DeviceMetricsSnapshot JSON without gpuAllocatedMemoryMB decodes with nil")
        func jsonBackwardCompatibility() throws {
            // Old-format JSON without the gpuAllocatedMemoryMB field
            let json = """
            {
                "timestamp": "2026-01-01T00:00:00Z",
                "thermalLevel": "nominal",
                "availableMemoryMB": 4096.0,
                "deviceModel": "TestDevice1,1"
            }
            """
            let data = try #require(json.data(using: .utf8))
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let snapshot = try decoder.decode(DeviceMetricsSnapshot.self, from: data)
            #expect(snapshot.gpuAllocatedMemoryMB == nil)
            #expect(snapshot.availableMemoryMB == 4096.0)
        }
    }
}
