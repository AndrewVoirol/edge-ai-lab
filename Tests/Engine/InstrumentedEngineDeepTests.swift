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

/// Tests for types declared in `InstrumentedEngine.swift` that can be exercised
/// without constructing a real `InstrumentedEngine` instance (which requires the
/// LiteRTLM SDK and a loaded model).
///
/// Covers:
/// - `InstrumentedEngineError` – error descriptions and pattern matching
/// - `BackendResult` – Sendable struct construction and exhaustive property checks
/// - `BackendResult.ActiveBackend` – raw value round-trips
/// - `BackendCapability.recommendedBackend` – mapping to `BackendRecommendation`
/// - `ExperimentalFlagsState` – Codable round-trip, Equatable behavior, default values
@Suite("InstrumentedEngine Deep Tests")
struct InstrumentedEngineDeepTests {

    // MARK: - InstrumentedEngineError

    @Suite("InstrumentedEngineError")
    struct ErrorTests {

        @Test("notInitialized has expected error description")
        func notInitializedDescription() {
            let error = InstrumentedEngineError.notInitialized
            #expect(error.errorDescription == "Engine is not initialized. Load a model first.")
        }

        @Test("notInitialized conforms to LocalizedError")
        func notInitializedLocalizedError() {
            let error: any Error = InstrumentedEngineError.notInitialized
            #expect(error.localizedDescription.contains("not initialized"))
        }

        @Test("bothBackendsFailed includes both backend names and errors in description")
        func bothBackendsFailedDescription() {
            let error = InstrumentedEngineError.bothBackendsFailed(
                primaryBackend: "GPU",
                primaryError: "Metal not available",
                fallbackBackend: "CPU",
                fallbackError: "Out of memory"
            )

            let description = error.errorDescription!
            #expect(description.contains("GPU"))
            #expect(description.contains("Metal not available"))
            #expect(description.contains("CPU"))
            #expect(description.contains("Out of memory"))
            #expect(description.contains("Both backends failed"))
        }

        @Test("bothBackendsFailed with CPU primary and GPU fallback")
        func bothBackendsFailedCPUPrimary() {
            let error = InstrumentedEngineError.bothBackendsFailed(
                primaryBackend: "CPU",
                primaryError: "Unsupported architecture",
                fallbackBackend: "GPU",
                fallbackError: "No Metal device"
            )

            let description = error.errorDescription!
            #expect(description.contains("CPU"))
            #expect(description.contains("Unsupported architecture"))
            #expect(description.contains("GPU"))
            #expect(description.contains("No Metal device"))
        }

        @Test("Pattern matching distinguishes between error cases")
        func patternMatching() {
            let notInit = InstrumentedEngineError.notInitialized
            let bothFailed = InstrumentedEngineError.bothBackendsFailed(
                primaryBackend: "GPU",
                primaryError: "err1",
                fallbackBackend: "CPU",
                fallbackError: "err2"
            )

            // Verify each case matches itself and not the other
            if case .notInitialized = notInit {
                // expected
            } else {
                Issue.record("notInitialized should match .notInitialized pattern")
            }

            if case .bothBackendsFailed(let primary, let primaryErr, let fallback, let fallbackErr) = bothFailed {
                #expect(primary == "GPU")
                #expect(primaryErr == "err1")
                #expect(fallback == "CPU")
                #expect(fallbackErr == "err2")
            } else {
                Issue.record("bothBackendsFailed should match .bothBackendsFailed pattern")
            }
        }

        @Test("Error can be caught as LocalizedError and provides description")
        func catchAsLocalizedError() {
            func throwIt() throws {
                throw InstrumentedEngineError.notInitialized
            }

            do {
                try throwIt()
                Issue.record("Should have thrown")
            } catch let error as LocalizedError {
                #expect(error.errorDescription != nil)
                #expect(error.errorDescription!.contains("not initialized"))
            } catch {
                Issue.record("Should catch as LocalizedError, got: \(type(of: error))")
            }
        }

        @Test("bothBackendsFailed with empty strings still produces description")
        func bothBackendsFailedEmptyStrings() {
            let error = InstrumentedEngineError.bothBackendsFailed(
                primaryBackend: "",
                primaryError: "",
                fallbackBackend: "",
                fallbackError: ""
            )
            // Should not crash and should still contain the framing text
            #expect(error.errorDescription != nil)
            #expect(error.errorDescription!.contains("Both backends failed"))
        }
    }

