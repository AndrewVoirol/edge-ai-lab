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

import XCTest
import LiteRTLM

#if os(iOS)
@testable import EdgeAILab_iOS
#elseif os(macOS)
@testable import EdgeAILab_macOS
#endif

/// Integration tests that load real AI models and run real inference.
///
/// These tests validate that the inference pipeline produces correct,
/// coherent output — not just that it's wired up correctly. They use
/// the actual `InstrumentedEngine` against models in the `models/` directory.
///
/// All tests use `XCTSkip` when the required model isn't found, so they
/// gracefully degrade on machines without staged models.
final class InferenceQualityTests: XCTestCase {

    override func setUpWithError() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("E2E test requires real Metal GPU — skipping on iOS Simulator")
        #endif
        try super.setUpWithError()
    }

    // MARK: - Model Discovery

    /// Scans the project's `models/` directory and the app Documents for `.litertlm` files.
    private var availableModels: [URL] {
        var models: [URL] = []

        #if os(macOS) || targetEnvironment(simulator)
        let projectModels = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // Engine/
            .deletingLastPathComponent()  // Tests/
            .deletingLastPathComponent()  // project root
            .appendingPathComponent("models")
        if let found = findModels(in: projectModels) {
            models.append(contentsOf: found)
        }
        #endif

        if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            if let found = findModels(in: docs) {
                models.append(contentsOf: found)
            }
        }

        var seen = Set<String>()
        return models.filter { url in
            let name = url.lastPathComponent
            if seen.contains(name) { return false }
            seen.insert(name)
            return true
        }
    }

    private func findModels(in directory: URL) -> [URL]? {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        ) else { return nil }
        let models = files.filter { $0.pathExtension == "litertlm" }
        return models.isEmpty ? nil : models
    }

    private func findModel(named filename: String) throws -> String {
        guard let model = availableModels.first(where: { $0.lastPathComponent == filename }) else {
            throw XCTSkip("Model \(filename) not available on this platform")
        }
        return model.path
    }

    private func findAnyModel() throws -> String {
        guard let model = availableModels.first else {
            throw XCTSkip("No models available in models/ directory")
        }
        return model.path
    }

    // MARK: - Engine Helpers

    /// Create a fresh InstrumentedEngine initialized with greedy sampling.
    private func makeEngine(modelPath: String, useGPU: Bool = true) async throws -> InstrumentedEngine {
        let engine = InstrumentedEngine()
        let cacheDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("InferenceQualityTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

        let flags = ExperimentalFlagsState(
            enableBenchmark: true,
            enableSpeculativeDecoding: nil,
            enableConversationConstrainedDecoding: false,
            visualTokenBudget: nil
        )

        try await engine.initialize(
            modelPath: modelPath,
            useGPU: useGPU,
            cacheDir: cacheDir.path,
            flags: flags,
            samplerConfig: try SamplerConfig(topK: 1, topP: 1.0, temperature: 1.0, seed: 0)
        )

        return engine
    }

    /// Collect the full response from an inference stream.
    private func collectResponse(from engine: InstrumentedEngine, prompt: String, enableThinking: Bool = false) async throws -> String {
        var response = ""
        for try await chunk in engine.sendMessageStream(prompt, enableThinking: enableThinking) {
            response += chunk
        }
        return response
    }

    // MARK: - Tests

    /// Load every available model, send a simple prompt, and verify non-empty,
    /// non-degenerate output. This is the broadest check: "does inference work at all?"
    func testAllAvailableModelsProduceCoherentOutput() async throws {
        let models = availableModels
        guard !models.isEmpty else {
            throw XCTSkip("No models available in models/ directory")
        }

        for modelURL in models {
            let modelPath = modelURL.path
            let modelName = modelURL.lastPathComponent

            print("╔═══════════════════════════════════════════")
            print("║ Testing: \(modelName)")
            print("╚═══════════════════════════════════════════")

            let engine = try await makeEngine(modelPath: modelPath)
            defer {
                Task { @MainActor in await engine.shutdown() }
            }

            XCTAssertTrue(engine.isReady, "[\(modelName)] Engine should be ready after init")

            let response = try await collectResponse(from: engine, prompt: "What is 2+2? Answer in one word.")

            XCTAssertFalse(response.isEmpty, "[\(modelName)] Response should not be empty")

            // Check for degenerate output (same token repeated many times)
            let words = response.split(separator: " ")
            let uniqueWords = Set(words)
            if words.count > 5 {
                #if targetEnvironment(simulator)
                if uniqueWords.count <= 2 {
                    print("  ⚠️ Degenerate output on simulator (expected)")
                }
                #else
                XCTAssertGreaterThan(uniqueWords.count, 2,
                    "[\(modelName)] Degenerate output — \(uniqueWords.count) unique words in \(words.count)")
                #endif
            }

            print("  ✅ Response (\(response.count) chars): \(response.prefix(100))")
        }

        print("✅ All \(models.count) model(s) produced coherent output")
    }

    /// Send the same prompt twice with greedy sampling and verify identical output.
    /// This validates that the sampler config is respected and output is reproducible.
    func testDeterministicOutputWithGreedySampling() async throws {
        let modelPath = try findModel(named: "gemma-4-E2B-it.litertlm")

        let engine = try await makeEngine(modelPath: modelPath)
        defer {
            Task { @MainActor in await engine.shutdown() }
        }

        let prompt = "Name three primary colors. List them separated by commas."

        // First run
        let response1 = try await collectResponse(from: engine, prompt: prompt)
        XCTAssertFalse(response1.isEmpty, "First response should not be empty")

        // Reset conversation to clear context
        try await engine.resetConversation()

        // Second run — should be identical with greedy decoding
        let response2 = try await collectResponse(from: engine, prompt: prompt)
        XCTAssertFalse(response2.isEmpty, "Second response should not be empty")

        XCTAssertEqual(response1, response2,
            "Greedy sampling should produce identical output for the same prompt. " +
            "Got:\n  Run 1: \(response1.prefix(200))\n  Run 2: \(response2.prefix(200))")
    }

    /// Send "My name is Alice", then ask "What is my name?", and verify
    /// the model maintains conversational context across turns.
    func testConversationContextMaintained() async throws {
        let modelPath = try findModel(named: "gemma-4-E2B-it.litertlm")

        let engine = try await makeEngine(modelPath: modelPath)
        defer {
            Task { @MainActor in await engine.shutdown() }
        }

        // Turn 1: establish context
        let _ = try await collectResponse(from: engine, prompt: "My name is Alice. Remember that.")

        // Turn 2: query context
        let response = try await collectResponse(from: engine, prompt: "What is my name? Just say the name, nothing else.")

        XCTAssertFalse(response.isEmpty, "Response should not be empty")
        XCTAssertTrue(response.lowercased().contains("alice"),
            "Model should remember the name 'Alice' from the previous turn. Got: \(response)")
    }

    /// Run inference with thinking mode enabled and verify the engine
    /// handles the `enableThinking: true` parameter without crashing.
    func testThinkingModeProducesOutput() async throws {
        let modelPath = try findModel(named: "gemma-4-E2B-it.litertlm")

        let engine = try await makeEngine(modelPath: modelPath)
        defer {
            Task { @MainActor in await engine.shutdown() }
        }

        let response = try await collectResponse(
            from: engine,
            prompt: "What is 15 * 23? Show your reasoning.",
            enableThinking: true
        )

        XCTAssertFalse(response.isEmpty,
            "Thinking mode should still produce output (response was empty)")
    }

    /// Initialize and shut down the engine 3 times, running inference each cycle.
    /// This validates there are no resource leaks or state corruption across init/shutdown cycles.
    func testRepeatedInitShutdownCycles() async throws {
        let modelPath = try findAnyModel()

        for cycle in 1...3 {
            print("🔄 Cycle \(cycle)/3")

            let engine = try await makeEngine(modelPath: modelPath)
            XCTAssertTrue(engine.isReady, "Cycle \(cycle): Engine should be ready after init")

            let response = try await collectResponse(from: engine, prompt: "Say hello.")
            XCTAssertFalse(response.isEmpty, "Cycle \(cycle): Response should not be empty")

            await engine.shutdown()
            XCTAssertFalse(engine.isReady, "Cycle \(cycle): Engine should not be ready after shutdown")
        }

        print("✅ 3 init/shutdown cycles completed without crash")
    }

    /// If a vision-capable model is available, send image data and verify
    /// the model produces a non-empty response. Skips if no vision model found.
    func testMultimodalInferenceWithImage() async throws {
        // Find a model that supports image input
        let visionModel = availableModels.first { modelURL in
            let metadata = KnownModelCatalog.lookup(path: modelURL.path)
            return metadata?.hasVision == true
        }

        guard let visionModelURL = visionModel else {
            throw XCTSkip("No vision-capable model available")
        }

        // Vision models need supportsVision: true during initialization
        // to load the vision executor in the native layer.
        let engine = InstrumentedEngine()
        let cacheDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("InferenceQualityTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

        let flags = ExperimentalFlagsState(
            enableBenchmark: true,
            enableSpeculativeDecoding: nil,
            enableConversationConstrainedDecoding: false,
            visualTokenBudget: nil
        )

        try await engine.initialize(
            modelPath: visionModelURL.path,
            useGPU: true,
            cacheDir: cacheDir.path,
            flags: flags,
            samplerConfig: try SamplerConfig(topK: 1, topP: 1.0, temperature: 1.0, seed: 0),
            systemMessage: nil,
            tools: nil,
            supportsVision: true
        )

        defer {
            Task { @MainActor in await engine.shutdown() }
        }

        // Create a minimal 1x1 red PNG
        let pngData = createMinimalPNG()

        var response = ""
        for try await chunk in engine.sendMessageStream(
            "Describe what you see in this image.",
            imageData: pngData,
            audioData: nil,
            enableThinking: false
        ) {
            response += chunk
        }

        XCTAssertFalse(response.isEmpty,
            "Multimodal inference should produce non-empty output")
        print("  ✅ Multimodal response (\(response.count) chars): \(response.prefix(100))")
    }

    // MARK: - Helpers

    /// Create a minimal valid 1x1 red PNG (67 bytes).
    private func createMinimalPNG() -> Data {
        // PNG header + IHDR + IDAT + IEND for a 1x1 red pixel
        let header: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        let ihdr: [UInt8] = [
            0x00, 0x00, 0x00, 0x0D, // length: 13
            0x49, 0x48, 0x44, 0x52, // "IHDR"
            0x00, 0x00, 0x00, 0x01, // width: 1
            0x00, 0x00, 0x00, 0x01, // height: 1
            0x08, 0x02,             // bit depth: 8, color type: RGB
            0x00, 0x00, 0x00,       // compression, filter, interlace
            0x90, 0x77, 0x53, 0xDE  // CRC
        ]
        let idat: [UInt8] = [
            0x00, 0x00, 0x00, 0x0C, // length: 12
            0x49, 0x44, 0x41, 0x54, // "IDAT"
            0x08, 0xD7, 0x63, 0xF8, 0xCF, 0xC0, 0x00, 0x00,
            0x01, 0x01, 0x01, 0x00,
            0x18, 0xDD, 0x8D, 0xB4  // CRC
        ]
        let iend: [UInt8] = [
            0x00, 0x00, 0x00, 0x00, // length: 0
            0x49, 0x45, 0x4E, 0x44, // "IEND"
            0xAE, 0x42, 0x60, 0x82  // CRC
        ]

        return Data(header + ihdr + idat + iend)
    }
}
