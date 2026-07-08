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

// MARK: - Test Helper

/// Builds a minimal `ModelMetadata` for unit tests.
private func makeMetadata(
    name: String = "Test Model",
    modelId: String = "test-org/test-model-it-litert-lm",
    modelFile: String = "test-model.litertlm",
    supportsImage: Bool = false,
    supportsAudio: Bool = false,
    capabilities: [String] = []
) -> ModelMetadata {
    ModelMetadata(
        name: name,
        modelId: modelId,
        modelFile: modelFile,
        description: "A test model",
        sizeInBytes: 1_000_000,
        minDeviceMemoryGB: 8,
        contextWindowSize: 128_000,
        architectureType: "Test",
        recommendedFor: "Testing",
        supportsImage: supportsImage,
        supportsAudio: supportsAudio,
        capabilities: capabilities,
        defaultConfig: ModelDefaultConfig(
            topK: 64,
            topP: 0.95,
            temperature: 1.0,
            maxContextLength: 32_000,
            maxTokens: 4_000,
            accelerators: "gpu,cpu",
            visionAccelerator: nil
        ),
        platformSupport: PlatformSupport(
            macOS: .gpuAndCpu,
            iOSDevice: .cpuOnly,
            iOSSimulator: .cpuOnly
        )
    )
}

// MARK: - ModelMetadataSwiftTests

@Suite("ModelMetadata")
struct ModelMetadataSwiftTests {

    // =========================================================================
    // MARK: - BackendCapability
    // =========================================================================

    @Suite("BackendCapability")
    struct BackendCapabilityTests {

        @Test("gpuOnly: supportsGPU true, supportsCPU false, recommendedBackend .gpu")
        func gpuOnly() {
            let cap = BackendCapability.gpuOnly
            #expect(cap.supportsGPU == true)
            #expect(cap.supportsCPU == false)
            #expect(cap.recommendedBackend == .gpu)
        }

        @Test("cpuOnly: supportsGPU false, supportsCPU true, recommendedBackend .cpu")
        func cpuOnly() {
            let cap = BackendCapability.cpuOnly
            #expect(cap.supportsGPU == false)
            #expect(cap.supportsCPU == true)
            #expect(cap.recommendedBackend == .cpu)
        }

        @Test("gpuAndCpu: supportsGPU true, supportsCPU true, recommendedBackend .gpu")
        func gpuAndCpu() {
            let cap = BackendCapability.gpuAndCpu
            #expect(cap.supportsGPU == true)
            #expect(cap.supportsCPU == true)
            #expect(cap.recommendedBackend == .gpu)
        }

        @Test("unknown: supportsGPU false, supportsCPU false, recommendedBackend .probeRequired")
        func unknown() {
            let cap = BackendCapability.unknown
            #expect(cap.supportsGPU == false)
            #expect(cap.supportsCPU == false)
            #expect(cap.recommendedBackend == .probeRequired)
        }
    }

    // =========================================================================
    // MARK: - RuntimeType
    // =========================================================================

    @Suite("RuntimeType")
    struct RuntimeTypeTests {

        @Test("litertlm: displayName, fileExtension, isSupported")
        func litertlm() {
            let rt = RuntimeType.litertlm
            #expect(rt.displayName == "LiteRT-LM")
            #expect(rt.fileExtension == "litertlm")
            #expect(rt.isSupported == true)
        }

        @Test("mlx: displayName, fileExtension, isSupported")
        func mlx() {
            let rt = RuntimeType.mlx
            #expect(rt.displayName == "MLX")
            #expect(rt.fileExtension == "safetensors")
            #expect(rt.isSupported == true)
        }

        @Test("gguf: displayName, fileExtension, isSupported")
        func gguf() {
            let rt = RuntimeType.gguf
            #expect(rt.displayName == "GGUF")
            #expect(rt.fileExtension == "gguf")
            #expect(rt.isSupported == true)
        }

        @Test("CaseIterable has exactly 3 cases")
        func caseCount() {
            #expect(RuntimeType.allCases.count == 3)
        }
    }

    // =========================================================================
    // MARK: - ModelMetadata Computed Properties
    // =========================================================================

    @Suite("Computed Properties")
    struct ComputedPropertyTests {

        @Test("downloadURL contains huggingface.co, modelId, and modelFile")
        func downloadURL() {
            let meta = makeMetadata(
                modelId: "litert-community/gemma-4-E2B-it-litert-lm",
                modelFile: "gemma-4-E2B-it.litertlm"
            )
            let url = meta.downloadURL
            #expect(url != nil)
            let urlString = url!.absoluteString
            #expect(urlString.contains("huggingface.co"))
            #expect(urlString.contains("litert-community/gemma-4-E2B-it-litert-lm"))
            #expect(urlString.contains("gemma-4-E2B-it.litertlm"))
        }

        @Test("requiresAuth true when modelId starts with google/")
        func requiresAuthGated() {
            let meta = makeMetadata(modelId: "google/gemma-3n-E2B-it-litert-lm")
            #expect(meta.requiresAuth == true)
        }

        @Test("requiresAuth false for litert-community/")
        func requiresAuthPublic() {
            let meta = makeMetadata(modelId: "litert-community/gemma-4-E2B-it-litert-lm")
            #expect(meta.requiresAuth == false)
        }

