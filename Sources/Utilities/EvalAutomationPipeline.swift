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
        
        // Step 1: Load built-in suites
        automationLog("[AUTOMATION] Step 1: Loading built-in eval suites...")
        let suites = BuiltInEvalSuites.allBuiltIn
        automationLog("[AUTOMATION_SUCCESS] Loaded \(suites.count) built-in suite(s):")
        for suite in suites {
            automationLog("[AUTOMATION]   - \(suite.name) (\(suite.category.displayName)): \(suite.promptCount) prompts")
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
        
        // Real mode: ensure model is available (downloads if needed — tests real user download flow)
        automationLog("[AUTOMATION] Step 4: Ensuring model is available...")
        let targetModel = ModelRegistry.gemma4E2BStandard
        await DeveloperAutomationHarness.ensureModelDownloaded(model: targetModel, docs: docs, viewModel: viewModel)
        
        // Re-scan after download
        let postDownloadFiles = (try? FileManager.default.contentsOfDirectory(at: docs, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension == "litertlm" } ?? []
        automationLog("[AUTOMATION]   Models after download: \(postDownloadFiles.count)")
        
        guard !postDownloadFiles.isEmpty else {
            automationLog("[AUTOMATION_FAILURE] No models available after download attempt. Model may have failed to download.")
            DeveloperAutomationHarness.signalComplete(1, message: "No models available for eval after download attempt")
            return
        }
        
        automationLog("[AUTOMATION] Step 5: Running eval suites...")
        let evalDir = docs.appendingPathComponent("eval_results")
        try? FileManager.default.createDirectory(at: evalDir, withIntermediateDirectories: true)
        let evalStore = EvalStore(storageDirectory: evalDir)
        guard let liteRTAdapter = viewModel.engine as? LiteRTEngineAdapter else {
            automationLog("[AUTOMATION_FAILURE] Automation harness requires LiteRT engine")
            DeveloperAutomationHarness.signalComplete(1, message: "No LiteRT engine")
            return
        }
        let evalRunner = EvalRunner(engine: liteRTAdapter, store: evalStore)
        
        let targetURL = docs.appendingPathComponent(targetModel.modelFile)
        let flags = RuntimeFlags(enableBenchmark: true, enableSpeculativeDecoding: nil, enableConversationConstrainedDecoding: false, visualTokenBudget: nil)
        let sampler = DeveloperAutomationHarness.safeSamplerConfig(topK: 1, topP: 1.0, temperature: 1.0)
        let cachesDir = DeveloperAutomationHarness.safeCachesDirectory().appendingPathComponent(targetModel.modelFile)
        try? FileManager.default.createDirectory(at: cachesDir, withIntermediateDirectories: true)
        
        do {
            guard let liteRTAdapter = viewModel.engine as? LiteRTEngineAdapter else {
                automationLog("[AUTOMATION_FAILURE] Automation harness requires LiteRT engine")
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
            DeveloperAutomationHarness.signalComplete(1, message: "Failed to initialize engine for eval")
            return
        }
        
        let modelEntry = EvalModelEntry(metadata: targetModel, modelPath: targetURL.path)
        var allResults: [(suiteName: String, passRate: Double, promptCount: Int)] = []
        
        for suite in suites {
            automationLog("\n[AUTOMATION] Running suite: \(suite.name) (\(suite.promptCount) prompts)...")
            
            // Tool Calling suites exercise the SDK's handleToolCalls path.
            // Log for diagnostics — multi-tool chains may have longer latency.
            if suite.category == .toolCalling {
                automationLog("[AUTOMATION]   ℹ️ Tool Calling suite: \(suite.promptCount) prompts including \(suite.prompts.filter { if case .toolCallChain = $0.expectedBehavior { return true } else { return false } }.count) multi-tool chain(s)")
            }
            
            do {
                let run = try await evalRunner.run(
                    suite: suite,
                    models: [modelEntry],
                    flags: flags,
                    cacheDir: cachesDir.path
                )
                
                // Calculate pass rate from the run
                let totalResults = run.modelResults.flatMap { $0.promptResults }
                let passed = totalResults.filter { $0.passed }.count
                let passRate = EvalPipelineLogic.calculatePassRate(passed: passed, total: totalResults.count)
                // Guard against non-finite values that crash JSONSerialization
                let safePassRate = passRate.isFinite ? passRate : 0.0
                
                allResults.append((suiteName: suite.name, passRate: safePassRate, promptCount: suite.promptCount))
                automationLog("[AUTOMATION]   Score: \(passed)/\(totalResults.count) (\(String(format: "%.0f", safePassRate * 100))%)")
            } catch {
                automationLog("[AUTOMATION_FAILURE] Suite '\(suite.name)' failed: \(error.localizedDescription)")
                allResults.append((suiteName: suite.name, passRate: 0.0, promptCount: suite.promptCount))
            }
            
            evalRunner.reset()
        }
        
        // Print summary
        automationLog("\n[AUTOMATION] ═══════════════════════════════════════════")
        automationLog("[AUTOMATION] Eval Pipeline Results Summary")
        automationLog("[AUTOMATION] ═══════════════════════════════════════════")
        
        var evalReport: [[String: Any]] = []
        for result in allResults {
            if EvalPipelineLogic.isSuiteSkipped(passRate: result.passRate) {
                // Skipped suite
                automationLog("[AUTOMATION]   ⏭️ \(result.suiteName): SKIPPED")
                evalReport.append([
                    "suite": result.suiteName,
                    "pass_rate": NSNull(),
                    "status": "skipped",
                    "model": targetModel.modelFile
                ])
            } else {
                let icon = EvalPipelineLogic.formatPassRateIcon(passRate: result.passRate)
                automationLog("[AUTOMATION]   \(icon) \(result.suiteName): \(String(format: "%.0f", result.passRate * 100))%")
                evalReport.append([
                    "suite": result.suiteName,
                    "pass_rate": result.passRate.isFinite ? result.passRate : 0.0,
                    "model": targetModel.modelFile
                ])
            }
        }
        
        // Output structured JSON
        let reportDict: [String: Any] = [
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "model": targetModel.modelFile,
            "suites": evalReport
        ]
        
        if let jsonData = try? JSONSerialization.data(withJSONObject: reportDict, options: [.prettyPrinted, .sortedKeys]),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            automationLog("\n[AUTOMATION_EVAL_RESULTS_JSON]")
            print(jsonString)
            automationLog("[AUTOMATION_EVAL_RESULTS_END]\n")
        }
        
        // Step 5: Regression check (if gated or baselines exist)
        let evalBaselinesURL = findEvalBaselinesFile()
        if let evalBaselinesURL = evalBaselinesURL {
            do {
                let data = try Data(contentsOf: evalBaselinesURL)
                let evalBaselines = try JSONDecoder().decode(EvalBaselines.self, from: data)
                automationLog("[AUTOMATION] Step 5: Checking eval regressions against \(evalBaselines.baselines.count) baseline(s)...")
                
                let checks = EvalRegressionChecker.checkRegression(
                    results: allResults.map { (suite: $0.suiteName, passRate: $0.passRate) },
                    baselines: evalBaselines,
                    model: targetModel.modelFile
                )
                
                let criticalRegressions = checks.filter { $0.isRegression && $0.severity == .critical }
                let floorViolations = checks.filter { $0.belowMinFloor }
                
                automationLog("\n[AUTOMATION_EVAL_REGRESSION]")
                for check in checks {
                    let icon = check.isRegression ? "❌" : (check.deviationPct > 0 ? "🎉" : "✅")
                    let floorNote = check.belowMinFloor ? " ⚠️ BELOW MIN FLOOR" : ""
                    automationLog("[AUTOMATION]   \(icon) \(check.suiteName): \(check.status) (\(String(format: "%.1f", check.deviationPct))% vs baseline)\(floorNote)")
                }
                
                let gateResult = EvalPipelineLogic.determineGateResult(
                    criticalRegressions: criticalRegressions.count,
                    floorViolations: floorViolations.count,
                    isGated: isGated
                )
                
                if gateResult.shouldFail {
                    automationLog("[AUTOMATION_FAILURE] \(gateResult.issueCount) critical eval regression(s) detected — CI gate FAILED")
                    DeveloperAutomationHarness.signalComplete(1, message: "Critical eval regression(s) detected, CI gate failed")
                    return
                } else if !criticalRegressions.isEmpty {
                    automationLog("[AUTOMATION] \(criticalRegressions.count) regression(s) detected (informational — not gated)")
                } else {
                    automationLog("[AUTOMATION_SUCCESS] No critical eval regressions detected")
                }
            } catch {
                automationLog("[AUTOMATION] Warning: Could not run eval regression check: \(error.localizedDescription)")
            }
        } else {
            automationLog("[AUTOMATION] No eval baselines file found — skipping regression check")
        }
        
        // Persist results to eval_history.json
        persistEvalHistory(results: allResults, model: targetModel.modelFile)
        
        let exitMessage = isGated ? "Eval pipeline completed (GATED — no regressions)" : "Eval pipeline completed (informational — not gated)"
        automationLog("[AUTOMATION_SUCCESS] \(exitMessage)")
        
        // Signal completion FIRST, then attempt engine shutdown.
        // signalComplete calls _exit() in non-XCUITest mode (e.g., devicectl --console),
        // which terminates immediately — the engine.shutdown() below won't execute.
        // This is intentional: LiteRT's callback_thread_pool can hang during shutdown
        // (DEADLINE_EXCEEDED on stuck GPU tasks), and _exit() bypasses C++ destructors
        // that would otherwise block indefinitely.
        //
        // Under XCUITest, signalComplete writes the marker file and returns, so the
        // engine shutdown WILL execute — but XCUITest tests are short-lived and the
        // tearDown terminates the app anyway.
        DeveloperAutomationHarness.signalComplete(0, message: "Eval pipeline completed successfully")
        
        // Best-effort engine cleanup (only reached under XCUITest).
        viewModel.engine.shutdown()
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
    static func persistEvalHistory(results: [(suiteName: String, passRate: Double, promptCount: Int)], model: String) {
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
                return [
                    "name": result.suiteName,
                    "pass_rate": result.passRate.isFinite ? result.passRate : 0.0,
                    "prompt_count": result.promptCount
                ] as [String: Any]
            }
            
            let newRun: [String: Any] = [
                "timestamp": ISO8601DateFormatter().string(from: Date()),
                "model": model,
                "suites": suiteEntries
            ]
            
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