    // MARK: - BackendResult

    @Suite("BackendResult")
    struct BackendResultTests {

        @Test("GPU result without fallback")
        func gpuNoFallback() {
            let result = BackendResult(
                activeBackend: .gpu,
                didFallback: false,
                fallbackReason: nil,
                detectedCapability: .gpuAndCpu
            )

            #expect(result.activeBackend == .gpu)
            #expect(result.didFallback == false)
            #expect(result.fallbackReason == nil)
            #expect(result.detectedCapability == .gpuAndCpu)
        }

        @Test("CPU result with fallback reason")
        func cpuWithFallback() {
            let reason = "GPU initialization failed: Metal shader compilation error"
            let result = BackendResult(
                activeBackend: .cpu,
                didFallback: true,
                fallbackReason: reason,
                detectedCapability: .cpuOnly
            )

            #expect(result.activeBackend == .cpu)
            #expect(result.didFallback == true)
            #expect(result.fallbackReason == reason)
            #expect(result.detectedCapability == .cpuOnly)
        }

        @Test("BackendResult with gpuOnly capability")
        func gpuOnlyCapability() {
            let result = BackendResult(
                activeBackend: .gpu,
                didFallback: false,
                fallbackReason: nil,
                detectedCapability: .gpuOnly
            )

            #expect(result.detectedCapability.supportsGPU == true)
            #expect(result.detectedCapability.supportsCPU == false)
        }

        @Test("BackendResult with unknown capability")
        func unknownCapability() {
            let result = BackendResult(
                activeBackend: .cpu,
                didFallback: true,
                fallbackReason: "Probe timed out",
                detectedCapability: .unknown
            )

            #expect(result.detectedCapability.supportsGPU == false)
            #expect(result.detectedCapability.supportsCPU == false)
        }

        @Test("BackendResult is Sendable")
        func isSendable() async {
            let result = BackendResult(
                activeBackend: .gpu,
                didFallback: false,
                fallbackReason: nil,
                detectedCapability: .gpuAndCpu
            )

            // Prove Sendable by crossing an actor boundary
            let backend = await Task.detached {
                result.activeBackend
            }.value

            #expect(backend == .gpu)
        }
    }

    // MARK: - BackendResult.ActiveBackend

    @Suite("ActiveBackend")
    struct ActiveBackendTests {

        @Test("Raw value for GPU is 'gpu'")
        func gpuRawValue() {
            #expect(BackendResult.ActiveBackend.gpu.rawValue == "gpu")
        }

        @Test("Raw value for CPU is 'cpu'")
        func cpuRawValue() {
            #expect(BackendResult.ActiveBackend.cpu.rawValue == "cpu")
        }

        @Test("Init from raw value 'gpu' succeeds")
        func initFromGPU() {
            let backend = BackendResult.ActiveBackend(rawValue: "gpu")
            #expect(backend == .gpu)
        }

        @Test("Init from raw value 'cpu' succeeds")
        func initFromCPU() {
            let backend = BackendResult.ActiveBackend(rawValue: "cpu")
            #expect(backend == .cpu)
        }

        @Test("Init from unknown raw value returns nil",
              arguments: ["tpu", "npu", "GPU", "CPU", "", "metal"])
        func initFromUnknownRawValue(rawValue: String) {
            let backend = BackendResult.ActiveBackend(rawValue: rawValue)
            #expect(backend == nil)
        }

        @Test("ActiveBackend is Sendable")
        func isSendable() async {
            let backend: BackendResult.ActiveBackend = .gpu
            let transferred = await Task.detached { backend }.value
            #expect(transferred == .gpu)
        }
    }

    // MARK: - BackendCapability.recommendedBackend

    @Suite("BackendCapability.recommendedBackend")
    struct RecommendedBackendTests {

        static let allCases: [(BackendCapability, BackendRecommendation)] = [
            (.gpuOnly, .gpu),
            (.cpuOnly, .cpu),
            (.gpuAndCpu, .gpu),
            (.unknown, .probeRequired),
        ]