        @Test("supportsMTP true when capabilities contains speculative_decoding")
        func supportsMTPTrue() {
            let meta = makeMetadata(capabilities: ["speculative_decoding", "llm_thinking"])
            #expect(meta.supportsMTP == true)
        }

        @Test("supportsMTP false when capabilities lacks speculative_decoding")
        func supportsMTPFalse() {
            let meta = makeMetadata(capabilities: ["llm_thinking"])
            #expect(meta.supportsMTP == false)
        }

        @Test("supportsToolCalling true when modelId contains -it")
        func supportsToolCallingTrue() {
            let meta = makeMetadata(modelId: "test-org/test-model-it-litert-lm")
            #expect(meta.supportsToolCalling == true)
        }

        @Test("supportsToolCalling false when modelId lacks -it")
        func supportsToolCallingFalse() {
            let meta = makeMetadata(modelId: "test-org/test-model-base-litert-lm")
            #expect(meta.supportsToolCalling == false)
        }
    }

    // =========================================================================
    // MARK: - ModelRegistry
    // =========================================================================

    @Suite("ModelRegistry")
    struct ModelRegistryTests {

        @Test("knownModels has at least 5 entries")
        func knownModelsCount() {
            #expect(ModelRegistry.knownModels.count >= 7)
        }

        @Test("lookup(filename:) returns non-nil for a known model")
        func lookupKnownFilename() {
            // Use the first known model's filename
            let knownFile = ModelRegistry.knownModels[0].modelFile
            let result = ModelRegistry.lookup(filename: knownFile)
            #expect(result != nil)
            #expect(result?.modelFile == knownFile)
        }

        @Test("lookup(filename:) returns nil for unknown filename")
        func lookupUnknownFilename() {
            let result = ModelRegistry.lookup(filename: "not-a-real-model.litertlm")
            #expect(result == nil)
        }

        @Test("lookup(path:) extracts filename from full path and matches")
        func lookupByPath() {
            let knownFile = ModelRegistry.knownModels[0].modelFile
            let fullPath = "/Users/test/Documents/models/\(knownFile)"
            let result = ModelRegistry.lookup(path: fullPath)
            #expect(result != nil)
            #expect(result?.modelFile == knownFile)
        }

        @Test("recommendedBackend for known model path is not .probeRequired")
        func recommendedBackendKnown() {
            let knownFile = ModelRegistry.knownModels[0].modelFile
            let path = "/some/path/\(knownFile)"
            let backend = ModelRegistry.recommendedBackend(for: path)
            #expect(backend != .probeRequired)
        }

        @Test("recommendedBackend for unknown path is .probeRequired")
        func recommendedBackendUnknown() {
            let backend = ModelRegistry.recommendedBackend(for: "/some/path/unknown-model.litertlm")
            #expect(backend == .probeRequired)
        }
    }

    // =========================================================================
    // MARK: - Codable Round-Trip
    // =========================================================================

    @Suite("Codable")
    struct CodableTests {

        @Test("encode and decode preserves all fields")
        func roundTrip() throws {
            let original = makeMetadata(
                name: "Round-Trip Test",
                modelId: "test-org/round-trip-it",
                modelFile: "round-trip.litertlm",
                supportsImage: true,
                supportsAudio: false,
                capabilities: ["speculative_decoding"]
            )

            let encoder = JSONEncoder()
            let decoder = JSONDecoder()

            let data = try encoder.encode(original)
            let decoded = try decoder.decode(ModelMetadata.self, from: data)

            #expect(decoded.name == original.name)
            #expect(decoded.modelId == original.modelId)
            #expect(decoded.modelFile == original.modelFile)
            #expect(decoded.sizeInBytes == original.sizeInBytes)
            #expect(decoded.minDeviceMemoryGB == original.minDeviceMemoryGB)
            #expect(decoded.contextWindowSize == original.contextWindowSize)
            #expect(decoded.supportsImage == original.supportsImage)
            #expect(decoded.supportsAudio == original.supportsAudio)
            #expect(decoded.capabilities == original.capabilities)
            #expect(decoded.runtimeType == original.runtimeType)
        }

        @Test("decode without runtimeType field defaults to .litertlm")
        func missingRuntimeTypeDefaults() throws {
            // Build JSON manually without the runtimeType key
            let json: [String: Any] = [
                "name": "Legacy Model",
                "modelId": "test-org/legacy-it",
                "modelFile": "legacy.litertlm",
                "description": "A legacy model without runtimeType",
                "sizeInBytes": 1_000_000,
                "minDeviceMemoryGB": 8,
                "contextWindowSize": 128_000,
                "architectureType": "Test",
                "recommendedFor": "Testing",
                "supportsImage": false,
                "supportsAudio": false,
                "capabilities": ["llm_thinking"],
                "defaultConfig": [
                    "topK": 64,
                    "topP": 0.95,
                    "temperature": 1.0,
                    "maxContextLength": 32_000,
                    "maxTokens": 4_000,
                    "accelerators": "gpu,cpu",
                ] as [String: Any],
                "platformSupport": [
                    "macOS": "gpuAndCpu",
                    "iOSDevice": "cpuOnly",
                    "iOSSimulator": "cpuOnly",
                ] as [String: String],
            ]

            let data = try JSONSerialization.data(withJSONObject: json)
            let decoded = try JSONDecoder().decode(ModelMetadata.self, from: data)

            #expect(decoded.runtimeType == .litertlm)
            #expect(decoded.name == "Legacy Model")
        }
    }
}
