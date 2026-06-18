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

/// Integration tests for the smart backend fallback system.
///
/// These tests exercise the REAL user code path:
///
///   ModelRegistry.lookup() → platformSupport.currentPlatform → recommendedBackend
///   → initializeWithFallback() → inference
///
/// This is what the app does when a user opens it. If these tests pass, the user's
/// experience matches what our platform support matrix says it should be.
///
/// **Why this exists:** Session 1 set `gemma4E2BStandard.iOSDevice = .cpuOnly` which
/// was wrong (GPU works on device). A direct backend test never caught this because
/// it bypasses the ModelRegistry routing entirely. This test catches that class of bug.
final class SmartFallbackIntegrationTests: XCTestCase {

    override func setUpWithError() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("E2E test requires real Metal GPU — skipping on iOS Simulator")
        #endif
        try super.setUpWithError()
    }

    // MARK: - Model Discovery

    private var availableModels: [URL] {
        var models: [URL] = []

        #if os(macOS) || targetEnvironment(simulator)
        let projectModels = URL(fileURLWithPath: #filePath)
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

    // MARK: - Platform Identity

    private var platformName: String {
        #if targetEnvironment(simulator)
        return "iOS Simulator"
        #elseif os(iOS)
        return "iOS Device"
        #elseif os(macOS)
        return "macOS"
        #else
        return "Unknown"
        #endif
    }

    // MARK: - Integration Test: ModelRegistry → Recommended Backend

    /// Verify that ModelRegistry returns the expected backend recommendation
    /// for every known model on the current platform.
    /// This is a fast, no-model-loading test that validates the metadata layer.
    func testRegistryRecommendations_AllKnownModels() throws {
        print("╔══════════════════════════════════════════════")
        print("║ REGISTRY RECOMMENDATION TEST — \(platformName)")
        print("╚══════════════════════════════════════════════")

        for model in ModelRegistry.knownModels {
            let capability = model.platformSupport.currentPlatform
            let recommendation = capability.recommendedBackend

            print("  \(model.name)")
            print("    Capability: \(capability.rawValue)")
            print("    Recommendation: \(recommendation.rawValue)")

            // No model should be .unknown on any platform we test on
            // If we see .unknown, it means we haven't filled in the platform data
            #if !targetEnvironment(simulator)
            // On real platforms (macOS, iOS device), .unknown means untested — flag it
            if capability == .unknown {
                XCTFail("[\(model.name)] platformSupport is .unknown on \(platformName) — fill in verified data")
            }
            #endif

            // Verify recommendation is internally consistent
            switch capability {
            case .gpuOnly:
                XCTAssertEqual(recommendation, .gpu,
                    "[\(model.name)] gpuOnly should recommend .gpu")
            case .cpuOnly:
                XCTAssertEqual(recommendation, .cpu,
                    "[\(model.name)] cpuOnly should recommend .cpu")
            case .gpuAndCpu:
                XCTAssertEqual(recommendation, .gpu,
                    "[\(model.name)] gpuAndCpu should recommend .gpu (prefer GPU)")
            case .unknown:
                XCTAssertEqual(recommendation, .probeRequired,
                    "[\(model.name)] unknown should recommend .probeRequired")
            }
        }

        print("✅ All \(ModelRegistry.knownModels.count) model registry recommendations validated")
    }

    // MARK: - Integration Test: Full Smart Fallback Path

    /// Test the COMPLETE user code path for each available model:
    /// ModelRegistry.lookup → recommendedBackend → initializeWithFallback → inference
    ///
    /// This is what happens when the user opens the app and a model auto-loads.
    func testSmartFallback_DesktopModel() async throws {
        let modelPath = try findModel(named: "gemma-4-E2B-it.litertlm")
        try await runSmartFallbackTest(
            modelPath: modelPath,
            expectedFilename: "gemma-4-E2B-it.litertlm",
            label: "Desktop GPU+CPU"
        )
    }

    func testSmartFallback_MobileModel() async throws {
        let modelPath = try findModel(named: "gemma-4-E2B-it-web.litertlm")
        try await runSmartFallbackTest(
            modelPath: modelPath,
            expectedFilename: "gemma-4-E2B-it-web.litertlm",
            label: "Mobile GPU"
        )
    }

    // MARK: - Core Integration Test Runner

    /// Exercises the real smart fallback path and validates the result matches expectations.
    private func runSmartFallbackTest(
        modelPath: String,
        expectedFilename: String,
        label: String
    ) async throws {
        print("╔══════════════════════════════════════════════")
        print("║ SMART FALLBACK TEST — \(label) on \(platformName)")
        print("╚══════════════════════════════════════════════")

        // Step 1: Verify ModelRegistry lookup
        let metadata = ModelRegistry.lookup(path: modelPath)
        XCTAssertNotNil(metadata, "[\(label)] ModelRegistry should recognize \(expectedFilename)")
        guard let metadata = metadata else { return }

        print("  ✓ Registry lookup: \(metadata.name)")

        // Step 2: Verify platform support is not .unknown
        let capability = metadata.platformSupport.currentPlatform
        print("  ✓ Platform capability: \(capability.rawValue)")

        #if !targetEnvironment(simulator)
        XCTAssertNotEqual(capability, .unknown,
            "[\(label)] Platform support should be filled in (not .unknown) on \(platformName)")
        #endif

        // Step 3: Get recommended backend
        let recommendation = capability.recommendedBackend
        print("  ✓ Recommended backend: \(recommendation.rawValue)")

        // Step 4: Create engine and run smart fallback (THE REAL CODE PATH)
        let engine = InstrumentedEngine()
        let cacheDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("integration_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

        defer {
            Task { @MainActor in
                await engine.shutdown()
            }
            try? FileManager.default.removeItem(at: cacheDir)
        }

        let flags = ExperimentalFlagsState(
            enableBenchmark: true,
            enableSpeculativeDecoding: nil,
            enableConversationConstrainedDecoding: false,
            visualTokenBudget: nil
        )

        let startTime = CFAbsoluteTimeGetCurrent()

        let result: BackendResult
        do {
            result = try await engine.initializeWithFallback(
                modelPath: modelPath,
                preferGPU: true,  // This is what the app sends — prefer GPU
                cacheDir: cacheDir.path,
                flags: flags
            )
        } catch {
            XCTFail("[\(label)] Smart fallback failed completely: \(error)")
            return
        }

        let loadTime = CFAbsoluteTimeGetCurrent() - startTime

        print("  ✓ Engine initialized in \(String(format: "%.2f", loadTime))s")
        print("    Active backend: \(result.activeBackend.rawValue)")
        print("    Did fallback: \(result.didFallback)")
        if let reason = result.fallbackReason {
            print("    Fallback reason: \(reason)")
        }

        // Step 5: Validate the result matches what the registry said should happen
        switch recommendation {
        case .gpu:
            XCTAssertEqual(result.activeBackend, .gpu,
                "[\(label)] Registry recommends GPU but engine activated \(result.activeBackend.rawValue)")
            if capability == .gpuOnly {
                // GPU-only model: fallback should NOT have triggered (there's no CPU to fall to)
                XCTAssertFalse(result.didFallback,
                    "[\(label)] GPU-only model should not trigger fallback")
            }
        case .cpu:
            XCTAssertEqual(result.activeBackend, .cpu,
                "[\(label)] Registry recommends CPU but engine activated \(result.activeBackend.rawValue)")
        case .probeRequired:
            // Unknown model — just confirm something initialized
            print("  ⚠️ probeRequired — accepting whatever backend succeeded")
        }

        // Step 6: Run actual inference to confirm it's not just loading
        XCTAssertTrue(engine.isReady, "[\(label)] Engine should be ready after smart fallback")

        let inferenceStart = CFAbsoluteTimeGetCurrent()
        var responseText = ""

        for try await chunk in engine.sendMessageStream("What is 2+2? Answer in one word.") {
            responseText += chunk
        }

        let inferenceTime = CFAbsoluteTimeGetCurrent() - inferenceStart

        XCTAssertFalse(responseText.isEmpty,
            "[\(label)] Inference should produce non-empty output")

        // Check for degenerate output (same token repeated)
        let words = responseText.split(separator: " ")
        let uniqueWords = Set(words)

        #if targetEnvironment(simulator)
        if uniqueWords.count <= 2 && words.count > 5 {
            throw XCTSkip("[\(label)] Degenerate output on simulator (expected)")
        }
        #else
        if uniqueWords.count <= 2 && words.count > 5 {
            XCTFail("[\(label)] Degenerate output — \(uniqueWords.count) unique words in \(words.count)")
        }
        #endif

        // Step 7: Report
        print("  ✓ Inference completed in \(String(format: "%.2f", inferenceTime))s")
        print("    Response (\(responseText.count) chars): \(responseText.prefix(100))...")

        if let bench = engine.lastBenchmarkInfo {
            print("    Decode: \(String(format: "%.1f", bench.lastDecodeTokensPerSecond)) tok/s")
            print("    Prefill: \(String(format: "%.1f", bench.lastPrefillTokensPerSecond)) tok/s")
            print("    TTFT: \(String(format: "%.3f", bench.timeToFirstTokenInSecond))s")
        }

        print("✅ [\(label)] Smart fallback integration test PASSED")
        print("   Path: Registry(\(capability.rawValue)) → Recommend(\(recommendation.rawValue)) → Active(\(result.activeBackend.rawValue)) → Inference ✓")
    }
    func testMultiTurnInference() async throws {
        // Find E4B model in the models/ directory
        let sourceFileURL = URL(fileURLWithPath: #filePath)
        let projectRoot = sourceFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let modelPath = projectRoot.appendingPathComponent("models/gemma-4-E4B-it.litertlm").path
        
        guard FileManager.default.fileExists(atPath: modelPath) else {
            throw XCTSkip("E4B model not found at \(modelPath). Skipping test.")
        }

        print("🚀 Initializing engine...")
        let engine = InstrumentedEngine()
        let flags = ExperimentalFlagsState(enableBenchmark: true, enableSpeculativeDecoding: nil, enableConversationConstrainedDecoding: false, visualTokenBudget: nil)
        
        try await engine.initialize(
            modelPath: modelPath,
            useGPU: true,
            cacheDir: NSTemporaryDirectory(),
            flags: flags,
            samplerConfig: SamplerConfig(topK: 64, topP: 0.95, temperature: 1.0, seed: 0)
        )

        XCTAssertTrue(engine.isReady, "Engine should be ready")

        print("🚀 Sending turn 1...")
        var response1 = ""
        for try await chunk in engine.sendMessageStream("Hi, what is your name?") {
            response1 += chunk
            print(chunk, terminator: "")
        }
        print("\n✅ Turn 1 finished. Response: \(response1.count) chars")

        print("🚀 Sending turn 2...")
        var response2 = ""
        do {
            for try await chunk in engine.sendMessageStream("Can you repeat what I just asked?") {
                response2 += chunk
                print(chunk, terminator: "")
            }
            print("\n✅ Turn 2 finished. Response: \(response2.count) chars")
        } catch {
            print("\n❌ Turn 2 failed with error: \(error)")
            XCTFail("Turn 2 failed: \(error)")
        }
    }
}
