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

// MARK: - DeviceMetrics Tests (Swift Testing)

/// Comprehensive tests for `DeviceMetrics.swift` covering:
/// - ThermalLevel enum (init, symbolName, colorName, label, Codable)
/// - DeviceMetricsSnapshot Codable round-trip
/// - InferenceMetrics computed properties (median, p95, min, max, memoryDelta, thermalStateChanged)
/// - DeviceMetrics static utility methods
@Suite("DeviceMetrics")
struct DeviceMetricsTests {

    // MARK: - Test Helpers

    /// Creates a DeviceMetricsSnapshot with configurable fields for test use.
    private static func makeSnapshot(
        timestamp: Date = Date(),
        thermalLevel: ThermalLevel = .nominal,
        availableMemoryMB: Double = 4096.0,
        deviceModel: String = "TestDevice1,1"
    ) -> DeviceMetricsSnapshot {
        DeviceMetricsSnapshot(
            timestamp: timestamp,
            thermalLevel: thermalLevel,
            availableMemoryMB: availableMemoryMB,
            deviceModel: deviceModel
        )
    }

    /// Creates an InferenceMetrics with configurable fields for test use.
    private static func makeMetrics(
        startThermal: ThermalLevel = .nominal,
        endThermal: ThermalLevel = .nominal,
        startMemoryMB: Double = 4096.0,
        endMemoryMB: Double = 3584.0,
        ttftMs: Double? = nil,
        decodeLatenciesMs: [Double] = [10.0, 20.0, 30.0],
        totalTokenCount: Int = 3
    ) -> InferenceMetrics {
        let start = makeSnapshot(
            thermalLevel: startThermal,
            availableMemoryMB: startMemoryMB
        )
        let end = makeSnapshot(
            thermalLevel: endThermal,
            availableMemoryMB: endMemoryMB
        )
        return InferenceMetrics(
            startSnapshot: start,
            endSnapshot: end,
            ttftMs: ttftMs,
            decodeLatenciesMs: decodeLatenciesMs,
            totalTokenCount: totalTokenCount
        )
    }

    // MARK: - ThermalLevel Tests

    @Suite("ThermalLevel")
    struct ThermalLevelTests {

        /// All ThermalLevel cases paired with the matching ProcessInfo.ThermalState.
        static let thermalCases: [(ThermalLevel, ProcessInfo.ThermalState)] = [
            (.nominal, .nominal),
            (.fair, .fair),
            (.serious, .serious),
            (.critical, .critical),
        ]

        /// All ThermalLevel cases for parameterized property tests.
        static let allCases: [ThermalLevel] = [.nominal, .fair, .serious, .critical]

        // MARK: Init from ProcessInfo.ThermalState

        @Test(
            "Init from ProcessInfo.ThermalState maps each case correctly",
            arguments: thermalCases
        )
        func initFromThermalState(
            expected: ThermalLevel,
            systemState: ProcessInfo.ThermalState
        ) {
            let result = ThermalLevel(from: systemState)
            #expect(result == expected)
        }

        // MARK: symbolName

        @Test("symbolName returns correct SF Symbol for each case", arguments: allCases)
        func symbolName(level: ThermalLevel) {
            let expected: [ThermalLevel: String] = [
                .nominal: "thermometer.low",
                .fair: "thermometer.medium",
                .serious: "thermometer.high",
                .critical: "thermometer.sun.fill",
            ]
            #expect(level.symbolName == expected[level])
        }

        // MARK: colorName

        @Test("colorName returns correct color for each case", arguments: allCases)
        func colorName(level: ThermalLevel) {
            let expected: [ThermalLevel: String] = [
                .nominal: "green",
                .fair: "yellow",
                .serious: "orange",
                .critical: "red",
            ]
            #expect(level.colorName == expected[level])
        }

        // MARK: label

        @Test("label returns correct human-readable label for each case", arguments: allCases)
        func label(level: ThermalLevel) {
            let expected: [ThermalLevel: String] = [
                .nominal: "Nominal",
                .fair: "Fair",
                .serious: "Serious",
                .critical: "Critical",
            ]
            #expect(level.label == expected[level])
        }

        // MARK: Codable Round-Trip

