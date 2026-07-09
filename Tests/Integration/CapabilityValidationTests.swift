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

import XCTest
import LiteRTLM

#if os(iOS)
@testable import EdgeAILab_iOS
#elseif os(macOS)
@testable import EdgeAILab_macOS
#endif

/// Validates that ModelMetadata capabilities match actual engine behavior.
///
/// The core question: "Does the metadata say this model supports X, and
/// does it ACTUALLY support X when we test it?"
///
/// This matters because the Trust Layer UI will use ModelMetadata to show
/// capability badges and warnings. If the metadata is wrong, the UI lies.
///
/// ## Test Pattern
/// For each capability:
/// 1. Read what ModelMetadata says the model supports
/// 2. Load the real model
/// 3. Test the capability with actual inference
/// 4. Compare declared vs. actual support
///
/// These tests DO NOT assert that metadata must be correct — they REPORT
/// discrepancies. The report becomes input for fixing either the metadata
/// or the engine behavior.
final class CapabilityValidationTests: XCTestCase {

    // MARK: - Setup

    override func setUpWithError() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Capability validation requires real Metal GPU — skipping on iOS Simulator")
        #endif
        try super.setUpWithError()
    }

    // MARK: - Model Discovery

    private var modelsDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // Integration/
            .deletingLastPathComponent()  // Tests/
            .deletingLastPathComponent()  // project root
            .appendingPathComponent("models")
    }

    private func findLiteRTModel(named filename: String) throws -> String {
        let modelURL = modelsDirectory.appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: modelURL.path) else {
            throw XCTSkip("Model \(filename) not found")
        }
        return modelURL.path
    }

    private func findMLXModel(named dirName: String) throws -> String {
        let modelURL = modelsDirectory.appendingPathComponent(dirName)
        let configURL = modelURL.appendingPathComponent("config.json")
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            throw XCTSkip("MLX model \(dirName) not found")
        }
        return modelURL.path
    }

    // MARK: - Helpers

    private func reportCapability(
        model: String,
        capability: String,
        declared: Bool,
        actual: String,
        detail: String
    ) {
        let match: String
        switch actual {
        case "SUPPORTED":
            match = declared ? "MATCH" : "MISMATCH_UNDECLARED"
        case "NOT_SUPPORTED":
            match = !declared ? "MATCH" : "MISMATCH_OVERCLAIMED"
        default:
            match = "UNKNOWN"
        }
        print("[CAPABILITY_VERIFY] model=\(model) | capability=\(capability) | declared=\(declared) | actual=\(actual) | match=\(match) | detail=\(detail)")
    }

    // MARK: - ModelRegistry Metadata Audit

    /// Audit all registered models' metadata for completeness and consistency.
    func testModelRegistryMetadataCompleteness() {
        let allModels = ModelRegistry.knownModels

        print("╔════════════════════════════════════════════════════")
        print("║ ModelRegistry Metadata Audit")
        print("╠════════════════════════════════════════════════════")

        for model in allModels {
            let issues: [String] = {
                var issues: [String] = []
                if model.name.isEmpty { issues.append("empty name") }
                if model.modelFile.isEmpty { issues.append("empty modelFile") }
                if model.sizeInBytes == 0 { issues.append("sizeInBytes=0") }
                if model.runtimeType == .litertlm && !model.modelFile.hasSuffix(".litertlm") {
                    issues.append("LiteRT model without .litertlm extension")
                }
                return issues
            }()

            print("║ \(model.name) (\(model.modelFile))")
            print("║   Runtime: \(model.runtimeType.displayName)")
            print("║   Multimodal: vision=\(model.supportsImage) audio=\(model.supportsAudio)")
            print("║   MTP: \(model.supportsMTP) | Tools: \(model.supportsToolCalling)")
            print("║   Issues: \(issues.isEmpty ? "none" : issues.joined(separator: ", "))")
            print("║")
        }
        print("╚════════════════════════════════════════════════════")
    }

    // MARK: - LiteRT E2B Standard: Full Capability Report

    /// Comprehensive capability validation for the primary test model.
    func testLiteRTE2BStandardCapabilities() async throws {
        let modelPath = try findLiteRTModel(named: "gemma-4-E2B-it.litertlm")

        // Look up metadata
        let metadata = ModelRegistry.lookup(filename: "gemma-4-E2B-it.litertlm")

        print("╔════════════════════════════════════════════════════")
        print("║ Capability Validation: gemma-4-E2B-it (LiteRT)")
        print("╠════════════════════════════════════════════════════")

        if let meta = metadata {
            print("║ Registry Match: ✅ \(meta.name)")
            print("║ Declared Capabilities:")
            print("║   supportsImage: \(meta.supportsImage)")
            print("║   supportsAudio: \(meta.supportsAudio)")
            print("║   supportsMTP: \(meta.supportsMTP)")
            print("║   supportsToolCalling: \(meta.supportsToolCalling)")
        } else {
            print("║ Registry Match: ❌ NOT FOUND in ModelRegistry")
        }

        // Test 1: Basic inference works
        let engine = InstrumentedEngine()
        let cacheDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CapabilityValidation-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

        let flags = ExperimentalFlagsState(
            enableBenchmark: true,
            enableSpeculativeDecoding: nil,
            enableConversationConstrainedDecoding: false,
            visualTokenBudget: nil
        )

        try await engine.initialize(
            modelPath: modelPath,
            useGPU: true,
            cacheDir: cacheDir.path,
            flags: flags,
            samplerConfig: try SamplerConfig(topK: 1, topP: 1.0, temperature: 1.0, seed: 42)
        )

        // Basic inference
        var response = ""
        for try await chunk in engine.sendMessageStream("Say hello in one word.") {
            response += chunk
        }
        let basicWorks = !response.isEmpty
        reportCapability(
            model: "gemma-4-E2B-it",
            capability: "basic_inference",
            declared: true,
            actual: basicWorks ? "SUPPORTED" : "NOT_SUPPORTED",
            detail: "response_length=\(response.count)"
        )

        // Test 2: Thinking mode
        var thinkingResponse = ""
        for try await chunk in engine.sendMessageStream("What is 5+5? Think step by step.", enableThinking: true) {
            thinkingResponse += chunk
        }
        let thinkingWorks = thinkingResponse.contains("<think>") || thinkingResponse.contains("</think>")
        reportCapability(
            model: "gemma-4-E2B-it",
            capability: "thinking_mode",
            declared: true,  // Gemma 4 models support thinking
            actual: thinkingWorks ? "SUPPORTED" : "NOT_SUPPORTED",
            detail: "has_think_tags=\(thinkingWorks) | response_length=\(thinkingResponse.count)"
        )

        // Test 3: Backend result
        let backendResult = engine.lastBackendResult
        reportCapability(
            model: "gemma-4-E2B-it",
            capability: "gpu_backend",
            declared: true,
            actual: backendResult != nil ? "SUPPORTED" : "NOT_SUPPORTED",
            detail: "backendResult=\(backendResult.map { "\($0)" } ?? "nil")"
        )

        // Test 4: Benchmark metrics
        let benchInfo = engine.lastBenchmarkInfo
        let hasBench = benchInfo != nil && (benchInfo?.lastDecodeTokensPerSecond ?? 0) > 0
        reportCapability(
            model: "gemma-4-E2B-it",
            capability: "benchmark_metrics",
            declared: true,
            actual: hasBench ? "SUPPORTED" : "NOT_SUPPORTED",
            detail: "tok/s=\(benchInfo?.lastDecodeTokensPerSecond ?? -1) | ttft=\(benchInfo?.timeToFirstTokenInSecond ?? -1)s"
        )

        await engine.shutdown()

        print("╚════════════════════════════════════════════════════")

        // Assert critical capabilities
        XCTAssertTrue(basicWorks, "E2B Standard must support basic inference")
    }

    // MARK: - MLX Gemma 4 E2B: Full Capability Report

    /// Comprehensive capability validation for the MLX model.
    func testMLXE2BCapabilities() async throws {
        #if !canImport(MLX)
        throw XCTSkip("MLX framework not available")
        #else
        let modelPath = try findMLXModel(named: "mlx-community--gemma-4-e2b-it-4bit")

        // Look up metadata
        let metadata = ModelRegistry.lookup(filename: "mlx-community--gemma-4-E2B-it-4bit")
            ?? ModelRegistry.lookup(filename: "mlx-community--gemma-4-e2b-it-4bit")

        print("╔════════════════════════════════════════════════════")
        print("║ Capability Validation: gemma-4-e2b-it-4bit (MLX)")
        print("╠════════════════════════════════════════════════════")

        if let meta = metadata {
            print("║ Registry Match: ✅ \(meta.name)")
            print("║ Declared Capabilities:")
            print("║   supportsImage: \(meta.supportsImage)")
            print("║   supportsAudio: \(meta.supportsAudio)")
            print("║   supportsMTP: \(meta.supportsMTP)")
            print("║   supportsToolCalling: \(meta.supportsToolCalling)")
        } else {
            print("║ Registry Match: ❌ NOT FOUND in ModelRegistry")
        }

        // Test: Basic inference
        let adapter = MLXEngineAdapter()
        let cacheDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MLXCapabilityValidation-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

        let config = ModelLoadConfig(
            modelPath: modelPath,
            preferGPU: true,
            cacheDir: cacheDir.path,
            generationConfig: GenerationConfig(
                maxTokens: 100,
                temperature: 1.0,
                topP: 1.0,
                topK: 1,
                seed: 42
            )
        )

        try await adapter.loadModel(config: config)
        XCTAssertTrue(adapter.isLoaded, "MLX adapter should be loaded")

        var response = ""
        var metrics: EnginePerformanceMetrics?
        let genConfig = GenerationConfig(maxTokens: 100, temperature: 1.0, topP: 1.0, topK: 1, seed: 42)

        for try await event in adapter.generateStream(prompt: "Say hello in one word.", config: genConfig) {
            switch event {
            case .text(let chunk):
                response += chunk
            case .metrics(let m):
                metrics = m
            case .toolCall, .done:
                break
            }
        }

        let basicWorks = !response.isEmpty
        reportCapability(
            model: "gemma-4-e2b-it-4bit",
            capability: "basic_inference",
            declared: true,
            actual: basicWorks ? "SUPPORTED" : "NOT_SUPPORTED",
            detail: "response_length=\(response.count) | tok/s=\(metrics?.tokensPerSecond ?? -1)"
        )

        // Performance metrics
        reportCapability(
            model: "gemma-4-e2b-it-4bit",
            capability: "performance_metrics",
            declared: true,
            actual: metrics != nil ? "SUPPORTED" : "NOT_SUPPORTED",
            detail: "tok/s=\(metrics?.tokensPerSecond ?? -1) | ttft=\(metrics?.timeToFirstToken ?? -1)s"
        )

        await adapter.shutdown()

        print("╚════════════════════════════════════════════════════")

        XCTAssertTrue(basicWorks, "MLX E2B must support basic inference")
        #endif
    }

    // MARK: - Cross-Model Capability Comparison

    /// Print a comparison table of declared capabilities across all available models.
    func testCapabilityComparisonTable() {
        let models = ModelRegistry.knownModels

        print("╔════════════════════════════════════════════════════════════════════════")
        print("║ Cross-Model Capability Matrix (from ModelRegistry)")
        print("╠════════════════════════════════════════════════════════════════════════")
        print("║ Model                          | Vision | Audio | MTP  | Tools | Runtime")
        print("╠════════════════════════════════════════════════════════════════════════")

        for model in models {
            let name = model.name.padding(toLength: 30, withPad: " ", startingAt: 0)
            let vision = model.supportsImage ? "  ✅  " : "  ❌  "
            let audio = model.supportsAudio ? "  ✅  " : "  ❌  "
            let mtp = model.supportsMTP ? "  ✅  " : "  ❌  "
            let tools = model.supportsToolCalling ? "  ✅  " : "  ❌  "
            let runtime = model.runtimeType.displayName
            print("║ \(name) |\(vision)|\(audio)|\(mtp)|\(tools)| \(runtime)")
        }

        print("╚════════════════════════════════════════════════════════════════════════")
    }
}
