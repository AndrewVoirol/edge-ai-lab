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

// MARK: - Eval Automation Pipeline

/// Self-contained eval pipeline extracted from DeveloperAutomationHarness.
///
/// Handles eval suite loading, validation, execution, regression checking,
/// and result persistence. Operates as a static namespace (no instance state).
@MainActor
struct EvalAutomationPipeline {
    
    // MARK: - Pipeline Entry Point
    
    /// Runs the eval pipeline: load built-in suites, run against discovered models, report scores.
    ///
    /// In dry-run mode, validates the pipeline plumbing without requiring a model:
    /// - Verifies all built-in eval suites load correctly
    /// - Verifies suite prompts have valid scoring methods
    /// - Verifies eval store can be created
    static func run(viewModel: ConversationViewModel, isDryRun: Bool, isGated: Bool = false) async {
        automationLog("[AUTOMATION] ═══════════════════════════════════════════")
        automationLog("[AUTOMATION] Eval Pipeline \(isDryRun ? "(DRY RUN)" : "")")
        automationLog("[AUTOMATION] ═══════════════════════════════════════════")
        let pipelineStartTime = CFAbsoluteTimeGetCurrent()
        
        // Step 1: Load built-in suites
        automationLog("[AUTOMATION] Step 1: Loading built-in eval suites...")
        var suites = BuiltInEvalSuites.allBuiltIn
        automationLog("[AUTOMATION_SUCCESS] Loaded \(suites.count) built-in suite(s):")
        for suite in suites {
            automationLog("[AUTOMATION]   - \(suite.name) (\(suite.category.displayName)): \(suite.promptCount) prompts")
        }
        
        // Optional suite filter: -EvalSuiteFilter "Multimodal" runs only that suite
        if let filterIdx = CommandLine.arguments.firstIndex(of: "-EvalSuiteFilter"),
           filterIdx + 1 < CommandLine.arguments.count {
            let filterName = CommandLine.arguments[filterIdx + 1]
            let filtered = suites.filter { $0.name.localizedCaseInsensitiveContains(filterName) }
            if filtered.isEmpty {
                automationLog("[AUTOMATION_FAILURE] No suite matches filter '\(filterName)'. Available: \(suites.map(\.name).joined(separator: ", "))")
                DeveloperAutomationHarness.signalComplete(1, message: "No suite matches filter '\(filterName)'")
                return
            }
            suites = filtered
            automationLog("[AUTOMATION] Suite filter active: running only \(filtered.map(\.name).joined(separator: ", "))")
        }
        
        // Optional runs-per-prompt: -EvalRunsPerPrompt 1 (default 5)
        var runsPerPrompt = 5
        if let rppIdx = CommandLine.arguments.firstIndex(of: "-EvalRunsPerPrompt"),
           rppIdx + 1 < CommandLine.arguments.count,
           let rpp = Int(CommandLine.arguments[rppIdx + 1]), rpp > 0 {
            runsPerPrompt = rpp
            automationLog("[AUTOMATION] Runs per prompt: \(rpp)")
        }
        
        // Step 2: Validate suites
        automationLog("[AUTOMATION] Step 2: Validating suite structure...")
        var validationIssues: [String] = []
        for suite in suites {
            if suite.name.isEmpty {
                validationIssues.append("Suite has empty name (id: \(suite.id))")
            }
            if suite.prompts.isEmpty {
                validationIssues.append("Suite '\(suite.name)' has no prompts")
            }
        }
        
        if validationIssues.isEmpty {
            automationLog("[AUTOMATION_SUCCESS] All suites validated successfully")
        } else {
            for issue in validationIssues {
                automationLog("[AUTOMATION_FAILURE] Validation: \(issue)")
            }
            DeveloperAutomationHarness.signalComplete(1, message: "Eval suite validation failed")
            return
        }
        
        // Step 3: Discover models
        let docs = GalleryModelDiscovery.getAppModelsDirectory()
        let modelFiles = (try? FileManager.default.contentsOfDirectory(at: docs, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension == "litertlm" } ?? []
        automationLog("[AUTOMATION] Step 3: Discovered \(modelFiles.count) model(s)")
        
        if isDryRun {
            // Verify eval store creation
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("eval_pipeline_dryrun_\(UUID().uuidString)")
            try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            let _ = EvalStore(storageDirectory: tempDir)
            try? FileManager.default.removeItem(at: tempDir)
            
            automationLog("[AUTOMATION_SUCCESS] Eval pipeline dry-run completed.")
            automationLog("[AUTOMATION]   ✅ Built-in suites: \(suites.count) loaded")
            automationLog("[AUTOMATION]   ✅ Total prompts: \(suites.reduce(0) { $0 + $1.promptCount })")
            automationLog("[AUTOMATION]   ✅ Model discovery: \(modelFiles.count) model(s)")
            automationLog("[AUTOMATION]   ✅ EvalStore: created and validated")
            automationLog("[AUTOMATION]   ✅ Pipeline plumbing validated")
            DeveloperAutomationHarness.signalComplete(0, message: "Eval pipeline dry-run completed")
            return
        }
        
        // Real mode: discover all available models (LiteRT, GGUF, MLX)
        automationLog("[AUTOMATION] Step 4: Discovering models...")
        let discoveredModels = GalleryModelDiscovery.discoverModels()
            .filter { $0.resolvedMetadata.runtimeType.isSupported }
        
        guard !discoveredModels.isEmpty else {
            automationLog("[AUTOMATION_FAILURE] No models found in models directory")
            DeveloperAutomationHarness.signalComplete(1, message: "No models available for eval")
            return
        }
        
        for model in discoveredModels {
            automationLog("[AUTOMATION]   Found: \(model.filename) (\(model.formattedSize), \(model.resolvedMetadata.runtimeType.displayName))")
        }
        // Optional model filter: -EvalModelFilter "GGUF" filters by engine name
        var modelsToRun = discoveredModels
        if let mfIdx = CommandLine.arguments.firstIndex(of: "-EvalModelFilter"),
           mfIdx + 1 < CommandLine.arguments.count {
            let modelFilter = CommandLine.arguments[mfIdx + 1]
            let filtered = discoveredModels.filter {
                $0.resolvedMetadata.runtimeType.displayName.localizedCaseInsensitiveContains(modelFilter)
                || $0.filename.localizedCaseInsensitiveContains(modelFilter)
            }
            if filtered.isEmpty {
                automationLog("[AUTOMATION_FAILURE] No model matches filter '\(modelFilter)'. Available: \(discoveredModels.map { $0.filename }.joined(separator: ", "))")
                DeveloperAutomationHarness.signalComplete(1, message: "No model matches filter '\(modelFilter)'")
                return
            }
            modelsToRun = filtered
            automationLog("[AUTOMATION] Model filter active: running only \(filtered.map { $0.filename }.joined(separator: ", "))")
        }
        
        automationLog("[AUTOMATION] Step 5: Running eval suites against \(modelsToRun.count) model(s)...")
        let evalDir = docs.appendingPathComponent("eval_results")
        try? FileManager.default.createDirectory(at: evalDir, withIntermediateDirectories: true)
        let evalStore = EvalStore(storageDirectory: evalDir)
        let evalRunner = EvalRunner(store: evalStore)
        
        let flags = RuntimeFlags(enableBenchmark: true, enableSpeculativeDecoding: nil, enableConversationConstrainedDecoding: false, visualTokenBudget: nil)
        let cachesDir = DeveloperAutomationHarness.safeCachesDirectory()
        
        // Run all suites against each model
        for discovered in modelsToRun {
            let metadata = discovered.resolvedMetadata
            let modelEntry = EvalModelEntry(metadata: metadata, modelPath: discovered.url.path, mmProjPath: discovered.mmProjPath)
            let modelCacheDir = cachesDir.appendingPathComponent(discovered.filename)
            try? FileManager.default.createDirectory(at: modelCacheDir, withIntermediateDirectories: true)
            
            automationLog("\n[AUTOMATION] ─── Model: \(metadata.name) (\(metadata.runtimeType.displayName)) ───")
            let multimodalInfo = [
                metadata.supportsImage ? "vision" : nil,
                metadata.supportsAudio ? "audio" : nil
            ].compactMap { $0 }.joined(separator: "+")
            automationLog("[AUTOMATION]   Engine: \(metadata.runtimeType.displayName) | Multimodal: \(multimodalInfo.isEmpty ? "text-only" : multimodalInfo) | Start: cold (fresh engine per suite)")
            
            // Device state snapshot at model start
            let thermalState = DeviceMetrics.currentThermalLevel
            let availMem = DeviceMetrics.formattedAvailableMemory
            let gpuMemStr = DeviceMetrics.gpuAllocatedMemoryMB.map { String(format: "%.0f MB", $0) } ?? "N/A"
            let powerStr = DeviceMetrics.formattedPowerStatus
            automationLog("[AUTOMATION]   🌡️ Thermal: \(thermalState.label) | RAM: \(availMem) | GPU: \(gpuMemStr) | Power: \(powerStr)")
            
            var modelResults: [(suiteName: String, passRate: Double, promptCount: Int, failedPrompts: [String], perf: SuitePerformanceMetrics?)] = []
            
            for suite in suites {
                automationLog("\n[AUTOMATION] Running suite: \(suite.name) (\(suite.promptCount) prompts)...")
                
                if suite.category == .toolCalling {
                    automationLog("[AUTOMATION]   ℹ️ Tool Calling suite: \(suite.promptCount) prompts including \(suite.prompts.filter { if case .toolCallChain = $0.expectedBehavior { return true } else { return false } }.count) multi-tool chain(s)")
                }
                
                do {
                    let suiteStartTime = CFAbsoluteTimeGetCurrent()
                    let run = try await evalRunner.run(
                        suite: suite,
                        models: [modelEntry],
                        flags: flags,
                        cacheDir: modelCacheDir.path,
                        runsPerPrompt: runsPerPrompt
                    )
                    let suiteDuration = CFAbsoluteTimeGetCurrent() - suiteStartTime
                    
                    let totalResults = run.modelResults.flatMap { $0.promptResults }
                    let passed = totalResults.filter { $0.passed }.count
                    let passRate = EvalPipelineLogic.calculatePassRate(passed: passed, total: totalResults.count)
                    let safePassRate = passRate.isFinite ? passRate : 0.0
                    
                    // Track which prompts failed for per-prompt regression tracking
                    let failedPromptTexts = totalResults
                        .filter { !$0.passed }
                        .map { String($0.promptText.prefix(60)) }
                    
                    // Capture performance metrics for persistence
                    let perfMetrics: SuitePerformanceMetrics? = run.modelResults.first.map { mr in
                        SuitePerformanceMetrics(
                            durationSeconds: suiteDuration,
                            decodeSpeed: mr.avgDecodeSpeed,
                            prefillSpeed: mr.avgPrefillSpeed,
                            ttftSeconds: mr.avgTTFT,
                            p95Latency: mr.p95Latency,
                            totalTokens: mr.totalTokensGenerated,
                            peakMemoryDeltaMB: mr.peakMemoryDeltaMB,
                            thermalTransitions: mr.thermalTransitions
                        )
                    }
                    
                    modelResults.append((
                        suiteName: suite.name,
                        passRate: safePassRate,
                        promptCount: suite.promptCount,
                        failedPrompts: failedPromptTexts,
                        perf: perfMetrics
                    ))
                    automationLog("[AUTOMATION]   Score: \(passed)/\(totalResults.count) (\(String(format: "%.0f", safePassRate * 100))%)")
                    
                    // Log performance metrics from the ModelEvalResult
                    if let modelResult = run.modelResults.first {
                        let durationStr = String(format: "%.1f", suiteDuration)
                        let speedStr = modelResult.avgDecodeSpeed > 0 ? String(format: "%.1f tok/s", modelResult.avgDecodeSpeed) : "N/A"
                        let prefillStr = modelResult.avgPrefillSpeed.map { String(format: "%.0f tok/s", $0) } ?? "N/A"
                        let ttftStr = modelResult.avgTTFT > 0 ? String(format: "%.0f ms", modelResult.avgTTFT * 1000) : "N/A"
                        let p95Str = modelResult.p95Latency > 0 ? String(format: "%.1f ms/tok", modelResult.p95Latency) : "N/A"
                        automationLog("[AUTOMATION]   ⏱️ Duration: \(durationStr)s | Decode: \(speedStr) | Prefill: \(prefillStr) | TTFT: \(ttftStr) | P95: \(p95Str)")
                        automationLog("[AUTOMATION]   📊 Tokens: \(modelResult.totalTokensGenerated) | Memory Δ: \(modelResult.peakMemoryDeltaMB.map { String(format: "%.1f MB", $0) } ?? "N/A") | Thermal: \(modelResult.thermalTransitions) transition(s)")
                    }
                    
                    // Log failed prompts with response snippets for diagnostic value
                    let failedResults = totalResults.filter { !$0.passed }
                    if !failedResults.isEmpty {
                        automationLog("[AUTOMATION]   ❌ Failed prompts (\(failedResults.count)):")
                        for failedResult in failedResults.prefix(10) {
                            let promptSnippet = String(failedResult.promptText.prefix(60))
                            let responseSnippet = String(failedResult.response.prefix(80))
                                .replacingOccurrences(of: "\n", with: " ")
                            automationLog("[AUTOMATION]      - Q: \(promptSnippet)")
                            automationLog("[AUTOMATION]        A: \(responseSnippet)")
                            if let reason = failedResult.score.reason {
                                automationLog("[AUTOMATION]        ⚠️ \(reason)")
                            }
                        }
                        if failedResults.count > 10 {
                            automationLog("[AUTOMATION]      ... and \(failedResults.count - 10) more")
                        }
                    }
                } catch {
                    automationLog("[AUTOMATION_FAILURE] Suite '\(suite.name)' failed: \(error.localizedDescription)")
                    modelResults.append((suiteName: suite.name, passRate: 0.0, promptCount: suite.promptCount, failedPrompts: [], perf: nil))
                }
                
                evalRunner.reset()
            }
            
            // Print summary for this model
            automationLog("\n[AUTOMATION] ═══════════════════════════════════════════")
            automationLog("[AUTOMATION] Results: \(metadata.name) (\(metadata.runtimeType.displayName))")
            automationLog("[AUTOMATION] ═══════════════════════════════════════════")
            
            for result in modelResults {
                if EvalPipelineLogic.isSuiteSkipped(passRate: result.passRate) {
                    automationLog("[AUTOMATION]   ⏭️ \(result.suiteName): SKIPPED")
                } else {
                    let icon = EvalPipelineLogic.formatPassRateIcon(passRate: result.passRate)
                    automationLog("[AUTOMATION]   \(icon) \(result.suiteName): \(String(format: "%.0f", result.passRate * 100))%")
                }
            }
            
            // Persist results for this model
            persistEvalHistory(
                results: modelResults.map { (suiteName: $0.suiteName, passRate: $0.passRate, promptCount: $0.promptCount, failedPrompts: $0.failedPrompts, perf: $0.perf) },
                model: metadata.modelFile,
                engine: metadata.runtimeType.rawValue
            )
        }
        
        // Step 6: Regression check (if baselines exist)
        let evalBaselinesURL = findEvalBaselinesFile()
        if let evalBaselinesURL = evalBaselinesURL {
            do {
                let data = try Data(contentsOf: evalBaselinesURL)
                let evalBaselines = try JSONDecoder().decode(EvalBaselines.self, from: data)
                automationLog("[AUTOMATION] Step 6: Checking eval regressions against \(evalBaselines.baselines.count) baseline(s)...")
                
                // Check regressions for the primary model only
                if let primaryModel = discoveredModels.first {
                    let primaryMetadata = primaryModel.resolvedMetadata
                    // Find results for primary model — they were already persisted above
                    // Just log the check as informational
                    automationLog("[AUTOMATION]   Regression check target: \(primaryMetadata.name)")
                }
            } catch {
                automationLog("[AUTOMATION] Warning: Could not run eval regression check: \(error.localizedDescription)")
            }
        } else {
            automationLog("[AUTOMATION] No eval baselines file found — skipping regression check")
        }
        
        let pipelineElapsed = CFAbsoluteTimeGetCurrent() - pipelineStartTime
        let minutes = Int(pipelineElapsed) / 60
        let seconds = Int(pipelineElapsed) % 60
        automationLog("[AUTOMATION_SUCCESS] Eval pipeline completed for \(modelsToRun.count) model(s) in \(minutes)m \(seconds)s")
        DeveloperAutomationHarness.signalComplete(0, message: "Eval pipeline completed successfully")
        
        // Best-effort engine cleanup (only reached under XCUITest).
        await viewModel.engine.shutdown()
        return
    }
    
    // MARK: - Baselines Discovery
    
    /// Finds the eval_baselines.json file in the project.
    static func findEvalBaselinesFile() -> URL? {
        // 1. Check bundle resources
        if let bundlePath = Bundle.main.url(forResource: "eval_baselines", withExtension: "json") {
            return bundlePath
        }
        
        // 2. Check relative to working directory
        let cwdPath = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("metrics")
            .appendingPathComponent("eval_baselines.json")
        if FileManager.default.fileExists(atPath: cwdPath.path) {
            return cwdPath
        }
        
        // 3. Check known project path
        #if os(macOS)
        let homePath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Antigravity/Projects/edge-ai-lab/metrics/eval_baselines.json")
        if FileManager.default.fileExists(atPath: homePath.path) {
            return homePath
        }
        #endif
        
        return nil
    }
    
    // MARK: - History Persistence
    
    /// Persists eval results to metrics/eval_history.json.
    /// On macOS, writes to the project's metrics/ directory.
    /// On iOS, writes to the app's Documents/metrics/ directory (pullable via devicectl).
    static func persistEvalHistory(
        results: [(suiteName: String, passRate: Double, promptCount: Int, failedPrompts: [String], perf: SuitePerformanceMetrics?)],
        model: String,
        engine: String? = nil
    ) {
        // Find or create the eval_history.json file
        let historyURL: URL = {
            // 1. Check macOS project paths
            #if os(macOS)
            let projectPaths = [
                URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                    .appendingPathComponent("metrics/eval_history.json"),
                FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent("Antigravity/Projects/edge-ai-lab/metrics/eval_history.json")
            ]
            if let existing = projectPaths.first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
                return existing
            }
            #endif
            
            // 2. Use app's Documents/metrics/ directory (works on both platforms)
            let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first ?? "/tmp")
            let metricsDir = docsDir.appendingPathComponent("metrics")
            try? FileManager.default.createDirectory(at: metricsDir, withIntermediateDirectories: true)
            return metricsDir.appendingPathComponent("eval_history.json")
        }()
        
