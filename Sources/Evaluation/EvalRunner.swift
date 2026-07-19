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
import Observation
import os

// MARK: - Eval Runner State

/// State machine states for the evaluation runner.
enum EvalRunnerState: Sendable, Equatable {
    /// No evaluation in progress.
    case idle

    /// Preparing the evaluation (loading suite, validating models).
    case preparing

    /// Running inference for a specific model and prompt.
    case running(modelIndex: Int, promptIndex: Int)

    /// Scoring results after inference completes.
    case scoring

    /// Evaluation completed successfully.
    case complete

    /// Evaluation failed with an error.
    case failed(String)

    /// Human-readable label for display.
    var displayLabel: String {
        switch self {
        case .idle:                             return "Idle"
        case .preparing:                        return "Preparing…"
        case .running(let m, let p):            return "Running model \(m + 1), prompt \(p + 1)…"
        case .scoring:                          return "Scoring…"
        case .complete:                         return "Complete"
        case .failed(let msg):                  return "Failed: \(msg)"
        }
    }

    /// Whether the runner is actively working.
    var isActive: Bool {
        switch self {
        case .preparing, .running, .scoring:    return true
        default:                                return false
        }
    }
}

// MARK: - Model Entry

/// A model to evaluate, pairing its metadata with the on-disk file path.
struct EvalModelEntry: Sendable {
    /// Metadata for the model (name, capabilities, etc.).
    let metadata: ModelMetadata

    /// Absolute path to the model file on disk.
    let modelPath: String

    /// Path to the companion multimodal projector file (mmproj-*.gguf), if available.
    /// Only used by GGUF engine for vision/audio support via libmtmd.
    var mmProjPath: String? = nil
}

// MARK: - Eval Runner

/// Evaluation execution engine that runs a suite of prompts against one or more models.
///
/// The runner follows a state machine pattern:
/// `idle → preparing → running → scoring → complete/failed`
///
/// For each model, the runner:
/// 1. Shuts down any existing engine session
/// 2. Initializes the engine with the new model (via `initializeWithFallback`)
/// 3. Runs each prompt, collecting response text, benchmark metrics, and tool call events
/// 4. Scores each response against the prompt's expected behavior
/// 5. Aggregates results into a `ModelEvalResult`
///
/// Progress tracking and cancellation are supported throughout.
@Observable
@MainActor
final class EvalRunner {

    private static let logger = Logger(
        subsystem: "com.andrewvoirol.EdgeAILab",
        category: "evalRunner"
    )

    // MARK: - State

    /// Current runner state.
    var state: EvalRunnerState = .idle

    /// The eval run being built (nil when idle).
    var currentRun: EvalRun?

    /// Callback invoked on the MainActor each time a prompt completes.
    /// Used by EvalRunnerView to populate live results.
    var onPromptComplete: (@MainActor @Sendable (PromptEvalResult) -> Void)?

    // MARK: - Progress Tracking

    /// Index of the model currently being evaluated (0-based).
    var currentModelIndex: Int = 0

    /// Index of the prompt currently being evaluated (0-based).
    var currentPromptIndex: Int = 0

    /// Total number of models to evaluate.
    var totalModels: Int = 0

    /// Total number of prompts per model.
    var totalPrompts: Int = 0

    /// Estimated seconds remaining (rough approximation).
    var estimatedTimeRemaining: TimeInterval = 0

    /// Human-readable progress description.
    var progressDescription: String = ""

    /// Overall progress fraction (0.0–1.0).
    var overallProgress: Double {
        guard totalModels > 0, totalPrompts > 0 else { return 0 }
        let totalWork = totalModels * totalPrompts
        let completedWork = currentModelIndex * totalPrompts + currentPromptIndex
        return Double(completedWork) / Double(totalWork)
    }

    // MARK: - Dependencies

    /// The inference engine currently in use for the active model evaluation.
    /// Created fresh per-model inside `evaluateModel()` via `EngineFactory`.
    /// Stored at class level so `cancel()` can invoke `cancelGeneration()`.
    private var engine: (any InferenceEngine)?

