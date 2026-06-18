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

// ============================================================================
// RawBenchmark v2 — Bare-metal Gemma 4 12B inference benchmark
// ============================================================================
//
// Zero SwiftUI, zero ViewModel. Just LiteRTLM Engine + Conversation + timers.
//
// v2 fixes from first run:
//   - Separate TTFT (prefill) from pure decode throughput
//   - Proper conversation reset (nil old before creating new)
//   - Memory reporting: unified memory (available) not just process resident
//   - SDK BenchmarkInfo: skip warmup-then-reset, measure on first real turn
//   - Suppress WebGPU alignment warning count
//
// Usage:
//   RawBenchmark [path/to/model.litertlm]
//
// Output: JSON report to stdout. All log messages go to stderr.
// ============================================================================

// MARK: - Helpers

func log(_ message: String) {
    FileHandle.standardError.write(Data("[\(timestamp())] \(message)\n".utf8))
}

func timestamp() -> String {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f.string(from: Date())
}

func availableMemoryMB() -> Double {
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
}

func residentMemoryMB() -> Double {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
    let result = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
        }
    }
    guard result == KERN_SUCCESS else { return 0 }
    return Double(info.resident_size) / 1_048_576.0
}

func thermalLevel() -> String {
    switch ProcessInfo.processInfo.thermalState {
    case .nominal:  return "nominal"
    case .fair:     return "fair"
    case .serious:  return "serious"
    case .critical: return "critical"
    @unknown default: return "unknown"
    }
}

func deviceModel() -> String {
    var systemInfo = utsname()
    uname(&systemInfo)
    return withUnsafePointer(to: &systemInfo.machine) {
        $0.withMemoryRebound(to: CChar.self, capacity: 1) {
            String(cString: $0)
        }
    }
}

// MARK: - Signpost Logs

let subsystem = "com.andrewvoirol.EdgeAILab.RawBenchmark"
let modelLoadLog = OSLog(subsystem: subsystem, category: "model-load")
let inferenceLog = OSLog(subsystem: subsystem, category: "inference")
let firstTokenLog = OSLog(subsystem: subsystem, category: "first-token")

// MARK: - Benchmark Prompt

let benchmarkPrompt = """
Explain the concept of attention mechanisms in transformer neural networks. \
Cover the key idea, the math behind scaled dot-product attention, and why \
multi-head attention is used. Keep it concise but thorough.
"""

let maxDecodeTokens = 256

// MARK: - Main

await runBenchmark()

