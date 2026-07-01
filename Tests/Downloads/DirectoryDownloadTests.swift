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

@Suite("DirectoryDownload & FileDownload")
struct DirectoryDownloadTests {

    // MARK: - Helpers

    /// Create a basic FileDownload for testing.
    private func makeFileDownload(
        filename: String = "model-00001-of-00003.safetensors",
        expectedSize: Int64 = 1_000_000_000,
        downloadedBytes: Int64 = 0,
        isComplete: Bool = false,
        hashVerified: Bool = false,
        expectedHash: String? = "abc123"
    ) -> ModelDownloadManager.FileDownload {
        ModelDownloadManager.FileDownload(
            filename: filename,
            url: URL(string: "https://huggingface.co/test/resolve/main/\(filename)")!,
            expectedSize: expectedSize,
            expectedHash: expectedHash,
            downloadedBytes: downloadedBytes,
            resumeData: nil,
            isComplete: isComplete,
            hashVerified: hashVerified
        )
    }

    /// Create a DirectoryDownload with the given file configurations.
    private func makeDirectoryDownload(
        modelId: String = "mlx-community/gemma-test-4bit",
        files: [ModelDownloadManager.FileDownload],
        totalBytes: Int64
    ) -> ModelDownloadManager.DirectoryDownload {
        ModelDownloadManager.DirectoryDownload(
            modelId: modelId,
            runtimeType: .mlx,
            files: files,
            totalBytes: totalBytes,
            localDirectory: URL(fileURLWithPath: "/tmp/models/test")
        )
    }

    /// Create a temporary directory with optional model files for checkMLXModelState tests.
    /// Returns the parent (documents) directory URL — the model directory is a child named `dirName`.
    private func createTempModelDirectory(
        dirName: String,
        includeConfig: Bool = true,
        includeSafetensors: Bool = true
    ) throws -> URL {
        let parentDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DirectoryDownloadTests-\(UUID().uuidString)")
        let modelDir = parentDir.appendingPathComponent(dirName)
        try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)

        if includeConfig {
            let configData = Data("{\"model_type\": \"gemma\"}".utf8)
            try configData.write(to: modelDir.appendingPathComponent("config.json"))
        }

        if includeSafetensors {
            let safetensorsData = Data("fake-weights".utf8)
            try safetensorsData.write(to: modelDir.appendingPathComponent("model-00001-of-00001.safetensors"))
        }

