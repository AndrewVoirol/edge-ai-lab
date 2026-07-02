// Copyright 2026 Andrew Voirol. Apache-2.0

import Foundation
import Testing

#if os(iOS)
@testable import EdgeAILab_iOS
#elseif os(macOS)
@testable import EdgeAILab_macOS
#endif

// MARK: - ModelFormatDetectorTests

/// Tests for `ModelFormatDetector`, covering both local path detection
/// and HuggingFace metadata-based format inference.
@Suite("ModelFormatDetector")
struct ModelFormatDetectorTests {

    // MARK: - Helpers

    /// Create a temporary directory for test fixtures.
    /// Returns the URL and a cleanup closure.
    private func makeTempDir() throws -> (URL, () -> Void) {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory
            .appendingPathComponent("ModelFormatDetectorTests-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let cleanup: () -> Void = { try? fm.removeItem(at: dir) }
        return (dir, cleanup)
    }

    /// Create an empty file at the given URL.
    private func touchFile(at url: URL) throws {
        try Data().write(to: url)
    }

    // MARK: - Local Path Detection: File Extensions

    @Test("Detects .litertlm file extension")
    func detectsLitertlmExtension() throws {
        let (dir, cleanup) = try makeTempDir()
        defer { cleanup() }

        let file = dir.appendingPathComponent("model.litertlm")
        try touchFile(at: file)

        let result = ModelFormatDetector.detectFormat(at: file)
        #expect(result == .litertlm)
    }

    @Test("Detects .task file extension as LiteRT-LM")
    func detectsTaskExtensionAsLitertlm() throws {
        let (dir, cleanup) = try makeTempDir()
        defer { cleanup() }

        let file = dir.appendingPathComponent("model.task")
        try touchFile(at: file)

        let result = ModelFormatDetector.detectFormat(at: file)
        #expect(result == .litertlm)
    }

    @Test("Detects .gguf file extension")
    func detectsGgufExtension() throws {
        let (dir, cleanup) = try makeTempDir()
        defer { cleanup() }

        let file = dir.appendingPathComponent("model.gguf")
        try touchFile(at: file)

        let result = ModelFormatDetector.detectFormat(at: file)
        #expect(result == .gguf)
    }

    @Test("Returns nil for unknown file extension")
    func returnsNilForUnknownExtension() throws {
        let (dir, cleanup) = try makeTempDir()
        defer { cleanup() }

        let file = dir.appendingPathComponent("model.bin")
        try touchFile(at: file)

        let result = ModelFormatDetector.detectFormat(at: file)
        #expect(result == nil)
    }

    @Test("Returns nil for non-existent path")
    func returnsNilForNonExistentPath() {
        let url = URL(fileURLWithPath: "/tmp/nonexistent-\(UUID().uuidString)/model.xyz")
        let result = ModelFormatDetector.detectFormat(at: url)
        #expect(result == nil)
    }

    // MARK: - Local Path Detection: MLX Directories

    @Test("Detects MLX directory with config.json and .safetensors")
    func detectsMLXDirectory() throws {
        let (dir, cleanup) = try makeTempDir()
        defer { cleanup() }

        let mlxDir = dir.appendingPathComponent("mlx-model")
        try FileManager.default.createDirectory(at: mlxDir, withIntermediateDirectories: true)
        try touchFile(at: mlxDir.appendingPathComponent("config.json"))
        try touchFile(at: mlxDir.appendingPathComponent("model-00001-of-00002.safetensors"))
        try touchFile(at: mlxDir.appendingPathComponent("model-00002-of-00002.safetensors"))

        let result = ModelFormatDetector.detectFormat(at: mlxDir)
        #expect(result == .mlx)
    }

    @Test("Returns nil for MLX directory missing config.json")
    func returnsNilForMLXDirMissingConfig() throws {
        let (dir, cleanup) = try makeTempDir()
        defer { cleanup() }

        let mlxDir = dir.appendingPathComponent("partial-mlx")
        try FileManager.default.createDirectory(at: mlxDir, withIntermediateDirectories: true)
        // Has safetensors but NO config.json
        try touchFile(at: mlxDir.appendingPathComponent("model.safetensors"))

        let result = ModelFormatDetector.detectFormat(at: mlxDir)
        #expect(result == nil)
    }

    @Test("Returns nil for MLX directory missing safetensors")
    func returnsNilForMLXDirMissingSafetensors() throws {
        let (dir, cleanup) = try makeTempDir()
        defer { cleanup() }

        let mlxDir = dir.appendingPathComponent("config-only")
        try FileManager.default.createDirectory(at: mlxDir, withIntermediateDirectories: true)
        // Has config.json but NO .safetensors files
        try touchFile(at: mlxDir.appendingPathComponent("config.json"))
        try touchFile(at: mlxDir.appendingPathComponent("README.md"))

        let result = ModelFormatDetector.detectFormat(at: mlxDir)
        #expect(result == nil)
    }

    @Test("detectMLXDirectory returns true for valid MLX layout")
    func detectMLXDirectoryReturnsTrue() throws {
        let (dir, cleanup) = try makeTempDir()
        defer { cleanup() }

        try touchFile(at: dir.appendingPathComponent("config.json"))
        try touchFile(at: dir.appendingPathComponent("weights.safetensors"))

        let result = ModelFormatDetector.detectMLXDirectory(at: dir)
        #expect(result == true)
    }

    @Test("detectMLXDirectory returns false for empty directory")
    func detectMLXDirectoryReturnsFalseForEmptyDir() throws {
        let (dir, cleanup) = try makeTempDir()
        defer { cleanup() }

        let result = ModelFormatDetector.detectMLXDirectory(at: dir)
        #expect(result == false)
    }

    // MARK: - HuggingFace Metadata Detection: libraryName

    @Test("Detects MLX from libraryName='mlx'")
    func detectsMLXFromLibraryName() {
        let model = HFModelInfo(
            id: "some-org/some-model",
            author: "some-org",
            libraryName: "mlx"
        )
        let result = ModelFormatDetector.detectFormat(from: model)
        #expect(result == .mlx)
    }

    @Test("Detects LiteRT-LM from libraryName='litert'")
    func detectsLitertlmFromLibraryName() {
        let model = HFModelInfo(
            id: "some-org/some-model",
            author: "some-org",
            libraryName: "litert"
        )
        let result = ModelFormatDetector.detectFormat(from: model)
        #expect(result == .litertlm)
    }

    @Test("Detects GGUF from libraryName='gguf'")
    func detectsGgufFromLibraryName() {
        let model = HFModelInfo(
            id: "some-org/some-model",
            author: "some-org",
            libraryName: "gguf"
        )
        let result = ModelFormatDetector.detectFormat(from: model)
        #expect(result == .gguf)
    }

    @Test("Detects GGUF from libraryName='llama.cpp'")
    func detectsGgufFromLlamaCppLibraryName() {
        let model = HFModelInfo(
            id: "some-org/some-model",
            author: "some-org",
            libraryName: "llama.cpp"
        )
        let result = ModelFormatDetector.detectFormat(from: model)
        #expect(result == .gguf)
    }

    // MARK: - HuggingFace Metadata Detection: Tags

    @Test("Detects MLX from tags containing 'mlx'")
    func detectsMLXFromTags() {
        let model = HFModelInfo(
            id: "some-org/some-model",
            author: "some-org",
            tags: ["text-generation", "mlx"]
        )
        let result = ModelFormatDetector.detectFormat(from: model)
        #expect(result == .mlx)
    }

    @Test("Detects LiteRT-LM from tags containing 'litert'")
    func detectsLitertlmFromTags() {
        let model = HFModelInfo(
            id: "some-org/some-model",
            author: "some-org",
            tags: ["text-generation", "litert"]
        )
        let result = ModelFormatDetector.detectFormat(from: model)
        #expect(result == .litertlm)
    }

    // MARK: - HuggingFace Metadata Detection: Siblings

    @Test("Detects MLX from siblings with config.json + safetensors")
    func detectsMLXFromSiblings() {
        let siblings = [
            HFSibling(rfilename: "config.json", size: 1024, lfs: nil),
            HFSibling(rfilename: "model-00001-of-00002.safetensors", size: 4_000_000_000, lfs: nil),
            HFSibling(rfilename: "model-00002-of-00002.safetensors", size: 4_000_000_000, lfs: nil),
            HFSibling(rfilename: "tokenizer.json", size: 2048, lfs: nil),
        ]
        let model = HFModelInfo(
            id: "some-org/some-model",
            author: "some-org",
            siblings: siblings
        )
        let result = ModelFormatDetector.detectFormat(from: model)
        #expect(result == .mlx)
    }

    @Test("Detects LiteRT-LM from siblings with .litertlm file")
    func detectsLitertlmFromSiblings() {
        let siblings = [
            HFSibling(rfilename: "model.litertlm", size: 2_000_000_000, lfs: nil),
            HFSibling(rfilename: "README.md", size: 500, lfs: nil),
        ]
        let model = HFModelInfo(
            id: "some-org/some-model",
            author: "some-org",
            siblings: siblings
        )
        let result = ModelFormatDetector.detectFormat(from: model)
        #expect(result == .litertlm)
    }

    @Test("Detects GGUF from siblings with .gguf file")
    func detectsGgufFromSiblings() {
        let siblings = [
            HFSibling(rfilename: "model-Q4_K_M.gguf", size: 3_000_000_000, lfs: nil),
            HFSibling(rfilename: "README.md", size: 500, lfs: nil),
        ]
        let model = HFModelInfo(
            id: "some-org/some-model",
            author: "some-org",
            siblings: siblings
        )
        let result = ModelFormatDetector.detectFormat(from: model)
        #expect(result == .gguf)
    }

    // MARK: - HuggingFace Metadata Detection: Model ID

    @Test("Detects MLX from mlx-community author")
    func detectsMLXFromMlxCommunityAuthor() {
        let model = HFModelInfo(
            id: "mlx-community/gemma-4-E2B-it-4bit",
            author: "mlx-community"
        )
        let result = ModelFormatDetector.detectFormat(from: model)
        #expect(result == .mlx)
    }

    @Test("Detects LiteRT-LM from model ID containing litert-lm")
    func detectsLitertlmFromModelId() {
        let model = HFModelInfo(
            id: "litert-community/gemma-4-E2B-it-litert-lm",
            author: "litert-community"
        )
        let result = ModelFormatDetector.detectFormat(from: model)
        #expect(result == .litertlm)
    }

    @Test("Detects GGUF from model ID containing -gguf suffix")
    func detectsGgufFromModelId() {
        let model = HFModelInfo(
            id: "TheBloke/Llama-2-7B-GGUF",
            author: "TheBloke"
        )
        // "GGUF" in the ID should trigger via lowercased check
        let result = ModelFormatDetector.detectFormat(from: model)
        #expect(result == .gguf)
    }

    // MARK: - HuggingFace Metadata Detection: No Signal

    @Test("Returns nil when no format can be detected from metadata")
    func returnsNilForNoDetectableFormat() {
        let model = HFModelInfo(
            id: "unknown-org/mystery-model",
            author: "unknown-org",
            tags: ["text-generation", "pytorch"]
        )
        let result = ModelFormatDetector.detectFormat(from: model)
        #expect(result == nil)
    }

    // MARK: - Priority Order Tests

    @Test("libraryName takes priority over tags")
    func libraryNameTakesPriorityOverTags() {
        // libraryName says mlx, tags say litert — libraryName wins
        let model = HFModelInfo(
            id: "some-org/some-model",
            author: "some-org",
            tags: ["litert"],
            libraryName: "mlx"
        )
        let result = ModelFormatDetector.detectFormat(from: model)
        #expect(result == .mlx)
    }

    @Test("libraryName takes priority over model ID")
    func libraryNameTakesPriorityOverModelId() {
        // libraryName says litert, but author is mlx-community — libraryName wins
        let model = HFModelInfo(
            id: "mlx-community/some-litert-model",
            author: "mlx-community",
            libraryName: "litert"
        )
        let result = ModelFormatDetector.detectFormat(from: model)
        #expect(result == .litertlm)
    }

    @Test("Tags take priority over siblings when no libraryName")
    func tagsTakePriorityOverSiblings() {
        // Tags say litert, but siblings contain MLX-like files
        let siblings = [
            HFSibling(rfilename: "config.json", size: 1024, lfs: nil),
            HFSibling(rfilename: "model.safetensors", size: 4_000_000_000, lfs: nil),
        ]
        let model = HFModelInfo(
            id: "some-org/some-model",
            author: "some-org",
            tags: ["litert"],
            siblings: siblings
        )
        let result = ModelFormatDetector.detectFormat(from: model)
        #expect(result == .litertlm)
    }
}
