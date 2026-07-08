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
import SwiftUI
import os

// NOTE: This file uses print() for structured stdout output AND os.Logger
// for the unified logging system. On macOS, stdout is captured by automation
// scripts. On iOS, os_log is readable via `log stream` or `idevicesyslog`
// without the memory overhead of `--console` mode (which causes Jetsam kills).
// The automationLog() helper writes to both channels.

// NOTE: automationLogger and automationLog() are defined in AutomationLogging.swift
// and shared across DeveloperAutomationHarness, BenchmarkAutomationPipeline, and EvalAutomationPipeline.

@MainActor
struct DeveloperAutomationHarness {
    
    static let benchmarkPrompt = """
    You are a helpful assistant. Please provide a detailed, comprehensive explanation of the following topic. \
    Include historical context, key concepts, practical applications, and recent developments. \
    Be thorough and informative in your response.

    Topic: The history and evolution of artificial intelligence, from its origins in the 1950s through \
    modern deep learning and large language models. Cover key milestones like the Dartmouth Conference, \
    expert systems, the AI winters, the rise of machine learning, neural networks, transformers, and \
    the current era of foundation models. Discuss how hardware advances, particularly GPUs and TPUs, \
    have enabled the scaling of AI systems. Explain the differences between narrow AI, general AI, and \
    superintelligence. Describe the role of data in training modern AI systems, including the challenges \
    of data quality, bias, and privacy. Finally, discuss the societal implications of AI, including its \
    impact on employment, healthcare, education, and scientific research.
    """
    
    // MARK: - Core Runner
    
    static func runSingleBenchmark(
        viewModel: ConversationViewModel,
        prompt: String,
        maxDecodeTokens: Int = 256
    ) async -> [String: Any]? {
        let engine = viewModel.engine
        automationLog("[AUTOMATION] Resetting conversation...")
        do {
            try await engine.resetConversation()
        } catch {
            automationLog("[AUTOMATION_FAILURE] Failed to reset conversation: \(error.localizedDescription)")
            return nil
        }
        
        automationLog("[AUTOMATION] Running warmup turn (priming counters)...")
        do {
            try await engine.warmup()
        } catch {
            automationLog("[AUTOMATION] Warmup warning: \(error.localizedDescription)")
        }
        
        automationLog("[AUTOMATION] Running benchmark turn (decodes capped at \(maxDecodeTokens))...")
        let inferenceStart = CFAbsoluteTimeGetCurrent()
        var tokenCount = 0
        var responseText = ""
        var firstTokenTime: Double? = nil
        
        let config = GenerationConfig(maxTokens: maxDecodeTokens, temperature: 1.0, topP: 1.0, topK: 1)
        
        do {
            for try await event in engine.generateStream(prompt: prompt, config: config) {
                switch event {
                case .text(let chunk):
                    if firstTokenTime == nil {
                        firstTokenTime = CFAbsoluteTimeGetCurrent() - inferenceStart
                    }
                    responseText += chunk
                    tokenCount += 1
                    if tokenCount >= maxDecodeTokens {
                        engine.cancelGeneration()
                        break
                    }
                case .done:
                    break
                case .metrics, .toolCall:
                    continue
                }
            }
        } catch {
            automationLog("[AUTOMATION_FAILURE] Inference run failed: \(error.localizedDescription)")
            return nil
        }
        
        guard let metrics = engine.lastPerformanceMetrics else {
            automationLog("[AUTOMATION_FAILURE] No benchmark metrics captured.")
            return nil
        }
        
        automationLog("[AUTOMATION] Benchmark turn finished. Generated tokens: \(tokenCount)")
        
        return [
            "prefill_tok_s": metrics.promptTokensPerSecond ?? 0.0,
            "decode_tok_s": metrics.tokensPerSecond,
            "ttft_s": metrics.timeToFirstToken ?? firstTokenTime ?? 0.0,
            "init_time_s": 0.0,  // Not available through generic InferenceEngine
            "median_token_latency_ms": viewModel.inferenceMetrics?.medianTokenLatencyMs ?? 0.0,
            "memory_delta_mb": metrics.memoryDeltaMB ?? viewModel.inferenceMetrics?.memoryDeltaMB ?? 0.0
        ]
    }
    
