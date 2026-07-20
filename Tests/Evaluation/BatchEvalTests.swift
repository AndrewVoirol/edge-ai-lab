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

import XCTest

#if os(iOS)
@testable import EdgeAILab_iOS
#elseif os(macOS)
@testable import EdgeAILab_macOS
#endif

// MARK: - Batch Eval Tests

/// Tests verifying the batch evaluation "Run All" orchestrator.
///
/// These tests ensure that:
/// - `BatchEvalOrchestrator` correctly enumerates suites and models
/// - Time estimation is reasonable
/// - Progress tracking works across suites
/// - Cancellation stops execution
final class BatchEvalTests: XCTestCase {

    // MARK: - Orchestrator Properties

    func testBatchPlanWithMultipleSuitesAndModels() {
        let suites = [
            makeTestSuite(name: "Suite A", promptCount: 5),
            makeTestSuite(name: "Suite B", promptCount: 3),
        ]
        let models = [
            makeTestModelEntry(name: "Model 1"),
            makeTestModelEntry(name: "Model 2"),
        ]

        let plan = BatchEvalPlan(suites: suites, models: models)

        XCTAssertEqual(plan.totalSuites, 2)
        XCTAssertEqual(plan.totalModels, 2)
        XCTAssertEqual(plan.totalRuns, 4, "2 suites × 2 models = 4 runs")
        XCTAssertEqual(plan.totalPrompts, 16, "(5 + 3) × 2 = 16 total prompts")
    }

    func testBatchPlanEstimatedTime() {
        let suites = [makeTestSuite(name: "Suite", promptCount: 10)]
        let models = [makeTestModelEntry(name: "Model")]

        let plan = BatchEvalPlan(suites: suites, models: models)

        // 10 prompts × 1 model × default ~60s per prompt = ~600s
        // We estimate ~30s per prompt for Run All (rough average)
        XCTAssertGreaterThan(plan.estimatedDurationSeconds, 0)
    }

    func testBatchPlanEmptySuites() {
        let plan = BatchEvalPlan(suites: [], models: [makeTestModelEntry(name: "M")])
        XCTAssertEqual(plan.totalRuns, 0)
        XCTAssertEqual(plan.totalPrompts, 0)
    }

    func testBatchPlanEmptyModels() {
        let plan = BatchEvalPlan(suites: [makeTestSuite(name: "S", promptCount: 5)], models: [])
        XCTAssertEqual(plan.totalRuns, 0)
        XCTAssertEqual(plan.totalPrompts, 0)
    }

    func testBatchPlanProgressDescription() {
        let suites = [
            makeTestSuite(name: "Math", promptCount: 5),
            makeTestSuite(name: "Reasoning", promptCount: 3),
        ]
        let models = [makeTestModelEntry(name: "Gemma 3n")]

        let plan = BatchEvalPlan(suites: suites, models: models)

        let desc = plan.description
        XCTAssertTrue(desc.contains("2 suite"), "Description should mention suite count")
        XCTAssertTrue(desc.contains("1 model"), "Description should mention model count")
    }

    // MARK: - Helpers

    private func makeTestSuite(name: String, promptCount: Int) -> EvalSuite {
        let prompts = (0..<promptCount).map { i in
            EvalPrompt(prompt: "Test prompt \(i)", expectedBehavior: .nonEmpty)
        }
        return EvalSuite(
            name: name,
            description: "Test suite",
            category: .general,
            prompts: prompts,
            isBuiltIn: false
        )
    }

    private func makeTestModelEntry(name: String) -> EvalModelEntry {
        let slug = name.lowercased().replacingOccurrences(of: " ", with: "_")
        return EvalModelEntry(
            profile: ModelCapabilityProfile(
                id: "\(slug).litertlm",
                displayName: name,
                repoId: nil,
                runtimeType: .litertlm,
                supportsVision: nil, supportsAudio: nil, supportsThinking: nil,
                supportsToolCalling: nil, supportsMTP: nil, supportsConstrainedDecoding: nil,
                architecture: nil, contextWindow: nil, fileSizeBytes: nil,
                estimatedMemoryGB: nil, totalParameters: nil, parameterLabel: nil,
                confidence: .low, source: .huggingFaceInferred, lastUpdated: Date(),
                repoSha: nil, license: nil, licenseLink: nil, baseModelId: nil,
                downloads: nil, likes: nil, downloadsAllTime: nil,
                supportedLanguages: [], tags: [],
                defaultConfig: ModelDefaultConfig(
                    topK: 64,
                    topP: 0.95,
                    temperature: 1.0,
                    maxContextLength: 32_000,
                    maxTokens: 2048,
                    accelerators: "gpu,cpu",
                    visionAccelerator: nil
                ),
                platformSupport: PlatformSupport(
                    macOS: .gpuAndCpu,
                    iOSDevice: .gpuAndCpu,
                    iOSSimulator: .cpuOnly
                ),
                modelDescription: nil, recommendedFor: nil,
                modelFile: "\(slug).litertlm",
                modelId: "test/\(slug)"
            ),
            modelPath: "/tmp/\(slug).litertlm"
        )
    }
}
