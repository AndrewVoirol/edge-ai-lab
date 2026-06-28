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
import LiteRTLM
import os

// MARK: - Benchmark State & Result

/// Observable state for the one-tap benchmark runner UI.
enum BenchmarkState: Sendable {
    case idle
    case warmingUp
    case running(currentRun: Int, totalRuns: Int)
    case completed(result: BenchmarkResult)
    case failed(error: String)
}

/// Aggregated benchmark result from multiple runs, using median values.
struct BenchmarkResult: Sendable {
    /// Median decode tokens per second across all runs.
    let medianDecodeTokensPerSecond: Double
    /// Median time to first token in seconds across all runs.
    let medianTTFTSeconds: Double
    /// Median prefill tokens per second across all runs.
    let medianPrefillTokensPerSecond: Double
    /// Number of inference runs that produced this result.
    let runCount: Int
    /// Timestamp when the benchmark completed.
    let timestamp: Date
}

// MARK: - Pure Logic

/// Testable pure-function logic for benchmark computations.
/// Uses `enum` to prevent accidental instantiation (per project conventions).
enum BenchmarkLogic {

    /// The standardized prompt used for all benchmark runs.
    /// Chosen for consistent output length and complexity across models.
    static let standardPrompt: String =
        "Explain the concept of machine learning to a curious teenager. " +
        "Cover what it is, how it works at a high level, and give three " +
        "real-world examples. Be clear and engaging."

    /// Default number of inference runs (excluding warmup).
    static let defaultRunCount: Int = 3

    /// Compute the median of an array of `Double` values.
    /// - Returns: The median value, or `nil` if the array is empty.
    static func median(of values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[mid - 1] + sorted[mid]) / 2.0
        }
        return sorted[mid]
    }

    /// Build a `BenchmarkResult` from arrays of per-run metrics.
    /// - Returns: A result with median values, or `nil` if any metric array is empty.
    static func buildResult(
        decodeSpeeds: [Double],
        ttftValues: [Double],
        prefillSpeeds: [Double],
        timestamp: Date = Date()
    ) -> BenchmarkResult? {
        guard let medianDecode = median(of: decodeSpeeds),
              let medianTTFT = median(of: ttftValues),
              let medianPrefill = median(of: prefillSpeeds) else {
            return nil
        }

        return BenchmarkResult(
            medianDecodeTokensPerSecond: medianDecode,
            medianTTFTSeconds: medianTTFT,
            medianPrefillTokensPerSecond: medianPrefill,
            runCount: decodeSpeeds.count,
            timestamp: timestamp
        )
    }
}

// MARK: - One-Tap Benchmark Runner

/// Runs a standardized multi-run benchmark with a single tap.
///
/// Workflow:
/// 1. **Warmup** — sends a throwaway "Hi" to prime the SDK's benchmark subsystem
///    (required because `getBenchmarkInfo()` returns nil on the first turn).
/// 2. **Benchmark Runs** — sends the standard prompt 3 times consecutively,
///    collecting `BenchmarkInfo` and `InferenceMetrics` from each run.
/// 3. **Aggregation** — computes the median of key metrics across all runs.
/// 4. **Persistence** — saves the median result to `MetricsStore`.
@Observable @MainActor
final class OneTapBenchmarkRunner {

    // MARK: - State

    /// The current benchmark state, observable by SwiftUI views.
    private(set) var state: BenchmarkState = .idle

    // MARK: - Dependencies

