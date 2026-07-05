// Copyright 2026 Andrew Voirol. Apache-2.0
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

// MARK: - EvalPipelineLogic Tests

@Suite("EvalPipelineLogic")
struct EvalPipelineLogicTests {

    // MARK: - calculatePassRate

    @Test("calculatePassRate returns 0 when total is zero")
    func calculatePassRateZeroTotal() {
        let result = EvalPipelineLogic.calculatePassRate(passed: 0, total: 0)
        #expect(result == 0.0)
    }

    @Test("calculatePassRate returns 1 when all prompts pass")
    func calculatePassRateAllPass() {
        let result = EvalPipelineLogic.calculatePassRate(passed: 10, total: 10)
        #expect(result == 1.0)
    }

    @Test("calculatePassRate returns 0 when none pass")
    func calculatePassRateNonePass() {
        let result = EvalPipelineLogic.calculatePassRate(passed: 0, total: 8)
        #expect(result == 0.0)
    }

    @Test("calculatePassRate returns correct fraction for partial pass")
    func calculatePassRatePartial() {
        // 3 out of 4 = 0.75
        let result = EvalPipelineLogic.calculatePassRate(passed: 3, total: 4)
        #expect(result == 0.75)
    }

    @Test("calculatePassRate returns 0 when total is negative")
    func calculatePassRateNegativeTotal() {
        let result = EvalPipelineLogic.calculatePassRate(passed: 2, total: -1)
        #expect(result == 0.0)
    }

    // MARK: - formatPassRateIcon

    @Test("formatPassRateIcon returns ✅ for pass rate at 0.7")
    func formatPassRateIconAtSeventyPercent() {
        let icon = EvalPipelineLogic.formatPassRateIcon(passRate: 0.7)
        #expect(icon == "✅")
    }

    @Test("formatPassRateIcon returns ✅ for pass rate above 0.7")
    func formatPassRateIconAboveSeventyPercent() {
        let icon = EvalPipelineLogic.formatPassRateIcon(passRate: 0.95)
        #expect(icon == "✅")
    }

    @Test("formatPassRateIcon returns ⚠️ for pass rate at 0.4")
    func formatPassRateIconAtFortyPercent() {
        let icon = EvalPipelineLogic.formatPassRateIcon(passRate: 0.4)
        #expect(icon == "⚠️")
    }

    @Test("formatPassRateIcon returns ⚠️ for pass rate between 0.4 and 0.7")
    func formatPassRateIconBetweenFortyAndSeventy() {
        let icon = EvalPipelineLogic.formatPassRateIcon(passRate: 0.55)
        #expect(icon == "⚠️")
    }

    @Test("formatPassRateIcon returns ❌ for pass rate below 0.4")
    func formatPassRateIconBelowForty() {
        let icon = EvalPipelineLogic.formatPassRateIcon(passRate: 0.2)
        #expect(icon == "❌")
    }

    @Test("formatPassRateIcon returns ❌ for zero pass rate")
    func formatPassRateIconZero() {
        let icon = EvalPipelineLogic.formatPassRateIcon(passRate: 0.0)
        #expect(icon == "❌")
    }

    // MARK: - isSuiteSkipped

    @Test("isSuiteSkipped returns true for negative pass rate")
    func isSuiteSkippedNegative() {
        #expect(EvalPipelineLogic.isSuiteSkipped(passRate: -1.0) == true)
    }

    @Test("isSuiteSkipped returns true for small negative pass rate")
    func isSuiteSkippedSmallNegative() {
        #expect(EvalPipelineLogic.isSuiteSkipped(passRate: -0.001) == true)
    }

    @Test("isSuiteSkipped returns false for zero pass rate")
    func isSuiteSkippedZero() {
        #expect(EvalPipelineLogic.isSuiteSkipped(passRate: 0.0) == false)
    }

    @Test("isSuiteSkipped returns false for positive pass rate")
    func isSuiteSkippedPositive() {
        #expect(EvalPipelineLogic.isSuiteSkipped(passRate: 0.85) == false)
    }

    // MARK: - determineGateResult

    @Test("determineGateResult fails when gated with critical regressions")
    func determineGateResultGatedWithRegressions() {
        let result = EvalPipelineLogic.determineGateResult(
            criticalRegressions: 2,
            floorViolations: 0,
            isGated: true
        )
        #expect(result.shouldFail == true)
        #expect(result.issueCount == 2)
    }

    @Test("determineGateResult fails when gated with floor violations")
    func determineGateResultGatedWithFloorViolations() {
        let result = EvalPipelineLogic.determineGateResult(
            criticalRegressions: 0,
            floorViolations: 3,
            isGated: true
        )
        #expect(result.shouldFail == true)
        #expect(result.issueCount == 3)
    }

    @Test("determineGateResult fails when gated with both regressions and floor violations")
    func determineGateResultGatedWithBoth() {
        let result = EvalPipelineLogic.determineGateResult(
            criticalRegressions: 1,
            floorViolations: 2,
            isGated: true
        )
        #expect(result.shouldFail == true)
        #expect(result.issueCount == 3)
    }

    @Test("determineGateResult passes when gated with no issues")
    func determineGateResultGatedNoIssues() {
        let result = EvalPipelineLogic.determineGateResult(
            criticalRegressions: 0,
            floorViolations: 0,
            isGated: true
        )
        #expect(result.shouldFail == false)
        #expect(result.issueCount == 0)
    }

    @Test("determineGateResult does not fail when not gated despite regressions")
    func determineGateResultNotGatedWithRegressions() {
        let result = EvalPipelineLogic.determineGateResult(
            criticalRegressions: 5,
            floorViolations: 2,
            isGated: false
        )
        #expect(result.shouldFail == false)
        #expect(result.issueCount == 7)
    }

    @Test("determineGateResult does not fail when not gated with no issues")
    func determineGateResultNotGatedNoIssues() {
        let result = EvalPipelineLogic.determineGateResult(
            criticalRegressions: 0,
            floorViolations: 0,
            isGated: false
        )
        #expect(result.shouldFail == false)
        #expect(result.issueCount == 0)
    }
}