    /// Store for persisting completed runs.
    private let store: EvalStore

    /// Portable export persistence for timestamped JSON exports.
    private let exportPersistence: EvalResultPersistence?

    /// Active task for cancellation support.
    private var runTask: Task<Void, Never>?

    /// Whether the current run has been cancelled.
    private var isCancelled: Bool = false

    // MARK: - Init

    /// Initialize the eval runner with a store and optional export persistence.
    ///
    /// The runner creates its own inference engine per model based on the
    /// model's `runtimeType`, so no engine parameter is needed.
    ///
    /// - Parameters:
    ///   - store: The eval store for persisting results.
    ///   - exportPersistence: Optional portable export persistence for timestamped JSON exports.
    init(
        store: EvalStore,
        exportPersistence: EvalResultPersistence? = nil
    ) {
        self.store = store
        self.exportPersistence = exportPersistence
    }

    // MARK: - Run Evaluation

    /// Run a full evaluation of the given suite against the specified models.
    ///
    /// - Parameters:
    ///   - suite: The eval suite containing prompts to run.
    ///   - models: The models to evaluate, with their file paths.
    ///   - flags: Experimental flags configuration for the engine.
    ///   - cacheDir: Cache directory path for the engine.
    /// - Returns: The completed `EvalRun` with all results.
    @discardableResult
    func run(
        suite: EvalSuite,
        models: [EvalModelEntry],
        flags: RuntimeFlags,
        cacheDir: String,
        runsPerPrompt: Int = 1
    ) async throws -> EvalRun {
        guard !models.isEmpty else {
            throw EvalRunnerError.noModels
        }

        // Reset state
        isCancelled = false
        state = .preparing
        totalModels = models.count
        totalPrompts = suite.promptCount
        currentModelIndex = 0
        currentPromptIndex = 0
        progressDescription = "Preparing evaluation…"

        Self.logger.info("🧪 Starting eval: \(suite.name, privacy: .public) with \(models.count) model(s), \(suite.promptCount) prompt(s)")

        // Create the run
        var run = EvalRun(
            suiteId: suite.id,
            suiteName: suite.name,
            suiteCategory: suite.category
        )
        currentRun = run

        let runStartTime = CFAbsoluteTimeGetCurrent()
        var allModelResults: [ModelEvalResult] = []

        // Evaluate each model
        for (modelIdx, modelEntry) in models.enumerated() {
            guard !isCancelled else {
                state = .failed("Cancelled by user")
                throw EvalRunnerError.cancelled
            }

            currentModelIndex = modelIdx
            progressDescription = "Loading \(modelEntry.metadata.name)…"

            Self.logger.info("📦 Evaluating model \(modelIdx + 1)/\(models.count): \(modelEntry.metadata.name, privacy: .public)")

            do {
                let modelResult = try await evaluateModel(
                    modelEntry: modelEntry,
                    suite: suite,
                    flags: flags,
                    cacheDir: cacheDir,
                    runsPerPrompt: max(1, runsPerPrompt)
                )
                allModelResults.append(modelResult)
            } catch {
                Self.logger.error("❌ Model evaluation failed: \(modelEntry.metadata.name, privacy: .public) — \(error.localizedDescription, privacy: .public)")

                // Create a failed result for this model
                let failedResult = ModelEvalResult(
                    modelName: modelEntry.metadata.name,
                    modelFile: modelEntry.metadata.modelFile,
                    avgDecodeSpeed: 0,
                    avgTTFT: 0,
                    p95Latency: 0,
                    totalTokensGenerated: 0,
                    totalDuration: 0,
                    promptResults: [],
                    passRate: 0,
                    peakMemoryDeltaMB: nil,
                    thermalTransitions: 0
                )
                allModelResults.append(failedResult)
            }
        }

        // Shut down the engine after eval so it's not left initialized with the last model.
        await engine?.shutdown()
        engine = nil

        // Finalize the run
        state = .scoring
        progressDescription = "Finalizing results…"

        run.modelResults = allModelResults
        run.completedAt = Date()
        currentRun = run

        // Persist the run
        do {
            try store.save(run)
            Self.logger.info("✅ Eval complete: \(suite.name, privacy: .public) — \(run.displaySummary, privacy: .public)")
        } catch {
            Self.logger.error("❌ Failed to persist eval run: \(error.localizedDescription, privacy: .public)")
        }

        // Export a portable timestamped JSON copy
        if let exportPersistence {
            do {
                let exportURL = try exportPersistence.save(run)
                Self.logger.info("📤 Exported eval results to: \(exportURL.lastPathComponent, privacy: .public)")
            } catch {
                Self.logger.error("❌ Failed to export eval results: \(error.localizedDescription, privacy: .public)")
            }
        }

        let totalTime = CFAbsoluteTimeGetCurrent() - runStartTime
        Self.logger.info("⏱️ Total eval time: \(String(format: "%.1f", totalTime), privacy: .public)s")

        state = .complete
        progressDescription = "Complete"
        estimatedTimeRemaining = 0

        return run
    }

