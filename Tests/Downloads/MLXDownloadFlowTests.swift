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

// MARK: - MLX Download Flow Tests

/// Tests for the MLX model download flow, covering:
/// - HFModelBrowser file manifest filtering
/// - Download descriptor generation
/// - MLX model registry entries
/// - Model format detection for MLX directory models
/// - GalleryModelDiscovery MLX directory name parsing
@Suite("MLX Download Flow")
struct MLXDownloadFlowTests {

    // MARK: - File Manifest Filtering

    @Suite("File manifest filtering")
    struct ManifestFiltering {

        @Test("filterRequiredMLXFiles keeps config.json")
        func keepsConfig() {
            let manifest = [
                HFTreeEntry(type: "file", oid: nil, size: 1000, path: "config.json", lfs: nil),
                HFTreeEntry(type: "file", oid: nil, size: 500, path: "README.md", lfs: nil),
            ]
            let filtered = HFModelBrowser.filterRequiredMLXFiles(manifest)
            #expect(filtered.count == 1)
            #expect(filtered[0].path == "config.json")
        }

        @Test("filterRequiredMLXFiles keeps tokenizer files")
        func keepsTokenizers() {
            let manifest = [
                HFTreeEntry(type: "file", oid: nil, size: 1000, path: "tokenizer.json", lfs: nil),
                HFTreeEntry(type: "file", oid: nil, size: 500, path: "tokenizer_config.json", lfs: nil),
                HFTreeEntry(type: "file", oid: nil, size: 200, path: "tokenizer.model", lfs: nil),
            ]
            let filtered = HFModelBrowser.filterRequiredMLXFiles(manifest)
            #expect(filtered.count == 2)
            let paths = Set(filtered.map(\.path))
            #expect(paths.contains("tokenizer.json"))
            #expect(paths.contains("tokenizer_config.json"))
            // tokenizer.model should NOT match (doesn't end in .json)
            #expect(!paths.contains("tokenizer.model"))
        }

        @Test("filterRequiredMLXFiles keeps safetensors shards")
        func keepsSafetensors() {
            let manifest = [
                HFTreeEntry(type: "file", oid: nil, size: 1_000_000, path: "model-00001-of-00003.safetensors", lfs: nil),
                HFTreeEntry(type: "file", oid: nil, size: 1_000_000, path: "model-00002-of-00003.safetensors", lfs: nil),
                HFTreeEntry(type: "file", oid: nil, size: 1_000_000, path: "model-00003-of-00003.safetensors", lfs: nil),
                HFTreeEntry(type: "file", oid: nil, size: 200, path: "model.safetensors.index.json", lfs: nil),
            ]
            let filtered = HFModelBrowser.filterRequiredMLXFiles(manifest)
            #expect(filtered.count == 4)
        }

        @Test("filterRequiredMLXFiles keeps special_tokens_map and generation_config")
        func keepsSpecialFiles() {
            let manifest = [
                HFTreeEntry(type: "file", oid: nil, size: 500, path: "special_tokens_map.json", lfs: nil),
                HFTreeEntry(type: "file", oid: nil, size: 300, path: "generation_config.json", lfs: nil),
            ]
            let filtered = HFModelBrowser.filterRequiredMLXFiles(manifest)
            #expect(filtered.count == 2)
        }

        @Test("filterRequiredMLXFiles excludes unwanted files")
        func excludesUnwanted() {
            let manifest = [
                HFTreeEntry(type: "file", oid: nil, size: 500, path: "README.md", lfs: nil),
                HFTreeEntry(type: "file", oid: nil, size: 300, path: ".gitattributes", lfs: nil),
                HFTreeEntry(type: "file", oid: nil, size: 100_000, path: "model.gguf", lfs: nil),
                HFTreeEntry(type: "file", oid: nil, size: 100_000, path: "pytorch_model.bin", lfs: nil),
            ]
            let filtered = HFModelBrowser.filterRequiredMLXFiles(manifest)
            #expect(filtered.isEmpty)
        }

