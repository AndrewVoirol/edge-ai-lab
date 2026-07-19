// Copyright 2026 Andrew Voirol. Apache-2.0
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0

import XCTest

#if os(iOS)
@testable import EdgeAILab_iOS
#elseif os(macOS)
@testable import EdgeAILab_macOS
#endif

/// Tests for InferenceConfigSnapshot — the per-message config proof.
final class InferenceConfigSnapshotTests: XCTestCase {

    // MARK: - Summary Generation

    func testSummary_AllFeaturesOn() {
        let snapshot = InferenceConfigSnapshot(
            modelName: "Gemma 4 E2B",
            runtimeType: "LiteRT-LM",
            computeBackend: "GPU (Metal)",
            thinkingEnabled: true,
            mtpEnabled: true,
            constrainedDecodingEnabled: true,
            toolCallingEnabled: true,
            temperature: 0.6,
            topK: 64,
            topP: 0.95,
            seed: 42
        )

        let summary = snapshot.summary
        XCTAssertTrue(summary.contains("Gemma 4 E2B"), "Should contain model name")
        XCTAssertTrue(summary.contains("GPU (Metal)"), "Should contain compute backend")
        XCTAssertTrue(summary.contains("Think ✓"), "Should contain thinking flag")
        XCTAssertTrue(summary.contains("Spec Dec ✓"), "Should contain speculative decoding flag")
        XCTAssertTrue(summary.contains("Structured ✓"), "Should contain structured output flag")
        XCTAssertTrue(summary.contains("Tools ✓"), "Should contain tools flag")
    }

    func testSummary_NoFeaturesOn() {
        let snapshot = InferenceConfigSnapshot(
            modelName: "Gemma 4 E2B",
            runtimeType: "MLX",
            computeBackend: "GPU (Metal)",
            thinkingEnabled: false,
            mtpEnabled: false,
            constrainedDecodingEnabled: false,
            toolCallingEnabled: false,
            temperature: 1.0,
            topK: 64,
            topP: 0.95,
            seed: 0
        )

        let summary = snapshot.summary
        XCTAssertTrue(summary.contains("Gemma 4 E2B"))
        XCTAssertFalse(summary.contains("Think ✓"))
        XCTAssertFalse(summary.contains("Spec Dec ✓"))
    }

    // MARK: - Detailed Lines

    func testDetailedLines_AllFields() {
        let snapshot = InferenceConfigSnapshot(
            modelName: "Test Model",
            runtimeType: "LiteRT-LM",
            computeBackend: "GPU (Metal)",
            thinkingEnabled: true,
            mtpEnabled: false,
            constrainedDecodingEnabled: true,
            toolCallingEnabled: false,
            temperature: 0.7,
            topK: 32,
            topP: 0.9,
            seed: 42
        )

        let lines = snapshot.detailedLines
        let labels = lines.map(\.label)
        XCTAssertTrue(labels.contains("Model"))
        XCTAssertTrue(labels.contains("Engine"))
        XCTAssertTrue(labels.contains("Compute"))
        XCTAssertTrue(labels.contains("Thinking"))
        XCTAssertTrue(labels.contains("Temperature"))
        XCTAssertTrue(labels.contains("Top-K"))
        XCTAssertTrue(labels.contains("Seed"))

        // Verify values
        let dict = Dictionary(uniqueKeysWithValues: lines)
        XCTAssertEqual(dict["Thinking"], "On")
        XCTAssertEqual(dict["Spec. Decoding"], "Off")
        XCTAssertEqual(dict["Seed"], "42")
    }

    func testDetailedLines_SeedZero_ShowsRandom() {
        let snapshot = InferenceConfigSnapshot(
            modelName: nil,
            runtimeType: nil,
            computeBackend: nil,
            thinkingEnabled: nil,
            mtpEnabled: nil,
            constrainedDecodingEnabled: nil,
            toolCallingEnabled: nil,
            temperature: nil,
            topK: nil,
            topP: nil,
            seed: 0
        )

        let dict = Dictionary(uniqueKeysWithValues: snapshot.detailedLines)
        XCTAssertEqual(dict["Seed"], "Random")
    }

    // MARK: - Factory

    func testCapture_FromFlags() {
        let flags = RuntimeFlags(
            enableThinking: true,
            enableToolCalling: true,
            enableAgentSkills: false,
            enableSpeculativeDecoding: true,
            enableConversationConstrainedDecoding: false
        )

        let snapshot = InferenceConfigSnapshot.capture(
            modelName: "Test Model",
            runtimeType: .litertlm,
            computeBackend: "GPU (Metal)",
            flags: flags,
            temperature: 0.8,
            topK: 40,
            topP: 0.95,
            seed: 123
        )

        XCTAssertEqual(snapshot.modelName, "Test Model")
        XCTAssertEqual(snapshot.runtimeType, "LiteRT-LM")
        XCTAssertEqual(snapshot.thinkingEnabled, true)
        XCTAssertEqual(snapshot.mtpEnabled, true)
        XCTAssertEqual(snapshot.constrainedDecodingEnabled, false)
        XCTAssertEqual(snapshot.toolCallingEnabled, true)
        XCTAssertEqual(snapshot.temperature, 0.8)
        XCTAssertEqual(snapshot.topK, 40)
        XCTAssertEqual(snapshot.seed, 123)
    }

    // MARK: - Codable

    func testCodable_RoundTrip() throws {
        let original = InferenceConfigSnapshot(
            modelName: "Gemma 4 E2B",
            runtimeType: "MLX",
            computeBackend: "GPU (Metal)",
            thinkingEnabled: true,
            mtpEnabled: false,
            constrainedDecodingEnabled: false,
            toolCallingEnabled: true,
            temperature: 0.6,
            topK: 64,
            topP: 0.95,
            seed: 42
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(InferenceConfigSnapshot.self, from: encoded)
        XCTAssertEqual(original, decoded, "Round-trip should produce equal snapshot")
    }

    func testCodable_MissingFields_DefaultsToNil() throws {
        // Simulate old JSON without inferenceConfig field
        let json = "{}"
        let data = json.data(using: .utf8)!
        let snapshot = try JSONDecoder().decode(InferenceConfigSnapshot.self, from: data)
        XCTAssertNil(snapshot.modelName)
        XCTAssertNil(snapshot.thinkingEnabled)
        XCTAssertNil(snapshot.temperature)
    }
}