        @Test("Maps each capability to the correct recommendation",
              arguments: allCases)
        func mappingIsCorrect(
            capability: BackendCapability,
            expected: BackendRecommendation
        ) {
            #expect(capability.recommendedBackend == expected)
        }
    }

    // MARK: - BackendCapability Computed Properties

    @Suite("BackendCapability Properties")
    struct BackendCapabilityPropertyTests {

        static let gpuSupportCases: [(BackendCapability, Bool)] = [
            (.gpuOnly, true),
            (.cpuOnly, false),
            (.gpuAndCpu, true),
            (.unknown, false),
        ]

        static let cpuSupportCases: [(BackendCapability, Bool)] = [
            (.gpuOnly, false),
            (.cpuOnly, true),
            (.gpuAndCpu, true),
            (.unknown, false),
        ]

        @Test("supportsGPU returns correct value for each case",
              arguments: gpuSupportCases)
        func supportsGPU(capability: BackendCapability, expected: Bool) {
            #expect(capability.supportsGPU == expected)
        }

        @Test("supportsCPU returns correct value for each case",
              arguments: cpuSupportCases)
        func supportsCPU(capability: BackendCapability, expected: Bool) {
            #expect(capability.supportsCPU == expected)
        }
    }

    // MARK: - BackendCapability Codable

    @Suite("BackendCapability Codable")
    struct BackendCapabilityCodableTests {

        static let allCases: [BackendCapability] = [.gpuOnly, .cpuOnly, .gpuAndCpu, .unknown]

        @Test("Codable round-trip preserves each case", arguments: allCases)
        func codableRoundTrip(capability: BackendCapability) throws {
            let data = try JSONEncoder().encode(capability)
            let decoded = try JSONDecoder().decode(BackendCapability.self, from: data)
            #expect(decoded == capability)
        }

        @Test("Raw value encoding produces expected JSON string", arguments: allCases)
        func rawValueEncoding(capability: BackendCapability) throws {
            let data = try JSONEncoder().encode(capability)
            let json = String(data: data, encoding: .utf8)
            #expect(json == "\"\(capability.rawValue)\"")
        }

