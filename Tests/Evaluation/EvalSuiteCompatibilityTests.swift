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
import Testing

#if os(iOS)
@testable import EdgeAILab_iOS
#elseif os(macOS)
@testable import EdgeAILab_macOS
#endif

// MARK: - Basic Compatibility

@Suite("EvalSuiteCompatibility — Basic")
struct BasicCompatibilityTests {

    @Test("nil profile returns .unknown")
    func nilProfileReturnsUnknown() {
        let suite = makeSuite(category: .general)
        let status = EvalSuiteCompatibility.check(suite: suite, profile: nil)
        if case .unknown = status { /* pass */ } else {
            Issue.record("Expected .unknown, got \(status)")
        }
    }

    @Test("text-only suite is compatible with text-only model")
    func textOnlyCompatible() {
        let suite = makeSuite(category: .general)
        let profile = makeEvalProfile()
        let status = EvalSuiteCompatibility.check(suite: suite, profile: profile)
        if case .compatible = status { /* pass */ } else {
            Issue.record("Expected .compatible, got \(status)")
        }
    }

    @Test("compatible status can run")
    func compatibleCanRun() {
        let status = EvalSuiteCompatibilityStatus.compatible
        #expect(status.canRun == true)
    }

    @Test("incompatible status cannot run")
    func incompatibleCannotRun() {
        let status = EvalSuiteCompatibilityStatus.incompatible(reasons: ["test"])
        #expect(status.canRun == false)
    }

    @Test("unknown status cannot run")
    func unknownCannotRun() {
        let status = EvalSuiteCompatibilityStatus.unknown
        #expect(status.canRun == false)
    }

    @Test("partially compatible can run")
    func partialCanRun() {
        let status = EvalSuiteCompatibilityStatus.partiallyCompatible(reasons: ["test"])
        #expect(status.canRun == true)
    }
}

// MARK: - Multimodal Compatibility

@Suite("EvalSuiteCompatibility — Multimodal")
struct MultimodalCompatibilityTests {

    @Test("multimodal suite incompatible with text-only model")
    func multimodalIncompatible() {
        let suite = makeSuite(category: .multimodal)
        let profile = makeEvalProfile(supportsVision: false, supportsAudio: false)
        let status = EvalSuiteCompatibility.check(suite: suite, profile: profile)
        if case .incompatible = status { /* pass */ } else {
            Issue.record("Expected .incompatible, got \(status)")
        }
    }

    @Test("multimodal suite compatible with vision model")
    func multimodalWithVision() {
        let suite = makeSuite(category: .multimodal)
        let profile = makeEvalProfile(supportsVision: true, supportsAudio: false)
        let status = EvalSuiteCompatibility.check(suite: suite, profile: profile)
        if case .compatible = status { /* pass */ } else {
            Issue.record("Expected .compatible, got \(status)")
        }
    }

    @Test("multimodal suite compatible with audio model")
    func multimodalWithAudio() {
        let suite = makeSuite(category: .multimodal)
        let profile = makeEvalProfile(supportsVision: false, supportsAudio: true)
        let status = EvalSuiteCompatibility.check(suite: suite, profile: profile)
        if case .compatible = status { /* pass */ } else {
            Issue.record("Expected .compatible, got \(status)")
        }
    }
}

// MARK: - Tool Calling Compatibility

@Suite("EvalSuiteCompatibility — Tool Calling")
struct ToolCallingCompatibilityTests {

    @Test("tool calling suite incompatible without tool calling")
    func toolCallingSuiteIncompatible() {
        let suite = makeSuite(
            category: .toolCalling,
            prompts: [makeToolCallingPrompt(), makeToolCallingPrompt()]
        )
        let profile = makeEvalProfile(supportsToolCalling: false)
        let status = EvalSuiteCompatibility.check(suite: suite, profile: profile)
        if case .incompatible = status { /* pass */ } else {
            Issue.record("Expected .incompatible, got \(status)")
        }
    }

    @Test("tool calling suite compatible with tool calling model")
    func toolCallingSuiteCompatible() {
        let suite = makeSuite(
            category: .toolCalling,
            prompts: [makeToolCallingPrompt(), makeToolCallingPrompt()]
        )
        let profile = makeEvalProfile(supportsToolCalling: true)
        let status = EvalSuiteCompatibility.check(suite: suite, profile: profile)
        if case .compatible = status { /* pass */ } else {
            Issue.record("Expected .compatible, got \(status)")
        }
    }

    @Test("mixed suite partially compatible without tool calling")
    func mixedSuitePartiallyCompatible() {
        let suite = makeSuite(
            category: .general,
            prompts: [makeTextPrompt(), makeToolCallingPrompt()]
        )
        let profile = makeEvalProfile(supportsToolCalling: false)
        let status = EvalSuiteCompatibility.check(suite: suite, profile: profile)
        if case .partiallyCompatible = status { /* pass */ } else {
            Issue.record("Expected .partiallyCompatible, got \(status)")
        }
    }
}