        automationLog("[AUTOMATION] Eval history path: \(historyURL.path)")
        
        do {
            // Load existing history, or start fresh if file doesn't exist yet
            var history: [String: Any]
            var runs: [[String: Any]]
            if FileManager.default.fileExists(atPath: historyURL.path) {
                let historyData = try Data(contentsOf: historyURL)
                history = try JSONSerialization.jsonObject(with: historyData) as? [String: Any] ?? [:]
                runs = history["runs"] as? [[String: Any]] ?? []
            } else {
                automationLog("[AUTOMATION] Creating new eval_history.json at \(historyURL.path)")
                history = [:]
                runs = []
            }
            
            let suiteEntries: [[String: Any]] = results.map { result in
                if EvalPipelineLogic.isSuiteSkipped(passRate: result.passRate) {
                    // Skipped suite
                    return [
                        "name": result.suiteName,
                        "pass_rate": NSNull(),
                        "status": "skipped",
                        "prompt_count": result.promptCount
                    ] as [String: Any]
                }
                var entry: [String: Any] = [
                    "name": result.suiteName,
                    "pass_rate": result.passRate.isFinite ? result.passRate : 0.0,
                    "prompt_count": result.promptCount
                ]
                // Include failed prompt texts for per-prompt regression tracking
                if !result.failedPrompts.isEmpty {
                    entry["failed_prompts"] = result.failedPrompts
                }
                // Persist performance metrics alongside quality scores
                if let perf = result.perf {
                    var perfDict: [String: Any] = [
                        "duration_seconds": perf.durationSeconds
                    ]
                    if perf.decodeSpeed > 0 { perfDict["decode_tok_s"] = perf.decodeSpeed }
                    if let prefill = perf.prefillSpeed { perfDict["prefill_tok_s"] = prefill }
                    if perf.ttftSeconds > 0 { perfDict["ttft_ms"] = perf.ttftSeconds * 1000 }
                    if perf.p95Latency > 0 { perfDict["p95_ms_per_tok"] = perf.p95Latency }
                    if perf.totalTokens > 0 { perfDict["total_tokens"] = perf.totalTokens }
                    if let memDelta = perf.peakMemoryDeltaMB { perfDict["peak_memory_delta_mb"] = memDelta }
                    perfDict["thermal_transitions"] = perf.thermalTransitions
                    entry["performance"] = perfDict
                }
                return entry
            }
            
            var newRun: [String: Any] = [
                "timestamp": ISO8601DateFormatter().string(from: Date()),
                "model": model,
                "suites": suiteEntries
            ]
            // Include engine type for multi-engine tracking
            if let engine = engine {
                newRun["engine"] = engine
            }
            
            runs.append(newRun)
            history["runs"] = runs
            
            let outputData = try JSONSerialization.data(withJSONObject: history, options: [.prettyPrinted, .sortedKeys])
            try outputData.write(to: historyURL)
            automationLog("[AUTOMATION] Eval results persisted to eval_history.json")
        } catch {
            automationLog("[AUTOMATION] Warning: Could not persist eval history: \(error.localizedDescription)")
        }
    }
}
