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

import Testing
import Foundation
#if os(iOS)
@testable import EdgeAILab_iOS
#elseif os(macOS)
@testable import EdgeAILab_macOS
#endif

/// Aggregated coverage tests for error types, small enums, and
/// pure logic snippets across multiple source files.
@Suite("Error Descriptions & Small Coverage Gaps")
struct ErrorDescriptionCoverageTests {

    // MARK: - ConversationStoreError

    @Suite("ConversationStoreError")
    struct ConversationStoreErrorTests {
        @Test("saveFailed error description contains 'save'")
        func saveFailed() {
            let error = ConversationStoreError.saveFailed(NSError(domain: "test", code: 42))
            #expect(error.errorDescription?.contains("save") == true)
        }

        @Test("loadFailed error description contains 'load'")
        func loadFailed() {
            let error = ConversationStoreError.loadFailed(NSError(domain: "test", code: 42))
            #expect(error.errorDescription?.contains("load") == true)
        }

        @Test("deleteFailed error description contains 'delete'")
        func deleteFailed() {
            let error = ConversationStoreError.deleteFailed(NSError(domain: "test", code: 42))
            #expect(error.errorDescription?.contains("delete") == true)
        }

        @Test("notFound error description contains UUID")
        func notFound() {
            let id = UUID(uuidString: "12345678-1234-1234-1234-123456789012")!
            let error = ConversationStoreError.notFound(id)
            #expect(error.errorDescription?.contains("12345678") == true)
        }
    }

    // MARK: - ExpectedBehavior Display

    @Suite("ExpectedBehavior displayDescription")
    struct ExpectedBehaviorDisplayTests {
        @Test("containsAny shows alternatives")
        func containsAny() {
            let behavior = ExpectedBehavior.containsAny(["cat", "dog"])
            #expect(behavior.displayDescription.contains("cat"))
            #expect(behavior.displayDescription.contains("dog"))
        }

        @Test("containsAll shows required items")
        func containsAll() {
            let behavior = ExpectedBehavior.containsAll(["red", "blue"])
            #expect(behavior.displayDescription.contains("red"))
            #expect(behavior.displayDescription.contains("blue"))
        }

        @Test("toolCall shows tool name")
        func toolCall() {
            let behavior = ExpectedBehavior.toolCall(toolName: "get_weather")
            #expect(behavior.displayDescription.contains("get_weather"))
        }

        @Test("toolCallWithArgs shows tool, key, and value")
        func toolCallWithArgs() {
            let behavior = ExpectedBehavior.toolCallWithArgs(
                toolName: "search",
                key: "query",
                expectedValue: "hello"
            )
            let desc = behavior.displayDescription
            #expect(desc.contains("search"))
            #expect(desc.contains("query"))
            #expect(desc.contains("hello"))
        }

        @Test("toolCallChain shows ordered tools")
        func toolCallChain() {
            let behavior = ExpectedBehavior.toolCallChain(["search", "summarize"])
            #expect(behavior.displayDescription.contains("search"))
            #expect(behavior.displayDescription.contains("summarize"))
            #expect(behavior.displayDescription.contains("→"))
        }

        @Test("matchesRegex shows pattern")
        func matchesRegex() {
            let behavior = ExpectedBehavior.matchesRegex("\\d{4}")
            #expect(behavior.displayDescription.contains("\\d{4}"))
        }

        @Test("custom shows description")
        func custom() {
            let behavior = ExpectedBehavior.custom(description: "Check formatting")
            #expect(behavior.displayDescription.contains("Check formatting"))
        }

        @Test("nonEmpty has description")
        func nonEmpty() {
            let behavior = ExpectedBehavior.nonEmpty
            #expect(!behavior.displayDescription.isEmpty)
            #expect(behavior.displayDescription.contains("Non-empty"))
        }
    }

    // MARK: - ExpectedBehavior Properties

    @Suite("ExpectedBehavior isAutoScorable & involvesToolCalling")
    struct ExpectedBehaviorPropertiesTests {
        @Test("custom is not auto-scorable")
        func customNotAutoScorable() {
            #expect(ExpectedBehavior.custom(description: "test").isAutoScorable == false)
        }

        @Test("containsText is auto-scorable")
        func containsTextAutoScorable() {
            #expect(ExpectedBehavior.containsText("test").isAutoScorable == true)
        }

        @Test("toolCall involves tool calling")
        func toolCallInvolvesTools() {
            #expect(ExpectedBehavior.toolCall(toolName: "test").involvesToolCalling == true)
        }

        @Test("toolCallWithArgs involves tool calling")
        func toolCallWithArgsInvolvesTools() {
            #expect(ExpectedBehavior.toolCallWithArgs(toolName: "t", key: "k", expectedValue: "v").involvesToolCalling == true)
        }

        @Test("toolCallChain involves tool calling")
        func toolCallChainInvolvesTools() {
            #expect(ExpectedBehavior.toolCallChain(["a", "b"]).involvesToolCalling == true)
        }

        @Test("containsText does not involve tool calling")
        func containsTextNoTools() {
            #expect(ExpectedBehavior.containsText("test").involvesToolCalling == false)
        }

        @Test("nonEmpty does not involve tool calling")
        func nonEmptyNoTools() {
            #expect(ExpectedBehavior.nonEmpty.involvesToolCalling == false)
        }
    }

    // MARK: - EvalScore Display Properties