        @Test("Codable round-trip preserves each ThermalLevel case", arguments: allCases)
        func codableRoundTrip(level: ThermalLevel) throws {
            let encoder = JSONEncoder()
            let decoder = JSONDecoder()

            let data = try encoder.encode(level)
            let decoded = try decoder.decode(ThermalLevel.self, from: data)
            #expect(decoded == level)
        }

        @Test("Raw value encoding produces expected JSON string", arguments: allCases)
        func rawValueEncoding(level: ThermalLevel) throws {
            let data = try JSONEncoder().encode(level)
            let jsonString = String(data: data, encoding: .utf8)
            #expect(jsonString == "\"\(level.rawValue)\"")
        }
    }

    // MARK: - DeviceMetricsSnapshot Tests

    @Suite("DeviceMetricsSnapshot")
    struct DeviceMetricsSnapshotTests {

        @Test("Codable round-trip preserves all fields")
        func codableRoundTrip() throws {
            let timestamp = Date(timeIntervalSinceReferenceDate: 750_000_000)
            let original = DeviceMetricsSnapshot(
                timestamp: timestamp,
                thermalLevel: .serious,
                availableMemoryMB: 2048.5,
                deviceModel: "iPhone17,2"
            )

            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            let data = try encoder.encode(original)
            let decoded = try decoder.decode(DeviceMetricsSnapshot.self, from: data)

            #expect(decoded.timestamp == original.timestamp)
            #expect(decoded.thermalLevel == original.thermalLevel)
            #expect(decoded.availableMemoryMB == original.availableMemoryMB)
            #expect(decoded.deviceModel == original.deviceModel)
        }

        @Test("Snapshot stores all provided values")
        func storesValues() {
            let now = Date()
            let snapshot = DeviceMetricsSnapshot(
                timestamp: now,
                thermalLevel: .critical,
                availableMemoryMB: 512.0,
                deviceModel: "arm64"
            )

            #expect(snapshot.timestamp == now)
            #expect(snapshot.thermalLevel == .critical)
            #expect(snapshot.availableMemoryMB == 512.0)
            #expect(snapshot.deviceModel == "arm64")
        }
    }

    // MARK: - InferenceMetrics Tests

    @Suite("InferenceMetrics")
    struct InferenceMetricsTests {

        // MARK: Median Token Latency

        @Suite("medianTokenLatencyMs")
        struct MedianTests {

            @Test("Returns median for odd number of elements")
            func oddCount() {
                // [10, 20, 30, 40, 50] → sorted → median is index 2 → 30
                let metrics = makeMetrics(
                    decodeLatenciesMs: [50.0, 10.0, 30.0, 20.0, 40.0],
                    totalTokenCount: 5
                )
                #expect(metrics.medianTokenLatencyMs == 30.0)
            }

            @Test("Returns average of two middle elements for even count")
            func evenCount() {
                // [10, 20, 30, 40] → sorted → average of index 1,2 → (20+30)/2 = 25
                let metrics = makeMetrics(
                    decodeLatenciesMs: [40.0, 10.0, 30.0, 20.0],
                    totalTokenCount: 4
                )
                #expect(metrics.medianTokenLatencyMs == 25.0)
            }

            @Test("Returns 0 for empty latency array")
            func emptyArray() {
                let metrics = makeMetrics(
                    decodeLatenciesMs: [],
                    totalTokenCount: 0
                )
                #expect(metrics.medianTokenLatencyMs == 0)
            }

            @Test("Returns the single element for array with one element")
            func singleElement() {
                let metrics = makeMetrics(
                    decodeLatenciesMs: [42.5],
                    totalTokenCount: 1
                )
                #expect(metrics.medianTokenLatencyMs == 42.5)
            }
        }

        // MARK: P95 Token Latency

        @Suite("p95TokenLatencyMs")
        struct P95Tests {

            @Test("Returns 95th percentile for known data")
            func knownData() {
                // 20 elements: 1.0...20.0
                // index = min(Int(20 * 0.95), 19) = min(19, 19) = 19
                // sorted[19] = 20.0
                let latencies = (1...20).map { Double($0) }
                let metrics = makeMetrics(
                    decodeLatenciesMs: latencies,
                    totalTokenCount: 20
                )
                #expect(metrics.p95TokenLatencyMs == 20.0)
            }