        return parentDir
    }

    /// Clean up a temporary directory.
    private func cleanupTempDirectory(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - FileDownload Tests

    @Test("FileDownload initialization sets all properties correctly")
    func testFileDownloadInitialization() {
        let file = makeFileDownload(
            filename: "model-00002-of-00003.safetensors",
            expectedSize: 2_000_000_000,
            downloadedBytes: 500_000_000,
            isComplete: false,
            hashVerified: true,
            expectedHash: "sha256hash"
        )

        #expect(file.filename == "model-00002-of-00003.safetensors")
        #expect(file.expectedSize == 2_000_000_000)
        #expect(file.downloadedBytes == 500_000_000)
        #expect(file.isComplete == false)
        #expect(file.hashVerified == true)
        #expect(file.expectedHash == "sha256hash")
        #expect(file.url.absoluteString.contains("model-00002-of-00003.safetensors"))
        #expect(file.resumeData == nil)
    }

    // MARK: - DirectoryDownload Progress Tests

    @Test("DirectoryDownload progress computes correctly with partial download")
    func testDirectoryDownloadProgress() {
        var file0 = makeFileDownload(filename: "shard-0.safetensors", expectedSize: 1_000_000_000)
        file0.downloadedBytes = 500_000_000
        file0.isComplete = false

        let file1 = makeFileDownload(filename: "shard-1.safetensors", expectedSize: 1_000_000_000)
        let file2 = makeFileDownload(filename: "shard-2.safetensors", expectedSize: 1_000_000_000)

        let dir = makeDirectoryDownload(
            files: [file0, file1, file2],
            totalBytes: 3_000_000_000
        )

        // 500MB / 3GB ≈ 0.1667
        let expectedProgress = Double(500_000_000) / Double(3_000_000_000)
        #expect(abs(dir.progress - expectedProgress) < 0.001)
        #expect(dir.downloadedBytes == 500_000_000)
        #expect(dir.isComplete == false)
        #expect(dir.completedFileCount == 0)
    }

    // MARK: - DirectoryDownload Completion Tests

    @Test("DirectoryDownload reports complete when all files are done")
    func testDirectoryDownloadCompletionTracking() {
        let files = (0..<3).map { i in
            makeFileDownload(
                filename: "shard-\(i).safetensors",
                expectedSize: 1_000_000_000,
                downloadedBytes: 1_000_000_000,
                isComplete: true,
                hashVerified: true
            )
        }

        let dir = makeDirectoryDownload(files: files, totalBytes: 3_000_000_000)

        #expect(dir.isComplete == true)
        #expect(dir.completedFileCount == 3)
        #expect(abs(dir.progress - 1.0) < 0.001)
        #expect(dir.downloadedBytes == 3_000_000_000)
    }

    @Test("DirectoryDownload not complete when only some files are done")
    func testDirectoryDownloadNotCompleteWhenPartial() {
        let file0 = makeFileDownload(
            filename: "shard-0.safetensors",
            expectedSize: 1_000_000_000,
            downloadedBytes: 1_000_000_000,
            isComplete: true
        )
        let file1 = makeFileDownload(
            filename: "shard-1.safetensors",
            expectedSize: 1_000_000_000,
            downloadedBytes: 1_000_000_000,
            isComplete: true
        )
        let file2 = makeFileDownload(
            filename: "shard-2.safetensors",
            expectedSize: 1_000_000_000,
            downloadedBytes: 300_000_000,
            isComplete: false
        )

        let dir = makeDirectoryDownload(files: [file0, file1, file2], totalBytes: 3_000_000_000)

        #expect(dir.isComplete == false)
        #expect(dir.completedFileCount == 2)
    }

    // MARK: - Edge Case: Zero Total Bytes

    @Test("DirectoryDownload with zero totalBytes returns 0 progress without division by zero")
    func testDirectoryDownloadZeroTotalBytes() {
        let file = makeFileDownload(expectedSize: 0, downloadedBytes: 0, isComplete: false)
        let dir = makeDirectoryDownload(files: [file], totalBytes: 0)

        #expect(dir.progress == 0)
        #expect(!dir.progress.isNaN)
        #expect(!dir.progress.isInfinite)
    }

    // MARK: - DownloadState Enum Cases

    @Test("DownloadState directory enum cases can be created and pattern-matched")
    func testDownloadStateEnumCases() {
        let downloading = ModelDownloadManager.DownloadState.downloadingDirectory(
            progress: 0.5,
            completedFiles: 2,
            totalFiles: 5
        )

        let paused = ModelDownloadManager.DownloadState.pausedDirectory(
            progress: 0.3,
            completedFiles: 1,
            totalFiles: 5
        )

        // Pattern match downloadingDirectory
        if case .downloadingDirectory(let progress, let completed, let total) = downloading {
            #expect(progress == 0.5)
            #expect(completed == 2)
            #expect(total == 5)
        } else {
            Issue.record("Failed to match .downloadingDirectory")
        }

        // Pattern match pausedDirectory
        if case .pausedDirectory(let progress, let completed, let total) = paused {
            #expect(progress == 0.3)
            #expect(completed == 1)
            #expect(total == 5)
        } else {
            Issue.record("Failed to match .pausedDirectory")
        }
    }

    // MARK: - checkMLXModelState Tests

    @Test("checkMLXModelState returns .downloaded for valid directory with config and safetensors")
    @MainActor
    func testCheckMLXModelStateWithValidDirectory() throws {
        let modelId = "mlx-community/gemma-test-4bit"
        let dirName = modelId.replacingOccurrences(of: "/", with: "--")
        let parentDir = try createTempModelDirectory(
            dirName: dirName,
            includeConfig: true,
            includeSafetensors: true
        )
        defer { cleanupTempDirectory(parentDir) }

        let manager = ModelDownloadManager(
            configuration: URLSessionConfiguration.ephemeral,
            documentsDirectory: parentDir
        )

        let state = manager.checkMLXModelState(modelId: modelId)

        if case .downloaded(let url) = state {
            #expect(url.lastPathComponent == dirName)
        } else {
            Issue.record("Expected .downloaded but got \(state)")
        }
    }

    @Test("checkMLXModelState returns .notDownloaded when config.json is missing")
    @MainActor
    func testCheckMLXModelStateMissingConfig() throws {
        let modelId = "mlx-community/gemma-noconfig"
        let dirName = modelId.replacingOccurrences(of: "/", with: "--")
        let parentDir = try createTempModelDirectory(
            dirName: dirName,
            includeConfig: false,
            includeSafetensors: true
        )
        defer { cleanupTempDirectory(parentDir) }

        let manager = ModelDownloadManager(
            configuration: URLSessionConfiguration.ephemeral,
            documentsDirectory: parentDir
        )

        let state = manager.checkMLXModelState(modelId: modelId)

        if case .notDownloaded = state {
            // Expected
        } else {
            Issue.record("Expected .notDownloaded but got \(state)")
        }
    }

    @Test("checkMLXModelState returns .notDownloaded when safetensors files are missing")
    @MainActor
    func testCheckMLXModelStateMissingSafetensors() throws {
        let modelId = "mlx-community/gemma-notensors"
        let dirName = modelId.replacingOccurrences(of: "/", with: "--")
        let parentDir = try createTempModelDirectory(
            dirName: dirName,
            includeConfig: true,
            includeSafetensors: false
        )
        defer { cleanupTempDirectory(parentDir) }

        let manager = ModelDownloadManager(
            configuration: URLSessionConfiguration.ephemeral,
            documentsDirectory: parentDir
        )

        let state = manager.checkMLXModelState(modelId: modelId)

        if case .notDownloaded = state {
            // Expected
        } else {
            Issue.record("Expected .notDownloaded but got \(state)")
        }
    }
}
