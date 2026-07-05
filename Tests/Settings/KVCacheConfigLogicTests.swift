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

/// Tests for `KVCacheConfigLogic` — pure-function logic for KV-cache (maxNumTokens) configuration.
/// Written TDD-first: these tests define the expected behavior before implementation.
@Suite("KVCacheConfigLogic")
struct KVCacheConfigLogicTests {

    // MARK: - Validation

    @Suite("Token Count Validation")
    struct Validation {

        @Test("nil token count is valid (auto mode)")
        func nilTokenCount_isValid() {
            let result = KVCacheConfigLogic.validate(tokenCount: nil)
            #expect(result.isValid == true)
        }

        @Test("Positive token count is valid")
        func positiveTokenCount_isValid() {
            let result = KVCacheConfigLogic.validate(tokenCount: 4096)
            #expect(result.isValid == true)
        }

        @Test("Zero token count is invalid")
        func zeroTokenCount_isInvalid() {
            let result = KVCacheConfigLogic.validate(tokenCount: 0)
            #expect(result.isValid == false)
            #expect(result.errorMessage != nil)
        }

        @Test("Negative token count is invalid")
        func negativeTokenCount_isInvalid() {
            let result = KVCacheConfigLogic.validate(tokenCount: -1)
            #expect(result.isValid == false)
            #expect(result.errorMessage != nil)
        }

        @Test("Very large token count is valid")
        func veryLargeTokenCount_isValid() {
            let result = KVCacheConfigLogic.validate(tokenCount: 262144)
            #expect(result.isValid == true)
        }
    }

    // MARK: - Stepper Range

    @Suite("Stepper Range")
    struct StepperRange {

        @Test("Stepper range uses model context length as upper bound")
        func stepperRange_usesModelContextLength() {
            let range = KVCacheConfigLogic.stepperRange(modelContextLength: 8192)
            #expect(range.upperBound == 8192)
            #expect(range.lowerBound > 0)
        }

        @Test("Stepper range defaults to 8192 when no model context")
        func stepperRange_defaultsWhenNoModelContext() {
            let range = KVCacheConfigLogic.stepperRange(modelContextLength: nil)
            #expect(range.upperBound == 8192)
            #expect(range.lowerBound > 0)
        }

        @Test("Stepper lower bound is 256")
        func stepperRange_lowerBound() {
            let range = KVCacheConfigLogic.stepperRange(modelContextLength: 4096)
            #expect(range.lowerBound == 256)
        }

        @Test("Stepper range for large context model")
        func stepperRange_largeContextModel() {
            let range = KVCacheConfigLogic.stepperRange(modelContextLength: 262144)
            #expect(range.upperBound == 262144)
        }
    }

    // MARK: - Stepper Presets

    @Suite("Stepper Presets")
    struct StepperPresets {

        @Test("Preset steps include standard powers of 2")
        func presetSteps_includeStandardValues() {
            let presets = KVCacheConfigLogic.presetSteps(modelContextLength: 8192)
            #expect(presets.contains(2048))
            #expect(presets.contains(4096))
            #expect(presets.contains(8192))
        }

        @Test("Preset steps are sorted ascending")
        func presetSteps_areSorted() {
            let presets = KVCacheConfigLogic.presetSteps(modelContextLength: 8192)
            #expect(presets == presets.sorted())
        }

        @Test("Preset steps don't exceed model context length")
        func presetSteps_dontExceedModelContext() {
            let presets = KVCacheConfigLogic.presetSteps(modelContextLength: 4096)
            for preset in presets {
                #expect(preset <= 4096)
            }
        }
    }

    // MARK: - Display Label

    @Suite("Display Label Formatting")
    struct DisplayLabel {

        @Test("Auto mode shows model default")
        func displayLabel_autoMode() {
            let label = KVCacheConfigLogic.formatDisplayLabel(tokenCount: nil, modelDefault: 8192)
            #expect(label.contains("Auto"))
            #expect(label.contains("8192"))
        }

        @Test("Custom value shows current and model default")
        func displayLabel_customWithModelDefault() {
            let label = KVCacheConfigLogic.formatDisplayLabel(tokenCount: 2048, modelDefault: 8192)
            #expect(label.contains("2048"))
        }

        @Test("Auto mode without model default")
        func displayLabel_autoWithoutModelDefault() {
            let label = KVCacheConfigLogic.formatDisplayLabel(tokenCount: nil, modelDefault: nil)
            #expect(label.contains("Auto"))
        }

        @Test("Custom value without model default")
        func displayLabel_customWithoutModelDefault() {
            let label = KVCacheConfigLogic.formatDisplayLabel(tokenCount: 4096, modelDefault: nil)
            #expect(label.contains("4096"))
        }
    }

    // MARK: - Restart Detection

    @Suite("Restart Detection")
    struct RestartDetection {

        @Test("Changing token count requires restart")
        func changingTokenCount_requiresRestart() {
            let result = KVCacheConfigLogic.requiresRestart(current: 4096, proposed: 2048)
            #expect(result == true)
        }

        @Test("Same token count does not require restart")
        func sameTokenCount_doesNotRequireRestart() {
            let result = KVCacheConfigLogic.requiresRestart(current: 4096, proposed: 4096)
            #expect(result == false)
        }

        @Test("Switching from auto to custom requires restart")
        func autoToCustom_requiresRestart() {
            let result = KVCacheConfigLogic.requiresRestart(current: nil, proposed: 2048)
            #expect(result == true)
        }

        @Test("Switching from custom to auto requires restart")
        func customToAuto_requiresRestart() {
            let result = KVCacheConfigLogic.requiresRestart(current: 4096, proposed: nil)
            #expect(result == true)
        }

        @Test("Both nil does not require restart")
        func bothNil_doesNotRequireRestart() {
            let result = KVCacheConfigLogic.requiresRestart(current: nil, proposed: nil)
            #expect(result == false)
        }
    }

    // MARK: - ValidationResult Properties

    @Suite("ValidationResult Properties")
    struct ValidationResultProperties {

        @Test("Valid result has no error message")
        func validResult_noErrorMessage() {
            let result = KVCacheConfigLogic.validate(tokenCount: 4096)
            #expect(result.errorMessage == nil)
        }

        @Test("Invalid result has descriptive error message")
        func invalidResult_hasErrorMessage() {
            let result = KVCacheConfigLogic.validate(tokenCount: -1)
            #expect(result.errorMessage != nil)
            #expect(result.errorMessage!.isEmpty == false)
        }
    }
}