            @Test("Returns correct p95 for 100 elements")
            func hundredElements() {
                // 100 elements: 1.0...100.0
                // index = min(Int(100 * 0.95), 99) = min(95, 99) = 95
                // sorted[95] = 96.0
                let latencies = (1...100).map { Double($0) }
                let metrics = makeMetrics(
                    decodeLatenciesMs: latencies,
                    totalTokenCount: 100
                )
                #expect(metrics.p95TokenLatencyMs == 96.0)
            }

            @Test("Returns 0 for empty array")
            func emptyArray() {
                let metrics = makeMetrics(
                    decodeLatenciesMs: [],
                    totalTokenCount: 0
                )
                #expect(metrics.p95TokenLatencyMs == 0)
            }

            @Test("Returns the single element for array with one element")
            func singleElement() {
                // index = min(Int(1 * 0.95), 0) = min(0, 0) = 0
                let metrics = makeMetrics(
                    decodeLatenciesMs: [99.9],
                    totalTokenCount: 1
                )
                #expect(metrics.p95TokenLatencyMs == 99.9)
            }
        }

        // MARK: Min/Max Token Latency

        @Suite("minTokenLatencyMs")
        struct MinTests {

            @Test("Returns minimum of known data")
            func knownData() {
                let metrics = makeMetrics(
                    decodeLatenciesMs: [50.0, 5.0, 100.0, 25.0],
                    totalTokenCount: 4
                )
                #expect(metrics.minTokenLatencyMs == 5.0)
            }

            @Test("Returns 0 for empty array")
            func emptyArray() {
                let metrics = makeMetrics(
                    decodeLatenciesMs: [],
                    totalTokenCount: 0
                )
                #expect(metrics.minTokenLatencyMs == 0)
            }
        }

        @Suite("maxTokenLatencyMs")
        struct MaxTests {

            @Test("Returns maximum of known data")
            func knownData() {
                let metrics = makeMetrics(
                    decodeLatenciesMs: [50.0, 5.0, 100.0, 25.0],
                    totalTokenCount: 4
                )
                #expect(metrics.maxTokenLatencyMs == 100.0)
            }

            @Test("Returns 0 for empty array")
            func emptyArray() {
                let metrics = makeMetrics(
                    decodeLatenciesMs: [],
                    totalTokenCount: 0
                )
                #expect(metrics.maxTokenLatencyMs == 0)
            }
        }

        // MARK: Memory Delta

        @Suite("memoryDeltaMB")
        struct MemoryDeltaTests {

            @Test("Calculates negative delta when memory consumed")
            func negativeWhenConsumed() {
                // start: 4096, end: 3584 → delta = 3584 - 4096 = -512
                let metrics = makeMetrics(
                    startMemoryMB: 4096.0,
                    endMemoryMB: 3584.0
                )
                #expect(metrics.memoryDeltaMB == -512.0)
            }

            @Test("Calculates positive delta when memory freed")
            func positiveWhenFreed() {
                let metrics = makeMetrics(
                    startMemoryMB: 2048.0,
                    endMemoryMB: 3072.0
                )
                #expect(metrics.memoryDeltaMB == 1024.0)
            }

            @Test("Returns zero when memory unchanged")
            func zeroWhenUnchanged() {
                let metrics = makeMetrics(
                    startMemoryMB: 4096.0,
                    endMemoryMB: 4096.0
                )
                #expect(metrics.memoryDeltaMB == 0.0)
            }
        }

        // MARK: Thermal State Changed

        @Suite("thermalStateChanged")
        struct ThermalStateChangedTests {

            @Test("Returns true when thermal levels differ")
            func differingLevels() {
                let metrics = makeMetrics(
                    startThermal: .nominal,
                    endThermal: .critical
                )
                #expect(metrics.thermalStateChanged == true)
            }

            @Test("Returns false when thermal levels are the same")
            func sameLevels() {
                let metrics = makeMetrics(
                    startThermal: .fair,
                    endThermal: .fair
                )
                #expect(metrics.thermalStateChanged == false)
            }
        }

        // MARK: InferenceMetrics Codable Round-Trip