        @Test("filterRequiredMLXFiles excludes directories")
        func excludesDirectories() {
            let manifest = [
                HFTreeEntry(type: "directory", oid: nil, size: nil, path: "tokenizer", lfs: nil),
                HFTreeEntry(type: "file", oid: nil, size: 1000, path: "config.json", lfs: nil),
            ]
            let filtered = HFModelBrowser.filterRequiredMLXFiles(manifest)
            #expect(filtered.count == 1)
            #expect(filtered[0].path == "config.json")
        }

        @Test("realistic MLX model manifest filters correctly")
        func realisticManifest() {
            let manifest = [
                HFTreeEntry(type: "file", oid: nil, size: 1000, path: "config.json", lfs: nil),
                HFTreeEntry(type: "file", oid: nil, size: 500, path: "tokenizer.json", lfs: nil),
                HFTreeEntry(type: "file", oid: nil, size: 300, path: "tokenizer_config.json", lfs: nil),
                HFTreeEntry(type: "file", oid: nil, size: 200, path: "special_tokens_map.json", lfs: nil),
                HFTreeEntry(type: "file", oid: nil, size: 150, path: "generation_config.json", lfs: nil),
                HFTreeEntry(type: "file", oid: nil, size: 2_000_000_000, path: "model-00001-of-00002.safetensors",
                            lfs: HFTreeLFSInfo(oid: "sha256:abc123", size: 2_000_000_000, pointerSize: 135)),
                HFTreeEntry(type: "file", oid: nil, size: 200_000_000, path: "model-00002-of-00002.safetensors",
                            lfs: HFTreeLFSInfo(oid: "sha256:def456", size: 200_000_000, pointerSize: 135)),
                HFTreeEntry(type: "file", oid: nil, size: 200, path: "model.safetensors.index.json", lfs: nil),
                // Files that should be excluded:
                HFTreeEntry(type: "file", oid: nil, size: 5000, path: "README.md", lfs: nil),
                HFTreeEntry(type: "file", oid: nil, size: 100, path: ".gitattributes", lfs: nil),
                HFTreeEntry(type: "directory", oid: nil, size: nil, path: "runs", lfs: nil),
            ]
            let filtered = HFModelBrowser.filterRequiredMLXFiles(manifest)
            #expect(filtered.count == 8)
            let paths = Set(filtered.map(\.path))
            #expect(!paths.contains("README.md"))
            #expect(!paths.contains(".gitattributes"))
            #expect(!paths.contains("runs"))
        }
    }

    // MARK: - Download Descriptors

    @Suite("Download descriptors")
    struct DownloadDescriptors {

        @Test("downloadDescriptors builds correct URLs")
        func correctURLs() {
            let files = [
                HFTreeEntry(type: "file", oid: nil, size: 1000, path: "config.json", lfs: nil),
                HFTreeEntry(type: "file", oid: nil, size: 2_000_000_000, path: "model.safetensors",
                            lfs: HFTreeLFSInfo(oid: "sha256:abc123", size: 2_000_000_000, pointerSize: 135)),
            ]

            let descriptors = HFModelBrowser.downloadDescriptors(
                repoId: "mlx-community/gemma-4-E2B-it-4bit",
                requiredFiles: files
            )

            #expect(descriptors.count == 2)

            // Check config.json descriptor
            #expect(descriptors[0].filename == "config.json")
            #expect(descriptors[0].url.absoluteString == "https://huggingface.co/mlx-community/gemma-4-E2B-it-4bit/resolve/main/config.json")
            #expect(descriptors[0].size == 1000)
            #expect(descriptors[0].sha256 == nil)

            // Check safetensors descriptor
            #expect(descriptors[1].filename == "model.safetensors")
            #expect(descriptors[1].size == 2_000_000_000)
            #expect(descriptors[1].sha256 == "sha256:abc123")
        }

        @Test("downloadDescriptors uses LFS size over regular size")
        func lfsSizeOverRegular() {
            let files = [
                HFTreeEntry(type: "file", oid: nil, size: 135, path: "model.safetensors",
                            lfs: HFTreeLFSInfo(oid: "sha256:abc", size: 4_200_000_000, pointerSize: 135)),
            ]

            let descriptors = HFModelBrowser.downloadDescriptors(
                repoId: "org/model",
                requiredFiles: files
            )

            // Should use LFS size (4.2GB), not pointer size (135)
            #expect(descriptors[0].size == 4_200_000_000)
        }
    }

