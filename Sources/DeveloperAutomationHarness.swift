import Foundation
import SwiftUI
import LiteRTLM

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
        print("[AUTOMATION] Resetting conversation...")
        do {
            try await viewModel.engine.resetConversation()
        } catch {
            print("[AUTOMATION_FAILURE] Failed to reset conversation: \(error.localizedDescription)")
            return nil
        }
        
        print("[AUTOMATION] Running warmup turn (priming counters)...")
        do {
            try await viewModel.engine.warmup()
        } catch {
            print("[AUTOMATION] Warmup warning: \(error.localizedDescription)")
        }
        
        print("[AUTOMATION] Running benchmark turn (decodes capped at \(maxDecodeTokens))...")
        let inferenceStart = CFAbsoluteTimeGetCurrent()
        var tokenCount = 0
        var responseText = ""
        var firstTokenTime: Double? = nil
        
        do {
            for try await chunk in viewModel.engine.sendMessageStream(prompt) {
                if firstTokenTime == nil {
                    firstTokenTime = CFAbsoluteTimeGetCurrent() - inferenceStart
                }
                responseText += chunk
                tokenCount += 1
                if tokenCount >= maxDecodeTokens {
                    break
                }
            }
        } catch {
            print("[AUTOMATION_FAILURE] Inference run failed: \(error.localizedDescription)")
            return nil
        }
        
        guard let info = viewModel.engine.lastBenchmarkInfo else {
            print("[AUTOMATION_FAILURE] No benchmark metrics captured.")
            return nil
        }
        
        print("[AUTOMATION] Benchmark turn finished. Generated tokens: \(tokenCount)")
        
        return [
            "prefill_tok_s": info.lastPrefillTokensPerSecond,
            "decode_tok_s": info.lastDecodeTokensPerSecond,
            "ttft_s": info.timeToFirstTokenInSecond,
            "init_time_s": info.initTimeInSecond,
            "median_token_latency_ms": viewModel.inferenceMetrics?.medianTokenLatencyMs ?? 0.0,
            "memory_delta_mb": viewModel.inferenceMetrics?.memoryDeltaMB ?? 0.0
        ]
    }
    
    // MARK: - Entry Point
    
    static func runIfRequested(viewModel: ConversationViewModel) {
        let isAllTests = CommandLine.arguments.contains("-RunAllTests")
        let isMatrix = CommandLine.arguments.contains("-RunMatrixBenchmark")
        
        guard isAllTests || isMatrix else { return }
        
        print("[AUTOMATION] Developer Automation Harness activated.")
        
        Task {
            let docs = GalleryModelDiscovery.getAppModelsDirectory()
            
            if isAllTests {
                // Single Clean-Slate Run
                print("[AUTOMATION] -RunAllTests detected. Wiping all local models from Documents...")
                wipeLocalModels(docs: docs, viewModel: viewModel)
                
                let targetModel = ModelRegistry.gemma4E2BStandard
                await ensureModelDownloaded(model: targetModel, docs: docs, viewModel: viewModel)
                
                let targetURL = docs.appendingPathComponent(targetModel.modelFile)
                print("[AUTOMATION] Loading model \(targetModel.modelFile) on GPU...")
                
                let flags = ExperimentalFlagsState(enableBenchmark: true, enableSpeculativeDecoding: nil, enableConversationConstrainedDecoding: false, visualTokenBudget: nil)
                let sampler = try! SamplerConfig(topK: 1, topP: 1.0, temperature: 1.0)
                
                let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
                    .appendingPathComponent(targetModel.modelFile)
                try? FileManager.default.createDirectory(at: cachesDir, withIntermediateDirectories: true)
                
                do {
                    try await viewModel.engine.initialize(
                        modelPath: targetURL.path,
                        useGPU: true,
                        cacheDir: cachesDir.path,
                        flags: flags,
                        samplerConfig: sampler
                    )
                } catch {
                    print("[AUTOMATION_FAILURE] Failed to initialize engine: \(error.localizedDescription)")
                    exit(1)
                }
                
                if let metrics = await runSingleBenchmark(viewModel: viewModel, prompt: benchmarkPrompt) {
                    print("[AUTOMATION_SUCCESS] Benchmark completed successfully.")
                    printReport(metrics: metrics, model: targetModel.modelFile, configLabel: "GPU / No MTP / Greedy")
                    exit(0)
                } else {
                    exit(1)
                }
                
            } else if isMatrix {
                // Multi-Configuration settings matrix
                print("[AUTOMATION] -RunMatrixBenchmark detected.")
                
                // Determine if we should only run a specific configuration (1-indexed)
                var configIndexToRun: Int? = nil
                for i in 1...10 {
                    if CommandLine.arguments.contains(String(i)) {
                        configIndexToRun = i
                        print("[AUTOMATION] Targeting Configuration \(i) only.")
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
                
                let greedy = try! SamplerConfig(topK: 1, topP: 1.0, temperature: 1.0)
                let sampling = try! SamplerConfig(topK: 64, topP: 0.95, temperature: 1.0)
                
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
                    
                    // 10s Cooldown to protect thermals
                    print("[AUTOMATION] Cooling down SoC for 10 seconds...")
                    try? await Task.sleep(nanoseconds: 10_000_000_000)
                    
                    let thermal = DeviceMetrics.currentThermalLevel
                    print("[AUTOMATION] Start Thermal State: \(thermal.label)")
                    
                    let targetURL = docs.appendingPathComponent(cfg.model.modelFile)
                    let flags = ExperimentalFlagsState(
                        enableBenchmark: true,
                        enableSpeculativeDecoding: cfg.enableMTP ? true : nil,
                        enableConversationConstrainedDecoding: false,
                        visualTokenBudget: nil
                    )
                    
                    await viewModel.engine.shutdown()
                    
                    let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
                        .appendingPathComponent(cfg.model.modelFile)
                    try? FileManager.default.createDirectory(at: cachesDir, withIntermediateDirectories: true)
                    
                    do {
                        try await viewModel.engine.initialize(
                            modelPath: targetURL.path,
                            useGPU: cfg.useGPU,
                            cacheDir: cachesDir.path,
                            flags: flags,
                            samplerConfig: cfg.sampler
                        )
                    } catch {
                        print("[AUTOMATION] Skipping config: Initialization failed: \(error.localizedDescription)")
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
                        await viewModel.engine.shutdown()
                    }
                }
                
                // Print Aggregated Results JSON
                if let jsonData = try? JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys]),
                   let jsonString = String(data: jsonData, encoding: .utf8) {
                    print("\n[AUTOMATION_RESULTS_JSON]")
                    print(jsonString)
                    print("[AUTOMATION_RESULTS_END]\n")
                }
                
                exit(0)
            }
        }
    }
    
    // MARK: - Helpers
    
    private static func wipeLocalModels(docs: URL, viewModel: ConversationViewModel) {
        do {
            let files = try FileManager.default.contentsOfDirectory(at: docs, includingPropertiesForKeys: nil)
            for file in files where file.pathExtension == "litertlm" {
                try FileManager.default.removeItem(at: file)
                print("[AUTOMATION] Removed: \(file.lastPathComponent)")
            }
            viewModel.refreshDiscoveredModels()
            viewModel.downloadManager.refreshStates()
            print("[AUTOMATION] Local models wiped. Discovered count: \(viewModel.discoveredModels.count)")
        } catch {
            print("[AUTOMATION_FAILURE] Failed to wipe models: \(error.localizedDescription)")
            exit(1)
        }
    }
    
    private static func ensureModelDownloaded(model: ModelMetadata, docs: URL, viewModel: ConversationViewModel) async {
        let state = viewModel.downloadManager.checkState(for: model)
        if case .downloaded = state {
            print("[AUTOMATION] \(model.modelFile) is already downloaded.")
            return
        }
        
        print("[AUTOMATION] Downloading \(model.modelFile) directly to iPhone...")
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
                    print("[AUTOMATION] Download progress (\(model.modelFile)): \(pct)%")
                    lastLoggedProgress = pct
                }
            case .downloaded:
                print("[AUTOMATION] \(model.modelFile) downloaded successfully.")
                completed = true
            case .failed(let msg):
                print("[AUTOMATION_FAILURE] Failed to download \(model.modelFile): \(msg)")
                exit(1)
            case .authRequired:
                print("[AUTOMATION_FAILURE] HF Auth required for \(model.modelFile)")
                exit(1)
            case .notDownloaded:
                break
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
            print("\n[AUTOMATION_RESULTS_JSON]")
            print(jsonString)
            print("[AUTOMATION_RESULTS_END]\n")
        }
    }
}
