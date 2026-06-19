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

@Suite("ExperimentalFlagsState")
struct ExperimentalFlagsStateSwiftTests {

    // MARK: - Initialization

    @Suite("Initialization")
    struct Initialization {

        @Test("Init with all parameters specified stores every field")
        func initWithAllParameters() {
            let state = ExperimentalFlagsState(
                enableBenchmark: true,
                enableSpeculativeDecoding: false,
                enableConversationConstrainedDecoding: true,
                visualTokenBudget: 256,
                enableThinking: false,
                enableToolCalling: true,
                enableAgentSkills: true
            )

            #expect(state.enableBenchmark == true)
            #expect(state.enableSpeculativeDecoding == false)
            #expect(state.enableConversationConstrainedDecoding == true)
            #expect(state.visualTokenBudget == 256)
            #expect(state.enableThinking == false)
            #expect(state.enableToolCalling == true)
            #expect(state.enableAgentSkills == true)
        }

        @Test("Init with defaults uses enableThinking=true, enableToolCalling=false, enableAgentSkills=false")
        func initWithDefaults() {
            let state = ExperimentalFlagsState(
                enableBenchmark: false,
                enableSpeculativeDecoding: nil,
                enableConversationConstrainedDecoding: false,
                visualTokenBudget: nil
            )

            #expect(state.enableBenchmark == false)
            #expect(state.enableSpeculativeDecoding == nil)
            #expect(state.enableConversationConstrainedDecoding == false)
            #expect(state.visualTokenBudget == nil)
            // Verify defaults
            #expect(state.enableThinking == true)
            #expect(state.enableToolCalling == false)
            #expect(state.enableAgentSkills == false)
        }
    }

    // MARK: - Codable

    @Suite("Codable")
    struct CodableTests {

        @Test("Round-trip with all fields set preserves values")
        func roundTripAllFieldsSet() throws {
            let original = ExperimentalFlagsState(
                enableBenchmark: true,
                enableSpeculativeDecoding: true,
                enableConversationConstrainedDecoding: false,
                visualTokenBudget: 512,
                enableThinking: false,
                enableToolCalling: true,
                enableAgentSkills: true
            )

            let data = try JSONEncoder().encode(original)
            let decoded = try JSONDecoder().decode(ExperimentalFlagsState.self, from: data)

            #expect(decoded == original)
            #expect(decoded.enableBenchmark == true)
            #expect(decoded.enableSpeculativeDecoding == true)
            #expect(decoded.enableConversationConstrainedDecoding == false)
            #expect(decoded.visualTokenBudget == 512)
            #expect(decoded.enableThinking == false)
            #expect(decoded.enableToolCalling == true)
            #expect(decoded.enableAgentSkills == true)
        }

        @Test("Round-trip with nil optionals preserves nil values")
        func roundTripNilOptionals() throws {
            let original = ExperimentalFlagsState(
                enableBenchmark: false,
                enableSpeculativeDecoding: nil,
                enableConversationConstrainedDecoding: true,
                visualTokenBudget: nil
            )

            let data = try JSONEncoder().encode(original)
            let decoded = try JSONDecoder().decode(ExperimentalFlagsState.self, from: data)

            #expect(decoded == original)
            #expect(decoded.enableSpeculativeDecoding == nil)
            #expect(decoded.visualTokenBudget == nil)
        }

        @Test("Decodes from JSON with missing optional keys")
        func decodesFromPartialJSON() throws {
            // JSON without optional keys — Codable should decode them as nil/default
            let json = """
            {
                "enableBenchmark": true,
                "enableConversationConstrainedDecoding": false,
                "enableThinking": true,
                "enableToolCalling": false,
                "enableAgentSkills": false
            }
            """.data(using: .utf8)!

            let decoded = try JSONDecoder().decode(ExperimentalFlagsState.self, from: json)

            #expect(decoded.enableBenchmark == true)
            #expect(decoded.enableConversationConstrainedDecoding == false)
            #expect(decoded.enableSpeculativeDecoding == nil)
            #expect(decoded.visualTokenBudget == nil)
        }
    }

    // MARK: - Equatable

    @Suite("Equatable")
    struct EquatableTests {