    /// Cancel the current evaluation.
    func cancel() {
        guard state.isActive else { return }
        Self.logger.info("🛑 Cancelling eval run")
        isCancelled = true
        engine?.cancelGeneration()
        runTask?.cancel()
        state = .failed("Cancelled by user")
    }

    /// Reset the runner to idle state.
    func reset() {
        state = .idle
        currentRun = nil
        currentModelIndex = 0
        currentPromptIndex = 0
        totalModels = 0
        totalPrompts = 0
        estimatedTimeRemaining = 0
        progressDescription = ""
        isCancelled = false
    }

    // MARK: - Model Evaluation

    /// Evaluate a single model against all prompts in the suite.
    private func evaluateModel(
        modelEntry: EvalModelEntry,
        suite: EvalSuite,
        flags: RuntimeFlags,
        cacheDir: String,
        runsPerPrompt: Int = 1
    ) async throws -> ModelEvalResult {
        let metadata = modelEntry.metadata

        // Shut down any existing engine session from a previous model
        await engine?.shutdown()
        engine = nil

        // Create a fresh engine for this model's runtime type.
        // Each model gets its own engine instance — no reuse across models.
        let requiredRuntime = metadata.runtimeType
        Self.logger.info("🔧 Creating \(requiredRuntime.displayName, privacy: .public) engine for \(metadata.name, privacy: .public)")

        let engine: any InferenceEngine
        do {
            engine = try EngineFactory.createEngine(for: requiredRuntime)
        } catch {
            Self.logger.error("❌ Failed to create \(requiredRuntime.displayName, privacy: .public) engine: \(error.localizedDescription, privacy: .public)")
            throw EvalRunnerError.engineInitFailed("Cannot create \(requiredRuntime.displayName) engine: \(error.localizedDescription)")
        }
        self.engine = engine  // Store for cancellation
        defer {
            Task { [weak engine] in
                await engine?.shutdown()
            }
        }

        // Initialize the engine with this model
        // Configure flags for eval: enable benchmarks, enable tool calling when any prompt expects it
        var evalFlags = flags
        evalFlags.enableBenchmark = true
        // Load tools if ANY prompt in the suite expects tool-calling behavior.
        // This is more accurate than checking the category, because suites like
        // Gemma 4 Capabilities (.general) include tool prompts, and suites like
        // Math Knowledge (.math) use text-only scoring and break when tools are loaded.
        evalFlags.enableToolCalling = suite.prompts.contains { $0.expectedBehavior.involvesToolCalling }

        // Build tools as AppTool for the generic InferenceEngine path.
        // ToolRegistry.defaultTools are LiteRTLM.Tool instances — use the adapter
        // to bridge them to AppTool for engine-agnostic consumption.
        let tools: [any AppTool]? = evalFlags.enableToolCalling
            ? ToolToAppToolAdapter.adaptAll(ToolRegistry.defaultTools)
            : nil

        let loadConfig = ModelLoadConfig(
            modelPath: modelEntry.modelPath,
            preferGPU: metadata.platformSupport.currentPlatform.supportsGPU,
            cacheDir: cacheDir,
            systemMessage: nil,
            tools: tools,
            supportsVision: metadata.supportsImage,
            supportsAudio: metadata.supportsAudio,
            runtimeFlags: evalFlags,
            mmProjPath: modelEntry.mmProjPath
        )
        try await engine.loadModel(config: loadConfig)

        Self.logger.info("✅ Engine initialized for eval: \(metadata.name, privacy: .public)")
        print("[EvalRunner] 🔧 Engine loaded: runtime=\(engine.runtimeType.displayName), supportsToolCalling=\(engine.supportsToolCalling), tools=\(tools?.count ?? 0)")

        // Track metrics across prompts
        let modelStartTime = CFAbsoluteTimeGetCurrent()
        var promptResults: [PromptEvalResult] = []
        var decodeSpeeds: [Double] = []
        var prefillSpeeds: [Double] = []
        var ttfts: [Double] = []
        var peakMemoryDelta: Double = 0
        var thermalTransitions = 0
        var promptDurations: [TimeInterval] = []

        // Run each prompt
        for (promptIdx, prompt) in suite.prompts.enumerated() {
            guard !isCancelled else { throw EvalRunnerError.cancelled }

            currentPromptIndex = promptIdx
            state = .running(modelIndex: currentModelIndex, promptIndex: promptIdx)
            progressDescription = "Model \(currentModelIndex + 1)/\(totalModels) · Prompt \(promptIdx + 1)/\(totalPrompts)"

            // Update estimated time remaining based on average prompt duration
            if !promptDurations.isEmpty {
                let avgDuration = promptDurations.reduce(0, +) / Double(promptDurations.count)
                let remainingPrompts = Double((totalModels - currentModelIndex - 1) * totalPrompts + (totalPrompts - promptIdx))
                estimatedTimeRemaining = avgDuration * remainingPrompts
            }

            Self.logger.info("🔄 Prompt \(promptIdx + 1)/\(suite.promptCount): \(prompt.truncatedPrompt, privacy: .public)")

            // Skip tool-call-scored prompts when the engine doesn't support tool calling.
            // Instead of running inference that will always produce 0 tool call events,
            // mark the prompt as skipped with a clear reason.
            if prompt.expectedBehavior.involvesToolCalling && !engine.supportsToolCalling {
                let skipReason = "Skipped: \(engine.runtimeType.displayName) engine does not support tool calling"
                Self.logger.info("⏭️ Skipping tool-call prompt: \(skipReason, privacy: .public)")
                let skippedResult = PromptEvalResult(
                    promptId: prompt.id,
                    promptText: prompt.prompt,
                    response: "",
                    passed: false,
                    score: .fail(reason: skipReason),
                    duration: 0
                )
                promptResults.append(skippedResult)
                onPromptComplete?(skippedResult)
                continue
            }

            // Reset conversation between prompts to get clean context.
            // Use system-preserving reset for GGUF to keep tool descriptions.
            if promptIdx > 0 {
                if let ggufEngine = engine as? GGUFEngineAdapter {
                    await ggufEngine.resetConversationKeepingSystem()
                } else {
                    try await engine.resetConversation()
                }
            }

            let promptResult = await evaluatePrompt(
                prompt: prompt,
                metadata: metadata,
                timeout: prompt.timeoutSeconds,
                tools: tools ?? []
            )

            // If runsPerPrompt > 1, run additional repetitions and aggregate.
            // First run already completed above. Run remaining N-1 times.
            if runsPerPrompt > 1 {
                var passCount = promptResult.passed ? 1 : 0
                var allSpeeds: [Double] = []
                if let s = promptResult.decodeSpeed { allSpeeds.append(s) }
                var allTTFTs: [Double] = []
                if let t = promptResult.ttft { allTTFTs.append(t) }

                for runIdx in 2...runsPerPrompt {
                    guard !isCancelled else { throw EvalRunnerError.cancelled }

                    progressDescription = "Model \(currentModelIndex + 1)/\(totalModels) · Prompt \(promptIdx + 1)/\(totalPrompts) · Run \(runIdx)/\(runsPerPrompt)"

                    // Reset conversation between repetitions
                    if let ggufEngine = engine as? GGUFEngineAdapter {
                        await ggufEngine.resetConversationKeepingSystem()
                    } else {
                        try await engine.resetConversation()
                    }

                    let repResult = await evaluatePrompt(
                        prompt: prompt,
                        metadata: metadata,
                        timeout: prompt.timeoutSeconds,
                        tools: tools ?? []
                    )

                    if repResult.passed { passCount += 1 }
                    if let s = repResult.decodeSpeed { allSpeeds.append(s) }
                    if let t = repResult.ttft { allTTFTs.append(t) }
                }

                // Majority vote: passed if > 50% of runs passed
                let aggregatePassed = passCount > runsPerPrompt / 2
                let avgSpeed = allSpeeds.isEmpty ? nil : allSpeeds.reduce(0, +) / Double(allSpeeds.count)
                let avgTTFT = allTTFTs.isEmpty ? nil : allTTFTs.reduce(0, +) / Double(allTTFTs.count)

                let aggregatedResult = PromptEvalResult(
                    promptId: prompt.id,
                    promptText: prompt.prompt,
                    response: promptResult.response,
                    passed: aggregatePassed,
                    score: aggregatePassed
                        ? .pass
                        : .fail(reason: "Passed \(passCount)/\(runsPerPrompt) runs (majority vote)"),
                    decodeSpeed: avgSpeed,
                    ttft: avgTTFT,
                    toolCallEvents: promptResult.toolCallEvents,
                    duration: promptResult.duration
                )

                promptResults.append(aggregatedResult)
                onPromptComplete?(aggregatedResult)
                promptDurations.append(aggregatedResult.duration)

                if let speed = avgSpeed { decodeSpeeds.append(speed) }
                if let t = avgTTFT { ttfts.append(t) }
            } else {
                promptResults.append(promptResult)
                onPromptComplete?(promptResult)
                promptDurations.append(promptResult.duration)

                if let speed = promptResult.decodeSpeed {
                    decodeSpeeds.append(speed)
                }
                if let t = promptResult.ttft {
                    ttfts.append(t)
                }
            }


            // Track resource metrics from engine performance data
            if let metrics = engine.lastPerformanceMetrics {
                if let delta = metrics.memoryDeltaMB {
                    let absDelta = abs(delta)
                    if absDelta > peakMemoryDelta {
                        peakMemoryDelta = absDelta
                    }
                }
                if metrics.thermalStateChanged == true {
                    thermalTransitions += 1
                }
                if let prefill = metrics.promptTokensPerSecond, prefill > 0 {
                    prefillSpeeds.append(prefill)
                }
            }
        }

        let modelDuration = CFAbsoluteTimeGetCurrent() - modelStartTime

        // Compute aggregated speed metrics
        let avgSpeed = decodeSpeeds.isEmpty ? 0 : decodeSpeeds.reduce(0, +) / Double(decodeSpeeds.count)
        let avgTTFT = ttfts.isEmpty ? 0 : ttfts.reduce(0, +) / Double(ttfts.count)
        let avgPrefill: Double? = prefillSpeeds.isEmpty ? nil : prefillSpeeds.reduce(0, +) / Double(prefillSpeeds.count)

        // Compute p95 latency from all prompt latencies
        let allLatencies = decodeSpeeds.sorted()
        let p95Latency: Double
        if allLatencies.isEmpty {
            p95Latency = 0
        } else {
            // p95 latency = slow end. Pick the 5th percentile of speeds (lowest speeds = highest latency).
            let p95Index = max(Int(Double(allLatencies.count) * 0.05), 0)
            // Convert tok/s to ms/tok for latency
            p95Latency = allLatencies[p95Index] > 0 ? 1000.0 / allLatencies[p95Index] : 0
        }

        // Compute pass rate and tool call accuracy
        let passCount = promptResults.filter(\.passed).count
        let passRate = promptResults.isEmpty ? 0 : Double(passCount) / Double(promptResults.count)

        let toolPrompts = suite.prompts.filter { $0.expectedBehavior.involvesToolCalling }
        let toolCallAccuracy: Double?
        if !toolPrompts.isEmpty {
            let toolResults = promptResults.filter { result in
                toolPrompts.contains { $0.id == result.promptId }
            }
            let toolPassed = toolResults.filter(\.passed).count
            toolCallAccuracy = Double(toolPassed) / Double(toolResults.count)
        } else {
            toolCallAccuracy = nil
        }

        // Compute total tokens from individual prompt results
        let computedTotalTokens = promptResults.reduce(0) { total, result in
            // Approximate tokens from decode speed * duration
            if let speed = result.decodeSpeed {
                return total + Int(speed * result.duration)
            }
            return total
        }

        return ModelEvalResult(
            modelName: metadata.name,
            modelFile: metadata.modelFile,
            avgDecodeSpeed: avgSpeed,
            avgTTFT: avgTTFT,
            avgPrefillSpeed: avgPrefill,
            p95Latency: p95Latency,
            totalTokensGenerated: computedTotalTokens,
            totalDuration: modelDuration,
            promptResults: promptResults,
            passRate: passRate,
            toolCallAccuracy: toolCallAccuracy,
            peakMemoryDeltaMB: peakMemoryDelta > 0 ? peakMemoryDelta : nil,
            thermalTransitions: thermalTransitions
        )
    }

