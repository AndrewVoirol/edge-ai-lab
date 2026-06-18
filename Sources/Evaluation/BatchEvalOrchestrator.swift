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

// MARK: - Batch Eval Plan

/// A plan describing a "Run All" batch evaluation across multiple suites and models.
///
/// This is a value type used for estimation and UI display before the run starts.
/// The actual execution is handled by `BatchEvalOrchestrator`.
struct BatchEvalPlan: Sendable {
    /// All suites to run.
    let suites: [EvalSuite]

    /// All models to evaluate against.
    let models: [EvalModelEntry]

    /// Average estimated seconds per prompt (rough heuristic).
    static let estimatedSecondsPerPrompt: Double = 30.0

    /// Total number of suites in this batch.
    var totalSuites: Int { suites.count }

    /// Total number of models to evaluate.
    var totalModels: Int { models.count }

    /// Total number of suite × model runs.
    var totalRuns: Int { suites.count * models.count }

    /// Total prompts across all suites × all models.
    var totalPrompts: Int {
        let promptsPerRound = suites.reduce(0) { $0 + $1.prompts.count }
        return promptsPerRound * models.count
    }

    /// Estimated total duration in seconds.
    var estimatedDurationSeconds: Double {
        Double(totalPrompts) * Self.estimatedSecondsPerPrompt
    }

    /// Human-readable estimated duration string.
    var estimatedDurationFormatted: String {
        let total = estimatedDurationSeconds
        if total < 60 {
            return "\(Int(total))s"
        } else if total < 3600 {
            let mins = Int(total / 60)
            return "\(mins) min"
        } else {
            let hours = Int(total / 3600)
            let mins = Int((total.truncatingRemainder(dividingBy: 3600)) / 60)
            return "\(hours)h \(mins)m"
        }
    }

    /// Human-readable description for confirmation UI.
    var description: String {
        let suiteWord = totalSuites == 1 ? "suite" : "suites"
        let modelWord = totalModels == 1 ? "model" : "models"
        return "\(totalSuites) \(suiteWord) × \(totalModels) \(modelWord) — \(totalPrompts) prompts (~\(estimatedDurationFormatted))"
    }
}

// MARK: - Batch Eval State

/// State of the batch evaluation orchestrator.
enum BatchEvalState: Sendable, Equatable {
    /// No batch evaluation in progress.
    case idle

    /// Running a specific suite against a specific model.
    case running(suiteIndex: Int, suiteName: String)

    /// All runs completed successfully.
    case complete(runsCompleted: Int)

    /// Batch cancelled by user.
    case cancelled(runsCompleted: Int)

    /// A run failed.
    case failed(String)

    /// Whether the orchestrator is actively working.
    var isActive: Bool {
        if case .running = self { return true }
        return false
    }

    /// Human-readable label for display.
    var displayLabel: String {
        switch self {
        case .idle:                             return "Ready"
        case .running(let idx, let name):       return "Running suite \(idx + 1): \(name)…"
        case .complete(let n):                  return "Complete — \(n) run\(n == 1 ? "" : "s") finished"
        case .cancelled(let n):                 return "Cancelled — \(n) run\(n == 1 ? "" : "s") finished"
        case .failed(let msg):                  return "Failed: \(msg)"
        }
    }
}

// MARK: - Batch Eval Orchestrator

/// Orchestrates sequential execution of all eval suites across all downloaded models.
///
/// Uses the existing `EvalRunner` for each individual suite × model run.
/// Provides aggregate progress tracking across all runs.
///
/// Usage:
/// ```swift
/// let orchestrator = BatchEvalOrchestrator(engine: engine, store: store)
/// let results = await orchestrator.runAll(plan: plan, flags: flags, cacheDir: dir)
/// ```
@Observable
@MainActor
final class BatchEvalOrchestrator {

    private static let logger = Logger(
        subsystem: "com.andrewvoirol.EdgeAILab",
        category: "batchEvalOrchestrator"
    )

    // MARK: - State

    /// Current orchestrator state.
    var state: BatchEvalState = .idle

    /// Number of completed suite×model runs.
    var completedRuns: Int = 0

    /// Total planned runs.
    var totalRuns: Int = 0

    /// The currently active EvalRunner (for progress tracking).
    var currentRunner: EvalRunner?

    /// All completed EvalRun results.
    var results: [EvalRun] = []

    /// Overall progress across all runs (0.0–1.0).
    var overallProgress: Double {
        guard totalRuns > 0 else { return 0 }
        let baseProgress = Double(completedRuns) / Double(totalRuns)
        let currentRunProgress = currentRunner?.overallProgress ?? 0
        let perRunFraction = 1.0 / Double(totalRuns)
        return baseProgress + (currentRunProgress * perRunFraction)
    }

    // MARK: - Dependencies

    private let engine: InstrumentedEngineProtocol
    private let store: EvalStore
    private var isCancelled = false

    init(engine: InstrumentedEngineProtocol, store: EvalStore) {
        self.engine = engine
        self.store = store
    }

    // MARK: - Run All

    /// Execute all suite × model combinations sequentially.
    ///
    /// - Parameters:
    ///   - plan: The batch plan describing what to run.
    ///   - flags: Experimental flags for the engine.
    ///   - cacheDir: Cache directory for the engine.
    /// - Returns: Array of completed `EvalRun` results.
    func runAll(
        plan: BatchEvalPlan,
        flags: ExperimentalFlagsState,
        cacheDir: String
    ) async -> [EvalRun] {
        isCancelled = false
        completedRuns = 0
        totalRuns = plan.totalRuns
        results = []
        state = .running(suiteIndex: 0, suiteName: plan.suites.first?.name ?? "")

        Self.logger.info("🚀 Starting batch eval: \(plan.description, privacy: .public)")

        for (suiteIndex, suite) in plan.suites.enumerated() {
            guard !isCancelled else { break }

            state = .running(suiteIndex: suiteIndex, suiteName: suite.name)

            let runner = EvalRunner(engine: engine, store: store)
            currentRunner = runner

            do {
                let run = try await runner.run(
                    suite: suite,
                    models: plan.models,
                    flags: flags,
                    cacheDir: cacheDir
                )
                results.append(run)
                completedRuns += 1

                Self.logger.info(
                    "✅ Completed suite \(suiteIndex + 1)/\(plan.totalSuites): \(suite.name, privacy: .public)"
                )
            } catch {
                Self.logger.error(
                    "❌ Suite \(suite.name, privacy: .public) failed: \(error.localizedDescription, privacy: .public)"
                )
                // Continue to next suite rather than aborting entire batch
                completedRuns += 1
            }
        }

        currentRunner = nil

        if isCancelled {
            state = .cancelled(runsCompleted: completedRuns)
            Self.logger.info("⚠️ Batch eval cancelled after \(self.completedRuns) run(s)")
        } else {
            state = .complete(runsCompleted: completedRuns)
            Self.logger.info("🏁 Batch eval complete: \(self.completedRuns) run(s)")
        }

        return results
    }

    /// Cancel the current batch evaluation.
    func cancel() {
        isCancelled = true
        currentRunner?.cancel()
    }
}
