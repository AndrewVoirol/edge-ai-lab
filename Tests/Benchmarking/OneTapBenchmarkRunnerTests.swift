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

// MARK: - BenchmarkLogic Tests (Swift Testing)

/// Tests for the pure `BenchmarkLogic` static methods.
/// These are unit-testable without any engine or SDK dependencies.
@Suite("BenchmarkLogic")
struct BenchmarkLogicTests {

    // MARK: - Median Computation

    @Test("Median of odd count (3 values)")
    func testMedianComputationOddCount() {
        // Unsorted input to verify sorting behavior
        let values: [Double] = [30.0, 10.0, 20.0]
        let result = BenchmarkLogic.median(of: values)
        #expect(result == 20.0)
    }

    @Test("Median of even count (4 values)")
    func testMedianComputationEvenCount() {
        let values: [Double] = [10.0, 40.0, 20.0, 30.0]
        let result = BenchmarkLogic.median(of: values)
        // Sorted: [10, 20, 30, 40] → median = (20 + 30) / 2 = 25
        #expect(result == 25.0)
    }

    @Test("Median of single value")
    func testMedianComputationSingleValue() {
        let values: [Double] = [42.5]
        let result = BenchmarkLogic.median(of: values)
        #expect(result == 42.5)
    }

    @Test("Median of empty array returns nil")
    func testMedianComputationEmpty() {
        let values: [Double] = []
        let result = BenchmarkLogic.median(of: values)
        #expect(result == nil)
    }

    // MARK: - Result Creation

    @Test("BenchmarkResult creation from valid run data")
    func testBenchmarkResultCreation() {
        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
        let result = BenchmarkLogic.buildResult(
            decodeSpeeds: [10.0, 20.0, 30.0],
            ttftValues: [0.5, 0.3, 0.4],
            prefillSpeeds: [100.0, 200.0, 150.0],
            timestamp: fixedDate
        )

        #expect(result != nil)
        #expect(result?.medianDecodeTokensPerSecond == 20.0)
        #expect(result?.medianTTFTSeconds == 0.4)
        #expect(result?.medianPrefillTokensPerSecond == 150.0)
        #expect(result?.runCount == 3)
        #expect(result?.timestamp == fixedDate)
    }

    @Test("BenchmarkResult returns nil when decode speeds are empty")
    func testBenchmarkResultCreationFailsOnEmptyDecodeSpeeds() {
        let result = BenchmarkLogic.buildResult(
            decodeSpeeds: [],
            ttftValues: [0.5],
            prefillSpeeds: [100.0]
        )
        #expect(result == nil)
    }

    @Test("BenchmarkResult returns nil when TTFT values are empty")
    func testBenchmarkResultCreationFailsOnEmptyTTFT() {
        let result = BenchmarkLogic.buildResult(
            decodeSpeeds: [10.0],
            ttftValues: [],
            prefillSpeeds: [100.0]
        )
        #expect(result == nil)
    }

    @Test("BenchmarkResult returns nil when prefill speeds are empty")
    func testBenchmarkResultCreationFailsOnEmptyPrefill() {
        let result = BenchmarkLogic.buildResult(
            decodeSpeeds: [10.0],
            ttftValues: [0.5],
            prefillSpeeds: []
        )
        #expect(result == nil)
    }

    // MARK: - Standard Prompt

    @Test("Standard prompt is non-empty")
    func testStandardPromptIsNonEmpty() {
        #expect(!BenchmarkLogic.standardPrompt.isEmpty)
        // Also verify it contains expected keywords for the standardized prompt
        #expect(BenchmarkLogic.standardPrompt.contains("machine learning"))
        #expect(BenchmarkLogic.standardPrompt.contains("teenager"))
    }

    // MARK: - Default Run Count

    @Test("Default run count is 3")
    func testDefaultRunCount() {
        #expect(BenchmarkLogic.defaultRunCount == 3)
    }

    // MARK: - Median Edge Cases

    @Test("Median of two values returns their average")
    func testMedianComputationTwoValues() {
        let values: [Double] = [10.0, 20.0]
        let result = BenchmarkLogic.median(of: values)
        #expect(result == 15.0)
    }

    @Test("Median with identical values")
    func testMedianComputationIdenticalValues() {
        let values: [Double] = [7.0, 7.0, 7.0]
        let result = BenchmarkLogic.median(of: values)
        #expect(result == 7.0)
    }

    @Test("Median of five values")
    func testMedianComputationFiveValues() {
        // 5 is odd, so median is the middle element
        let values: [Double] = [50.0, 10.0, 30.0, 20.0, 40.0]
        let result = BenchmarkLogic.median(of: values)
        // Sorted: [10, 20, 30, 40, 50] → median = 30
        #expect(result == 30.0)
    }
}
