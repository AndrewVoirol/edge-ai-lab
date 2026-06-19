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

// MARK: - EvalRunnerLogic Tests

@Suite("EvalRunnerLogic")
struct EvalRunnerLogicTests {

    // MARK: - formatTimeRemaining

    @Suite("formatTimeRemaining")
    struct FormatTimeRemainingTests {

        @Test("Zero seconds shows ~0s remaining")
        func zeroSeconds() {
            #expect(EvalRunnerLogic.formatTimeRemaining(0) == "~0s remaining")
        }

        @Test("30 seconds shows seconds only")
        func thirtySeconds() {
            #expect(EvalRunnerLogic.formatTimeRemaining(30) == "~30s remaining")
        }

        @Test("60 seconds shows 1m 0s")
        func sixtySeconds() {
            #expect(EvalRunnerLogic.formatTimeRemaining(60) == "~1m 0s remaining")
        }

        @Test("90 seconds shows 1m 30s")
        func ninetySeconds() {
            #expect(EvalRunnerLogic.formatTimeRemaining(90) == "~1m 30s remaining")
        }

        @Test("3600 seconds shows 60m 0s")
        func oneHour() {
            #expect(EvalRunnerLogic.formatTimeRemaining(3600) == "~60m 0s remaining")
        }

        @Test("Negative value truncates toward zero")
        func negativeValue() {
            // Int(-5) / 60 == 0, Int(-5) % 60 == -5
            #expect(EvalRunnerLogic.formatTimeRemaining(-5) == "~-5s remaining")
        }
    }

    // MARK: - allSuites

    @Suite("allSuites")
    struct AllSuitesTests {

        @Test("Both empty arrays produce empty result")
        func bothEmpty() {
            let result = EvalRunnerLogic.allSuites(builtIn: [], custom: [])
            #expect(result.isEmpty)
        }

        @Test("Non-empty arrays concatenate in order")
        func nonEmpty() {
            let builtIn = [makeSuite(name: "A"), makeSuite(name: "B")]
            let custom = [makeSuite(name: "C")]
            let result = EvalRunnerLogic.allSuites(builtIn: builtIn, custom: custom)
            #expect(result.count == 3)
            #expect(result.map(\.name) == ["A", "B", "C"])
        }

        @Test("Order preserved — built-in first, then custom")
        func orderPreserved() {
            let builtIn = [makeSuite(name: "Z")]
            let custom = [makeSuite(name: "A")]
            let result = EvalRunnerLogic.allSuites(builtIn: builtIn, custom: custom)
            #expect(result.map(\.name) == ["Z", "A"])
        }
    }

    // MARK: - canRun

    @Suite("canRun")
    struct CanRunTests {

        @Test("Valid combo — suite selected, models selected, not running")
        func validCombo() {
            #expect(EvalRunnerLogic.canRun(
                selectedSuiteId: UUID(),
                selectedModelFiles: ["model.bin"],
                isRunning: false
            ) == true)
        }

        @Test("Nil suite ID disables run")
        func nilSuiteId() {
            #expect(EvalRunnerLogic.canRun(
                selectedSuiteId: nil,
                selectedModelFiles: ["model.bin"],
                isRunning: false
            ) == false)
        }

        @Test("Empty model files disables run")
        func emptyModels() {
            #expect(EvalRunnerLogic.canRun(
                selectedSuiteId: UUID(),
                selectedModelFiles: [],
                isRunning: false
            ) == false)
        }

        @Test("isRunning true disables run")
        func isRunning() {
            #expect(EvalRunnerLogic.canRun(
                selectedSuiteId: UUID(),
                selectedModelFiles: ["model.bin"],
                isRunning: true
            ) == false)
        }

        @Test("All invalid — nil suite, empty models, running")
        func allInvalid() {
            #expect(EvalRunnerLogic.canRun(
                selectedSuiteId: nil,
                selectedModelFiles: [],
                isRunning: true
            ) == false)
        }

        @Test("Nil suite and running, but models present")
        func nilSuiteAndRunning() {
            #expect(EvalRunnerLogic.canRun(
                selectedSuiteId: nil,
                selectedModelFiles: ["a.bin"],
                isRunning: true
            ) == false)
        }
    }

    // MARK: - passRatePercent

    @Suite("passRatePercent")
    struct PassRatePercentTests {

        @Test("Zero rate returns 0%")
        func zeroRate() {
            #expect(EvalRunnerLogic.passRatePercent(0.0) == 0)
        }

        @Test("Full rate returns 100%")
        func fullRate() {
            #expect(EvalRunnerLogic.passRatePercent(1.0) == 100)
        }

        @Test("Half rate returns 50%")
        func halfRate() {
            #expect(EvalRunnerLogic.passRatePercent(0.5) == 50)
        }

        @Test("0.753 truncates to 75%")
        func truncates() {
            #expect(EvalRunnerLogic.passRatePercent(0.753) == 75)
        }

        @Test("0.999 truncates to 99%")
        func nearlyFull() {
            #expect(EvalRunnerLogic.passRatePercent(0.999) == 99)
        }
    }

    // MARK: - selectAllToggleLabel

    @Suite("selectAllToggleLabel")
    struct SelectAllToggleLabelTests {

        @Test("All selected shows Deselect All")
        func allSelected() {
            #expect(EvalRunnerLogic.selectAllToggleLabel(selectedCount: 5, totalCount: 5) == "Deselect All")
        }

        @Test("None selected shows Select All")
        func noneSelected() {
            #expect(EvalRunnerLogic.selectAllToggleLabel(selectedCount: 0, totalCount: 5) == "Select All")
        }

        @Test("Partial selection shows Select All")
        func partialSelection() {
            #expect(EvalRunnerLogic.selectAllToggleLabel(selectedCount: 3, totalCount: 5) == "Select All")
        }

        @Test("Both zero shows Deselect All")
        func bothZero() {
            #expect(EvalRunnerLogic.selectAllToggleLabel(selectedCount: 0, totalCount: 0) == "Deselect All")
        }
    }

    // MARK: - batchCanRun

    @Suite("batchCanRun")
    struct BatchCanRunTests {

        @Test("All conditions met — can run")
        func allConditionsMet() {
            #expect(EvalRunnerLogic.batchCanRun(
                isRunning: false,
                isBatchRunning: false,
                modelCount: 3
            ) == true)
        }

        @Test("isRunning disables batch")
        func isRunningDisablesBatch() {
            #expect(EvalRunnerLogic.batchCanRun(
                isRunning: true,
                isBatchRunning: false,
                modelCount: 3
            ) == false)
        }

        @Test("isBatchRunning disables batch")
        func batchAlreadyRunning() {
            #expect(EvalRunnerLogic.batchCanRun(
                isRunning: false,
                isBatchRunning: true,
                modelCount: 3
            ) == false)
        }

        @Test("No models disables batch")
        func noModels() {
            #expect(EvalRunnerLogic.batchCanRun(
                isRunning: false,
                isBatchRunning: false,
                modelCount: 0
            ) == false)
        }

        @Test("All invalid — running, batch running, no models")
        func allInvalid() {
            #expect(EvalRunnerLogic.batchCanRun(
                isRunning: true,
                isBatchRunning: true,
                modelCount: 0
            ) == false)
        }
    }

    // MARK: - Helpers

    /// Creates a minimal `EvalSuite` for testing.
    private static func makeSuite(name: String) -> EvalSuite {
        EvalSuite(
            name: name,
            description: "Test suite",
            category: .general,
            prompts: []
        )
    }
}
