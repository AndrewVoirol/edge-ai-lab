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

import Foundation

// MARK: - Thermal State

/// Display-friendly thermal state with color coding for the benchmark bar.
enum ThermalLevel: String, Codable, Sendable {
    case nominal   // 🟢 Normal operation
    case fair      // 🟡 Slightly elevated, performance may be reduced
    case serious   // 🟠 High thermal load, significant throttling likely
    case critical  // 🔴 Imminent thermal shutdown risk

    /// Map from the system's ProcessInfo.ThermalState.
    init(from systemState: ProcessInfo.ThermalState) {
        switch systemState {
        case .nominal:  self = .nominal
        case .fair:     self = .fair
        case .serious:  self = .serious
        case .critical: self = .critical
        @unknown default: self = .nominal
        }
    }

    /// SF Symbol name for display.
    var symbolName: String {
        switch self {
        case .nominal:  return "thermometer.low"
        case .fair:     return "thermometer.medium"
        case .serious:  return "thermometer.high"
        case .critical: return "thermometer.sun.fill"
        }
    }

    /// Display color name (used by SwiftUI .foregroundStyle).
    var colorName: String {
        switch self {
        case .nominal:  return "green"
        case .fair:     return "yellow"
        case .serious:  return "orange"
        case .critical: return "red"
        }
    }

    /// Human-readable label.
    var label: String {
        switch self {
        case .nominal:  return "Nominal"
        case .fair:     return "Fair"
        case .serious:  return "Serious"
        case .critical: return "Critical"
        }
    }
}

// MARK: - Device Metrics Snapshot

/// A point-in-time snapshot of device metrics captured during inference.
struct DeviceMetricsSnapshot: Codable, Sendable {
    /// When this snapshot was taken.
    let timestamp: Date

    /// Thermal state at capture time.
    let thermalLevel: ThermalLevel

    /// Available memory in megabytes (from `os_proc_available_memory()`).
    let availableMemoryMB: Double

    /// Device model identifier (e.g., "iPhone17,2" for iPhone 16 Pro Max).
    let deviceModel: String
}

// MARK: - Inference Metrics

/// Comprehensive metrics captured during a single inference run.
/// Extends the SDK's BenchmarkInfo with device-level instrumentation.
struct InferenceMetrics: Codable, Sendable {
    /// Device state at the start of inference.
    let startSnapshot: DeviceMetricsSnapshot

    /// Device state at the end of inference.
    let endSnapshot: DeviceMetricsSnapshot

    /// Time to first token (prefill latency) in milliseconds, or nil if no tokens were produced.
    let ttftMs: Double?

    /// Per-token decode latency intervals in milliseconds (excludes TTFT).
    /// Each entry is the time between consecutive token arrivals, starting from the
    /// second token onward. This isolates pure decode throughput from prefill latency.
    let decodeLatenciesMs: [Double]

    /// Total number of tokens decoded (includes the first token).
    let totalTokenCount: Int

    // MARK: - Computed Statistics (decode-only, excludes TTFT)

    /// Median per-token decode latency in milliseconds (excludes TTFT).
    var medianTokenLatencyMs: Double {
        guard !decodeLatenciesMs.isEmpty else { return 0 }
        let sorted = decodeLatenciesMs.sorted()
        let mid = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[mid - 1] + sorted[mid]) / 2.0
        }
        return sorted[mid]
    }

    /// 95th percentile token latency in milliseconds (excludes TTFT).
    var p95TokenLatencyMs: Double {
        guard !decodeLatenciesMs.isEmpty else { return 0 }
        let sorted = decodeLatenciesMs.sorted()
        let index = min(Int(Double(sorted.count) * 0.95), sorted.count - 1)
        return sorted[index]
    }

    /// Minimum decode token latency in milliseconds (excludes TTFT).
    var minTokenLatencyMs: Double {
        decodeLatenciesMs.min() ?? 0
    }

    /// Maximum decode token latency in milliseconds (excludes TTFT).
    var maxTokenLatencyMs: Double {
        decodeLatenciesMs.max() ?? 0
    }

    /// Memory delta: how much available memory changed during inference.
    /// Negative values indicate memory consumption.
    var memoryDeltaMB: Double {
        endSnapshot.availableMemoryMB - startSnapshot.availableMemoryMB
    }

    /// Whether the thermal state changed during inference.
    var thermalStateChanged: Bool {
        startSnapshot.thermalLevel != endSnapshot.thermalLevel
    }

    // MARK: - Latency Histogram (Tier 1: Always-On)

    /// Histogram of decode token latencies bucketed by duration.
    /// Computed from the existing `decodeLatenciesMs` array — zero collection overhead.
    /// Buckets: 0-10ms, 10-20ms, 20-50ms, 50-100ms, 100-200ms, 200ms+
    var latencyHistogram: [String: Int] {
        InstrumentationLogic.computeLatencyHistogram(from: decodeLatenciesMs)
    }

    // MARK: - Memory Bandwidth Estimation (Tier 2: Benchmark-Only)

    /// Estimated memory bandwidth in GB/s during inference.
    /// Formula: abs(memoryDelta in bytes) / (inference duration in seconds) / 1e9
    /// Returns nil if duration is zero or negative (invalid measurement).
    var estimatedMemoryBandwidthGBps: Double? {
        InstrumentationLogic.computeMemoryBandwidth(
            startMemoryMB: startSnapshot.availableMemoryMB,
            endMemoryMB: endSnapshot.availableMemoryMB,
            startTimestamp: startSnapshot.timestamp,
            endTimestamp: endSnapshot.timestamp
        )
    }
}