    // MARK: - Safe Exit
    
    /// Marker file path written when automation completes. XCUITests
    /// check for this file instead of relying on accessibility elements
    /// or process exit (both unreliable under XCUITest).
    nonisolated static var completionMarkerPath: String {
        #if os(macOS)
        // macOS: /tmp is globally accessible and shared between the app
        // and XCUITest runner processes. NSTemporaryDirectory() returns
        // per-process paths that differ between the two.
        return "/tmp/automation_complete.txt"
        #else
        // iOS device: /tmp is not writable (sandbox restriction).
        // NSTemporaryDirectory() resolves to the app's sandboxed temp dir.
        return NSTemporaryDirectory() + "automation_complete.txt"
        #endif
    }
    
    /// Static completion code set by the harness when automation finishes.
    nonisolated(unsafe) static var completionCode: Int32? = nil
    
    /// Guards against double-execution (iOS App.init() can fire multiple times).
    nonisolated(unsafe) private static var hasRun = false
    
    /// Signals that automation has finished.
    /// Writes a marker file to disk and sets the static property.
    /// XCUITests poll for the marker file existence.
    ///
    /// When launched via `devicectl --console` (no XCUITest), we call exit() so
    /// the console session returns cleanly. Under XCUITest we do NOT call exit()
    /// because XCUITest detects process termination and relaunches the app
    /// without the original launch arguments.
    nonisolated static func signalComplete(_ code: Int32, message: String = "") {
        fflush(stdout)
        automationLog("[AUTOMATION] Signaling completion with code \(code): \(message)")
        completionCode = code
        // Write marker file with exit code and diagnostic message
        let content = "\(code)\n\(message)"
        try? content.write(toFile: completionMarkerPath, atomically: true, encoding: .utf8)

        // Exit cleanly when NOT under XCUITest (e.g., devicectl --console launch).
        // This allows `devicectl --console` to return naturally with the exit code.
        //
        // Detection: XCTestConfigurationFilePath is only set in the TEST RUNNER process,
        // NOT in the app process launched by XCUITest. So we also check for
        // -RunAutomationHarness in the launch args — XCUITest passes this to signal
        // that the app should stay alive for marker-file-based communication.
        let isUnderXCUITest = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || CommandLine.arguments.contains("-RunAutomationHarness")
        if !isUnderXCUITest {
            fflush(stdout)
            fflush(stderr)
            // Brief delay to ensure stdout is flushed to the console pipe
            Thread.sleep(forTimeInterval: 0.5)
            // Use _exit() instead of exit() to avoid hanging on LiteRT C++ destructor
            // cleanup. exit() runs atexit handlers and C++ static destructors, which
            // try to join() LiteRT's callback_thread_pool. If any GPU callback thread
            // is stuck (DEADLINE_EXCEEDED), exit() hangs indefinitely. _exit() is a
            // POSIX immediate termination — safe because all results are already
            // persisted to disk and stdout has been flushed.
            _exit(code)
        }
    }
    
    // MARK: - Entry Point
    
