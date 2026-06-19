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
import SwiftUI
#if os(iOS)
@testable import EdgeAILab_iOS
#elseif os(macOS)
@testable import EdgeAILab_macOS
#endif

// MARK: - PerformanceTier Tests

@Suite("PerformanceTier")
struct PerformanceTierSwiftTests {

    // MARK: - Boundary tests via init(decodeSpeed:)

    @Suite("init(decodeSpeed:)")
    struct InitTests {

        /// (input speed, expected tier)
        static let boundaryArgs: [(Double, PerformanceTier)] = [
            // Excellent: 80+
            (80.0, .excellent),
            (100.0, .excellent),
            (999.0, .excellent),
            // Great: 40..<80
            (79.99, .great),
            (40.0, .great),
            (60.0, .great),
            // Good: 20..<40
            (39.99, .good),
            (20.0, .good),
            (30.0, .good),
            // Fair: 10..<20
            (19.99, .fair),
            (10.0, .fair),
            (15.0, .fair),
            // Slow: <10
            (9.99, .slow),
            (5.0, .slow),
            (0.0, .slow),
            (-1.0, .slow),
            (-100.0, .slow),
        ]

        @Test("maps decode speed to correct tier", arguments: boundaryArgs)
        func decodeSpeedMapping(speed: Double, expected: PerformanceTier) {
            let tier = PerformanceTier(decodeSpeed: speed)
            #expect(tier == expected, "Speed \(speed) should map to \(expected), got \(tier)")
        }
    }

    // MARK: - Label tests

    static let allCasesWithLabels: [(PerformanceTier, String)] = [
        (.excellent, "Blazing"),
        (.great, "Fast"),
        (.good, "Good"),
        (.fair, "Fair"),
        (.slow, "Slow"),
    ]

    @Test("label returns expected string", arguments: allCasesWithLabels)
    func labelValue(tier: PerformanceTier, expectedLabel: String) {
        #expect(tier.label == expectedLabel)
    }

    // MARK: - Color tests

    static let allCases: [PerformanceTier] = [
        .excellent, .great, .good, .fair, .slow,
    ]

    @Test("color is non-nil for every case", arguments: allCases)
    func colorIsNonNil(tier: PerformanceTier) {
        // Color is a value type — just verify we can access it without crashing
        // and it produces a real value.
        let color: Color = tier.color
        #expect(color == tier.color, "color should be deterministic")
    }
}

// MARK: - PassRateTier Tests

@Suite("PassRateTier")
struct PassRateTierTests {

    // MARK: - Boundary tests via init(rate:)

    @Suite("init(rate:)")
    struct InitTests {

        static let boundaryArgs: [(Double, PassRateTier)] = [
            // Excellent: 0.8+
            (0.8, .excellent),
            (1.0, .excellent),
            (0.95, .excellent),
            // Moderate: 0.5..<0.8
            (0.799, .moderate),
            (0.5, .moderate),
            (0.65, .moderate),
            // Poor: <0.5
            (0.499, .poor),
            (0.0, .poor),
            (0.25, .poor),
            (-0.1, .poor),
            (-1.0, .poor),
        ]

        @Test("maps pass rate to correct tier", arguments: boundaryArgs)
        func passRateMapping(rate: Double, expected: PassRateTier) {
            let tier = PassRateTier(rate: rate)
            #expect(tier == expected, "Rate \(rate) should map to \(expected), got \(tier)")
        }
    }

    // MARK: - Color tests

    static let allCases: [PassRateTier] = [.excellent, .moderate, .poor]

    @Test("color is non-nil for every case", arguments: allCases)
    func colorIsNonNil(tier: PassRateTier) {
        let color: Color = tier.color
        #expect(color == tier.color, "color should be deterministic")
    }

    // MARK: - Static convenience color(for:)

    static let convenienceArgs: [(Double, PassRateTier)] = [
        (0.9, .excellent),
        (0.6, .moderate),
        (0.3, .poor),
    ]

    @Test("color(for:) matches init+color", arguments: convenienceArgs)
    func staticColorConvenience(rate: Double, expectedTier: PassRateTier) {
        let fromStatic = PassRateTier.color(for: rate)
        let fromInit = PassRateTier(rate: rate).color
        #expect(fromStatic == fromInit,
                "color(for: \(rate)) should equal PassRateTier(rate:).color")
        #expect(fromInit == expectedTier.color)
    }
}

// MARK: - ConfidenceTier Tests

@Suite("ConfidenceTier")
struct ConfidenceTierTests {

    // MARK: - Mapping from MetadataConfidence

    static let mappingArgs: [(MetadataConfidence, ConfidenceTier)] = [
        (.verified, .verified),
        (.high, .high),
        (.medium, .medium),
        (.low, .low),
    ]

    @Test("init maps MetadataConfidence to correct tier", arguments: mappingArgs)
    func confidenceMapping(
        confidence: MetadataConfidence,
        expected: ConfidenceTier
    ) {
        let tier = ConfidenceTier(confidence)
        #expect(tier == expected,
                "MetadataConfidence.\(confidence) should map to ConfidenceTier.\(expected)")
    }

    // MARK: - Color tests

    static let allCases: [ConfidenceTier] = [.verified, .high, .medium, .low]

    @Test("color is non-nil for every case", arguments: allCases)
    func colorIsNonNil(tier: ConfidenceTier) {
        let color: Color = tier.color
        #expect(color == tier.color, "color should be deterministic")
    }

    // MARK: - Static convenience color(for:)

    static let convenienceArgs: [MetadataConfidence] = [
        .verified, .high, .medium, .low,
    ]

    @Test("color(for:) matches init+color", arguments: convenienceArgs)
    func staticColorConvenience(confidence: MetadataConfidence) {
        let fromStatic = ConfidenceTier.color(for: confidence)
        let fromInit = ConfidenceTier(confidence).color
        #expect(fromStatic == fromInit,
                "color(for: .\(confidence)) should equal ConfidenceTier(confidence).color")
    }
}