        @Test("Decoding unknown raw value fails gracefully")
        func unknownRawValueFails() throws {
            let json = "\"quantum\""
            let data = Data(json.utf8)
            #expect(throws: (any Error).self) {
                try JSONDecoder().decode(BackendCapability.self, from: data)
            }
        }
    }

    // MARK: - ExperimentalFlagsState

    @Suite("ExperimentalFlagsState")
    struct ExperimentalFlagsStateTests {

        @Test("Codable round-trip preserves all fields")
        func codableRoundTrip() throws {
            let original = ExperimentalFlagsState(
                enableBenchmark: true,
                enableSpeculativeDecoding: true,
                enableConversationConstrainedDecoding: true,
                visualTokenBudget: 256,
                enableThinking: false,
                enableToolCalling: true,
                enableAgentSkills: true
            )

            let data = try JSONEncoder().encode(original)
            let decoded = try JSONDecoder().decode(ExperimentalFlagsState.self, from: data)
            #expect(decoded == original)
        }

        @Test("Codable round-trip with nil optionals")
        func codableRoundTripNils() throws {
            let original = ExperimentalFlagsState(
                enableBenchmark: false,
                enableSpeculativeDecoding: nil,
                enableConversationConstrainedDecoding: false,
                visualTokenBudget: nil
            )

            let data = try JSONEncoder().encode(original)
            let decoded = try JSONDecoder().decode(ExperimentalFlagsState.self, from: data)
            #expect(decoded == original)
            #expect(decoded.enableSpeculativeDecoding == nil)
            #expect(decoded.visualTokenBudget == nil)
        }

        @Test("Equatable: identical states are equal")
        func equalStates() {
            let a = ExperimentalFlagsState(
                enableBenchmark: true,
                enableSpeculativeDecoding: nil,
                enableConversationConstrainedDecoding: false,
                visualTokenBudget: nil
            )
            let b = ExperimentalFlagsState(
                enableBenchmark: true,
                enableSpeculativeDecoding: nil,
                enableConversationConstrainedDecoding: false,
                visualTokenBudget: nil
            )
            #expect(a == b)
        }

        @Test("Equatable: differing enableBenchmark makes states unequal")
        func unequalBenchmark() {
            let a = ExperimentalFlagsState(
                enableBenchmark: true,
                enableSpeculativeDecoding: nil,
                enableConversationConstrainedDecoding: false,
                visualTokenBudget: nil
            )
            let b = ExperimentalFlagsState(
                enableBenchmark: false,
                enableSpeculativeDecoding: nil,
                enableConversationConstrainedDecoding: false,
                visualTokenBudget: nil
            )
            #expect(a != b)
        }

        @Test("Equatable: differing visualTokenBudget makes states unequal")
        func unequalVisualTokenBudget() {
            let a = ExperimentalFlagsState(
                enableBenchmark: true,
                enableSpeculativeDecoding: nil,
                enableConversationConstrainedDecoding: false,
                visualTokenBudget: 128
            )
            let b = ExperimentalFlagsState(
                enableBenchmark: true,
                enableSpeculativeDecoding: nil,
                enableConversationConstrainedDecoding: false,
                visualTokenBudget: 256
            )
            #expect(a != b)
        }

        @Test("Equatable: nil vs non-nil speculative decoding are unequal")
        func unequalSpeculativeDecoding() {
            let a = ExperimentalFlagsState(
                enableBenchmark: true,
                enableSpeculativeDecoding: nil,
                enableConversationConstrainedDecoding: false,
                visualTokenBudget: nil
            )
            let b = ExperimentalFlagsState(
                enableBenchmark: true,
                enableSpeculativeDecoding: true,
                enableConversationConstrainedDecoding: false,
                visualTokenBudget: nil
            )
            #expect(a != b)
        }

        @Test("Default values for enableThinking, enableToolCalling, enableAgentSkills")
        func defaultValues() {
            let state = ExperimentalFlagsState(
                enableBenchmark: true,
                enableSpeculativeDecoding: nil,
                enableConversationConstrainedDecoding: false,
                visualTokenBudget: nil
            )
            // Verify defaults from the init parameter list
            #expect(state.enableThinking == true)
            #expect(state.enableToolCalling == false)
            #expect(state.enableAgentSkills == false)
        }

        @Test("Is Sendable")
        func isSendable() async {
            let state = ExperimentalFlagsState(
                enableBenchmark: true,
                enableSpeculativeDecoding: nil,
                enableConversationConstrainedDecoding: false,
                visualTokenBudget: nil
            )
            let transferred = await Task.detached { state.enableBenchmark }.value
            #expect(transferred == true)
        }

        @Test("JSON contains expected keys")
        func jsonKeys() throws {
            let state = ExperimentalFlagsState(
                enableBenchmark: true,
                enableSpeculativeDecoding: false,
                enableConversationConstrainedDecoding: true,
                visualTokenBudget: 512,
                enableThinking: true,
                enableToolCalling: false,
                enableAgentSkills: true
            )

            let data = try JSONEncoder().encode(state)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let required = try #require(json)

            #expect(required["enableBenchmark"] as? Bool == true)
            #expect(required["enableSpeculativeDecoding"] as? Bool == false)
            #expect(required["enableConversationConstrainedDecoding"] as? Bool == true)
            #expect(required["visualTokenBudget"] as? Int == 512)
            #expect(required["enableThinking"] as? Bool == true)
            #expect(required["enableToolCalling"] as? Bool == false)
            #expect(required["enableAgentSkills"] as? Bool == true)
        }
    }

    // MARK: - BackendRecommendation

    @Suite("BackendRecommendation")
    struct BackendRecommendationTests {

        @Test("Raw values are correct")
        func rawValues() {
            #expect(BackendRecommendation.gpu.rawValue == "gpu")
            #expect(BackendRecommendation.cpu.rawValue == "cpu")
            #expect(BackendRecommendation.probeRequired.rawValue == "probeRequired")
        }

        @Test("Init from raw value round-trips",
              arguments: ["gpu", "cpu", "probeRequired"])
        func rawValueRoundTrip(rawValue: String) {
            let recommendation = BackendRecommendation(rawValue: rawValue)
            #expect(recommendation != nil)
            #expect(recommendation?.rawValue == rawValue)
        }

        @Test("Init from unknown raw value returns nil",
              arguments: ["GPU", "tpu", "", "probe_required"])
        func unknownRawValue(rawValue: String) {
            #expect(BackendRecommendation(rawValue: rawValue) == nil)
        }
    }
}
