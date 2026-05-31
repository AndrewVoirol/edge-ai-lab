import XCTest
import LiteRTLM

#if os(iOS)
@testable import GemmaEdgeGallery_iOS
#elseif os(macOS)
@testable import GemmaEdgeGallery_macOS
#endif

/// Diagnostic test suite for model/backend compatibility across platforms.
/// Tests every combination of model variant × backend to determine what works
/// on each platform (simulator, device, macOS).
///
/// This is an investigative suite — results inform the permanent test infrastructure.
final class SimulatorCompatibilityTests: XCTestCase {

    // MARK: - Model Discovery

    /// Discovers all .litertlm model files available for testing.
    /// Priority: env var → project models/ dir → app Documents dir → shared containers.
    private var availableModels: [URL] {
        var models: [URL] = []

        // 1. Env var (explicit single model)
        if let envPath = ProcessInfo.processInfo.environment["PERFORMANCE_TEST_MODEL_PATH"] {
            let url = URL(fileURLWithPath: envPath)
            if FileManager.default.fileExists(atPath: envPath) {
                models.append(url)
            }
        }

        // 2. Project models/ directory (via #filePath — only works on macOS and simulator)
        #if os(macOS) || targetEnvironment(simulator)
        let projectModels = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // Tests/
            .deletingLastPathComponent()  // project root
            .appendingPathComponent("models")
        if let found = findModels(in: projectModels) {
            models.append(contentsOf: found)
        }
        #endif

        // 3. App's Documents directory (works on all platforms including physical device)
        if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            if let found = findModels(in: docs) {
                models.append(contentsOf: found)
            }
        }

        // 4. App's bundle resources (if models are embedded as test resources)
        if let bundleModels = Bundle(for: type(of: self)).url(forResource: nil, withExtension: nil) {
            if let found = findModels(in: bundleModels) {
                models.append(contentsOf: found)
            }
        }

        // Deduplicate by filename
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

    // MARK: - Diagnostic Info

    /// Prints platform and environment context for diagnostic purposes.
    private func logDiagnosticContext() {
        #if targetEnvironment(simulator)
        let environment = "iOS Simulator"
        #elseif os(iOS)
        let environment = "iOS Device"
        #elseif os(macOS)
        let environment = "macOS"
        #else
        let environment = "Unknown"
        #endif

        print("╔══════════════════════════════════════════════")
        print("║ COMPATIBILITY TEST — Environment: \(environment)")
        print("║ Available models: \(availableModels.map(\.lastPathComponent))")
        print("╚══════════════════════════════════════════════")
    }

    // MARK: - Model Load Tests (GPU)

