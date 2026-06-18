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

import Testing
import Foundation

#if os(iOS)
@testable import EdgeAILab_iOS
#elseif os(macOS)
@testable import EdgeAILab_macOS
#endif

// MARK: - Eval Pipeline Integration Tests (Swift Testing)

/// Validates the eval pipeline integration end-to-end.
///
/// These tests verify that built-in suites are well-formed, eval results
/// serialize correctly, and the pipeline components compose properly.
///
/// ## Pattern
/// Uses Swift Testing (`@Test`/`@Suite`) per project conventions.
/// Existing XCTest eval tests cover individual type behavior; these tests
/// focus on cross-cutting pipeline concerns.
@Suite("Eval Pipeline")
struct EvalPipelineTests {

    // MARK: - Built-In Suite Validation

    @Test("All built-in suites have at least 1 prompt with a valid scoring method")
    func testBuiltInSuitesAllHaveValidScoringMethods() {
        let suites = BuiltInEvalSuites.allBuiltIn

        for suite in suites {
            #expect(!suite.prompts.isEmpty,
                    "Suite '\(suite.name)' must have at least 1 prompt")

            // Verify every prompt has a recognized ExpectedBehavior case
            for prompt in suite.prompts {
                let description = prompt.expectedBehavior.displayDescription
                #expect(!description.isEmpty,
                        "Prompt '\(prompt.truncatedPrompt)' in suite '\(suite.name)' has no display description for its scoring method")
            }
        }
    }

    @Test("All built-in suites have non-empty name and category")
    func testBuiltInSuitesHaveNonEmptyNames() {
        let suites = BuiltInEvalSuites.allBuiltIn

        for suite in suites {
            #expect(!suite.name.isEmpty,
                    "Suite id=\(suite.id) must have a non-empty name")
            #expect(!suite.category.displayName.isEmpty,
                    "Suite '\(suite.name)' must have a non-empty category display name")
            #expect(!suite.category.rawValue.isEmpty,
                    "Suite '\(suite.name)' must have a non-empty category raw value")
        }
    }

    // MARK: - Serialization

    @Test("EvalRun results serialize to valid JSON")
    func testEvalResultsSerializeToJSON() throws {
        let suiteId = UUID()
        let promptId = UUID()

        let promptResult = PromptEvalResult(
            promptId: promptId,
            promptText: "What is 2+2?",
            response: "The answer is 4.",
            passed: true,
            score: .pass,
            decodeSpeed: 45.0,
            ttft: 0.5,
            duration: 1.2
        )

        let modelResult = ModelEvalResult(
            modelName: "Gemma 4 E2B",
            modelFile: "gemma-4-E2B-it.bin",
            avgDecodeSpeed: 45.0,
            avgTTFT: 0.5,
            p95Latency: 12.0,
            totalTokensGenerated: 512,
            totalDuration: 60.0,
            promptResults: [promptResult]
        )

        let run = EvalRun(
            suiteId: suiteId,
            suiteName: "Pipeline Test Suite",
            suiteCategory: .math,
            startedAt: Date(timeIntervalSince1970: 1000),
            completedAt: Date(timeIntervalSince1970: 1060),
            platform: "macOS",
            deviceName: "Test Mac",
            modelResults: [modelResult]
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(run)
        #expect(data.count > 0, "Encoded JSON data should not be empty")

        // Verify it's valid JSON by parsing back to a dictionary
        let jsonObject = try JSONSerialization.jsonObject(with: data)
        let dict = try #require(jsonObject as? [String: Any],
                                "Serialized EvalRun should decode as a JSON dictionary")

        #expect(dict["suiteName"] as? String == "Pipeline Test Suite")
        #expect(dict["platform"] as? String == "macOS")
        #expect(dict["deviceName"] as? String == "Test Mac")

        // Verify modelResults array is present
        let modelResults = try #require(dict["modelResults"] as? [[String: Any]],
                                        "JSON should contain modelResults array")
        #expect(modelResults.count == 1)
        #expect(modelResults[0]["modelName"] as? String == "Gemma 4 E2B")
    }

    // MARK: - Pipeline Dry Run

    @Test("BuiltInEvalSuites.allBuiltIn loads without error and returns > 0 suites")
    func testPipelineDryRunValidatesSuiteLoading() {
        let suites = BuiltInEvalSuites.allBuiltIn

        #expect(suites.count > 0,
                "BuiltInEvalSuites.allBuiltIn should return at least 1 suite")

        // Verify each suite is independently valid for pipeline consumption
        for suite in suites {
            #expect(!suite.id.uuidString.isEmpty,
                    "Suite '\(suite.name)' must have a valid UUID")
            #expect(suite.promptCount > 0,
                    "Suite '\(suite.name)' must have at least 1 prompt for the pipeline to run")
            #expect(suite.estimatedDurationSeconds > 0,
                    "Suite '\(suite.name)' must have a positive estimated duration")
        }
    }

    // MARK: - History File Format

    @Test("Eval history entry serializes to JSON with expected structure")
    func testEvalHistoryFileFormat() throws {
        let suiteId = UUID()
        let start = Date(timeIntervalSince1970: 5000)
        let end = Date(timeIntervalSince1970: 5200)

        let promptResult = PromptEvalResult(
            promptId: UUID(),
            promptText: "Convert 72°F to Celsius",
            response: "22.2°C",
            passed: true,
            score: .pass,
            decodeSpeed: 38.5,
            ttft: 0.65,
            duration: 2.1
        )

        let modelResult = ModelEvalResult(
            modelName: "Gemma Test Model",
            modelFile: "gemma-test.litertlm",
            avgDecodeSpeed: 38.5,
            avgTTFT: 0.65,
            p95Latency: 15.0,
            totalTokensGenerated: 256,
            totalDuration: 45.0,
            promptResults: [promptResult],
            peakMemoryDeltaMB: 128.0,
            thermalTransitions: 1
        )

        let run = EvalRun(
            suiteId: suiteId,
            suiteName: "History Format Test",
            suiteCategory: .general,
            startedAt: start,
            completedAt: end,
            platform: "iOS",
            deviceName: "iPhone 16 Pro",
            modelResults: [modelResult]
        )

        // Create the index entry (this is what gets written to index.json)
        let entry = EvalRunIndexEntry(from: run)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // Verify the index entry round-trips
        let entryData = try encoder.encode(entry)
        let decodedEntry = try decoder.decode(EvalRunIndexEntry.self, from: entryData)

        #expect(decodedEntry.id == run.id)
        #expect(decodedEntry.suiteName == "History Format Test")
        #expect(decodedEntry.modelCount == 1)
        #expect(decodedEntry.platform == "iOS")
        #expect(decodedEntry.deviceName == "iPhone 16 Pro")
        #expect(decodedEntry.isComplete)
        #expect(decodedEntry.overallPassRate == 1.0)

        // Verify the full run also round-trips
        let runData = try encoder.encode(run)
        let decodedRun = try decoder.decode(EvalRun.self, from: runData)

        #expect(decodedRun.suiteId == suiteId)
        #expect(decodedRun.suiteName == "History Format Test")
        #expect(decodedRun.suiteCategory == .general)
        #expect(decodedRun.modelResults.count == 1)
        #expect(decodedRun.modelResults[0].promptResults.count == 1)
        #expect(decodedRun.modelResults[0].promptResults[0].passed)
        #expect(decodedRun.modelResults[0].peakMemoryDeltaMB == 128.0)
        #expect(decodedRun.modelResults[0].thermalTransitions == 1)
    }

    // MARK: - Prompt Count Consistency

    @Test("suite.promptCount matches suite.prompts.count for all built-in suites")
    func testEvalSuitePromptCountMatchesPrompts() {
        let suites = BuiltInEvalSuites.allBuiltIn

        for suite in suites {
            #expect(suite.promptCount == suite.prompts.count,
                    "Suite '\(suite.name)': promptCount (\(suite.promptCount)) should equal prompts.count (\(suite.prompts.count))")
        }
    }
}