    // MARK: - Prompt Evaluation

    /// Evaluate a single prompt: run inference, capture metrics, score the result.
    private func evaluatePrompt(
        prompt: EvalPrompt,
        metadata: ModelMetadata,
        timeout: Int,
        tools: [any AppTool]
    ) async -> PromptEvalResult {
        let promptStartTime = CFAbsoluteTimeGetCurrent()
        var capturedToolEvents: [ToolCallEvent] = []

        // Engine must be loaded by evaluateModel() before calling this method
        guard let engine = engine else {
            return PromptEvalResult(
                promptId: prompt.id,
                promptText: prompt.prompt,
                response: "",
                passed: false,
                score: .fail(reason: "Engine not loaded — internal error"),
                duration: 0
            )
        }

        // Register tool call tracker to capture events during this prompt
        ToolExecutionTracker.shared.registerCallback { event in
            capturedToolEvents.append(event)
        }
        defer { ToolExecutionTracker.shared.clearCallback() }

        // Skip multimodal prompts if the engine doesn't actually support them.
        // Use engine capabilities (ground truth after model load) instead of metadata
        // flags, which can be incorrect — e.g., GGUF models without an mmproj file
        // have metadata.supportsImage forced to false even when the model family
        // supports vision.
        if prompt.isImagePrompt && !engine.supportsVision {
            // Surface diagnostic info about WHY vision isn't available
            var reason = "Engine does not support image input (supportsVision=false)"
            #if canImport(MLX) && !targetEnvironment(simulator)
            if let mlxEngine = engine as? MLXEngineAdapter, let err = mlxEngine.vlmLoadError {
                reason += ". VLM load error: \(err)"
                Self.logger.warning("⚠️ VLM was expected but load failed: \(String(describing: err), privacy: .public)")
            }
            #endif
            if engine.runtimeType == .gguf {
                reason += ". GGUF vision requires mmproj companion file alongside the model."
                Self.logger.warning("⚠️ GGUF model skipping image prompt — no mmproj file found.")
            }
            return PromptEvalResult(
                promptId: prompt.id,
                promptText: prompt.prompt,
                response: "",
                passed: false,
                score: .fail(reason: reason),
                duration: 0
            )
        }
        if prompt.isAudioPrompt && !metadata.supportsAudio {
            return PromptEvalResult(
                promptId: prompt.id,
                promptText: prompt.prompt,
                response: "",
                passed: false,
                score: .fail(reason: "Model does not support audio input"),
                duration: 0
            )
        }

        // Build a tool lookup table for dispatching
        let toolLookup = Dictionary(uniqueKeysWithValues: tools.map { ($0.name, $0) })

        // Multi-turn tool execution loop.
        // Each turn: send prompt → model generates → if tool call, execute tool,
        // feed result back → repeat. Max 5 turns to prevent infinite loops.
        //
        // Uses a task group with a result enum: the inference task returns
        // .completed with the response and events, the timeout task throws.
        // First task to finish wins.
        let maxTurns = 5

        enum InferenceResult: Sendable {
            case completed(response: String, toolEvents: [ToolCallEvent])
            case timeout
        }

        do {
            let result = try await withThrowingTaskGroup(
                of: InferenceResult.self
            ) { group -> InferenceResult in
                // Timeout task
                group.addTask {
                    try await Task.sleep(for: .seconds(timeout))
                    return .timeout
                }

                // Multi-turn inference task
                group.addTask { [engine] in
                    var currentPrompt = prompt.prompt
                    var localToolEvents: [ToolCallEvent] = []
                    var lastTextResponse = ""
                    var isFirstTurn = true

                    for _ in 1...maxTurns {
                        try Task.checkCancellation()

                        // Run one inference turn
                        var turnResponse = ""
                        var turnToolCalls: [AppToolCall] = []

                        // Pass image/audio data only on the first turn — subsequent turns
                        // are tool-result feedback where re-sending media is
                        // unnecessary and wastes prefill budget.
                        var evalConfig = GenerationConfig.default
                        if isFirstTurn, let imgData = prompt.imageData {
                            evalConfig.imageData = [imgData]
                        }
                        if isFirstTurn, let audData = prompt.audioData {
                            evalConfig.audioData = [audData]
                        }
                        let stream = engine.generateStream(
                            prompt: currentPrompt,
                            config: evalConfig
                        )

                        for try await event in stream {
                            switch event {
                            case .text(let chunk):
                                turnResponse += chunk
                            case .toolCall(let call):
                                turnToolCalls.append(call)
                            default:
                                break
                            }
                        }

                        isFirstTurn = false

                        // Determine if the engine handles tool dispatch natively.
                        // MLX: ChatSession.toolDispatch executes tools internally and
                        //   yields .toolCall events for observability only. The stream
                        //   already contains the final text response after tool execution.
                        // LiteRT-LM: Handles tools internally, never emits .toolCall events.
                        // GGUF: Emits .toolCall events and relies on the caller (this loop)
                        //   to execute tools and feed results back.
                        let engineHandlesToolsNatively = engine.runtimeType != .gguf

                        if turnToolCalls.isEmpty || engineHandlesToolsNatively {
                            // No tool calls, or the engine already executed them natively.
                            // Return the text response as-is.
                            return .completed(
                                response: turnResponse,
                                toolEvents: localToolEvents
                            )
                        }

                        lastTextResponse = turnResponse

                        // Execute each tool call and build a result summary
                        var toolResultParts: [String] = []
                        for call in turnToolCalls {
                            // Convert AnyCodable arguments to [String: Any]
                            let argsJSON: String
                            if let data = try? JSONEncoder().encode(call.arguments) {
                                argsJSON = String(data: data, encoding: .utf8) ?? "{}"
                            } else {
                                argsJSON = "{}"
                            }

                            let argsDict: [String: Any]
                            if let data = argsJSON.data(using: .utf8),
                               let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                                argsDict = parsed
                            } else {
                                argsDict = [:]
                            }

                            if let tool = toolLookup[call.toolName] {
                                let startTime = CFAbsoluteTimeGetCurrent()
                                do {
                                    let result = try await tool.execute(arguments: argsDict)
                                    let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
                                    localToolEvents.append(ToolCallEvent(
                                        toolName: call.toolName,
                                        arguments: argsJSON,
                                        result: result,
                                        durationMs: elapsed,
                                        timestamp: Date(),
                                        succeeded: true
                                    ))
                                    toolResultParts.append("Tool \(call.toolName) returned: \(result)")
                                } catch {
                                    let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
                                    localToolEvents.append(ToolCallEvent(
                                        toolName: call.toolName,
                                        arguments: argsJSON,
                                        result: "Error: \(error.localizedDescription)",
                                        durationMs: elapsed,
                                        timestamp: Date(),
                                        succeeded: false
                                    ))
                                    toolResultParts.append("Tool \(call.toolName) failed: \(error.localizedDescription)")
                                }
                            } else {
                                // Tool not found — record as failed
                                localToolEvents.append(ToolCallEvent(
                                    toolName: call.toolName,
                                    arguments: argsJSON,
                                    result: "Unknown tool",
                                    durationMs: 0,
                                    timestamp: Date(),
                                    succeeded: false
                                ))
                                toolResultParts.append("Tool \(call.toolName) is not available")
                            }
                        }

                        // Feed tool results back as the next prompt for the model
                        currentPrompt = toolResultParts.joined(separator: "\n")
                    }

                    // Exhausted max turns — return whatever text we have
                    return .completed(
                        response: lastTextResponse,
                        toolEvents: localToolEvents
                    )
                }

                // First result wins
                guard let first = try await group.next() else {
                    throw EvalRunnerError.promptTimeout(prompt.id)
                }
                group.cancelAll()
                return first
            }

            // Unpack the result
            let finalResponse: String
            switch result {
            case .completed(let response, let toolEvents):
                finalResponse = response
                // Merge events from both sources:
                // 1. capturedToolEvents — populated by ToolExecutionTracker callback
                //    (used by LiteRT-LM which handles tools internally, never emitting .toolCall in the stream)
                // 2. toolEvents — populated by the multi-turn loop when it receives .toolCall events
                //    (used by engines like GGUF that emit tool calls in the GenerationEvent stream)
                capturedToolEvents.append(contentsOf: toolEvents)
            case .timeout:
                let duration = CFAbsoluteTimeGetCurrent() - promptStartTime
                return PromptEvalResult(
                    promptId: prompt.id,
                    promptText: prompt.prompt,
                    response: "",
                    passed: false,
                    score: .timeout,
                    duration: duration
                )
            }

            // --- Success path: inference completed within timeout ---

            let duration = CFAbsoluteTimeGetCurrent() - promptStartTime

            // Capture performance metrics from the engine
            let decodeSpeed = engine.lastPerformanceMetrics?.tokensPerSecond
            let ttft = engine.lastPerformanceMetrics?.timeToFirstToken

            // Score the response
            let evalScore = EvalScorer.score(
                response: finalResponse,
                toolCallEvents: capturedToolEvents,
                against: prompt.expectedBehavior
            )

            let passed: Bool
            if case .pass = evalScore {
                passed = true
            } else {
                passed = false
            }

            Self.logger.info(
                "\(passed ? "✅" : "❌", privacy: .public) Prompt scored: \(evalScore.displayLabel, privacy: .public) — \(prompt.truncatedPrompt, privacy: .public)"
            )

            return PromptEvalResult(
                promptId: prompt.id,
                promptText: prompt.prompt,
                response: finalResponse,
                passed: passed,
                score: evalScore,
                decodeSpeed: decodeSpeed,
                ttft: ttft,
                toolCallEvents: capturedToolEvents,
                duration: duration
            )
        } catch is CancellationError {
            // Timeout via task group cancellation
            let duration = CFAbsoluteTimeGetCurrent() - promptStartTime
            return PromptEvalResult(
                promptId: prompt.id,
                promptText: prompt.prompt,
                response: "",
                passed: false,
                score: .timeout,
                duration: duration
            )
        } catch {
            // Inference or other error
            let duration = CFAbsoluteTimeGetCurrent() - promptStartTime
            return PromptEvalResult(
                promptId: prompt.id,
                promptText: prompt.prompt,
                response: "",
                passed: false,
                score: .error(error.localizedDescription),
                duration: duration
            )
        }
    }

}

// MARK: - Errors

/// Errors specific to eval runner operations.
enum EvalRunnerError: LocalizedError {
    case noModels
    case cancelled
    case promptTimeout(UUID)
    case engineInitFailed(String)

    var errorDescription: String? {
        switch self {
        case .noModels:
            return "No models specified for evaluation"
        case .cancelled:
            return "Evaluation was cancelled"
        case .promptTimeout(let id):
            return "Prompt timed out: \(id)"
        case .engineInitFailed(let reason):
            return "Engine initialization failed: \(reason)"
        }
    }
}