    @Suite("EvalScore displayLabel & symbolName & properties")
    struct EvalScoreDisplayTests {
        @Test("pass displayLabel is Pass")
        func passLabel() {
            #expect(EvalScore.pass.displayLabel == "Pass")
        }

        @Test("fail displayLabel is Fail")
        func failLabel() {
            #expect(EvalScore.fail(reason: "test").displayLabel == "Fail")
        }

        @Test("timeout displayLabel is Timeout")
        func timeoutLabel() {
            #expect(EvalScore.timeout.displayLabel == "Timeout")
        }

        @Test("error displayLabel is Error")
        func errorLabel() {
            #expect(EvalScore.error("crash").displayLabel == "Error")
        }

        @Test("manualReviewNeeded displayLabel")
        func manualReviewLabel() {
            #expect(EvalScore.manualReviewNeeded.displayLabel == "Needs Review")
        }

        @Test("pass isPass is true")
        func passIsPass() {
            #expect(EvalScore.pass.isPass == true)
        }

        @Test("fail isPass is false")
        func failNotPass() {
            #expect(EvalScore.fail(reason: "x").isPass == false)
        }

        @Test("fail isFailure is true")
        func failIsFailure() {
            #expect(EvalScore.fail(reason: "x").isFailure == true)
        }

        @Test("timeout isFailure is true")
        func timeoutIsFailure() {
            #expect(EvalScore.timeout.isFailure == true)
        }

        @Test("error isFailure is true")
        func errorIsFailure() {
            #expect(EvalScore.error("x").isFailure == true)
        }

        @Test("manualReviewNeeded is not failure")
        func manualReviewNotFailure() {
            #expect(EvalScore.manualReviewNeeded.isFailure == false)
        }

        @Test("pass has no reason")
        func passNoReason() {
            #expect(EvalScore.pass.reason == nil)
        }

        @Test("fail has reason")
        func failHasReason() {
            #expect(EvalScore.fail(reason: "wrong answer").reason == "wrong answer")
        }

        @Test("error has reason")
        func errorHasReason() {
            #expect(EvalScore.error("crashed").reason == "crashed")
        }

        @Test("timeout has reason")
        func timeoutHasReason() {
            #expect(EvalScore.timeout.reason == "Inference timed out")
        }

        @Test("Each score has a non-empty symbol name")
        func symbolNames() {
            #expect(!EvalScore.pass.symbolName.isEmpty)
            #expect(!EvalScore.fail(reason: "").symbolName.isEmpty)
            #expect(!EvalScore.timeout.symbolName.isEmpty)
            #expect(!EvalScore.error("").symbolName.isEmpty)
            #expect(!EvalScore.manualReviewNeeded.symbolName.isEmpty)
        }
    }

    // MARK: - EvalCategory

    @Suite("EvalCategory properties")
    struct EvalCategoryTests {
        @Test("All cases have non-empty displayName")
        func displayNames() {
            for cat in EvalCategory.allCases {
                #expect(!cat.displayName.isEmpty)
            }
        }

        @Test("All cases have a symbolName")
        func symbolNames() {
            for cat in EvalCategory.allCases {
                #expect(!cat.symbolName.isEmpty)
            }
        }

        @Test("Codable round-trip preserves value")
        func codable() throws {
            for cat in EvalCategory.allCases {
                let data = try JSONEncoder().encode(cat)
                let decoded = try JSONDecoder().decode(EvalCategory.self, from: data)
                #expect(decoded == cat)
            }
        }
    }

    // MARK: - EvalRun Computed Properties

    @Suite("EvalRun computed properties")
    struct EvalRunComputedTests {
        private func makeRun(
            completedAt: Date? = nil,
            modelResults: [ModelEvalResult] = []
        ) -> EvalRun {
            EvalRun(
                suiteId: UUID(),
                suiteName: "Test",
                startedAt: Date(timeIntervalSince1970: 1000),
                completedAt: completedAt,
                platform: "macOS",
                deviceName: "Test",
                modelResults: modelResults
            )
        }

        @Test("isComplete is true when completedAt is set")
        func isComplete() {
            let run = makeRun(completedAt: Date(timeIntervalSince1970: 1060))
            #expect(run.isComplete == true)
        }

        @Test("isComplete is false when completedAt is nil")
        func isNotComplete() {
            let run = makeRun()
            #expect(run.isComplete == false)
        }

        @Test("duration calculates correctly")
        func duration() {
            let run = makeRun(completedAt: Date(timeIntervalSince1970: 1060))
            #expect(run.duration == 60.0)
        }

        @Test("duration is nil when not complete")
        func durationNil() {
            let run = makeRun()
            #expect(run.duration == nil)
        }

        @Test("formattedDuration shows minutes and seconds")
        func formattedDuration() {
            let run = makeRun(completedAt: Date(timeIntervalSince1970: 1094))
            // 94 seconds = 1m 34s
            #expect(run.formattedDuration == "1m 34s")
        }

        @Test("formattedDuration shows In progress for incomplete")
        func formattedDurationInProgress() {
            let run = makeRun()
            #expect(run.formattedDuration.contains("progress"))
        }

        @Test("modelCount returns correct value")
        func modelCount() {
            let model = ModelEvalResult(
                modelName: "Test",
                modelFile: "test.litertlm",
                avgDecodeSpeed: 42.0,
                avgTTFT: 0.5,
                p95Latency: 25.0,
                totalTokensGenerated: 100,
                totalDuration: 10.0,
                promptResults: []
            )
            let run = makeRun(modelResults: [model])
            #expect(run.modelCount == 1)
        }
    }
}
