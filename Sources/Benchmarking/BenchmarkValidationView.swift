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

// NOTE: This file uses print() for structured stdout output AND os.Logger
// for the unified logging system. On macOS, stdout is captured by automation
// scripts. On iOS, os_log captures validation output without --console.

import SwiftUI
import LiteRTLM
import os

private let validationLogger = Logger(subsystem: "com.andrewvoirol.EdgeAILab", category: "validation")

private func validationLog(_ message: String) {
    print(message)
    validationLogger.notice("\(message, privacy: .public)")
}

// MARK: - Validation Runner

/// Runs internal validation checks for the benchmarking subsystem.
/// Ported from IO 2026 Concierge E2EValidationRunner pattern.
@MainActor
class BenchmarkValidationRunner: ObservableObject {
    @Published var status: String = "Starting Validations..."

    struct ValidationResult: Identifiable, Hashable {
        let id = UUID()
        let text: String
    }

    @Published var results: [ValidationResult] = []
    private var passCount = 0
    private var failCount = 0

    func runAll() async {
        status = "Running Benchmark Validations..."

        // Check 1: MetricsStore Entry encoding/decoding round-trip
        await runCheck("MetricsStore Entry Encoding") {
            let flags = ExperimentalFlagsState(
                enableBenchmark: true,
                enableSpeculativeDecoding: nil,
                enableConversationConstrainedDecoding: false,
                visualTokenBudget: nil
            )
            let entry = MetricsStore.Entry(
                timestamp: ISO8601DateFormatter().string(from: Date()),
                model: "test-model.litertlm",
                platform: "macOS",
                device: "TestDevice",
                metrics: MetricsStore.Entry.Metrics(
                    initTimeSeconds: 1.5,
                    ttftSeconds: 0.3,
                    decodeTokensPerSecond: 42.0,
                    prefillTokensPerSecond: 150.0,
                    lastPrefillTokenCount: 128,
                    lastDecodeTokenCount: 256,
                    thermalStateAtStart: "nominal",
                    thermalStateAtEnd: "nominal",
                    availableMemoryAtStartMB: 4096.0,
                    availableMemoryAtEndMB: 3800.0,
                    medianTokenLatencyMs: 23.5,
                    p95TokenLatencyMs: 35.0,
                    tokenLatenciesMs: [20.0, 23.0, 25.0]
                ),
                flags: flags
            )

            let encoder = JSONEncoder()
            let decoder = JSONDecoder()
            let data = try encoder.encode(entry)
            let decoded = try decoder.decode(MetricsStore.Entry.self, from: data)
            guard decoded.model == entry.model,
                  decoded.metrics.decodeTokensPerSecond == entry.metrics.decodeTokensPerSecond else {
                throw ValidationError("Round-trip mismatch")
            }
        }

        // Check 2: DeviceMetrics reports non-zero values
        await runCheck("DeviceMetrics Non-Zero Values") {
            let snapshot = DeviceMetrics.captureSnapshot()
            guard snapshot.availableMemoryMB > 0 else {
                throw ValidationError("Available memory is zero")
            }
            guard !snapshot.deviceModel.isEmpty else {
                throw ValidationError("Device model is empty")
            }
            // Thermal level should be a valid enum value (won't crash if it parsed)
            _ = snapshot.thermalLevel.label
        }

        // Check 3: baselines.json parsing (if available)
        await runCheck("Baselines JSON Parsing") {
            // Try to find and parse baselines.json — if it doesn't exist, that's acceptable
            if let bundlePath = Bundle.main.url(forResource: "baselines", withExtension: "json") {
                let data = try Data(contentsOf: bundlePath)
                let baselines = try JSONDecoder().decode(BenchmarkBaselines.self, from: data)
                guard !baselines.regressionRules.isEmpty else {
                    throw ValidationError("No regression rules defined")
                }
            }
            // If no baselines file exists, the check still passes (first run scenario)
        }

        // Check 4: BenchmarkRegressionChecker produces valid results
        await runCheck("BenchmarkRegressionChecker Logic") {
            let baseline = BenchmarkBaselineEntry(
                id: "test",
                model: "test-model",
                variant: "standard",
                backend: "gpu",
                deviceFamily: "test",
                metrics: ["decode_tok_s": 40.0, "ttft_s": 0.5],
                source: "test",
                notes: "test"
            )
            let rules: [String: RegressionRule] = [
                "decode_tok_s": RegressionRule(
                    direction: .higherIsBetter,
                    thresholdPct: 10,
                    severity: .critical,
                    description: "Decode speed"
                ),
                "ttft_s": RegressionRule(
                    direction: .lowerIsBetter,
                    thresholdPct: 20,
                    severity: .warning,
                    description: "Time to first token"
                )
            ]
            let results = BenchmarkRegressionChecker.checkRegression(
                results: ["decode_tok_s": 42.0, "ttft_s": 0.45],
                baseline: baseline,
                rules: rules
            )
            guard !results.isEmpty else {
                throw ValidationError("Regression checker returned empty results")
            }
            // The test values are improvements, so none should be regressions
            let regressions = results.filter(\.isRegression)
            guard regressions.isEmpty else {
                throw ValidationError("False regression detected on known-good values")
            }
        }

        // Check 5: BuiltInEvalSuites loads correctly
        await runCheck("BuiltInEvalSuites Loading") {
            let suites = BuiltInEvalSuites.allBuiltIn
            guard !suites.isEmpty else {
                throw ValidationError("No built-in eval suites loaded")
            }
            for suite in suites {
                guard !suite.name.isEmpty else {
                    throw ValidationError("Suite has empty name")
                }
                guard !suite.prompts.isEmpty else {
                    throw ValidationError("Suite '\(suite.name)' has no prompts")
                }
            }
        }

        // Summary
        status = "Validations Complete"
        let summary = "\(passCount) passed, \(failCount) failed"
        logResult("Summary: \(summary)")
        validationLog("[VALIDATION_COMPLETE] \(summary)")
        
        // Persist results to Documents/metrics/validation_results.json
        // This allows on-device results to be verified without --console
        persistResults()
    }