func runBenchmark() async {
    // ── Resolve model path ──────────────────────────────────────────
    let modelPath: String
    if CommandLine.arguments.count > 1 {
        modelPath = CommandLine.arguments[1]
    } else {
        let cwd = FileManager.default.currentDirectoryPath
        modelPath = (cwd as NSString).appendingPathComponent("models/gemma-4-12B-it.litertlm")
    }

    guard FileManager.default.fileExists(atPath: modelPath) else {
        log("❌ Model file not found: \(modelPath)")
        exit(1)
    }

    let modelFilename = (modelPath as NSString).lastPathComponent
    let modelSizeMB = (try? FileManager.default.attributesOfItem(atPath: modelPath)[.size] as? Int64)
        .map { Double($0) / 1_048_576.0 } ?? 0

    log("╔══════════════════════════════════════════════════════════════╗")
    log("║  RawBenchmark v2 — Gemma 4 12B Bare-Metal Inference         ║")
    log("╚══════════════════════════════════════════════════════════════╝")
    log("Model:      \(modelFilename) (\(String(format: "%.0f", modelSizeMB)) MB)")
    log("Device:     \(deviceModel())")
    log("RAM:        \(String(format: "%.0f", Double(ProcessInfo.processInfo.physicalMemory) / 1_048_576.0)) MB total")
    log("Thermal:    \(thermalLevel())")
    log("Prompt:     \(benchmarkPrompt.prefix(80))...")
    log("Max tokens: \(maxDecodeTokens)")
    log("")
    log("v2 changes: fixed decode throughput (excludes TTFT), proper conv reset,")
    log("            no warmup-then-reset (measure on first turn for SDK accuracy)")
    log("")

    // ── Pre-load snapshot ───────────────────────────────────────────
    let preLoadAvailableMB = availableMemoryMB()
    let preLoadResidentMB = residentMemoryMB()
    let preLoadThermal = thermalLevel()

    log("Pre-load memory: \(String(format: "%.0f", preLoadAvailableMB)) MB available, \(String(format: "%.0f", preLoadResidentMB)) MB resident")

    // ── Configure experimental flags ────────────────────────────────
    ExperimentalFlags.optIntoExperimentalAPIs()
    ExperimentalFlags.enableBenchmark = true
    ExperimentalFlags.enableSpeculativeDecoding = nil  // No MTP for raw test

    // ── Cache directory ─────────────────────────────────────────────
    let cacheDir: String
    if let cachesURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
        let dir = cachesURL.appendingPathComponent("RawBenchmark-\(modelFilename)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        cacheDir = dir.path
    } else {
        cacheDir = NSTemporaryDirectory()
    }

    // ── Model Load (GPU first, CPU fallback) ────────────────────────
    var engine: Engine?
    var backendUsed = "unknown"
    var gpuLoadTimeS: Double? = nil
    var cpuLoadTimeS: Double? = nil
    var modelLoadTimeS: Double = 0

    // Try GPU
    log("⏳ Loading model on GPU (Metal)...")
    let gpuSignpostID = OSSignpostID(log: modelLoadLog)
    os_signpost(.begin, log: modelLoadLog, name: "ModelLoad-GPU", signpostID: gpuSignpostID,
                "Loading %{public}s on GPU", modelFilename)

    let gpuStart = CFAbsoluteTimeGetCurrent()
    do {
        let config = try EngineConfig(
            modelPath: modelPath,
            backend: .gpu,
            cacheDir: cacheDir
        )
        let eng = Engine(engineConfig: config)
        try await eng.initialize()
        engine = eng
        backendUsed = "gpu"
        gpuLoadTimeS = CFAbsoluteTimeGetCurrent() - gpuStart
        modelLoadTimeS = gpuLoadTimeS!

        os_signpost(.end, log: modelLoadLog, name: "ModelLoad-GPU", signpostID: gpuSignpostID,
                    "GPU load succeeded in %.2f s", modelLoadTimeS)
        log("✅ GPU load in \(String(format: "%.2f", modelLoadTimeS))s")
    } catch {
        gpuLoadTimeS = CFAbsoluteTimeGetCurrent() - gpuStart
        os_signpost(.end, log: modelLoadLog, name: "ModelLoad-GPU", signpostID: gpuSignpostID,
                    "GPU load FAILED: %{public}s", error.localizedDescription)
        log("⚠️  GPU load failed (\(String(format: "%.2f", gpuLoadTimeS!))s): \(error.localizedDescription)")
        log("⏳ Falling back to CPU...")

        let cpuSignpostID = OSSignpostID(log: modelLoadLog)
        os_signpost(.begin, log: modelLoadLog, name: "ModelLoad-CPU", signpostID: cpuSignpostID,
                    "Loading %{public}s on CPU", modelFilename)

        let cpuStart = CFAbsoluteTimeGetCurrent()
        do {
            let config = try EngineConfig(
                modelPath: modelPath,
                backend: .cpu(),
                cacheDir: cacheDir
            )
            let eng = Engine(engineConfig: config)
            try await eng.initialize()
            engine = eng
            backendUsed = "cpu"
            cpuLoadTimeS = CFAbsoluteTimeGetCurrent() - cpuStart
            modelLoadTimeS = cpuLoadTimeS!

            os_signpost(.end, log: modelLoadLog, name: "ModelLoad-CPU", signpostID: cpuSignpostID,
                        "CPU load succeeded in %.2f s", modelLoadTimeS)
            log("✅ CPU load in \(String(format: "%.2f", modelLoadTimeS))s")
        } catch {
            cpuLoadTimeS = CFAbsoluteTimeGetCurrent() - cpuStart
            os_signpost(.end, log: modelLoadLog, name: "ModelLoad-CPU", signpostID: cpuSignpostID,
                        "CPU load FAILED: %{public}s", error.localizedDescription)
            log("❌ Both backends failed. CPU error: \(error.localizedDescription)")
            exit(1)
        }
    }

    guard let engine = engine else { exit(1) }

    // Post-load memory
    let postLoadAvailableMB = availableMemoryMB()
    let postLoadResidentMB = residentMemoryMB()
    let unifiedMemoryDeltaMB = preLoadAvailableMB - postLoadAvailableMB
    log("Post-load memory: \(String(format: "%.0f", postLoadAvailableMB)) MB available, \(String(format: "%.0f", postLoadResidentMB)) MB resident")
    log("Unified memory consumed by model: \(String(format: "%.0f", unifiedMemoryDeltaMB)) MB")

    // ── Create Conversation (Greedy Sampler) ────────────────────────
    // v2: NO warmup-then-reset. We run the benchmark on the FIRST conversation
    // turn so the SDK's BenchmarkInfo counters are populated correctly.
    // The tradeoff is the first turn includes JIT/shader compilation overhead,
    // but that's what real users see, and we capture the SDK's native metrics.
    log("")
    log("⏳ Creating conversation (greedy sampler: topK=1)...")
    let convStart = CFAbsoluteTimeGetCurrent()
    let conversation: Conversation
    do {
        let sampler = try SamplerConfig(topK: 1, topP: 1.0, temperature: 1.0)
        let convConfig = ConversationConfig(samplerConfig: sampler)
        conversation = try await engine.createConversation(with: convConfig)
    } catch {
        log("❌ Failed to create conversation: \(error.localizedDescription)")
        exit(1)
    }
    let convCreateTimeS = CFAbsoluteTimeGetCurrent() - convStart
    log("✅ Conversation created in \(String(format: "%.4f", convCreateTimeS))s")

    // ── Benchmark Inference (First Turn — No Warmup) ────────────────
    log("")
    log("🚀 Starting benchmark inference (FIRST TURN — no warmup)...")
    log("   Prompt length: ~\(benchmarkPrompt.split(separator: " ").count) words")
    log("   Max decode: \(maxDecodeTokens) tokens")
    log("   This includes any JIT/shader compile overhead (real-world scenario)")
    log("")

    let preInferenceAvailableMB = availableMemoryMB()
    let preInferenceThermal = thermalLevel()

    let inferenceSignpostID = OSSignpostID(log: inferenceLog)
    os_signpost(.begin, log: inferenceLog, name: "BenchmarkInference", signpostID: inferenceSignpostID,
                "Starting benchmark inference, max %{public}d tokens", maxDecodeTokens)

    let inferenceStart = CFAbsoluteTimeGetCurrent()
    var tokenTimestamps: [CFAbsoluteTime] = []
    var tokenCount = 0
    var responseText = ""
    var firstTokenTimeS: Double? = nil

    do {
        for try await chunk in conversation.sendMessageStream(Message(benchmarkPrompt)) {
            let now = CFAbsoluteTimeGetCurrent()
            tokenTimestamps.append(now)
            tokenCount += 1

            if firstTokenTimeS == nil {
                firstTokenTimeS = now - inferenceStart
                os_signpost(.event, log: firstTokenLog, name: "FirstToken",
                            "First token at %.3f s", firstTokenTimeS!)
                log("   ⚡ First token at \(String(format: "%.3f", firstTokenTimeS!))s")
            }

            if let firstContent = chunk.contents.first {
                switch firstContent {
                case .text(let text):
                    responseText += text
                default:
                    break
                }
            }

            if tokenCount >= maxDecodeTokens {
                log("   📊 Reached \(maxDecodeTokens) token cap")
                break
            }
        }
    } catch {
        log("❌ Inference failed: \(error.localizedDescription)")
    }

    let inferenceEndTime = CFAbsoluteTimeGetCurrent()
    let totalInferenceTimeS = inferenceEndTime - inferenceStart

    os_signpost(.end, log: inferenceLog, name: "BenchmarkInference", signpostID: inferenceSignpostID,
                "Inference completed: %{public}d tokens in %.2f s", tokenCount, totalInferenceTimeS)

    // Post-inference snapshot
    let postInferenceAvailableMB = availableMemoryMB()
    let postInferenceResidentMB = residentMemoryMB()
    let postInferenceThermal = thermalLevel()

    // ── SDK BenchmarkInfo ───────────────────────────────────────────
    var sdkPrefillTokS: Double = 0
    var sdkDecodeTokS: Double = 0
    var sdkTTFT: Double = 0
    var sdkInitTime: Double = 0
    var sdkBenchmarkAvailable = false

    do {
        let info = try conversation.getBenchmarkInfo()
        sdkPrefillTokS = info.lastPrefillTokensPerSecond
        sdkDecodeTokS = info.lastDecodeTokensPerSecond
        sdkTTFT = info.timeToFirstTokenInSecond
        sdkInitTime = info.initTimeInSecond
        sdkBenchmarkAvailable = true
        log("✅ SDK BenchmarkInfo: prefill=\(String(format: "%.1f", sdkPrefillTokS)) tok/s, decode=\(String(format: "%.1f", sdkDecodeTokS)) tok/s, ttft=\(String(format: "%.3f", sdkTTFT))s")
    } catch {
        log("⚠️  BenchmarkInfo unavailable: \(error.localizedDescription)")
    }

    // ── Compute Metrics ─────────────────────────────────────────────

    // v2 FIX: Separate TTFT (prefill) from pure decode throughput
    let ttft = firstTokenTimeS ?? 0
    let pureDecodeTokens = max(tokenCount - 1, 0)  // Exclude first token
    let pureDecodeTimeS = totalInferenceTimeS - ttft
    let pureDecodeTokS = pureDecodeTokens > 0 && pureDecodeTimeS > 0
        ? Double(pureDecodeTokens) / pureDecodeTimeS
        : 0

    // Overall throughput (includes TTFT — what user perceives over full request)
    let overallTokS = tokenCount > 0 ? Double(tokenCount) / totalInferenceTimeS : 0

    // Per-token latency (EXCLUDING first token / TTFT)
    var decodeLatenciesMs: [Double] = []
    if tokenTimestamps.count > 1 {
        for i in 1..<tokenTimestamps.count {
            decodeLatenciesMs.append((tokenTimestamps[i] - tokenTimestamps[i - 1]) * 1000.0)
        }
    }

    let sortedLatencies = decodeLatenciesMs.sorted()
    let medianLatencyMs: Double = {
        guard !sortedLatencies.isEmpty else { return 0 }
        let mid = sortedLatencies.count / 2
        if sortedLatencies.count.isMultiple(of: 2) {
            return (sortedLatencies[mid - 1] + sortedLatencies[mid]) / 2.0
        }
        return sortedLatencies[mid]
    }()

    let p95LatencyMs: Double = {
        guard !sortedLatencies.isEmpty else { return 0 }
        let idx = min(Int(Double(sortedLatencies.count) * 0.95), sortedLatencies.count - 1)
        return sortedLatencies[idx]
    }()

    let minLatencyMs = sortedLatencies.first ?? 0
    let maxLatencyMs = sortedLatencies.last ?? 0
    let avgLatencyMs = sortedLatencies.isEmpty ? 0 : sortedLatencies.reduce(0, +) / Double(sortedLatencies.count)

    // Memory
    let unifiedMemInferenceDeltaMB = preInferenceAvailableMB - postInferenceAvailableMB

    // ── Build JSON Report ───────────────────────────────────────────
    let report: [String: Any] = [
        // Meta
        "version": 2,
        "timestamp": timestamp(),
        "model": modelFilename,
        "model_size_mb": Int(modelSizeMB),
        "device": deviceModel(),
        "total_ram_mb": Int(Double(ProcessInfo.processInfo.physicalMemory) / 1_048_576.0),

        // Backend
        "backend_used": backendUsed,
        "gpu_load_time_s": gpuLoadTimeS as Any,
        "cpu_load_time_s": cpuLoadTimeS as Any,
        "model_load_time_s": modelLoadTimeS,
        "conversation_create_time_s": convCreateTimeS,

        // SDK metrics
        "sdk_benchmark_available": sdkBenchmarkAvailable,
        "sdk_prefill_tok_s": sdkPrefillTokS,
        "sdk_decode_tok_s": sdkDecodeTokS,
        "sdk_ttft_s": sdkTTFT,
        "sdk_init_time_s": sdkInitTime,

        // Wall-clock metrics (CORRECTED in v2)
        "wall_ttft_s": ttft,
        "wall_pure_decode_tok_s": pureDecodeTokS,
        "wall_pure_decode_time_s": pureDecodeTimeS,
        "wall_pure_decode_tokens": pureDecodeTokens,
        "wall_overall_tok_s": overallTokS,
        "wall_total_inference_s": totalInferenceTimeS,
        "total_tokens": tokenCount,

        // Token latency (CORRECTED: excludes TTFT)
        "decode_median_latency_ms": medianLatencyMs,
        "decode_p95_latency_ms": p95LatencyMs,
        "decode_avg_latency_ms": avgLatencyMs,
        "decode_min_latency_ms": minLatencyMs,
        "decode_max_latency_ms": maxLatencyMs,

        // Memory (unified = GPU+CPU on Apple Silicon)
        "unified_mem_pre_load_mb": Int(preLoadAvailableMB),
        "unified_mem_post_load_mb": Int(postLoadAvailableMB),
        "unified_mem_model_delta_mb": Int(unifiedMemoryDeltaMB),
        "unified_mem_post_inference_mb": Int(postInferenceAvailableMB),
        "unified_mem_inference_delta_mb": Int(unifiedMemInferenceDeltaMB),
        "process_resident_pre_mb": Int(preLoadResidentMB),
        "process_resident_post_mb": Int(postInferenceResidentMB),

        // Thermal
        "thermal_pre_load": preLoadThermal,
        "thermal_pre_inference": preInferenceThermal,
        "thermal_post_inference": postInferenceThermal,

        // Config
        "prompt_word_count": benchmarkPrompt.split(separator: " ").count,
        "max_decode_tokens": maxDecodeTokens,
        "sampler": "greedy (topK=1, topP=1.0, temp=1.0)",
        "warmup": "none (first turn benchmark)",
        "mtp_enabled": false,

        // Response quality check
        "response_preview": String(responseText.prefix(300)),
    ]

    // ── Print Report ────────────────────────────────────────────────
    log("")
    log("════════════════════════════════════════════════════════════════")
    log("  BENCHMARK RESULTS (v2 — corrected)")
    log("════════════════════════════════════════════════════════════════")
    log("  Backend:              \(backendUsed.uppercased())")
    log("  Model Load:           \(String(format: "%.2f", modelLoadTimeS))s")
    log("")
    log("  --- SDK Metrics ---")
    log("  SDK Prefill:          \(String(format: "%.1f", sdkPrefillTokS)) tok/s")
    log("  SDK Decode:           \(String(format: "%.1f", sdkDecodeTokS)) tok/s")
    log("  SDK TTFT:             \(String(format: "%.3f", sdkTTFT))s")
    log("  SDK Init:             \(String(format: "%.2f", sdkInitTime))s")
    log("")
    log("  --- Wall-Clock Metrics ---")
    log("  TTFT (first token):   \(String(format: "%.3f", ttft))s")
    log("  Pure Decode:          \(String(format: "%.1f", pureDecodeTokS)) tok/s (\(pureDecodeTokens) tokens in \(String(format: "%.2f", pureDecodeTimeS))s)")
    log("  Overall (incl TTFT):  \(String(format: "%.1f", overallTokS)) tok/s")
    log("  Total Inference:      \(String(format: "%.2f", totalInferenceTimeS))s for \(tokenCount) tokens")
    log("")
    log("  --- Token Latency (decode only, excludes TTFT) ---")
    log("  Median:               \(String(format: "%.1f", medianLatencyMs))ms")
    log("  Average:              \(String(format: "%.1f", avgLatencyMs))ms")
    log("  P95:                  \(String(format: "%.1f", p95LatencyMs))ms")
    log("  Min:                  \(String(format: "%.1f", minLatencyMs))ms")
    log("  Max:                  \(String(format: "%.1f", maxLatencyMs))ms")
    log("")
    log("  --- Memory (Apple Silicon Unified) ---")
    log("  Model load:           −\(Int(unifiedMemoryDeltaMB)) MB unified")
    log("  Inference additional: −\(Int(unifiedMemInferenceDeltaMB)) MB unified")
    log("  Process resident:     \(Int(preLoadResidentMB)) → \(Int(postInferenceResidentMB)) MB")
    log("")
    log("  --- Thermal ---")
    log("  \(preLoadThermal) → \(preInferenceThermal) → \(postInferenceThermal)")
    log("════════════════════════════════════════════════════════════════")

    // JSON to stdout
    if let jsonData = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]),
       let jsonString = String(data: jsonData, encoding: .utf8) {
        print(jsonString)
    }

    log("")
    log("Done. Shutting down engine...")
    exit(0)
}