    private let engine: InstrumentedEngineProtocol
    private let metricsStore: MetricsStore
    private let modelName: String

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.andrewvoirol.EdgeAILab",
        category: "one-tap-benchmark"
    )

    // MARK: - Init

    /// Create a one-tap benchmark runner.
    /// - Parameters:
    ///   - engine: The instrumented engine to run inferences on. Must already be initialized.
    ///   - metricsStore: The store to persist benchmark results to.
    ///   - modelName: The model name for metrics store entries.
    init(engine: InstrumentedEngineProtocol, metricsStore: MetricsStore, modelName: String) {
        self.engine = engine
        self.metricsStore = metricsStore
        self.modelName = modelName
    }

    // MARK: - Run

    /// Execute the full one-tap benchmark: warmup → runs → aggregate → persist.
    ///
    /// Updates `state` throughout for UI observation.
    /// Safe to call from SwiftUI button actions.
    func run() async {
        guard engine.isReady else {
            state = .failed(error: "Engine is not ready. Please load a model first.")
            Self.logger.error("❌ Benchmark aborted: engine not ready")
            return
        }

        do {
            // Phase 1: Warmup
            state = .warmingUp
            Self.logger.info("🔄 Starting warmup run...")
            try await engine.warmup()
            Self.logger.info("✅ Warmup complete")

            // Phase 2: Benchmark runs
            let totalRuns = BenchmarkLogic.defaultRunCount
            var decodeSpeeds: [Double] = []
            var ttftValues: [Double] = []
            var prefillSpeeds: [Double] = []

            for runIndex in 1...totalRuns {
                state = .running(currentRun: runIndex, totalRuns: totalRuns)
                Self.logger.info("🏃 Starting benchmark run \(runIndex)/\(totalRuns)")

                // Consume the full response stream
                for try await _ in engine.sendMessageStream(BenchmarkLogic.standardPrompt) {
                    // Discard response tokens — we only need the benchmark metrics
                }

                // Collect benchmark info from the engine
                guard let benchmarkInfo = engine.lastBenchmarkInfo else {
                    let message = "Run \(runIndex): engine.lastBenchmarkInfo was nil after inference"
                    Self.logger.error("❌ \(message)")
                    state = .failed(error: message)
                    return
                }

                decodeSpeeds.append(benchmarkInfo.lastDecodeTokensPerSecond)
                ttftValues.append(benchmarkInfo.timeToFirstTokenInSecond)
                prefillSpeeds.append(benchmarkInfo.lastPrefillTokensPerSecond)

                Self.logger.info(
                    "📊 Run \(runIndex) metrics — decode: \(benchmarkInfo.lastDecodeTokensPerSecond, format: .fixed(precision: 1)) tok/s, " +
                    "TTFT: \(benchmarkInfo.timeToFirstTokenInSecond, format: .fixed(precision: 3))s, " +
                    "prefill: \(benchmarkInfo.lastPrefillTokensPerSecond, format: .fixed(precision: 1)) tok/s"
                )

                // Persist each individual run to the metrics store
                let entry = MetricsStore.createEntry(
                    from: benchmarkInfo,
                    modelName: modelName,
                    flags: engine.flagsState,
                    inferenceMetrics: engine.lastInferenceMetrics
                )
                do {
                    try metricsStore.append(entry: entry)
                } catch {
                    // Non-fatal: log and continue
                    Self.logger.error("⚠️ MetricsStore persistence failed for run \(runIndex): \(error.localizedDescription, privacy: .public)")
                }
            }

            // Phase 3: Compute median result
            guard let result = BenchmarkLogic.buildResult(
                decodeSpeeds: decodeSpeeds,
                ttftValues: ttftValues,
                prefillSpeeds: prefillSpeeds
            ) else {
                state = .failed(error: "Failed to compute median — no valid runs collected")
                return
            }

            state = .completed(result: result)
            Self.logger.info(
                "🎉 Benchmark complete — median decode: \(result.medianDecodeTokensPerSecond, format: .fixed(precision: 1)) tok/s, " +
                "median TTFT: \(result.medianTTFTSeconds, format: .fixed(precision: 3))s, " +
                "median prefill: \(result.medianPrefillTokensPerSecond, format: .fixed(precision: 1)) tok/s"
            )

        } catch {
            let message = error.localizedDescription
            state = .failed(error: message)
            Self.logger.error("❌ Benchmark failed: \(message, privacy: .public)")
        }
    }

    /// Reset the runner to idle state for re-running.
    func reset() {
        state = .idle
    }
}