    // MARK: - Helpers

    private func runCheck(_ name: String, body: () throws -> Void) async {
        do {
            try body()
            passCount += 1
            logResult("\(name): PASS")
        } catch {
            failCount += 1
            logResult("\(name): FAIL — \(error.localizedDescription)")
        }
    }

    private func logResult(_ msg: String) {
        results.append(ValidationResult(text: msg))
        validationLog("[VALIDATION_TEST] \(msg)")
    }

    private struct ValidationError: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
    
    /// Writes validation results to Documents/metrics/validation_results.json.
    /// Enables on-device result verification without --console mode.
    private func persistResults() {
        // Use Documents/metrics/ — reliably writable on both macOS and iOS
        guard let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            validationLog("[VALIDATION_TEST] Warning: Could not find Documents directory")
            return
        }
        let metricsDir = docsDir.appendingPathComponent("metrics")
        try? FileManager.default.createDirectory(at: metricsDir, withIntermediateDirectories: true)
        let outputURL = metricsDir.appendingPathComponent("validation_results.json")
        
        let payload: [String: Any] = [
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "passed": passCount,
            "failed": failCount,
            "results": results.map { ["text": $0.text] }
        ]
        
        do {
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: outputURL)
            validationLog("[VALIDATION_TEST] Results persisted to \(outputURL.path)")
        } catch {
            validationLog("[VALIDATION_TEST] Warning: Could not persist results: \(error.localizedDescription)")
        }
    }
}

// MARK: - Validation View

/// Displays benchmark validation results in a monospaced scrollable list.
/// Launched via the `-RunValidation` launch argument.
///
/// Ported from IO 2026 Concierge E2EValidationView pattern.
struct BenchmarkValidationView: View {
    @StateObject private var runner = BenchmarkValidationRunner()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Edge AI Lab — Benchmark Validation")
                .font(.headline)
            Text(runner.status)
                .foregroundColor(.gray)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(runner.results) { result in
                        Text(result.text)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(result.text.contains("PASS") ? .green : .red)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
        .task {
            await runner.runAll()
        }
    }
}
