// Copyright 2026 Andrew Voirol. Apache-2.0

import Testing
import Foundation

#if os(iOS)
@testable import EdgeAILab_iOS
#elseif os(macOS)
@testable import EdgeAILab_macOS
#endif

/// Tests for VLM model detection in `MLXEngineAdapter`.
///
/// VLMs (Gemma 4, Qwen-VL, PaliGemma) ship with `processor_config.json` or
/// `preprocessor_config.json` alongside their weights. Text-only LLMs do not.
/// The detection helper determines which factory (`VLMModelFactory` vs `LLMModelFactory`)
/// to use when loading the model — a correctness-critical routing decision.
@Suite("MLX VLM Detection")
struct MLXVLMDetectionTests {

    /// Helper to create a temporary directory for testing.
    private func createTempDir() throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("MLXVLMDetectionTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Helper to clean up a temporary directory.
    private func removeTempDir(_ dir: URL) {
        try? FileManager.default.removeItem(at: dir)
    }

    @Test("Directory with processor_config.json detected as VLM")
    func testIsVLMModel_WithProcessorConfig_ReturnsTrue() throws {
        let dir = try createTempDir()
        defer { removeTempDir(dir) }

        // Create processor_config.json
        let configPath = dir.appendingPathComponent("processor_config.json")
        try Data("{}".utf8).write(to: configPath)

        #expect(MLXVLMDetectionHelper.isVLMModel(at: dir) == true)
    }

    @Test("Directory with preprocessor_config.json detected as VLM")
    func testIsVLMModel_WithPreprocessorConfig_ReturnsTrue() throws {
        let dir = try createTempDir()
        defer { removeTempDir(dir) }

        // Create preprocessor_config.json (alternative naming used by some models)
        let configPath = dir.appendingPathComponent("preprocessor_config.json")
        try Data("{}".utf8).write(to: configPath)

        #expect(MLXVLMDetectionHelper.isVLMModel(at: dir) == true)
    }

    @Test("Directory without processor config not detected as VLM")
    func testIsVLMModel_WithoutProcessorConfig_ReturnsFalse() throws {
        let dir = try createTempDir()
        defer { removeTempDir(dir) }

        // Only create config.json (present in all models, LLM and VLM)
        let configPath = dir.appendingPathComponent("config.json")
        try Data("{}".utf8).write(to: configPath)

        #expect(MLXVLMDetectionHelper.isVLMModel(at: dir) == false)
    }

    @Test("Empty directory not detected as VLM")
    func testIsVLMModel_EmptyDirectory_ReturnsFalse() throws {
        let dir = try createTempDir()
        defer { removeTempDir(dir) }

        #expect(MLXVLMDetectionHelper.isVLMModel(at: dir) == false)
    }
}