// MARK: - Filtering

@Suite("EvalSuiteCompatibility — Filtering")
struct FilteringTests {

    @Test("filterCompatible removes incompatible suites")
    func filterRemovesIncompatible() {
        let textSuite = makeSuite(name: "Text", category: .general)
        let multimodalSuite = makeSuite(name: "Vision", category: .multimodal)
        let suites = [textSuite, multimodalSuite]

        let profile = makeEvalProfile(supportsVision: false, supportsAudio: false)
        let filtered = EvalSuiteCompatibility.filterCompatible(suites: suites, profile: profile)
        #expect(filtered.count == 1)
        #expect(filtered.first?.name == "Text")
    }

    @Test("filterCompatible returns all when no profile")
    func filterReturnsAllWithoutProfile() {
        let suites = [makeSuite(name: "A", category: .general), makeSuite(name: "B", category: .multimodal)]
        let filtered = EvalSuiteCompatibility.filterCompatible(suites: suites, profile: nil)
        #expect(filtered.count == 2)
    }

    @Test("annotate returns statuses for all suites")
    func annotateReturnsAll() {
        let suites = [makeSuite(name: "A", category: .general), makeSuite(name: "B", category: .multimodal)]
        let profile = makeEvalProfile(supportsVision: false, supportsAudio: false)
        let annotated = EvalSuiteCompatibility.annotate(suites: suites, profile: profile)
        #expect(annotated.count == 2)
    }
}

// MARK: - Display Properties

@Suite("EvalSuiteCompatibilityStatus — Display")
struct DisplayTests {

    @Test("compatible display summary")
    func compatibleSummary() {
        let status = EvalSuiteCompatibilityStatus.compatible
        #expect(status.displaySummary == "Compatible")
        #expect(status.symbolName == "checkmark.seal.fill")
    }

    @Test("incompatible display summary")
    func incompatibleSummary() {
        let status = EvalSuiteCompatibilityStatus.incompatible(reasons: ["No vision"])
        #expect(status.displaySummary.contains("No vision"))
        #expect(status.symbolName == "xmark.seal.fill")
    }

    @Test("unknown display summary")
    func unknownSummary() {
        let status = EvalSuiteCompatibilityStatus.unknown
        #expect(status.displaySummary == "Compatibility unknown")
    }
}

// MARK: - Test Helpers

/// Creates a minimal EvalSuite for testing.
private func makeSuite(
    name: String = "Test Suite",
    category: EvalCategory = .general,
    prompts: [EvalPrompt]? = nil
) -> EvalSuite {
    EvalSuite(
        name: name,
        description: "Test suite",
        category: category,
        prompts: prompts ?? [makeTextPrompt()],
        isBuiltIn: true
    )
}

/// Creates a text-only eval prompt.
private func makeTextPrompt() -> EvalPrompt {
    EvalPrompt(
        prompt: "What is 2+2?",
        expectedBehavior: .containsText("4"),
        timeoutSeconds: 30
    )
}

/// Creates a tool-calling eval prompt.
private func makeToolCallingPrompt() -> EvalPrompt {
    EvalPrompt(
        prompt: "Use the calculator to compute 2+2",
        expectedBehavior: .toolCall(toolName: "calculator"),
        timeoutSeconds: 30
    )
}

/// Creates a minimal ModelCapabilityProfile for eval testing.
private func makeEvalProfile(
    supportsVision: Bool = false,
    supportsAudio: Bool = false,
    supportsThinking: Bool = true,
    supportsToolCalling: Bool = true
) -> ModelCapabilityProfile {
    ModelCapabilityProfile(
        id: "test/model",
        displayName: "Test Model",
        repoId: nil,
        runtimeType: .litertlm,
        supportsVision: SourcedValue(supportsVision, source: .configJSON),
        supportsAudio: SourcedValue(supportsAudio, source: .configJSON),
        supportsThinking: SourcedValue(supportsThinking, source: .heuristic),
        supportsToolCalling: SourcedValue(supportsToolCalling, source: .heuristic),
        supportsMTP: nil,
        supportsConstrainedDecoding: nil,
        architecture: nil,
        contextWindow: nil,
        fileSizeBytes: nil,
        estimatedMemoryGB: nil,
        totalParameters: nil,
        parameterLabel: nil,
        confidence: .medium,
        source: .huggingFaceInferred,
        lastUpdated: Date(),
        repoSha: nil,
        license: nil,
        licenseLink: nil,
        baseModelId: nil,
        downloads: nil,
        likes: nil,
        downloadsAllTime: nil,
        supportedLanguages: [],
        tags: [],
        defaultConfig: nil,
        platformSupport: nil,
        modelDescription: nil,
        recommendedFor: nil,
        modelFile: nil,
        modelId: nil
    )
}