        @Test("Codable round-trip preserves all fields and computed properties")
        func codableRoundTrip() throws {
            let original = makeMetrics(
                startThermal: .nominal,
                endThermal: .serious,
                startMemoryMB: 4096.0,
                endMemoryMB: 3072.0,
                decodeLatenciesMs: [10.0, 20.0, 30.0, 40.0, 50.0],
                totalTokenCount: 5
            )

            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            let data = try encoder.encode(original)
            let decoded = try decoder.decode(InferenceMetrics.self, from: data)

            // Stored properties
            #expect(decoded.decodeLatenciesMs == original.decodeLatenciesMs)
            #expect(decoded.totalTokenCount == original.totalTokenCount)
            #expect(decoded.startSnapshot.thermalLevel == original.startSnapshot.thermalLevel)
            #expect(decoded.endSnapshot.thermalLevel == original.endSnapshot.thermalLevel)
            #expect(
                decoded.startSnapshot.availableMemoryMB
                    == original.startSnapshot.availableMemoryMB
            )
            #expect(
                decoded.endSnapshot.availableMemoryMB
                    == original.endSnapshot.availableMemoryMB
            )

            // Computed properties should match after decoding
            #expect(decoded.medianTokenLatencyMs == original.medianTokenLatencyMs)
            #expect(decoded.p95TokenLatencyMs == original.p95TokenLatencyMs)
            #expect(decoded.minTokenLatencyMs == original.minTokenLatencyMs)
            #expect(decoded.maxTokenLatencyMs == original.maxTokenLatencyMs)
            #expect(decoded.memoryDeltaMB == original.memoryDeltaMB)
            #expect(decoded.thermalStateChanged == original.thermalStateChanged)
        }
    }

    // MARK: - DeviceMetrics Utility Tests

    @Suite("DeviceMetrics Utility")
    struct DeviceMetricsUtilityTests {

        @Test("captureSnapshot returns snapshot with valid available memory")
        func captureSnapshotMemory() {
            let snapshot = DeviceMetrics.captureSnapshot()
            // os_proc_available_memory() returns 0 on iOS Simulator
            #if targetEnvironment(simulator)
            #expect(snapshot.availableMemoryMB >= 0)
            #else
            #expect(snapshot.availableMemoryMB > 0)
            #endif
        }
        @Test("captureSnapshot returns snapshot with non-empty device model")
        func captureSnapshotDeviceModel() {
            let snapshot = DeviceMetrics.captureSnapshot()
            #expect(!snapshot.deviceModel.isEmpty)
        }

        @Test("captureSnapshot timestamp is recent")
        func captureSnapshotTimestamp() {
            let before = Date()
            let snapshot = DeviceMetrics.captureSnapshot()
            let after = Date()

            #expect(snapshot.timestamp >= before)
            #expect(snapshot.timestamp <= after)
        }

        @Test("availableMemoryMB returns a non-negative value")
        func availableMemoryIsNonNegative() {
            let memory = DeviceMetrics.availableMemoryMB
            // os_proc_available_memory() returns 0 on iOS Simulator
            #if targetEnvironment(simulator)
            #expect(memory >= 0)
            #else
            #expect(memory > 0)
            #endif
        }

        @Test("deviceModel returns a non-empty string")
        func deviceModelIsNonEmpty() {
            let model = DeviceMetrics.deviceModel
            #expect(!model.isEmpty)
        }

        @Test("formattedAvailableMemory returns a non-empty string")
        func formattedMemoryIsNonEmpty() {
            let formatted = DeviceMetrics.formattedAvailableMemory
            #expect(!formatted.isEmpty)
        }

        @Test("formattedAvailableMemory contains 'free' suffix")
        func formattedMemoryContainsFree() {
            let formatted = DeviceMetrics.formattedAvailableMemory
            #expect(formatted.contains("free"))
        }

        @Test("formattedAvailableMemory contains MB or GB unit")
        func formattedMemoryContainsUnit() {
            let formatted = DeviceMetrics.formattedAvailableMemory
            let hasUnit = formatted.contains("MB") || formatted.contains("GB")
            #expect(hasUnit, "Expected '\(formatted)' to contain MB or GB")
        }

        @Test("currentThermalLevel returns a valid ThermalLevel")
        func currentThermalLevelIsValid() {
            let level = DeviceMetrics.currentThermalLevel
            let validCases: [ThermalLevel] = [.nominal, .fair, .serious, .critical]
            #expect(validCases.contains(level))
        }
    }
}
