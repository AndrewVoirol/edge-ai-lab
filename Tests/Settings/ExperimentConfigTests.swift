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

/// Tests for `ExperimentConfig` — the frozen experiment configuration snapshot.
final class ExperimentConfigTests: XCTestCase {

    // MARK: - Codable Round-Trip

    func testCodableRoundTrip() throws {
        let config = makeTestConfig()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(config)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ExperimentConfig.self, from: data)

        XCTAssertEqual(decoded.modelName, config.modelName)
        XCTAssertEqual(decoded.modelFile, config.modelFile)
        XCTAssertEqual(decoded.backend, config.backend)
        XCTAssertEqual(decoded.thinkingEnabled, config.thinkingEnabled)
        XCTAssertEqual(decoded.toolCallingEnabled, config.toolCallingEnabled)
        XCTAssertEqual(decoded.temperature, config.temperature)
    }

    // MARK: - Short Name Parsing

    func testModelShortNameE2B() {
        let config = makeTestConfig(modelName: "Gemma 4 E2B · Desktop GPU+CPU")
        XCTAssertEqual(config.modelShortName, "E2B")
    }

    func testModelShortName12B() {
        let config = makeTestConfig(modelName: "Gemma 4 12B · Desktop GPU")
        XCTAssertEqual(config.modelShortName, "12B")
    }

    func testModelShortNameE4B() {
        let config = makeTestConfig(modelName: "Gemma 4 E4B · Desktop GPU+CPU")
        XCTAssertEqual(config.modelShortName, "E4B")
    }

    func testModelShortNameFallback() {
        let config = makeTestConfig(modelName: "Custom Model")
        XCTAssertEqual(config.modelShortName, "Custom")
    }

    // MARK: - Light Summary

    func testLightSummaryBasic() {
        let config = makeTestConfig(
            modelName: "Gemma 4 E2B",
            backend: "GPU",
            thinkingEnabled: true,
            toolCallingEnabled: false
        )
        XCTAssertTrue(config.lightSummary.contains("E2B"))
        XCTAssertTrue(config.lightSummary.contains("GPU"))
        XCTAssertTrue(config.lightSummary.contains("Thinking"))
        XCTAssertFalse(config.lightSummary.contains("Tools"))
    }

    func testLightSummaryWithTools() {
        let config = makeTestConfig(toolCallingEnabled: true)
        XCTAssertTrue(config.lightSummary.contains("Tools"))
    }

    func testLightSummaryWithFallback() {
        let config = makeTestConfig(didFallback: true)
        XCTAssertTrue(config.lightSummary.contains("Fallback"))
    }

    // MARK: - Variant Parsing

    func testParseVariantIT() {
        XCTAssertEqual(ExperimentConfig.parseVariant(from: "gemma-4-E2B-it.litertlm"), "IT")
    }

    func testParseVariantWebIT() {
        let result = ExperimentConfig.parseVariant(from: "gemma-4-E2B-it-web.litertlm")
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.contains("IT"))
        XCTAssertTrue(result!.contains("Web"))
    }

    func testParseVariantHW() {
        let result = ExperimentConfig.parseVariant(from: "gemma-3n-E2B-HW.litertlm")
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.contains("HW"))
    }

    func testParseVariantNone() {
        XCTAssertNil(ExperimentConfig.parseVariant(from: "some-model.litertlm"))
    }

    // MARK: - Active Feature Badges

    func testActiveFeatureBadgesEmpty() {
        let config = makeTestConfig(
            thinkingEnabled: false,
            toolCallingEnabled: false,
            mtpEnabled: false,
            agentSkillsEnabled: false
        )
        XCTAssertTrue(config.activeFeatureBadges.isEmpty)
    }

    func testActiveFeatureBadgesAll() {
        let config = makeTestConfig(
            thinkingEnabled: true,
            toolCallingEnabled: true,
            mtpEnabled: true,
            agentSkillsEnabled: true
        )
        XCTAssertEqual(config.activeFeatureBadges.count, 4)
    }

    // MARK: - Helpers

    private func makeTestConfig(
        modelName: String = "Test Model E2B",
        modelFile: String = "test-model.litertlm",
        backend: String = "GPU",
        didFallback: Bool = false,
        thinkingEnabled: Bool = true,
        toolCallingEnabled: Bool = false,
        mtpEnabled: Bool = false,
        agentSkillsEnabled: Bool = false
    ) -> ExperimentConfig {
        ExperimentConfig(
            modelName: modelName,
            modelFile: modelFile,
            modelId: "test/test-model",
            architectureType: "Dense",
            modelVariant: "IT",
            backend: backend,
            didFallback: didFallback,
            temperature: 1.0,
            topK: 64,
            topP: 0.95,
            seed: 0,
            thinkingEnabled: thinkingEnabled,
            toolCallingEnabled: toolCallingEnabled,
            agentSkillsEnabled: agentSkillsEnabled,
            mtpEnabled: mtpEnabled,
            benchmarkEnabled: true,
            systemMessage: nil,
            createdAt: Date()
        )
    }
}
