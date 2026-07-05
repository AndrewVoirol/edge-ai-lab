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

// MARK: - Benchmark Automation Pipeline

/// Self-contained benchmark pipeline extracted from DeveloperAutomationHarness.
///
/// Handles model discovery, benchmark execution, crash recovery, baseline comparison,
/// and regression checking. Operates as a static namespace (no instance state).
@MainActor
struct BenchmarkAutomationPipeline {
    
    // MARK: - Crash Recovery Keys
    
    // Crash-recovery UserDefaults keys (ported from IO 2026 Concierge InferenceBenchmark)
    private static let kActiveConfigKey = "benchmark_active_config"
    private static let kProcessedConfigsKey = "benchmark_processed_configs"
    private static let kBenchmarkRunIdKey = "benchmark_run_id"
    
    /// Returns or creates a persistent run ID for the current benchmark session.
    /// The run ID survives app restarts so crash-resumed runs share the same ID.
    private static var benchmarkRunId: String {
        let defaults = UserDefaults.standard
        if let existing = defaults.string(forKey: kBenchmarkRunIdKey) {
            return existing
        }
        let created = UUID().uuidString
        defaults.set(created, forKey: kBenchmarkRunIdKey)
        return created
    }
    
    /// Clears all benchmark crash-recovery state from UserDefaults.
    private static func clearBenchmarkState() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: kActiveConfigKey)
        defaults.removeObject(forKey: kProcessedConfigsKey)
        defaults.removeObject(forKey: kBenchmarkRunIdKey)
    }
    
    // MARK: - Pipeline Entry Point
    
    /// Runs the benchmark pipeline: discover models, benchmark, compare against baselines.
    ///
    /// In dry-run mode, validates the pipeline plumbing without requiring a model:
    /// - Verifies baselines.json parses correctly
    /// - Verifies regression rules are valid
    /// - Verifies model discovery works
    ///
    /// Crash recovery (ported from IO 2026 Concierge InferenceBenchmark):
    /// - Before each config starts, persists the config ID to `benchmark_active_config`
    /// - On startup, checks for a stale active config — if found, logs `interruptedPreviousRun`
    /// - Tracks processed configs in `benchmark_processed_configs` to skip on relaunch
    /// - Clears all state keys after the full pipeline completes
    static func run(viewModel: ConversationViewModel, isDryRun: Bool) async {
        automationLog("[AUTOMATION] ═══════════════════════════════════════════")
        automationLog("[AUTOMATION] Benchmark Pipeline \(isDryRun ? "(DRY RUN)" : "")")
        automationLog("[AUTOMATION] ═══════════════════════════════════════════")
        
        // Pre-flight: log build config and memory status
        #if DEBUG
        let buildConfig = "Debug"
        #else
        let buildConfig = "Release"
        #endif
        let snapshot = DeviceMetrics.captureSnapshot()
        automationLog("[AUTOMATION] Build config: \(buildConfig)")
        automationLog("[AUTOMATION] Available memory: \(String(format: "%.0f", snapshot.availableMemoryMB)) MB")
        automationLog("[AUTOMATION] Device: \(snapshot.deviceModel)")
        
        #if DEBUG
        #if os(iOS)
        if snapshot.availableMemoryMB < 2000 {
            automationLog("[AUTOMATION] ⚠️ WARNING: Low memory (\(String(format: "%.0f", snapshot.availableMemoryMB)) MB) with Debug build.")
            automationLog("[AUTOMATION] ⚠️ Debug builds use ~2x more memory. Consider: BUILD_CONFIG=Release ./automation/deploy_device.sh")
        }
        #endif
        #endif
        
        let runId = benchmarkRunId
        let defaults = UserDefaults.standard
        let metricsStore = MetricsStore()
        
        // --- Crash Recovery: detect interrupted previous run ---
        if let crashedConfigId = defaults.string(forKey: kActiveConfigKey) {
            automationLog("[AUTOMATION] Detected interrupted previous run on config: \(crashedConfigId)")
            automationLog("[AUTOMATION] Logging interruptedPreviousRun event and skipping config.")
            
            // Log the interrupted run as a JSONL entry with turnIndex -1
            let interruptedEntry: [String: Any] = [
                "event": "interruptedPreviousRun",
                "configId": crashedConfigId,
                "runId": runId,
                "turnIndex": -1,
                "timestamp": ISO8601DateFormatter().string(from: Date())
            ]
            if let jsonData = try? JSONSerialization.data(withJSONObject: interruptedEntry, options: [.sortedKeys]),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                print("[BENCHMARK_TURN] \(jsonString)")
                metricsStore.appendRawJSONL(jsonString)
            }
            
            defaults.removeObject(forKey: kActiveConfigKey)
            
            // Mark the crashed config as processed so we skip it
            var processed = defaults.stringArray(forKey: kProcessedConfigsKey) ?? []
            if !processed.contains(crashedConfigId) {
                processed.append(crashedConfigId)
                defaults.set(processed, forKey: kProcessedConfigsKey)
            }
        }
        
        var processedConfigs = defaults.stringArray(forKey: kProcessedConfigsKey) ?? []
        
        // Step 1: Load baselines
        automationLog("[AUTOMATION] Step 1: Loading baselines...")
        let baselinesURL = findBaselinesFile()
        if let baselinesURL = baselinesURL {
            automationLog("[AUTOMATION] Baselines file found: \(baselinesURL.lastPathComponent)")
            do {
                let data = try Data(contentsOf: baselinesURL)
                let baselines = try JSONDecoder().decode(BenchmarkBaselines.self, from: data)
                automationLog("[AUTOMATION_SUCCESS] Parsed \(baselines.baselines.count) baselines, \(baselines.regressionRules.count) regression rules")
            } catch {
                automationLog("[AUTOMATION_FAILURE] Failed to parse baselines: \(error.localizedDescription)")
                DeveloperAutomationHarness.signalComplete(1, message: "Failed to parse baselines")
                return
            }
        } else {
            automationLog("[AUTOMATION] No baselines file found — first run, no regression check possible")
        }
        
        // Step 2: Discover models
        let docs = GalleryModelDiscovery.getAppModelsDirectory()
        let modelFiles = (try? FileManager.default.contentsOfDirectory(at: docs, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension == "litertlm" } ?? []
        automationLog("[AUTOMATION] Step 2: Discovered \(modelFiles.count) model(s)")
        for file in modelFiles {
            automationLog("[AUTOMATION]   - \(file.lastPathComponent)")
        }
        
        if isDryRun {
            automationLog("[AUTOMATION_SUCCESS] Benchmark pipeline dry-run completed.")
            automationLog("[AUTOMATION]   ✅ Baselines: \(baselinesURL != nil ? "parsed" : "not found (acceptable for first run)")")
            automationLog("[AUTOMATION]   ✅ Model discovery: \(modelFiles.count) model(s)")
            automationLog("[AUTOMATION]   ✅ Pipeline plumbing validated")
            clearBenchmarkState()
            DeveloperAutomationHarness.signalComplete(0, message: "Benchmark pipeline dry-run completed")
            return
        }
        
        // Step 3: Ensure model is available (downloads if needed)
        automationLog("[AUTOMATION] Step 3: Ensuring model is available...")
        let targetModel = ModelRegistry.gemma4E2BStandard
        await DeveloperAutomationHarness.ensureModelDownloaded(model: targetModel, docs: docs, viewModel: viewModel)
        
        // Re-scan after download
        let postDownloadFiles = (try? FileManager.default.contentsOfDirectory(at: docs, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension == "litertlm" } ?? []
        automationLog("[AUTOMATION]   Models after download: \(postDownloadFiles.count)")
        
        guard !postDownloadFiles.isEmpty else {
            automationLog("[AUTOMATION_FAILURE] No models available after download attempt. Model may have failed to download.")
            clearBenchmarkState()
            DeveloperAutomationHarness.signalComplete(1, message: "No models available after download attempt")
            return
        }
        
        let configId = BenchmarkPipelineLogic.buildConfigId(modelFile: targetModel.modelFile, backend: "gpu", samplingStrategy: "greedy")
        
        // Skip if this config was already processed (crash recovery)
        if BenchmarkPipelineLogic.shouldSkipConfig(configId: configId, processedConfigs: processedConfigs) {
            automationLog("[AUTOMATION] Skipping already-processed config: \(configId)")
        } else {
            // Persist active config before starting (crash recovery breadcrumb)
            defaults.set(configId, forKey: kActiveConfigKey)
            
            let targetURL = docs.appendingPathComponent(targetModel.modelFile)
            let flags = RuntimeFlags(enableBenchmark: true, enableSpeculativeDecoding: nil, enableConversationConstrainedDecoding: false, visualTokenBudget: nil)
            let sampler = DeveloperAutomationHarness.safeSamplerConfig(topK: 1, topP: 1.0, temperature: 1.0)
            let cachesDir = DeveloperAutomationHarness.safeCachesDirectory().appendingPathComponent(targetModel.modelFile)
            try? FileManager.default.createDirectory(at: cachesDir, withIntermediateDirectories: true)
            
            do {
                guard let liteRTAdapter = viewModel.engine as? LiteRTEngineAdapter else {
                    automationLog("[AUTOMATION_FAILURE] Automation harness requires LiteRT engine")
                    clearBenchmarkState()
                    DeveloperAutomationHarness.signalComplete(1, message: "No LiteRT engine")
                    return
                }
                try await liteRTAdapter.initializeLiteRT(
                    modelPath: targetURL.path,
                    useGPU: true,
                    cacheDir: cachesDir.path,
                    flags: flags.toLiteRTFlags(),
                    samplerConfig: sampler
                )
            } catch {
                automationLog("[AUTOMATION_FAILURE] Failed to initialize engine: \(error.localizedDescription)")
                clearBenchmarkState()
                DeveloperAutomationHarness.signalComplete(1, message: "Failed to initialize engine for benchmark")
                return
            }
            
            // Warmup turn tagged with turnIndex: -1 (cold probe)
            let warmupEntry: [String: Any] = [
                "event": "warmup",
                "configId": configId,
                "runId": runId,
                "turnIndex": -1,
                "timestamp": ISO8601DateFormatter().string(from: Date())
            ]
            if let jsonData = try? JSONSerialization.data(withJSONObject: warmupEntry, options: [.sortedKeys]),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                print("[BENCHMARK_TURN] \(jsonString)")
                metricsStore.appendRawJSONL(jsonString)
            }
            
            if let metrics = await DeveloperAutomationHarness.runSingleBenchmark(viewModel: viewModel, prompt: DeveloperAutomationHarness.benchmarkPrompt) {
                automationLog("[AUTOMATION_SUCCESS] Benchmark completed.")
                DeveloperAutomationHarness.printReport(metrics: metrics, model: targetModel.modelFile, configLabel: "GPU / No MTP / Greedy")
                
                // Stream the benchmark turn result to JSONL
                var turnEntry: [String: Any] = metrics
                turnEntry["configId"] = configId
                turnEntry["runId"] = runId
                turnEntry["turnIndex"] = 0
                turnEntry["timestamp"] = ISO8601DateFormatter().string(from: Date())
                if let jsonData = try? JSONSerialization.data(withJSONObject: turnEntry, options: [.sortedKeys]),
                   let jsonString = String(data: jsonData, encoding: .utf8) {
                    print("[BENCHMARK_TURN] \(jsonString)")
                    metricsStore.appendRawJSONL(jsonString)
                }
                
                // Clear active config — this config completed successfully
                defaults.removeObject(forKey: kActiveConfigKey)
                processedConfigs.append(configId)
                defaults.set(processedConfigs, forKey: kProcessedConfigsKey)
                
                // Step 4: Regression check
                if let baselinesURL = baselinesURL {
                    do {
                        let data = try Data(contentsOf: baselinesURL)
                        let baselines = try JSONDecoder().decode(BenchmarkBaselines.self, from: data)
                        
                        // Convert [String: Any] metrics to [String: Double]
                        let doubleMetrics = BenchmarkPipelineLogic.convertMetricsToDoubles(metrics: metrics)
                        
                        // Find matching baseline by model name and backend
                        let matchingBaselines = baselines.baselines.filter {
                            $0.model == targetModel.modelFile && $0.backend == "gpu"
                        }
                        
                        guard let baseline = matchingBaselines.first else {
                            automationLog("[AUTOMATION] No matching baseline found for \(targetModel.modelFile) / gpu")
                            clearBenchmarkState()
                            DeveloperAutomationHarness.signalComplete(0, message: "No matching baseline found, skipping regression check")
                            return
                        }
                        
                        let results = BenchmarkRegressionChecker.checkRegression(
                            results: doubleMetrics,
                            baseline: baseline,
                            rules: baselines.regressionRules
                        )
                        
                        let hasCritical = BenchmarkPipelineLogic.hasCriticalRegressions(results: results)
                        
                        automationLog("\n[AUTOMATION_BENCHMARK_REGRESSION]")
                        for result in results {
                            let icon = BenchmarkPipelineLogic.formatRegressionIcon(isRegression: result.isRegression, deviationPct: result.deviationPct)
                            automationLog("[AUTOMATION]   \(icon) \(result.metricKey): \(result.status) (\(String(format: "%.1f", result.deviationPct))% vs baseline)")
                        }
                        
                        if hasCritical {
                            automationLog("[AUTOMATION_FAILURE] Critical regression(s) detected")
                            clearBenchmarkState()
                            DeveloperAutomationHarness.signalComplete(1, message: "Critical benchmark regression(s) detected")
                            return
                        } else {
                            automationLog("[AUTOMATION_SUCCESS] No critical regressions detected")
                        }
                    } catch {
                        automationLog("[AUTOMATION] Warning: Could not run regression check: \(error.localizedDescription)")
                    }
                }
            } else {
                // Benchmark failed — clear active config but don't mark as processed
                defaults.removeObject(forKey: kActiveConfigKey)
                clearBenchmarkState()
                DeveloperAutomationHarness.signalComplete(1, message: "Benchmark run failed")
                return
            }
        }
        
        // Pipeline complete — clear all benchmark state keys
        clearBenchmarkState()
        DeveloperAutomationHarness.signalComplete(0, message: "Benchmark pipeline completed successfully")
        return
    }
    
    // MARK: - Baselines Discovery
    
    /// Finds the baselines.json file in the project.
    static func findBaselinesFile() -> URL? {
        // 1. Check bundle resources
        if let bundlePath = Bundle.main.url(forResource: "baselines", withExtension: "json") {
            return bundlePath
        }
        
        // 2. Check relative to working directory
        let cwdPath = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("metrics")
            .appendingPathComponent("baselines.json")
        if FileManager.default.fileExists(atPath: cwdPath.path) {
            return cwdPath
        }
        
        // 3. Check known project path
        #if os(macOS)
        let homePath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Antigravity/Projects/edge-ai-lab/metrics/baselines.json")
        if FileManager.default.fileExists(atPath: homePath.path) {
            return homePath
        }
        #endif
        
        return nil
    }
}
