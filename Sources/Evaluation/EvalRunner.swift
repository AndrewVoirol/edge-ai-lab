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

    /// The inference engine used to run models.
    private let engine: InstrumentedEngineProtocol

    /// Store for persisting completed runs.
    private let store: EvalStore

    /// Active task for cancellation support.
    private var runTask: Task<Void, Never>?

    /// Whether the current run has been cancelled.
    private var isCancelled: Bool = false

    // MARK: - Init

    /// Initialize the eval runner with an engine and store.
    /// - Parameters:
    ///   - engine: The instrumented engine to use for inference.
    ///   - store: The eval store for persisting results.
    init(engine: InstrumentedEngineProtocol, store: EvalStore) {
        self.engine = engine
        self.store = store
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
        flags: ExperimentalFlagsState,
        cacheDir: String
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
                    cacheDir: cacheDir
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
        // The user will need to re-select their model, but the engine won't be in an unexpected state.
        await engine.shutdown()

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
        engine.cancelGeneration()
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
        flags: ExperimentalFlagsState,
        cacheDir: String
    ) async throws -> ModelEvalResult {
        let metadata = modelEntry.metadata

        // Shut down any existing engine session
        await engine.shutdown()

        // Initialize the engine with this model
        // Configure flags for eval: enable benchmarks, enable tool calling for tool suites
        var evalFlags = flags
        evalFlags.enableBenchmark = true
        evalFlags.enableToolCalling = suite.category == .toolCalling || suite.category == .math

        let tools: [Tool]? = evalFlags.enableToolCalling ? ToolRegistry.defaultTools : nil

        _ = try await engine.initializeWithFallback(
            modelPath: modelEntry.modelPath,
            preferGPU: metadata.platformSupport.currentPlatform.supportsGPU,
            cacheDir: cacheDir,
            flags: evalFlags,
            samplerConfig: nil,
            systemMessage: nil,
            tools: tools,
            supportsVision: metadata.supportsImage,
            supportsAudio: metadata.supportsAudio
        )

        Self.logger.info("✅ Engine initialized for eval: \(metadata.name, privacy: .public)")

        // Track metrics across prompts
        let modelStartTime = CFAbsoluteTimeGetCurrent()
        var promptResults: [PromptEvalResult] = []
        var decodeSpeeds: [Double] = []
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

            // Reset conversation between prompts to get clean context
            if promptIdx > 0 {
                try await engine.resetConversation()
            }

            let promptResult = await evaluatePrompt(
                prompt: prompt,
                metadata: metadata,
                timeout: prompt.timeoutSeconds
            )

            promptResults.append(promptResult)
            onPromptComplete?(promptResult)
            promptDurations.append(promptResult.duration)

            // Aggregate metrics
            if let speed = promptResult.decodeSpeed {
                decodeSpeeds.append(speed)
            }
            if let t = promptResult.ttft {
                ttfts.append(t)
            }


            // Track resource metrics
            if let metrics = engine.lastInferenceMetrics {
                let delta = abs(metrics.memoryDeltaMB)
                if delta > peakMemoryDelta {
                    peakMemoryDelta = delta
                }
                if metrics.thermalStateChanged {
                    thermalTransitions += 1
                }
            }
        }

        let modelDuration = CFAbsoluteTimeGetCurrent() - modelStartTime

        // Compute aggregated speed metrics
        let avgSpeed = decodeSpeeds.isEmpty ? 0 : decodeSpeeds.reduce(0, +) / Double(decodeSpeeds.count)
        let avgTTFT = ttfts.isEmpty ? 0 : ttfts.reduce(0, +) / Double(ttfts.count)

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
        timeout: Int
    ) async -> PromptEvalResult {
        let promptStartTime = CFAbsoluteTimeGetCurrent()
        var collectedResponse = ""
        var capturedToolEvents: [ToolCallEvent] = []

        // Register tool call tracker to capture events during this prompt
        ToolExecutionTracker.shared.registerCallback { event in
            capturedToolEvents.append(event)
        }
        defer { ToolExecutionTracker.shared.clearCallback() }

        // Skip multimodal prompts if the model doesn't support them
        if prompt.isImagePrompt && !metadata.supportsImage {
            return PromptEvalResult(
                promptId: prompt.id,
                promptText: prompt.prompt,
                response: "",
                passed: false,
                score: .fail(reason: "Model does not support image input"),
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

        do {
            // Run inference with timeout
            try await withThrowingTaskGroup(of: String.self) { group in
                // Inference task
                group.addTask { [engine] in
                    var fullResponse = ""
                    let stream: AsyncThrowingStream<String, Error>

                    if prompt.isMultimodal {
                        stream = engine.sendMessageStream(
                            prompt.prompt,
                            imageData: prompt.imageData,
                            audioData: prompt.audioData
                        )
                    } else {
                        stream = engine.sendMessageStream(prompt.prompt)
                    }

                    for try await chunk in stream {
                        fullResponse += chunk
                    }
                    return fullResponse
                }

                // Timeout task
                group.addTask {
                    try await Task.sleep(for: .seconds(timeout))
                    throw EvalRunnerError.promptTimeout(prompt.id)
                }

                // Take the first result (either inference completes or timeout fires)
                if let result = try await group.next() {
                    collectedResponse = result
                }
                group.cancelAll()
            }
        } catch is EvalRunnerError {
            // Timeout
            let duration = CFAbsoluteTimeGetCurrent() - promptStartTime
            return PromptEvalResult(
                promptId: prompt.id,
                promptText: prompt.prompt,
                response: collectedResponse,
                passed: false,
                score: .timeout,
                duration: duration
            )
        } catch {
            // Inference error
            let duration = CFAbsoluteTimeGetCurrent() - promptStartTime
            return PromptEvalResult(
                promptId: prompt.id,
                promptText: prompt.prompt,
                response: collectedResponse,
                passed: false,
                score: .error(error.localizedDescription),
                duration: duration
            )
        }

        let duration = CFAbsoluteTimeGetCurrent() - promptStartTime

        // Capture benchmark metrics from the engine
        let decodeSpeed = engine.lastBenchmarkInfo?.lastDecodeTokensPerSecond
        let ttft = engine.lastBenchmarkInfo?.timeToFirstTokenInSecond

        // Score the response
        let evalScore = EvalScorer.score(
            response: collectedResponse,
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
            response: collectedResponse,
            passed: passed,
            score: evalScore,
            decodeSpeed: decodeSpeed,
            ttft: ttft,
            toolCallEvents: capturedToolEvents,
            duration: duration
        )
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