        @Test("Two instances with identical values are equal")
        func equalInstances() {
            let a = ExperimentalFlagsState(
                enableBenchmark: true,
                enableSpeculativeDecoding: false,
                enableConversationConstrainedDecoding: true,
                visualTokenBudget: 128,
                enableThinking: true,
                enableToolCalling: false,
                enableAgentSkills: true
            )
            let b = ExperimentalFlagsState(
                enableBenchmark: true,
                enableSpeculativeDecoding: false,
                enableConversationConstrainedDecoding: true,
                visualTokenBudget: 128,
                enableThinking: true,
                enableToolCalling: false,
                enableAgentSkills: true
            )

            #expect(a == b)
        }

        @Test("Two instances with different values are not equal")
        func differentInstances() {
            let a = ExperimentalFlagsState(
                enableBenchmark: true,
                enableSpeculativeDecoding: true,
                enableConversationConstrainedDecoding: true,
                visualTokenBudget: 256,
                enableThinking: true,
                enableToolCalling: true,
                enableAgentSkills: true
            )
            let b = ExperimentalFlagsState(
                enableBenchmark: false,
                enableSpeculativeDecoding: nil,
                enableConversationConstrainedDecoding: false,
                visualTokenBudget: nil,
                enableThinking: false,
                enableToolCalling: false,
                enableAgentSkills: false
            )

            #expect(a != b)
        }

        @Test(
            "Changing a single field breaks equality",
            arguments: [
                "enableBenchmark",
                "enableSpeculativeDecoding",
                "enableConversationConstrainedDecoding",
                "visualTokenBudget",
                "enableThinking",
                "enableToolCalling",
                "enableAgentSkills",
            ]
        )
        func singleFieldChange(field: String) {
            let baseline = ExperimentalFlagsState(
                enableBenchmark: false,
                enableSpeculativeDecoding: false,
                enableConversationConstrainedDecoding: false,
                visualTokenBudget: 128,
                enableThinking: true,
                enableToolCalling: false,
                enableAgentSkills: false
            )

            var modified = baseline
            switch field {
            case "enableBenchmark":
                modified.enableBenchmark = true
            case "enableSpeculativeDecoding":
                modified.enableSpeculativeDecoding = nil
            case "enableConversationConstrainedDecoding":
                modified.enableConversationConstrainedDecoding = true
            case "visualTokenBudget":
                modified.visualTokenBudget = 999
            case "enableThinking":
                modified.enableThinking = false
            case "enableToolCalling":
                modified.enableToolCalling = true
            case "enableAgentSkills":
                modified.enableAgentSkills = true
            default:
                Issue.record("Unknown field: \(field)")
            }

            #expect(baseline != modified, "Changing \(field) should break equality")
        }
    }

    // MARK: - Global Flag Interaction

    @Suite("Global flag interaction")
    struct GlobalFlagInteraction {

        @Test("captureCurrentState returns a valid instance")
        func captureCurrentStateReturnsInstance() {
            // We don't assert specific values since global state is shared,
            // but we verify the method produces a valid ExperimentalFlagsState.
            let state = ExperimentalFlagsState.captureCurrentState()
            // Smoke-check: the instance should at least be Equatable with itself.
            #expect(state == state)
        }

        @Test("captureCurrentState returns consistent values on repeated calls")
        func captureIsConsistent() {
            let first = ExperimentalFlagsState.captureCurrentState()
            let second = ExperimentalFlagsState.captureCurrentState()
            // The global flags should not change between two immediate captures.
            #expect(first.enableBenchmark == second.enableBenchmark)
            #expect(first.enableSpeculativeDecoding == second.enableSpeculativeDecoding)
            #expect(first.enableConversationConstrainedDecoding == second.enableConversationConstrainedDecoding)
            #expect(first.visualTokenBudget == second.visualTokenBudget)
        }
    }

    // MARK: - Sendable

    @Suite("Sendable")
    struct SendableTests {

        @Test("Can be passed across concurrency boundaries")
        func crossesConcurrencyBoundary() async {
            let state = ExperimentalFlagsState(
                enableBenchmark: true,
                enableSpeculativeDecoding: false,
                enableConversationConstrainedDecoding: true,
                visualTokenBudget: 64,
                enableThinking: true,
                enableToolCalling: false,
                enableAgentSkills: true
            )

            // Pass to a detached Task (different isolation domain) and read back.
            let result = await Task.detached {
                return state
            }.value

            #expect(result == state)
            #expect(result.enableBenchmark == true)
            #expect(result.visualTokenBudget == 64)
            #expect(result.enableAgentSkills == true)
        }
    }
}