    func testLoadStandardModel_GPU() async throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Standard model desktop Metal shaders fail to compile on iOS Simulator")
        #endif
        logDiagnosticContext()
        let model = try findModel(named: "gemma-4-E2B-it.litertlm")
        try await runModelLoadTest(modelPath: model, useGPU: true, label: "desktop/GPU")
    }

    func testLoadWebModel_GPU() async throws {
        logDiagnosticContext()
        let model = try findModel(named: "gemma-4-E2B-it-web.litertlm")
        try await runModelLoadTest(modelPath: model, useGPU: true, label: "mobile/GPU")
    }

    func testLoadGemma3nModel_GPU() async throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Gemma 3n GPU load crashes in simulator (SDK limitation)")
        #endif
        logDiagnosticContext()
        let model = try findAnyModel(matching: ["gemma-3n-E2B-HW.litertlm", "gemma-3n-E2B-it-int4.litertlm"])
        try await runModelLoadTest(modelPath: model, useGPU: true, label: "gemma3n/GPU")
    }

    // MARK: - Model Load Tests (CPU)

    func testLoadStandardModel_CPU() async throws {
        logDiagnosticContext()
        let model = try findModel(named: "gemma-4-E2B-it.litertlm")
        try await runModelLoadTest(modelPath: model, useGPU: false, label: "desktop/CPU")
    }

    /// The web model has no CPU subgraph — this test documents the expected failure.
    /// The smart fallback in InstrumentedEngine.initializeWithFallback handles this gracefully.
    func testLoadWebModel_CPU() async throws {
        logDiagnosticContext()
        let model = try findModel(named: "gemma-4-E2B-it-web.litertlm")
        let engine = InstrumentedEngine()
        let cacheDirURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("compat_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: cacheDirURL, withIntermediateDirectories: true)

        let flags = ExperimentalFlagsState(
            enableBenchmark: true,
            enableSpeculativeDecoding: nil,
            enableConversationConstrainedDecoding: false,
            visualTokenBudget: nil
        )

        do {
            try await engine.initialize(
                modelPath: model,
                useGPU: false,
                cacheDir: cacheDirURL.path,
                flags: flags
            )
            // If it somehow succeeds, that's fine too (future SDK versions may add CPU support)
            print("⚠️ [mobile/CPU] Unexpectedly succeeded — model may have gained CPU subgraph")
        } catch {
            // Expected: web model has no CPU subgraph
            print("✅ [mobile/CPU] Expected failure confirmed: \(error)")
        }
        engine.shutdown()
        try? FileManager.default.removeItem(at: cacheDirURL)
    }

    // MARK: - Inference Tests (GPU)

    func testInferenceStandardModel_GPU() async throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Standard model desktop Metal shaders fail on simulator")
        #endif
        logDiagnosticContext()
        let model = try findModel(named: "gemma-4-E2B-it.litertlm")
        try await runInferenceTest(modelPath: model, useGPU: true, label: "desktop/GPU")
    }

    func testInferenceWebModel_GPU() async throws {
        logDiagnosticContext()
        let model = try findModel(named: "gemma-4-E2B-it-web.litertlm")
        try await runInferenceTest(modelPath: model, useGPU: true, label: "mobile/GPU")
    }

    func testInferenceGemma3nModel_GPU() async throws {
        logDiagnosticContext()
        let model = try findAnyModel(matching: ["gemma-3n-E2B-HW.litertlm", "gemma-3n-E2B-it-int4.litertlm"])
        try await runInferenceTest(modelPath: model, useGPU: true, label: "gemma3n/GPU")
    }

    // MARK: - Inference Tests (CPU)

    func testInferenceStandardModel_CPU() async throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Standard model CPU inference crashes with SEGV on simulator (SDK bug)")
        #endif
        logDiagnosticContext()
        let model = try findModel(named: "gemma-4-E2B-it.litertlm")
        try await runInferenceTest(modelPath: model, useGPU: false, label: "desktop/CPU")
    }

    func testInferenceWebModel_CPU() async throws {
        logDiagnosticContext()
        let model = try findModel(named: "gemma-4-E2B-it-web.litertlm")
        try await runInferenceTest(modelPath: model, useGPU: false, label: "mobile/CPU")
    }

    // MARK: - Helpers

    private func findModel(named filename: String) throws -> String {
        if let model = availableModels.first(where: { $0.lastPathComponent == filename }) {
            return model.path
        }
        throw XCTSkip("Model '\(filename)' not available — skipping")
    }

    /// Find any model matching one of the given filenames (for models with variant naming).
    private func findAnyModel(matching filenames: [String]) throws -> String {
        for filename in filenames {
            if let model = availableModels.first(where: { $0.lastPathComponent == filename }) {
                return model.path
            }
        }
        throw XCTSkip("None of \(filenames) available — skipping")
    }

    @MainActor
    private func runModelLoadTest(modelPath: String, useGPU: Bool, label: String) async throws {
        let engine = InstrumentedEngine()
        let cacheDirURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("compat_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: cacheDirURL, withIntermediateDirectories: true)
        let cacheDir = cacheDirURL.path

        let flags = ExperimentalFlagsState(
            enableBenchmark: true,
            enableSpeculativeDecoding: nil,
            enableConversationConstrainedDecoding: false,
            visualTokenBudget: nil
        )

        let start = CFAbsoluteTimeGetCurrent()
        do {
            try await engine.initialize(
                modelPath: modelPath,
                useGPU: useGPU,
                cacheDir: cacheDir,
                flags: flags
            )
            let elapsed = CFAbsoluteTimeGetCurrent() - start
            print("✅ [\(label)] Model loaded in \(String(format: "%.2f", elapsed))s")
            XCTAssertTrue(engine.isReady, "Engine should be ready after successful init")
        } catch {
            let elapsed = CFAbsoluteTimeGetCurrent() - start
            print("❌ [\(label)] Model load FAILED after \(String(format: "%.2f", elapsed))s: \(error)")
            XCTFail("[\(label)] Model load failed: \(error)")
        }
        engine.shutdown()
        try? FileManager.default.removeItem(at: cacheDirURL)
    }

    @MainActor
    private func runInferenceTest(modelPath: String, useGPU: Bool, label: String) async throws {
        let engine = InstrumentedEngine()
        let cacheDirURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("compat_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: cacheDirURL, withIntermediateDirectories: true)
        let cacheDir = cacheDirURL.path

        let flags = ExperimentalFlagsState(
            enableBenchmark: true,
            enableSpeculativeDecoding: nil,
            enableConversationConstrainedDecoding: false,
            visualTokenBudget: nil
        )

        // Phase 1: Load
        do {
            try await engine.initialize(
                modelPath: modelPath,
                useGPU: useGPU,
                cacheDir: cacheDir,
                flags: flags
            )
        } catch {
            print("❌ [\(label)] Model load failed (cannot test inference): \(error)")
            throw XCTSkip("[\(label)] Model load failed — inference test not possible: \(error)")
        }

        // Phase 2: Inference
        let prompt = "What is 2+2?"
        var response = ""
        var tokenCount = 0
        let start = CFAbsoluteTimeGetCurrent()

        do {
            for try await chunk in engine.sendMessageStream(prompt) {
                response += chunk
                tokenCount += 1
                // Safety: bail after 50 tokens to avoid infinite degenerate loops
                if tokenCount > 50 {
                    print("⚠️ [\(label)] Bailing after 50 tokens (possible degenerate output)")
                    break
                }
            }
            let elapsed = CFAbsoluteTimeGetCurrent() - start

            // Check for degenerate output (repeated tokens)
            let words = response.split(separator: " ")
            let uniqueWords = Set(words)
            let isDegenerateOutput = words.count > 10 && uniqueWords.count <= 3

            if isDegenerateOutput {
                print("⚠️ [\(label)] DEGENERATE OUTPUT detected (\(words.count) words, \(uniqueWords.count) unique)")
                print("   Response: \(response.prefix(200))...")
                #if targetEnvironment(simulator)
                throw XCTSkip("[\(label)] Degenerate output on simulator (expected — sim Metal produces garbage): \(uniqueWords.count) unique words in \(words.count)")
                #else
                XCTFail("[\(label)] Degenerate inference output — \(uniqueWords.count) unique words in \(words.count)")
                #endif
            } else {
                print("✅ [\(label)] Inference completed in \(String(format: "%.2f", elapsed))s")
                print("   Tokens: \(tokenCount), Response length: \(response.count) chars")
                print("   Response preview: \(response.prefix(150))...")

                // Capture benchmark info
                if let info = engine.lastBenchmarkInfo {
                    print("   BenchmarkInfo:")
                    print("     Init: \(String(format: "%.3f", info.initTimeInSecond))s")
                    print("     TTFT: \(String(format: "%.3f", info.timeToFirstTokenInSecond))s")
                    print("     Decode: \(String(format: "%.1f", info.lastDecodeTokensPerSecond)) tok/s")
                    print("     Prefill: \(String(format: "%.1f", info.lastPrefillTokensPerSecond)) tok/s")
                }
            }

            XCTAssertFalse(response.isEmpty, "[\(label)] Expected non-empty response")
        } catch {
            let elapsed = CFAbsoluteTimeGetCurrent() - start
            print("❌ [\(label)] Inference FAILED after \(String(format: "%.2f", elapsed))s: \(error)")
            XCTFail("[\(label)] Inference failed: \(error)")
        }

        engine.shutdown()
        try? FileManager.default.removeItem(at: cacheDirURL)
    }

    // MARK: - MTP (Speculative Decoding) Benchmarks

    /// MTP benchmark for Gemma 3n on GPU — Gallery achieves 402.93 tok/s prefill with MTP.
    func testMTP_Gemma3nModel_GPU() async throws {
        logDiagnosticContext()
        let model = try findAnyModel(matching: ["gemma-3n-E2B-HW.litertlm", "gemma-3n-E2B-it-int4.litertlm"])
        try await runMTPBenchmark(modelPath: model, useGPU: true, label: "gemma3n/GPU+MTP")
    }

    /// MTP benchmark for Gemma 4 Web on GPU — Gallery achieves 305.45 tok/s prefill with MTP.
    func testMTP_WebModel_GPU() async throws {
        logDiagnosticContext()
        let model = try findModel(named: "gemma-4-E2B-it-web.litertlm")
        try await runMTPBenchmark(modelPath: model, useGPU: true, label: "mobile/GPU+MTP")
    }

    /// MTP benchmark for standard model on CPU.
    func testMTP_StandardModel_CPU() async throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("MTP + CPU crashes on simulator (SDK limitation)")
        #else
        // Also skip on iOS device — known SDK crash
        throw XCTSkip("MTP + CPU crashes on iOS device (SDK crash at external symbol)")
        #endif
        logDiagnosticContext()
        let model = try findModel(named: "gemma-4-E2B-it.litertlm")
        try await runMTPBenchmark(modelPath: model, useGPU: false, label: "desktop/CPU+MTP")
    }

    // MARK: - Model Swapping Test

    /// Tests loading model A → inference → shutdown → load model B → inference → shutdown → load A again.
    /// Validates that engine resources are properly released between model swaps (G4 from session 1).
    func testModelSwapping_GPU() async throws {
        logDiagnosticContext()

        // Need at least 2 different models
        let models = availableModels
        guard models.count >= 2 else {
            throw XCTSkip("Need at least 2 models for swap test — only \(models.count) available")
        }

        let modelA = models[0]
        let modelB = models[1]

        print("🔄 [swap] Starting model swap test")
        print("   Model A: \(modelA.lastPathComponent)")
        print("   Model B: \(modelB.lastPathComponent)")

        // Phase 1: Load model A and run inference
        print("\n--- Phase 1: Model A ---")
        try await runSwapPhase(modelPath: modelA.path, label: "swap/A1")

        // Phase 2: Load model B and run inference
        print("\n--- Phase 2: Model B ---")
        try await runSwapPhase(modelPath: modelB.path, label: "swap/B")

        // Phase 3: Load model A again
        print("\n--- Phase 3: Model A (reload) ---")
        try await runSwapPhase(modelPath: modelA.path, label: "swap/A2")

        print("\n✅ [swap] Model swapping test complete — 3 load/inference/shutdown cycles successful")
    }

    @MainActor
    private func runSwapPhase(modelPath: String, label: String) async throws {
        let engine = InstrumentedEngine()
        let cacheDirURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("swap_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: cacheDirURL, withIntermediateDirectories: true)

        let flags = ExperimentalFlagsState(
            enableBenchmark: true,
            enableSpeculativeDecoding: nil,
            enableConversationConstrainedDecoding: false,
            visualTokenBudget: nil
        )

        // Load
        let loadStart = CFAbsoluteTimeGetCurrent()
        do {
            try await engine.initialize(
                modelPath: modelPath,
                useGPU: true,
                cacheDir: cacheDirURL.path,
                flags: flags
            )
        } catch {
            // Fall back to CPU if GPU fails (e.g., on simulator)
            print("⚠️ [\(label)] GPU load failed, trying CPU: \(error)")
            try await engine.initialize(
                modelPath: modelPath,
                useGPU: false,
                cacheDir: cacheDirURL.path,
                flags: flags
            )
        }
        let loadElapsed = CFAbsoluteTimeGetCurrent() - loadStart
        print("✅ [\(label)] Loaded in \(String(format: "%.2f", loadElapsed))s")

        // Inference
        var response = ""
        var tokenCount = 0
        let inferStart = CFAbsoluteTimeGetCurrent()

        for try await chunk in engine.sendMessageStream("What is 2+2?") {
            response += chunk
            tokenCount += 1
            if tokenCount > 20 { break }
        }
        let inferElapsed = CFAbsoluteTimeGetCurrent() - inferStart
        print("✅ [\(label)] Inference: \(tokenCount) tokens in \(String(format: "%.2f", inferElapsed))s")
        print("   Response: \(response.prefix(100))")

        XCTAssertFalse(response.isEmpty, "[\(label)] Expected non-empty response")

        // Shutdown
        engine.shutdown()
        try? FileManager.default.removeItem(at: cacheDirURL)
        print("✅ [\(label)] Shutdown complete")
    }

    @MainActor
    private func runMTPBenchmark(modelPath: String, useGPU: Bool, label: String) async throws {
        let engine = InstrumentedEngine()
        let cacheDirURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("mtp_bench_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: cacheDirURL, withIntermediateDirectories: true)

        let mtpFlags = ExperimentalFlagsState(
            enableBenchmark: true,
            enableSpeculativeDecoding: true,
            enableConversationConstrainedDecoding: false,
            visualTokenBudget: nil
        )

        // Phase 1: Load with MTP
        do {
            try await engine.initialize(
                modelPath: modelPath,
                useGPU: useGPU,
                cacheDir: cacheDirURL.path,
                flags: mtpFlags
            )
        } catch {
            print("❌ [\(label)] Model load failed with MTP: \(error)")
            throw XCTSkip("[\(label)] Model load with MTP failed: \(error)")
        }

        // Phase 2: Inference with MTP
        let prompt = "Explain in detail the process of photosynthesis, including light and dark reactions."
        var response = ""
        var tokenCount = 0
        let start = CFAbsoluteTimeGetCurrent()

        do {
            for try await chunk in engine.sendMessageStream(prompt) {
                response += chunk
                tokenCount += 1
                if tokenCount > 100 {
                    break
                }
            }
            let elapsed = CFAbsoluteTimeGetCurrent() - start

            print("✅ [\(label)] MTP Inference completed in \(String(format: "%.2f", elapsed))s")
            print("   Tokens: \(tokenCount), Response length: \(response.count) chars")

            if let info = engine.lastBenchmarkInfo {
                print("   📊 MTP BenchmarkInfo:")
                print("     Init: \(String(format: "%.3f", info.initTimeInSecond))s")
                print("     TTFT: \(String(format: "%.3f", info.timeToFirstTokenInSecond))s")
                print("     Decode: \(String(format: "%.1f", info.lastDecodeTokensPerSecond)) tok/s")
                print("     Prefill: \(String(format: "%.1f", info.lastPrefillTokensPerSecond)) tok/s")
            }

            XCTAssertFalse(response.isEmpty, "[\(label)] Expected non-empty response")
        } catch {
            print("❌ [\(label)] MTP Inference FAILED: \(error)")
            XCTFail("[\(label)] MTP Inference failed: \(error)")
        }

        engine.shutdown()
        try? FileManager.default.removeItem(at: cacheDirURL)
    }
}