// MARK: - Thermal Transition

/// Records a single thermal state transition observed during inference.
struct ThermalTransition: Codable, Sendable {
    /// The thermal level before the transition.
    let from: ThermalLevel
    /// The thermal level after the transition.
    let to: ThermalLevel
    /// When the transition occurred.
    let timestamp: Date
}

// MARK: - Instrumentation Logic

/// Pure-function logic for instrumentation computations.
/// Extracted into an enum namespace for testability (no instance state).
enum InstrumentationLogic {

    /// Bucket definitions for the latency histogram.
    static let histogramBuckets: [(label: String, range: ClosedRange<Double>)] = [
        ("0-10ms", 0...10),
        ("10-20ms", 10...20),
        ("20-50ms", 20...50),
        ("50-100ms", 50...100),
        ("100-200ms", 100...200),
    ]

    /// Compute a latency histogram from an array of decode latencies in milliseconds.
    /// Each latency is placed into exactly one bucket. The upper bound of each bucket
    /// is exclusive (except "200ms+" which captures everything >= 200).
    static func computeLatencyHistogram(from latencies: [Double]) -> [String: Int] {
        var histogram: [String: Int] = [
            "0-10ms": 0,
            "10-20ms": 0,
            "20-50ms": 0,
            "50-100ms": 0,
            "100-200ms": 0,
            "200ms+": 0,
        ]
        for latency in latencies {
            switch latency {
            case ..<10:
                histogram["0-10ms", default: 0] += 1
            case 10..<20:
                histogram["10-20ms", default: 0] += 1
            case 20..<50:
                histogram["20-50ms", default: 0] += 1
            case 50..<100:
                histogram["50-100ms", default: 0] += 1
            case 100..<200:
                histogram["100-200ms", default: 0] += 1
            default:
                histogram["200ms+", default: 0] += 1
            }
        }
        return histogram
    }

    /// Estimate memory bandwidth in GB/s from start/end memory and timestamps.
    /// Returns nil if duration is zero or negative.
    static func computeMemoryBandwidth(
        startMemoryMB: Double,
        endMemoryMB: Double,
        startTimestamp: Date,
        endTimestamp: Date
    ) -> Double? {
        let durationSeconds = endTimestamp.timeIntervalSince(startTimestamp)
        guard durationSeconds > 0 else { return nil }
        let memoryDeltaBytes = abs(endMemoryMB - startMemoryMB) * 1_048_576.0
        return memoryDeltaBytes / durationSeconds / 1_000_000_000.0
    }
}

// MARK: - DeviceMetrics Utility

/// Utility for capturing real-time device state.
enum DeviceMetrics {

    /// Capture a snapshot of current device metrics.
    static func captureSnapshot() -> DeviceMetricsSnapshot {
        DeviceMetricsSnapshot(
            timestamp: Date(),
            thermalLevel: currentThermalLevel,
            availableMemoryMB: availableMemoryMB,
            deviceModel: deviceModel
        )
    }

    /// Current thermal state of the device.
    static var currentThermalLevel: ThermalLevel {
        ThermalLevel(from: ProcessInfo.processInfo.thermalState)
    }

    /// Available memory in megabytes.
    /// On iOS, uses `os_proc_available_memory()` which is the recommended API
    /// for checking memory pressure (more accurate than `mach_task_info`).
    /// On macOS, uses `ProcessInfo.physicalMemory` minus resident memory as approximation.
    static var availableMemoryMB: Double {
        #if os(iOS)
        return Double(os_proc_available_memory()) / 1_048_576.0
        #else
        // macOS fallback: estimate available memory from physical - used
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        if result == KERN_SUCCESS {
            let usedMB = Double(info.resident_size) / 1_048_576.0
            let totalMB = Double(ProcessInfo.processInfo.physicalMemory) / 1_048_576.0
            return totalMB - usedMB
        }
        return Double(ProcessInfo.processInfo.physicalMemory) / 1_048_576.0
        #endif
    }

    /// Device model identifier from utsname.
    static var deviceModel: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(cString: $0)
            }
        }
    }

    /// Format available memory for compact display.
    /// - Returns: A string like "4.2 GB free" or "512 MB free".
    static var formattedAvailableMemory: String {
        let mb = availableMemoryMB
        if mb >= 1024 {
            return String(format: "%.1f GB free", mb / 1024.0)
        }
        return String(format: "%.0f MB free", mb)
    }
}