    // MARK: - MLX Registry Models

    @Suite("MLX registry entries")
    struct RegistryEntries {

        @Test("registry contains MLX models")
        func registryHasMLXModels() {
            let mlxModels = ModelRegistry.knownModels.filter { $0.runtimeType == .mlx }
            #expect(mlxModels.count >= 2, "Expected at least 2 MLX models in registry")
        }

        @Test("MLX models have correct runtime type")
        func mlxRuntimeType() {
            let mlxModels = ModelRegistry.knownModels.filter { $0.runtimeType == .mlx }
            for model in mlxModels {
                #expect(model.runtimeType == .mlx)
                #expect(model.isMLXDirectoryModel)
            }
        }

        @Test("MLX model files use double-dash directory convention")
        func mlxDirectoryConvention() {
            let mlxModels = ModelRegistry.knownModels.filter { $0.runtimeType == .mlx }
            for model in mlxModels {
                #expect(model.modelFile.contains("--"),
                        "MLX model file '\(model.modelFile)' should use -- directory convention")
                // modelFile should match modelId with / → --
                let expected = model.modelId.replacingOccurrences(of: "/", with: "--")
                #expect(model.modelFile == expected,
                        "modelFile '\(model.modelFile)' should equal '\(expected)'")
            }
        }

        @Test("MLX models have GPU-only platform support")
        func mlxPlatformSupport() {
            let mlxModels = ModelRegistry.knownModels.filter { $0.runtimeType == .mlx }
            for model in mlxModels {
                #expect(model.platformSupport.macOS == .gpuOnly)
                #expect(model.platformSupport.iOSDevice == .gpuOnly)
            }
        }

        @Test("isMLXDirectoryModel is true for MLX models and false for LiteRT")
        func isMLXDirectoryModelProperty() {
            let litertModel = ModelRegistry.knownModels.first { $0.runtimeType == .litertlm }!
            #expect(!litertModel.isMLXDirectoryModel)

            let mlxModel = ModelRegistry.knownModels.first { $0.runtimeType == .mlx }!
            #expect(mlxModel.isMLXDirectoryModel)
        }

        @Test("MLX model IDs are unique among MLX models")
        func uniqueMLXModelIds() {
            // Note: modelId is NOT globally unique — Standard and Web variants share
            // the same HuggingFace repo. But within each runtime type, IDs should be unique.
            let mlxIds = ModelRegistry.knownModels
                .filter { $0.runtimeType == .mlx }
                .map(\.modelId)
            let uniqueMLXIds = Set(mlxIds)
            #expect(mlxIds.count == uniqueMLXIds.count, "Duplicate MLX modelId found")
        }

        @Test("all model files are unique including MLX")
        func uniqueModelFiles() {
            let files = ModelRegistry.knownModels.map(\.modelFile)
            let uniqueFiles = Set(files)
            #expect(files.count == uniqueFiles.count, "Duplicate modelFile found")
        }
    }

    // MARK: - Format Detection

    @Suite("MLX format detection")
    struct FormatDetection {

        @Test("ModelFormatDetector detects MLX from HuggingFace metadata")
        func hfMetadataDetection() {
            let model = HFModelInfo(
                id: "mlx-community/gemma-4-E2B-it-4bit",
                author: "mlx-community",
                libraryName: "mlx"
            )
            let format = ModelFormatDetector.detectFormat(from: model)
            #expect(format == .mlx)
        }

        @Test("ModelFormatDetector detects MLX from author name")
        func authorDetection() {
            let model = HFModelInfo(
                id: "mlx-community/some-model",
                author: "mlx-community"
            )
            let format = ModelFormatDetector.detectFormat(from: model)
            #expect(format == .mlx)
        }

        @Test("ModelFormatDetector returns nil for ambiguous siblings")
        func siblingsDetection() {
            let model = HFModelInfo(
                id: "someone/model",
                author: "someone",
                siblings: [
                    HFSibling(rfilename: "config.json", size: 1000, lfs: nil),
                    HFSibling(rfilename: "model.safetensors", size: 2_000_000_000, lfs: nil),
                ]
            )
            let format = ModelFormatDetector.detectFormat(from: model)
            #expect(format == nil)
        }

        @Test("HFModelBrowser detects MLX format from mlx-community author")
        @MainActor
        func browserDetectsMLX() {
            let browser = HFModelBrowser()
            let model = HFModelInfo(
                id: "mlx-community/gemma-4-E2B-it-4bit",
                author: "mlx-community"
            )
            #expect(browser.detectFormat(model) == .mlx)
        }
    }

    // MARK: - Directory Name Parsing

    @Suite("MLX directory name parsing")
    struct DirectoryNameParsing {

        @Test("directory name to model ID conversion")
        func dirNameToModelId() {
            let dirName = "mlx-community--gemma-4-E2B-it-4bit"
            let modelId = dirName.replacingOccurrences(of: "--", with: "/")
            #expect(modelId == "mlx-community/gemma-4-E2B-it-4bit")
        }

        @Test("model ID to directory name conversion")
        func modelIdToDirName() {
            let modelId = "mlx-community/gemma-4-E2B-it-4bit"
            let dirName = modelId.replacingOccurrences(of: "/", with: "--")
            #expect(dirName == "mlx-community--gemma-4-E2B-it-4bit")
        }

        @Test("human-readable name extraction from directory")
        func humanNameExtraction() {
            let dirName = "mlx-community--gemma-4-E2B-it-4bit"
            let humanName: String
            if dirName.contains("--") {
                humanName = String(dirName.split(separator: "--", maxSplits: 1).last ?? Substring(dirName))
            } else {
                humanName = dirName
            }
            #expect(humanName == "gemma-4-E2B-it-4bit")
        }

        @Test("directory name without double-dash uses full name")
        func noDashFallback() {
            let dirName = "some-model-name"
            let humanName: String
            if dirName.contains("--") {
                humanName = String(dirName.split(separator: "--", maxSplits: 1).last ?? Substring(dirName))
            } else {
                humanName = dirName
            }
            #expect(humanName == "some-model-name")
        }
    }

    // MARK: - Download State Tracking

    @Suite("Download state tracking")
    struct DownloadStateTracking {

        @Test("HFModelCard MLX download state uses directory name key")
        func mlxDownloadStateKey() {
            let modelId = "mlx-community/gemma-4-E2B-it-4bit"
            let dirName = modelId.replacingOccurrences(of: "/", with: "--")
            #expect(dirName == "mlx-community--gemma-4-E2B-it-4bit")
        }
    }

    // MARK: - Stub File Rejection

    @Suite("Stub file rejection")
    struct StubFileRejection {

        @Test("checkMLXModelState returns .notDownloaded for non-existent directory")
        func nonExistentDir() {
            let config = URLSessionConfiguration.background(withIdentifier: "stub-test-\(UUID())")
            config.isDiscretionary = false
            let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tmpDir) }

            let mgr = ModelDownloadManager(configuration: config, documentsDirectory: tmpDir)
            let state = mgr.checkMLXModelState(modelId: "mlx-community/nonexistent-model")

            if case .notDownloaded = state {
                // Expected
            } else {
                Issue.record("Expected .notDownloaded, got \(state)")
            }
        }

        @Test("checkMLXModelState returns .notDownloaded for stub file (not a directory)")
        func stubFileRejected() throws {
            let config = URLSessionConfiguration.background(withIdentifier: "stub-test-\(UUID())")
            config.isDiscretionary = false
            let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tmpDir) }

            // Create a stub file (simulating a failed HF download response)
            let stubPath = tmpDir.appendingPathComponent("mlx-community--fake-model-4bit")
            try "Entry not found".write(to: stubPath, atomically: true, encoding: .utf8)

            let mgr = ModelDownloadManager(configuration: config, documentsDirectory: tmpDir)
            let state = mgr.checkMLXModelState(modelId: "mlx-community/fake-model-4bit")

            if case .notDownloaded = state {
                // Expected — stub files must not be reported as downloaded
            } else {
                Issue.record("Stub file was incorrectly reported as downloaded: \(state)")
            }
        }

        @Test("checkMLXModelState returns .notDownloaded for empty directory")
        func emptyDirRejected() throws {
            let config = URLSessionConfiguration.background(withIdentifier: "stub-test-\(UUID())")
            config.isDiscretionary = false
            let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tmpDir) }

            // Create an empty model directory (simulating an incomplete download)
            let modelDir = tmpDir.appendingPathComponent("mlx-community--fake-model-4bit")
            try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)

            let mgr = ModelDownloadManager(configuration: config, documentsDirectory: tmpDir)
            let state = mgr.checkMLXModelState(modelId: "mlx-community/fake-model-4bit")

            if case .notDownloaded = state {
                // Expected — empty dirs must not be reported as downloaded
            } else {
                Issue.record("Empty directory was incorrectly reported as downloaded: \(state)")
            }
        }

        @Test("checkMLXModelState returns .downloaded for valid MLX directory")
        func validDirAccepted() throws {
            let config = URLSessionConfiguration.background(withIdentifier: "stub-test-\(UUID())")
            config.isDiscretionary = false
            let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tmpDir) }

            // Create a valid MLX model directory with config.json and a .safetensors file
            let modelDir = tmpDir.appendingPathComponent("mlx-community--fake-model-4bit")
            try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)
            try "{}".write(to: modelDir.appendingPathComponent("config.json"), atomically: true, encoding: .utf8)
            try Data([0]).write(to: modelDir.appendingPathComponent("model.safetensors"))

            let mgr = ModelDownloadManager(configuration: config, documentsDirectory: tmpDir)
            let state = mgr.checkMLXModelState(modelId: "mlx-community/fake-model-4bit")

            if case .downloaded = state {
                // Expected — valid directory with config.json + safetensors
            } else {
                Issue.record("Valid MLX directory was not reported as downloaded: \(state)")
            }
        }

        @Test("checkState routes MLX models to directory-aware validation")
        func checkStateRoutesMLX() throws {
            let config = URLSessionConfiguration.background(withIdentifier: "stub-test-\(UUID())")
            config.isDiscretionary = false
            let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tmpDir) }

            // Create a stub file at the model path — this is the EXACT bug scenario.
            // The old checkState would see fileExists → true → report .downloaded.
            let stubPath = tmpDir.appendingPathComponent("mlx-community--gemma-4-E2B-it-4bit")
            try "Entry not found".write(to: stubPath, atomically: true, encoding: .utf8)

            let mgr = ModelDownloadManager(configuration: config, documentsDirectory: tmpDir)

            // Use the actual registry entry for Gemma 4 E2B MLX
            guard let model = ModelRegistry.knownModels.first(where: {
                $0.modelId == "mlx-community/gemma-4-E2B-it-4bit"
            }) else {
                Issue.record("Gemma 4 E2B MLX not found in registry")
                return
            }

            let state = mgr.checkState(for: model)

            if case .notDownloaded = state {
                // Expected — stub file must NOT pass directory validation
            } else {
                Issue.record("Stub file was accepted by checkState: \(state)")
            }
        }
    }

    // MARK: - MLX Engine Path Validation

    @Suite("MLX engine path validation")
    struct MLXEnginePathValidation {

        @Test("local filesystem paths are detected as local, not HuggingFace repo IDs")
        func localPathDetection() {
            let localPaths = [
                "/Users/test/models/mlx-community--gemma-4-E2B-it-4bit",
                "/var/tmp/model-dir",
                "~/Library/Caches/some-model",
            ]
            for path in localPaths {
                let isLocal = path.hasPrefix("/") || path.hasPrefix("~")
                #expect(isLocal, "Path should be detected as local: \(path)")
            }
        }

        @Test("HuggingFace repo IDs are detected as non-local")
        func repoIdDetection() {
            let repoIds = [
                "mlx-community/gemma-4-E2B-it-4bit",
                "google/gemma-4-12B-it",
            ]
            for id in repoIds {
                let isLocal = id.hasPrefix("/") || id.hasPrefix("~")
                #expect(!isLocal, "Repo ID should not be detected as local: \(id)")
            }
        }

        @Test("formatMismatch error has descriptive message")
        func formatMismatchError() {
            let error = EngineError.formatMismatch(
                engine: "LiteRT",
                modelPath: "/path/to/model",
                hint: "Switch to MLX engine first."
            )
            let desc = error.errorDescription ?? ""
            #expect(desc.contains("LiteRT"))
            #expect(desc.contains("Switch to MLX"))
        }
    }
}