    static func runIfRequested(viewModel: ConversationViewModel) {
        // Prevent double-execution — on iOS, App.init() can fire multiple times
        guard !hasRun else { return }
        
        let isAllTests = CommandLine.arguments.contains("-RunAllTests")
        let isMatrix = CommandLine.arguments.contains("-RunMatrixBenchmark")
        let isFlowRun = CommandLine.arguments.contains("-RunFlow")
        let isAllFlows = CommandLine.arguments.contains("-RunAllFlows")
        let isListFlows = CommandLine.arguments.contains("-ListFlows")
        let isBenchmarkPipeline = CommandLine.arguments.contains("-RunBenchmarkPipeline")
        let isEvalPipeline = CommandLine.arguments.contains("-RunEvalPipeline")
        let isEvalGated = CommandLine.arguments.contains("-EvalGated")
        let isDryRun = CommandLine.arguments.contains("-DryRun")
        let isValidation = CommandLine.arguments.contains("-RunValidation")
        
        guard isAllTests || isMatrix || isFlowRun || isAllFlows || isListFlows
                || isBenchmarkPipeline || isEvalPipeline || isValidation else { return }
        
        hasRun = true
        automationLog("[AUTOMATION] Developer Automation Harness activated.")
        
        // Apply dry-run mode to flow runner if requested
        if isDryRun {
            AutomationFlowRunner.isDryRun = true
            automationLog("[AUTOMATION] Dry-run mode enabled — UI assertions will be skipped.")
        }
        
        // Handle flow-related commands
        if isListFlows {
            // Wrap in Task so signalComplete fires AFTER App.init() returns.
            // The -ListFlows path previously ran synchronously during App.init(),
            // calling signalComplete(0) → exit(0) before XCUITest could establish
            // its accessibility session. This caused "does not have a process ID"
            // errors because the app exited before XCUITest connected.
            Task {
                let flows = AutomationFlowRunner.discoverFlows()
                automationLog("[AUTOMATION] Available flows (\(flows.count)):")
                for flow in flows {
                    automationLog("[AUTOMATION]   - \(flow)")
                }
                signalComplete(0)
            }
            return
        }
        
        if isFlowRun {
            guard let flowArgIndex = CommandLine.arguments.firstIndex(of: "-RunFlow"),
                  flowArgIndex + 1 < CommandLine.arguments.count else {
                automationLog("[AUTOMATION_FAILURE] -RunFlow requires a flow name argument.")
                automationLog("[AUTOMATION] Usage: -RunFlow <flow_name>")
                automationLog("[AUTOMATION] Available flows: \(AutomationFlowRunner.discoverFlows().joined(separator: ", "))")
                signalComplete(1)
                return
            }
            let flowName = CommandLine.arguments[flowArgIndex + 1]
            Task {
                let result = await AutomationFlowRunner.executeFlow(named: flowName)
                let msg = result.passed
                    ? "Flow '\(flowName)' passed (\(result.stepResults.count) steps)"
                    : "Flow '\(flowName)' failed at step \(result.failedStep ?? -1): \(result.stepResults.last?.message ?? "load error")"
                signalComplete(result.passed ? 0 : 1, message: msg)
            }
            return
        }
        
        if isAllFlows {
            Task {
                let results = await AutomationFlowRunner.executeAllFlows()
                let allPassed = results.allSatisfy(\.passed)
                let failedNames = results.filter { !$0.passed }.map(\.flowName).joined(separator: ", ")
                let msg = allPassed ? "All \(results.count) flows passed" : "Failed flows: \(failedNames)"
                signalComplete(allPassed ? 0 : 1, message: msg)
            }
            return
        }
        
        // MARK: - Validation
        
        if isValidation {
            automationLog("[AUTOMATION] -RunValidation detected. Launching validation harness...")
            // Run validation in a detached task to avoid @MainActor starvation from SwiftUI
            // BenchmarkValidationRunner is @MainActor and never gets scheduled during initial render.
            // Instead, run checks directly on a background thread and write results.
            Task.detached(priority: .userInitiated) {
                
                // Run validation checks inline (bypassing @MainActor BenchmarkValidationRunner)
                var results: [(name: String, passed: Bool, error: String?)] = []
                
                // Check 1: MetricsStore Entry encoding/decoding round-trip
                do {
                    let flags = RuntimeFlags(enableBenchmark: true, enableSpeculativeDecoding: nil, enableConversationConstrainedDecoding: false, visualTokenBudget: nil)
                    let entry = MetricsStore.Entry(
                        timestamp: ISO8601DateFormatter().string(from: Date()),
                        model: "test-model.litertlm", platform: "iOS", device: "TestDevice",
                        metrics: MetricsStore.Entry.Metrics(
                            initTimeSeconds: 1.5, ttftSeconds: 0.3,
                            decodeTokensPerSecond: 42.0, prefillTokensPerSecond: 150.0,
                            lastPrefillTokenCount: 128, lastDecodeTokenCount: 256,
                            thermalStateAtStart: "nominal", thermalStateAtEnd: "nominal",
                            availableMemoryAtStartMB: 4096.0, availableMemoryAtEndMB: 3800.0,
                            medianTokenLatencyMs: 23.5, p95TokenLatencyMs: 35.0,
                            decodeLatenciesMs: [20.0, 23.0, 25.0],
                            latencyHistogram: nil,
                            thermalTransitions: nil,
                            estimatedMemoryBandwidthGBps: nil,
                            modelLoadDurationMs: nil,
                            gpuAllocatedMemoryAtStartMB: nil,
                            gpuAllocatedMemoryAtEndMB: nil
                        ), flags: flags)
                    let data = try JSONEncoder().encode(entry)
                    let decoded = try JSONDecoder().decode(MetricsStore.Entry.self, from: data)
                    guard decoded.model == entry.model else { throw NSError(domain: "", code: 1, userInfo: [NSLocalizedDescriptionKey: "Round-trip mismatch"]) }
                    results.append(("MetricsStore Entry Encoding", true, nil))
                } catch {
                    results.append(("MetricsStore Entry Encoding", false, error.localizedDescription))
                }
                
                // Check 2: DeviceMetrics
                do {
                    let snapshot = DeviceMetrics.captureSnapshot()
                    guard snapshot.availableMemoryMB > 0 else { throw NSError(domain: "", code: 1, userInfo: [NSLocalizedDescriptionKey: "Memory is zero"]) }
                    guard !snapshot.deviceModel.isEmpty else { throw NSError(domain: "", code: 1, userInfo: [NSLocalizedDescriptionKey: "Device model empty"]) }
                    results.append(("DeviceMetrics Non-Zero Values", true, nil))
                } catch {
                    results.append(("DeviceMetrics Non-Zero Values", false, error.localizedDescription))
                }
                
                // Check 3: BuiltInEvalSuites loads
                do {
                    let suites = BuiltInEvalSuites.allBuiltIn
                    guard !suites.isEmpty else { throw NSError(domain: "", code: 1, userInfo: [NSLocalizedDescriptionKey: "No suites"]) }
                    results.append(("BuiltInEvalSuites Loading", true, nil))
                } catch {
                    results.append(("BuiltInEvalSuites Loading", false, error.localizedDescription))
                }
                
                // Persist results
                let passCount = results.filter(\.passed).count
                let failCount = results.filter { !$0.passed }.count
                if let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                    let metricsDir = docsDir.appendingPathComponent("metrics")
                    try? FileManager.default.createDirectory(at: metricsDir, withIntermediateDirectories: true)
                    let outputURL = metricsDir.appendingPathComponent("validation_results.json")
                    let payload: [String: Any] = [
                        "timestamp": ISO8601DateFormatter().string(from: Date()),
                        "platform": "iOS",
                        "passed": passCount,
                        "failed": failCount,
                        "results": results.map { ["name": $0.name, "passed": $0.passed, "error": $0.error ?? ""] }
                    ]
                    if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) {
                        try? data.write(to: outputURL)
                    }

                }
                
                signalComplete(failCount == 0 ? 0 : 1, message: "\(passCount) passed, \(failCount) failed")
            }
            return
        }
        
        // MARK: - Benchmark Pipeline
        
        if isBenchmarkPipeline {
            // Delay pipeline start to avoid @MainActor starvation during SwiftUI initial render
            DispatchQueue.global().asyncAfter(deadline: .now() + 2.0) {
                Task { @MainActor in
                    await BenchmarkAutomationPipeline.run(viewModel: viewModel, isDryRun: isDryRun)
                }
            }
            return
        }
        
        // MARK: - Eval Pipeline
        
        if isEvalPipeline {
            // Delay pipeline start to avoid @MainActor starvation during SwiftUI initial render
            DispatchQueue.global().asyncAfter(deadline: .now() + 2.0) {
                Task { @MainActor in
                    await EvalAutomationPipeline.run(viewModel: viewModel, isDryRun: isDryRun, isGated: isEvalGated)
                }
            }
            return
        }
        
        Task {
            let docs = GalleryModelDiscovery.getAppModelsDirectory()
            
            if isAllTests {
                // Single Clean-Slate Run
                automationLog("[AUTOMATION] -RunAllTests detected. Wiping all local models from Documents...")
                wipeLocalModels(docs: docs, viewModel: viewModel)
                
                let targetModel = ModelRegistry.gemma4E2BStandard
                await ensureModelDownloaded(model: targetModel, docs: docs, viewModel: viewModel)
                
                let targetURL = docs.appendingPathComponent(targetModel.modelFile)
                automationLog("[AUTOMATION] Loading model \(targetModel.modelFile) on GPU...")
                
                let flags = RuntimeFlags(enableBenchmark: true, enableSpeculativeDecoding: nil, enableConversationConstrainedDecoding: false, visualTokenBudget: nil)
                let sampler = safeSamplerConfig(topK: 1, topP: 1.0, temperature: 1.0)
                
                let cachesDir = safeCachesDirectory().appendingPathComponent(targetModel.modelFile)
                try? FileManager.default.createDirectory(at: cachesDir, withIntermediateDirectories: true)
                
                do {
                    guard let liteRTAdapter = viewModel.engine as? LiteRTEngineAdapter else {
                        automationLog("[AUTOMATION_FAILURE] Automation harness requires LiteRT engine")
                        exit(1)
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
                    exit(1)
                }
                
                if let metrics = await runSingleBenchmark(viewModel: viewModel, prompt: benchmarkPrompt) {
                    automationLog("[AUTOMATION_SUCCESS] Benchmark completed successfully.")
                    printReport(metrics: metrics, model: targetModel.modelFile, configLabel: "GPU / No MTP / Greedy")
                    exit(0)
                } else {
                    exit(1)
                }
                
            } else if isMatrix {
                // Multi-Configuration settings matrix
                automationLog("[AUTOMATION] -RunMatrixBenchmark detected.")
                
                // Determine if we should only run a specific configuration (1-indexed)
                var configIndexToRun: Int? = nil
                for i in 1...10 {
                    if CommandLine.arguments.contains(String(i)) {
                        configIndexToRun = i
                        automationLog("[AUTOMATION] Targeting Configuration \(i) only.")
                        break
                    }
                }
                
                struct Config {
                    let label: String
                    let model: ModelMetadata
                    let useGPU: Bool
                    let enableMTP: Bool
                    let sampler: SamplerConfig
                }
                
                let greedy = safeSamplerConfig(topK: 1, topP: 1.0, temperature: 1.0)
                let sampling = safeSamplerConfig(topK: 64, topP: 0.95, temperature: 1.0)
                
                let matrix = [
                    Config(label: "Standard Model / GPU / No MTP / Greedy", model: ModelRegistry.gemma4E2BStandard, useGPU: true, enableMTP: false, sampler: greedy),
                    Config(label: "Standard Model / GPU / MTP / Greedy", model: ModelRegistry.gemma4E2BStandard, useGPU: true, enableMTP: true, sampler: greedy),
                    Config(label: "Standard Model / CPU / No MTP / Greedy", model: ModelRegistry.gemma4E2BStandard, useGPU: false, enableMTP: false, sampler: greedy),
                    Config(label: "Standard Model / GPU / No MTP / Sampling (topK=64)", model: ModelRegistry.gemma4E2BStandard, useGPU: true, enableMTP: false, sampler: sampling),
                    Config(label: "E4B Web Model / GPU / No MTP / Greedy", model: ModelRegistry.gemma4E4BWeb, useGPU: true, enableMTP: false, sampler: greedy),
                    Config(label: "E4B Web Model / GPU / MTP / Greedy", model: ModelRegistry.gemma4E4BWeb, useGPU: true, enableMTP: true, sampler: greedy),
                    Config(label: "E4B Web Model / GPU / No MTP / Sampling (topK=64)", model: ModelRegistry.gemma4E4BWeb, useGPU: true, enableMTP: false, sampler: sampling),
                    Config(label: "E4B Standard Model / CPU / No MTP / Greedy", model: ModelRegistry.gemma4E4BStandard, useGPU: false, enableMTP: false, sampler: greedy),
                    Config(label: "12B Model / GPU / No MTP / Greedy", model: ModelRegistry.gemma4_12B, useGPU: true, enableMTP: false, sampler: greedy),
                    Config(label: "12B Model / GPU / MTP / Greedy", model: ModelRegistry.gemma4_12B, useGPU: true, enableMTP: true, sampler: greedy)
                ]
                
                // Ensure required model is available
                if let target = configIndexToRun, target >= 1 && target <= matrix.count {
                    await ensureModelDownloaded(model: matrix[target - 1].model, docs: docs, viewModel: viewModel)
                } else {
                    for cfg in matrix {
                        await ensureModelDownloaded(model: cfg.model, docs: docs, viewModel: viewModel)
                    }
                }
                
                var results: [[String: Any]] = []
                
                for (index, cfg) in matrix.enumerated() {
                    if let target = configIndexToRun, index + 1 != target {
                        continue
                    }
                    
                    print("\n════════════════════════════════════════════════")
                    print("⚙️  RUNNING CONFIG \(index + 1)/\(matrix.count): \(cfg.label)")
                    print("════════════════════════════════════════════════")
                    
                    await waitAndCoolDownIfNeeded()
                    
                    let thermal = DeviceMetrics.currentThermalLevel
                    automationLog("[AUTOMATION] Start Thermal State: \(thermal.label)")
                    
                    let targetURL = docs.appendingPathComponent(cfg.model.modelFile)
                    let flags = RuntimeFlags(
                        enableBenchmark: true,
                        enableSpeculativeDecoding: cfg.enableMTP ? true : nil,
                        enableConversationConstrainedDecoding: false,
                        visualTokenBudget: nil
                    )
                    
                    viewModel.engine.shutdown()
                    
                    let cachesDir = safeCachesDirectory().appendingPathComponent(cfg.model.modelFile)
                    try? FileManager.default.createDirectory(at: cachesDir, withIntermediateDirectories: true)
                    
                    do {
                        guard let liteRTAdapter = viewModel.engine as? LiteRTEngineAdapter else {
                            automationLog("[AUTOMATION] Skipping config: No LiteRT engine")
                            continue
                        }
                        try await liteRTAdapter.initializeLiteRT(
                            modelPath: targetURL.path,
                            useGPU: cfg.useGPU,
                            cacheDir: cachesDir.path,
                            flags: flags.toLiteRTFlags(),
                            samplerConfig: cfg.sampler
                        )
                    } catch {
                        automationLog("[AUTOMATION] Skipping config: Initialization failed: \(error.localizedDescription)")
                        viewModel.engine.shutdown()
                        continue
                    }
                    
                    if let metrics = await runSingleBenchmark(viewModel: viewModel, prompt: benchmarkPrompt) {
                        var report = metrics
                        report["config"] = cfg.label
                        report["model"] = cfg.model.modelFile
                        report["thermal_start"] = thermal.label
                        report["thermal_end"] = DeviceMetrics.currentThermalLevel.label
                        results.append(report)
                    }
                    
                    if configIndexToRun == nil {
                         viewModel.engine.shutdown()
                    }
                }
                
                // Print Aggregated Results JSON
                if let jsonData = try? JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys]),
                   let jsonString = String(data: jsonData, encoding: .utf8) {
                    automationLog("\n[AUTOMATION_RESULTS_JSON]")
                    print(jsonString)
                    automationLog("[AUTOMATION_RESULTS_END]\n")
                }
                
                exit(0)
            }
        }
    }
    
    // MARK: - Helpers
    
    static func safeSamplerConfig(topK: Int, topP: Float, temperature: Float) -> SamplerConfig {
        do {
            return try SamplerConfig(topK: topK, topP: topP, temperature: temperature)
        } catch {
            automationLog("[AUTOMATION_FAILURE] Invalid SamplerConfig parameters. Falling back to greedy.")
            // Hardcoded valid greedy parameters — if this throws, the SDK contract is broken.
            guard let fallback = try? SamplerConfig(topK: 1, topP: 1.0, temperature: 1.0) else {
                fatalError("Hardcoded greedy SamplerConfig(topK: 1, topP: 1.0, temperature: 1.0) threw — SDK contract violation")
            }
            return fallback
        }
    }
    
    static func safeCachesDirectory() -> URL {
        guard let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            automationLog("[AUTOMATION_FAILURE] Could not resolve caches directory.")
            exit(1)
        }
        return url
    }
    
    static func waitAndCoolDownIfNeeded() async {
        automationLog("[AUTOMATION] Checking thermal state before benchmark...")
        let maxRetries = 12 // up to 60 seconds (12 * 5s)
        var retries = 0
        while retries < maxRetries {
            let state = DeviceMetrics.currentThermalLevel
            if state == .nominal || state == .fair {
                automationLog("[AUTOMATION] Thermal state is \(state.label). Proceeding.")
                return
            }
            automationLog("[AUTOMATION] Thermal state is \(state.label). Cooling down for 5 seconds...")
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            retries += 1
        }
        automationLog("[AUTOMATION] Timeout waiting for thermals. Proceeding with state: \(DeviceMetrics.currentThermalLevel.label)")
    }
    
    private static func wipeLocalModels(docs: URL, viewModel: ConversationViewModel) {
        do {
            let files = try FileManager.default.contentsOfDirectory(at: docs, includingPropertiesForKeys: nil)
            for file in files where file.pathExtension == "litertlm" {
                try FileManager.default.removeItem(at: file)
                automationLog("[AUTOMATION] Removed: \(file.lastPathComponent)")
            }
            viewModel.refreshDiscoveredModels()
            viewModel.downloadManager.refreshStates()
            automationLog("[AUTOMATION] Local models wiped. Discovered count: \(viewModel.discoveredModels.count)")
        } catch {
            automationLog("[AUTOMATION_FAILURE] Failed to wipe models: \(error.localizedDescription)")
            exit(1)
        }
    }
    
    static func ensureModelDownloaded(model: ModelMetadata, docs: URL, viewModel: ConversationViewModel) async {
        let state = viewModel.downloadManager.checkState(for: model)
        if case .downloaded = state {
            automationLog("[AUTOMATION] \(model.modelFile) is already downloaded.")
            return
        }
        
        automationLog("[AUTOMATION] Downloading \(model.modelFile) directly to iPhone...")
        viewModel.downloadManager.download(model)
        
        var completed = false
        var lastLoggedProgress = -1
        
        while !completed {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            let s = viewModel.downloadManager.checkState(for: model)
            switch s {
            case .downloading(let progress):
                let pct = Int(progress * 100)
                if pct != lastLoggedProgress {
                    automationLog("[AUTOMATION] Download progress (\(model.modelFile)): \(pct)%")
                    lastLoggedProgress = pct
                }
            case .downloadingDirectory(let progress, let completed, let total):
                let pct = Int(progress * 100)
                if pct != lastLoggedProgress {
                    automationLog("[AUTOMATION] Download progress (\(model.modelFile)): \(pct)% [\(completed)/\(total) files]")
                    lastLoggedProgress = pct
                }
            case .downloaded:
                automationLog("[AUTOMATION] \(model.modelFile) downloaded successfully.")
                completed = true
            case .failed(let msg):
                automationLog("[AUTOMATION_FAILURE] Failed to download \(model.modelFile): \(msg)")
                exit(1)
            case .authRequired:
                automationLog("[AUTOMATION_FAILURE] HF Auth required for \(model.modelFile)")
                exit(1)
            case .notDownloaded:
                break
            case .queued(let position):
                automationLog("[AUTOMATION] \(model.modelFile) queued at position \(position)")
            case .paused:
                automationLog("[AUTOMATION] \(model.modelFile) paused — resuming...")
                viewModel.downloadManager.resumeDownload(model)
            case .pausedDirectory:
                automationLog("[AUTOMATION] \(model.modelFile) directory download paused")
            }
        }
    }
    
    static func printReport(metrics: [String: Any], model: String, configLabel: String) {
        let report: [String: Any] = [
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "model": model,
            "config": configLabel,
            "prefill_tok_s": metrics["prefill_tok_s"] ?? 0.0,
            "decode_tok_s": metrics["decode_tok_s"] ?? 0.0,
            "ttft_s": metrics["ttft_s"] ?? 0.0,
            "init_time_s": metrics["init_time_s"] ?? 0.0,
            "median_token_latency_ms": metrics["median_token_latency_ms"] ?? 0.0,
            "memory_delta_mb": metrics["memory_delta_mb"] ?? 0.0
        ]
        
        if let jsonData = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            automationLog("\n[AUTOMATION_RESULTS_JSON]")
            print(jsonString)
            automationLog("[AUTOMATION_RESULTS_END]\n")
        }
    }
}

