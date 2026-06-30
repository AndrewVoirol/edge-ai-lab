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
import LiteRTLM
import os

// NOTE: This file uses print() for structured stdout output AND os.Logger
// for the unified logging system. On macOS, stdout is captured by automation
// scripts. On iOS, os_log is readable via `log stream` or `idevicesyslog`
// without the memory overhead of `--console` mode (which causes Jetsam kills).
// The automationLog() helper writes to both channels.

private let automationLogger = Logger(subsystem: "com.andrewvoirol.EdgeAILab", category: "automation")

/// Writes a message to both stdout (for macOS script parsing) and os_log
/// (for iOS device log capture without --console).
private func automationLog(_ message: String) {
    print(message)
    automationLogger.notice("\(message, privacy: .public)")
}

@MainActor
struct DeveloperAutomationHarness {
    
    private static let benchmarkPrompt = """
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
    
    private static func runSingleBenchmark(
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
                    await runBenchmarkPipeline(viewModel: viewModel, isDryRun: isDryRun)
                }
            }
            return
        }
        
        // MARK: - Eval Pipeline
        
        if isEvalPipeline {
            // Delay pipeline start to avoid @MainActor starvation during SwiftUI initial render
            DispatchQueue.global().asyncAfter(deadline: .now() + 2.0) {
                Task { @MainActor in
                    await runEvalPipeline(viewModel: viewModel, isDryRun: isDryRun, isGated: isEvalGated)
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
                    guard let liteRTEngine = (viewModel.engine as? LiteRTEngineAdapter)?.wrappedEngine else {
                        automationLog("[AUTOMATION_FAILURE] Automation harness requires LiteRT engine")
                        exit(1)
                    }
                    try await liteRTEngine.initialize(
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
                        guard let liteRTEngine = (viewModel.engine as? LiteRTEngineAdapter)?.wrappedEngine else {
                            automationLog("[AUTOMATION] Skipping config: No LiteRT engine")
                            continue
                        }
                        try await liteRTEngine.initialize(
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
    
    private static func ensureModelDownloaded(model: ModelMetadata, docs: URL, viewModel: ConversationViewModel) async {
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
    
    private static func printReport(metrics: [String: Any], model: String, configLabel: String) {
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
    
    // MARK: - Benchmark Pipeline
    
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
    private static func runBenchmarkPipeline(viewModel: ConversationViewModel, isDryRun: Bool) async {
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
                signalComplete(1, message: "Failed to parse baselines")
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
            signalComplete(0, message: "Benchmark pipeline dry-run completed")
            return
        }
        
        // Step 3: Ensure model is available (downloads if needed)
        automationLog("[AUTOMATION] Step 3: Ensuring model is available...")
        let targetModel = ModelRegistry.gemma4E2BStandard
        await ensureModelDownloaded(model: targetModel, docs: docs, viewModel: viewModel)
        
        // Re-scan after download
        let postDownloadFiles = (try? FileManager.default.contentsOfDirectory(at: docs, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension == "litertlm" } ?? []
        automationLog("[AUTOMATION]   Models after download: \(postDownloadFiles.count)")
        
        guard !postDownloadFiles.isEmpty else {
            automationLog("[AUTOMATION_FAILURE] No models available after download attempt. Model may have failed to download.")
            clearBenchmarkState()
            signalComplete(1, message: "No models available after download attempt")
            return
        }
        
        let configId = "\(targetModel.modelFile)_gpu_greedy"
        
        // Skip if this config was already processed (crash recovery)
        if processedConfigs.contains(configId) {
            automationLog("[AUTOMATION] Skipping already-processed config: \(configId)")
        } else {
            // Persist active config before starting (crash recovery breadcrumb)
            defaults.set(configId, forKey: kActiveConfigKey)
            
            let targetURL = docs.appendingPathComponent(targetModel.modelFile)
            let flags = RuntimeFlags(enableBenchmark: true, enableSpeculativeDecoding: nil, enableConversationConstrainedDecoding: false, visualTokenBudget: nil)
            let sampler = safeSamplerConfig(topK: 1, topP: 1.0, temperature: 1.0)
            let cachesDir = safeCachesDirectory().appendingPathComponent(targetModel.modelFile)
            try? FileManager.default.createDirectory(at: cachesDir, withIntermediateDirectories: true)
            
            do {
                guard let liteRTEngine = (viewModel.engine as? LiteRTEngineAdapter)?.wrappedEngine else {
                    automationLog("[AUTOMATION_FAILURE] Automation harness requires LiteRT engine")
                    clearBenchmarkState()
                    signalComplete(1, message: "No LiteRT engine")
                    return
                }
                try await liteRTEngine.initialize(
                    modelPath: targetURL.path,
                    useGPU: true,
                    cacheDir: cachesDir.path,
                    flags: flags.toLiteRTFlags(),
                    samplerConfig: sampler
                )
            } catch {
                automationLog("[AUTOMATION_FAILURE] Failed to initialize engine: \(error.localizedDescription)")
                clearBenchmarkState()
                signalComplete(1, message: "Failed to initialize engine for benchmark")
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
            
            if let metrics = await runSingleBenchmark(viewModel: viewModel, prompt: benchmarkPrompt) {
                automationLog("[AUTOMATION_SUCCESS] Benchmark completed.")
                printReport(metrics: metrics, model: targetModel.modelFile, configLabel: "GPU / No MTP / Greedy")
                
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
                        var doubleMetrics: [String: Double] = [:]
                        for (key, value) in metrics {
                            if let d = value as? Double {
                                doubleMetrics[key] = d
                            }
                        }
                        
                        // Find matching baseline by model name and backend
                        let matchingBaselines = baselines.baselines.filter {
                            $0.model == targetModel.modelFile && $0.backend == "gpu"
                        }
                        
                        guard let baseline = matchingBaselines.first else {
                            automationLog("[AUTOMATION] No matching baseline found for \(targetModel.modelFile) / gpu")
                            clearBenchmarkState()
                            signalComplete(0, message: "No matching baseline found, skipping regression check")
                            return
                        }
                        
                        let results = BenchmarkRegressionChecker.checkRegression(
                            results: doubleMetrics,
                            baseline: baseline,
                            rules: baselines.regressionRules
                        )
                        
                        let criticalRegressions = results.filter { $0.isRegression && $0.severity == .critical }
                        
                        automationLog("\n[AUTOMATION_BENCHMARK_REGRESSION]")
                        for result in results {
                            let icon = result.isRegression ? "❌" : (result.deviationPct > 0 ? "🎉" : "✅")
                            automationLog("[AUTOMATION]   \(icon) \(result.metricKey): \(result.status) (\(String(format: "%.1f", result.deviationPct))% vs baseline)")
                        }
                        
                        if !criticalRegressions.isEmpty {
                            automationLog("[AUTOMATION_FAILURE] \(criticalRegressions.count) critical regression(s) detected")
                            clearBenchmarkState()
                            signalComplete(1, message: "Critical benchmark regression(s) detected")
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
                signalComplete(1, message: "Benchmark run failed")
                return
            }
        }
        
        // Pipeline complete — clear all benchmark state keys
        clearBenchmarkState()
        signalComplete(0, message: "Benchmark pipeline completed successfully")
        return
    }
    
    // MARK: - Eval Pipeline
    
    /// Runs the eval pipeline: load built-in suites, run against discovered models, report scores.
    ///
    /// In dry-run mode, validates the pipeline plumbing without requiring a model:
    /// - Verifies all built-in eval suites load correctly
    /// - Verifies suite prompts have valid scoring methods
    /// - Verifies eval store can be created
    private static func runEvalPipeline(viewModel: ConversationViewModel, isDryRun: Bool, isGated: Bool = false) async {
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
            signalComplete(1, message: "Eval suite validation failed")
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
            signalComplete(0, message: "Eval pipeline dry-run completed")
            return
        }
        
        // Real mode: ensure model is available (downloads if needed — tests real user download flow)
        automationLog("[AUTOMATION] Step 4: Ensuring model is available...")
        let targetModel = ModelRegistry.gemma4E2BStandard
        await ensureModelDownloaded(model: targetModel, docs: docs, viewModel: viewModel)
        
        // Re-scan after download
        let postDownloadFiles = (try? FileManager.default.contentsOfDirectory(at: docs, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension == "litertlm" } ?? []
        automationLog("[AUTOMATION]   Models after download: \(postDownloadFiles.count)")
        
        guard !postDownloadFiles.isEmpty else {
            automationLog("[AUTOMATION_FAILURE] No models available after download attempt. Model may have failed to download.")
            signalComplete(1, message: "No models available for eval after download attempt")
            return
        }
        
        automationLog("[AUTOMATION] Step 5: Running eval suites...")
        let evalDir = docs.appendingPathComponent("eval_results")
        try? FileManager.default.createDirectory(at: evalDir, withIntermediateDirectories: true)
        let evalStore = EvalStore(storageDirectory: evalDir)
        guard let liteRTAdapter = viewModel.engine as? LiteRTEngineAdapter else {
            automationLog("[AUTOMATION_FAILURE] Automation harness requires LiteRT engine")
            signalComplete(1, message: "No LiteRT engine")
            return
        }
        let evalRunner = EvalRunner(engine: liteRTAdapter, store: evalStore)
        
        let targetURL = docs.appendingPathComponent(targetModel.modelFile)
        let flags = RuntimeFlags(enableBenchmark: true, enableSpeculativeDecoding: nil, enableConversationConstrainedDecoding: false, visualTokenBudget: nil)
        let sampler = safeSamplerConfig(topK: 1, topP: 1.0, temperature: 1.0)
        let cachesDir = safeCachesDirectory().appendingPathComponent(targetModel.modelFile)
        try? FileManager.default.createDirectory(at: cachesDir, withIntermediateDirectories: true)
        
        do {
            guard let liteRTEngine = (viewModel.engine as? LiteRTEngineAdapter)?.wrappedEngine else {
                automationLog("[AUTOMATION_FAILURE] Automation harness requires LiteRT engine")
                signalComplete(1, message: "No LiteRT engine")
                return
            }
            try await liteRTEngine.initialize(
                modelPath: targetURL.path,
                useGPU: true,
                cacheDir: cachesDir.path,
                flags: flags.toLiteRTFlags(),
                samplerConfig: sampler
            )
        } catch {
            automationLog("[AUTOMATION_FAILURE] Failed to initialize engine: \(error.localizedDescription)")
            signalComplete(1, message: "Failed to initialize engine for eval")
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
                let passRate = totalResults.isEmpty ? 0.0 : Double(passed) / Double(totalResults.count)
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
            if result.passRate < 0 {
                // Skipped suite
                automationLog("[AUTOMATION]   ⏭️ \(result.suiteName): SKIPPED")
                evalReport.append([
                    "suite": result.suiteName,
                    "pass_rate": NSNull(),
                    "status": "skipped",
                    "model": targetModel.modelFile
                ])
            } else {
                let icon = result.passRate >= 0.7 ? "✅" : (result.passRate >= 0.4 ? "⚠️" : "❌")
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
                
                if isGated && (!criticalRegressions.isEmpty || !floorViolations.isEmpty) {
                    let issueCount = criticalRegressions.count + floorViolations.count
                    automationLog("[AUTOMATION_FAILURE] \(issueCount) critical eval regression(s) detected — CI gate FAILED")
                    signalComplete(1, message: "Critical eval regression(s) detected, CI gate failed")
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
        signalComplete(0, message: "Eval pipeline completed successfully")
        
        // Best-effort engine cleanup (only reached under XCUITest).
        viewModel.engine.shutdown()
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
                if result.passRate < 0 {
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
