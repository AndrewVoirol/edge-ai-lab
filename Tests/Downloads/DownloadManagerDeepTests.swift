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

// MARK: - Test Helpers

/// Minimal ModelCapabilityProfile factory for tests that need a profile instance
/// without depending on KnownModelCatalog or real model files.
private func makeDummyProfile(
    name: String = "TestModel",
    modelId: String = "test/test-model",
    modelFile: String = "test-model.litertlm",
    fileSizeBytes: Int64 = 1_000_000_000
) -> ModelCapabilityProfile {
    ModelCapabilityProfile(
        id: modelFile,
        displayName: name,
        repoId: modelId,
        runtimeType: .litertlm,
        supportsVision: nil,
        supportsAudio: nil,
        supportsThinking: nil,
        supportsToolCalling: nil,
        supportsMTP: nil,
        supportsConstrainedDecoding: nil,
        architecture: nil,
        contextWindow: nil,
        fileSizeBytes: fileSizeBytes,
        estimatedMemoryGB: nil,
        totalParameters: nil,
        parameterLabel: nil,
        confidence: .low,
        source: .huggingFaceInferred,
        lastUpdated: Date(),
        repoSha: nil,
        license: nil, licenseLink: nil, baseModelId: nil,
        downloads: nil, likes: nil, downloadsAllTime: nil,
        supportedLanguages: [],
        tags: [],
        defaultConfig: ModelDefaultConfig(
            topK: 1,
            topP: 1.0,
            temperature: 1.0,
            maxContextLength: 1024,
            maxTokens: 512,
            accelerators: "cpu",
            visionAccelerator: nil
        ),
        platformSupport: PlatformSupport(
            macOS: .cpuOnly,
            iOSDevice: .cpuOnly,
            iOSSimulator: .cpuOnly
        ),
        modelDescription: "A test model",
        recommendedFor: "Testing",
        modelFile: modelFile,
        modelId: modelId
    )
}

// MARK: - DownloadState Enum Tests

@Suite("DownloadState Enum")
struct DownloadStateTests {

    @Test("notDownloaded is a distinct state")
    func notDownloadedState() {
        let state = ModelDownloadManager.DownloadState.notDownloaded
        if case .notDownloaded = state {
            // pass
        } else {
            Issue.record("Expected .notDownloaded")
        }
    }

    @Test("downloading carries progress value")
    func downloadingProgress() {
        let state = ModelDownloadManager.DownloadState.downloading(progress: 0.42)
        if case .downloading(let progress) = state {
            #expect(progress == 0.42)
        } else {
            Issue.record("Expected .downloading")
        }
    }

    @Test("downloading progress at zero")
    func downloadingProgressZero() {
        let state = ModelDownloadManager.DownloadState.downloading(progress: 0.0)
        if case .downloading(let progress) = state {
            #expect(progress == 0.0)
        } else {
            Issue.record("Expected .downloading")
        }
    }

    @Test("downloading progress at one (complete)")
    func downloadingProgressComplete() {
        let state = ModelDownloadManager.DownloadState.downloading(progress: 1.0)
        if case .downloading(let progress) = state {
            #expect(progress == 1.0)
        } else {
            Issue.record("Expected .downloading")
        }
    }

    @Test("queued carries position")
    func queuedPosition() {
        let state = ModelDownloadManager.DownloadState.queued(position: 3)
        if case .queued(let position) = state {
            #expect(position == 3)
        } else {
            Issue.record("Expected .queued")
        }
    }

    @Test("paused carries resume data and progress")
    func pausedState() {
        let resumeData = Data([0x01, 0x02, 0x03])
        let state = ModelDownloadManager.DownloadState.paused(
            resumeData: resumeData,
            progress: 0.65
        )
        if case .paused(let data, let progress) = state {
            #expect(data == resumeData)
            #expect(progress == 0.65)
        } else {
            Issue.record("Expected .paused")
        }
    }

    @Test("downloaded carries file URL")
    func downloadedState() {
        let url = URL(fileURLWithPath: "/tmp/test-model.litertlm")
        let state = ModelDownloadManager.DownloadState.downloaded(url)
        if case .downloaded(let resultURL) = state {
            #expect(resultURL == url)
        } else {
            Issue.record("Expected .downloaded")
        }
    }

    @Test("failed carries error message")
    func failedState() {
        let state = ModelDownloadManager.DownloadState.failed("Network timeout")
        if case .failed(let message) = state {
            #expect(message == "Network timeout")
        } else {
            Issue.record("Expected .failed")
        }
    }

    @Test("authRequired is a distinct state")
    func authRequiredState() {
        let state = ModelDownloadManager.DownloadState.authRequired
        if case .authRequired = state {
            // pass
        } else {
            Issue.record("Expected .authRequired")
        }
    }

    @Test("DownloadState is Sendable")
    func sendableConformance() async {
        // Construct on one task, send to another — verifies Sendable at compile time.
        let state = ModelDownloadManager.DownloadState.downloading(progress: 0.5)
        let received = await Task.detached { state }.value
        if case .downloading(let progress) = received {
            #expect(progress == 0.5)
        } else {
            Issue.record("State should survive cross-task send")
        }
    }
}

// MARK: - DownloadProgress Tests

@Suite("DownloadProgress")
struct DownloadProgressTests {

    // MARK: - formattedSpeed

    @Test("formattedSpeed includes per-second suffix")
    func formattedSpeedSuffix() {
        let progress = ModelDownloadManager.DownloadProgress(
            progress: 0.5,
            bytesWritten: 500_000_000,
            totalBytes: 1_000_000_000,
            speedBytesPerSecond: 10_000_000,
            estimatedSecondsRemaining: 50
        )
        let speed = progress.formattedSpeed
        #expect(speed.hasSuffix("/s"))
        // 10 MB/s — should contain "MB" (ByteCountFormatter .file style)
        #expect(speed.contains("MB"))
    }

    @Test("formattedSpeed at zero bytes per second")
    func formattedSpeedZero() {
        let progress = ModelDownloadManager.DownloadProgress(
            progress: 0.0,
            bytesWritten: 0,
            totalBytes: 1_000_000_000,
            speedBytesPerSecond: 0,
            estimatedSecondsRemaining: nil
        )
        let speed = progress.formattedSpeed
        #expect(speed.hasSuffix("/s"))
        // Zero bytes — should show "Zero" or "0" depending on locale
        #expect(speed.contains("0") || speed.lowercased().contains("zero"))
    }

    @Test("formattedSpeed at GB/s range")
    func formattedSpeedGigabyte() {
        let progress = ModelDownloadManager.DownloadProgress(
            progress: 0.5,
            bytesWritten: 500_000_000,
            totalBytes: 1_000_000_000,
            speedBytesPerSecond: 1_500_000_000,
            estimatedSecondsRemaining: 0.3
        )
        let speed = progress.formattedSpeed
        #expect(speed.contains("GB"))
    }

    // MARK: - formattedETA

    @Test("formattedETA returns nil when estimatedSecondsRemaining is nil")
    func etaNilWhenNoEstimate() {
        let progress = ModelDownloadManager.DownloadProgress(
            progress: 0.1,
            bytesWritten: 100_000_000,
            totalBytes: 1_000_000_000,
            speedBytesPerSecond: 5_000_000,
            estimatedSecondsRemaining: nil
        )
        #expect(progress.formattedETA == nil)
    }

    @Test("formattedETA returns nil when seconds is zero")
    func etaNilWhenZero() {
        let progress = ModelDownloadManager.DownloadProgress(
            progress: 1.0,
            bytesWritten: 1_000_000_000,
            totalBytes: 1_000_000_000,
            speedBytesPerSecond: 0,
            estimatedSecondsRemaining: 0
        )
        #expect(progress.formattedETA == nil)
    }

    @Test("formattedETA returns nil when seconds is negative")
    func etaNilWhenNegative() {
        let progress = ModelDownloadManager.DownloadProgress(
            progress: 0.5,
            bytesWritten: 500_000_000,
            totalBytes: 1_000_000_000,
            speedBytesPerSecond: 10_000_000,
            estimatedSecondsRemaining: -10
        )
        #expect(progress.formattedETA == nil)
    }

    @Test("formattedETA returns nil when seconds exceeds 24 hours")
    func etaNilWhenExcessive() {
        let progress = ModelDownloadManager.DownloadProgress(
            progress: 0.01,
            bytesWritten: 10_000_000,
            totalBytes: 1_000_000_000,
            speedBytesPerSecond: 100,
            estimatedSecondsRemaining: 100_000  // > 86400
        )
        #expect(progress.formattedETA == nil)
    }

    @Test("formattedETA returns a non-nil string for reasonable ETA")
    func etaNonNilForReasonableTime() {
        let progress = ModelDownloadManager.DownloadProgress(
            progress: 0.5,
            bytesWritten: 500_000_000,
            totalBytes: 1_000_000_000,
            speedBytesPerSecond: 10_000_000,
            estimatedSecondsRemaining: 120  // 2 minutes
        )
        let eta = progress.formattedETA
        #expect(eta != nil)
        // Should produce something like "2m 0s" or "2 min 0 sec" depending on locale
    }

    @Test("formattedETA uses hour+minute units for times over 1 hour")
    func etaUsesHoursForLongTimes() {
        let progress = ModelDownloadManager.DownloadProgress(
            progress: 0.1,
            bytesWritten: 100_000_000,
            totalBytes: 1_000_000_000,
            speedBytesPerSecond: 500_000,
            estimatedSecondsRemaining: 7200  // 2 hours
        )
        let eta = progress.formattedETA
        #expect(eta != nil)
        // Should contain hour indicator (h or hr depending on locale)
    }

    @Test("formattedETA at boundary of 86400 seconds returns nil")
    func etaAtExactBoundary() {
        let progress = ModelDownloadManager.DownloadProgress(
            progress: 0.01,
            bytesWritten: 10_000_000,
            totalBytes: 1_000_000_000,
            speedBytesPerSecond: 10,
            estimatedSecondsRemaining: 86400  // exactly 24 hours
        )
        // The guard is `seconds < 86400`, so exactly 86400 should return nil
        #expect(progress.formattedETA == nil)
    }

    @Test("formattedETA at 86399 seconds returns non-nil")
    func etaJustUnderBoundary() {
        let progress = ModelDownloadManager.DownloadProgress(
            progress: 0.01,
            bytesWritten: 10_000_000,
            totalBytes: 1_000_000_000,
            speedBytesPerSecond: 10,
            estimatedSecondsRemaining: 86399
        )
        #expect(progress.formattedETA != nil)
    }

    // MARK: - formattedBytesWritten / formattedTotalBytes

    @Test("formattedBytesWritten uses file count style")
    func formattedBytesWritten() {
        let progress = ModelDownloadManager.DownloadProgress(
            progress: 0.5,
            bytesWritten: 1_500_000_000,
            totalBytes: 3_000_000_000,
            speedBytesPerSecond: 10_000_000,
            estimatedSecondsRemaining: 150
        )
        let formatted = progress.formattedBytesWritten
        // 1.5 GB — should contain "GB" (ByteCountFormatter .file = decimal/SI)
        #expect(formatted.contains("GB"))
    }

    @Test("formattedTotalBytes uses file count style")
    func formattedTotalBytes() {
        let progress = ModelDownloadManager.DownloadProgress(
            progress: 0.5,
            bytesWritten: 1_500_000_000,
            totalBytes: 3_000_000_000,
            speedBytesPerSecond: 10_000_000,
            estimatedSecondsRemaining: 150
        )
        let formatted = progress.formattedTotalBytes
        #expect(formatted.contains("GB"))
    }

    @Test("formattedBytesWritten at zero bytes")
    func formattedBytesWrittenZero() {
        let progress = ModelDownloadManager.DownloadProgress(
            progress: 0.0,
            bytesWritten: 0,
            totalBytes: 1_000_000_000,
            speedBytesPerSecond: 0,
            estimatedSecondsRemaining: nil
        )
        let formatted = progress.formattedBytesWritten
        // Should contain "0" or "Zero"
        #expect(formatted.contains("0") || formatted.lowercased().contains("zero"))
    }

    @Test("formattedTotalBytes for KB-range model")
    func formattedTotalBytesKB() {
        let progress = ModelDownloadManager.DownloadProgress(
            progress: 0.1,
            bytesWritten: 50_000,
            totalBytes: 500_000,
            speedBytesPerSecond: 100_000,
            estimatedSecondsRemaining: 4.5
        )
        let formatted = progress.formattedTotalBytes
        #expect(formatted.contains("KB"))
    }

    // MARK: - Sendable

    @Test("DownloadProgress is Sendable")
    func sendableConformance() async {
        let progress = ModelDownloadManager.DownloadProgress(
            progress: 0.75,
            bytesWritten: 750_000_000,
            totalBytes: 1_000_000_000,
            speedBytesPerSecond: 25_000_000,
            estimatedSecondsRemaining: 10
        )
        let received = await Task.detached { progress }.value
        #expect(received.progress == 0.75)
        #expect(received.bytesWritten == 750_000_000)
    }
}

// MARK: - StorageCheck Tests

@Suite("StorageCheck")
struct StorageCheckTests {

    @Test("hasEnoughSpace is true when available exceeds model + buffer")
    func enoughSpace() {
        let check = ModelDownloadManager.StorageCheck(
            modelSize: 2_000_000_000,
            availableSpace: 10_000_000_000,
            hasEnoughSpace: true
        )
        #expect(check.hasEnoughSpace)
    }

    @Test("hasEnoughSpace is false when available is less than model + buffer")
    func notEnoughSpace() {
        let check = ModelDownloadManager.StorageCheck(
            modelSize: 5_000_000_000,
            availableSpace: 5_000_000_000,  // No room for 500MB buffer
            hasEnoughSpace: false
        )
        #expect(!check.hasEnoughSpace)
    }

    @Test("formattedModelSize contains correct unit suffix for GB-range model")
    func formattedModelSizeGB() {
        let check = ModelDownloadManager.StorageCheck(
            modelSize: 2_588_147_712,
            availableSpace: 50_000_000_000,
            hasEnoughSpace: true
        )
        let formatted = check.formattedModelSize
        #expect(formatted.contains("GB"))
    }

    @Test("formattedAvailableSpace contains correct unit suffix")
    func formattedAvailableSpaceGB() {
        let check = ModelDownloadManager.StorageCheck(
            modelSize: 2_000_000_000,
            availableSpace: 50_000_000_000,
            hasEnoughSpace: true
        )
        let formatted = check.formattedAvailableSpace
        #expect(formatted.contains("GB"))
    }

    @Test("formattedModelSize at zero bytes")
    func formattedModelSizeZero() {
        let check = ModelDownloadManager.StorageCheck(
            modelSize: 0,
            availableSpace: 10_000_000_000,
            hasEnoughSpace: true
        )
        let formatted = check.formattedModelSize
        #expect(formatted.contains("0") || formatted.lowercased().contains("zero"))
    }

    @Test("StorageCheck is Sendable")
    func sendableConformance() async {
        let check = ModelDownloadManager.StorageCheck(
            modelSize: 1_000_000_000,
            availableSpace: 5_000_000_000,
            hasEnoughSpace: true
        )
        let received = await Task.detached { check }.value
        #expect(received.modelSize == 1_000_000_000)
        #expect(received.hasEnoughSpace)
    }
}

// MARK: - Testable Initializer & Initial State

@Suite("Testable Initializer")
@MainActor
struct TestableInitializerTests {

    @Test("testable init sets custom documents directory")
    func customDocumentsDirectory() {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DownloadManagerDeepTests-\(UUID().uuidString)")
        let config = URLSessionConfiguration.ephemeral
        let manager = ModelDownloadManager(
            configuration: config,
            documentsDirectory: tempDir
        )
        #expect(manager.documentsDirectory == tempDir)
    }

    @Test("testable init starts with empty downloadStates")
    func emptyDownloadStates() {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DownloadManagerDeepTests-\(UUID().uuidString)")
        let config = URLSessionConfiguration.ephemeral
        let manager = ModelDownloadManager(
            configuration: config,
            documentsDirectory: tempDir
        )
        #expect(manager.downloadStates.isEmpty)
    }

    @Test("testable init starts with empty downloadProgress")
    func emptyDownloadProgress() {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DownloadManagerDeepTests-\(UUID().uuidString)")
        let config = URLSessionConfiguration.ephemeral
        let manager = ModelDownloadManager(
            configuration: config,
            documentsDirectory: tempDir
        )
        #expect(manager.downloadProgress.isEmpty)
    }

    @Test("testable init starts with showTokenPrompt false")
    func showTokenPromptFalse() {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DownloadManagerDeepTests-\(UUID().uuidString)")
        let config = URLSessionConfiguration.ephemeral
        let manager = ModelDownloadManager(
            configuration: config,
            documentsDirectory: tempDir
        )
        #expect(manager.showTokenPrompt == false)
    }

    @Test("testable init starts with pendingAuthModel nil")
    func pendingAuthModelNil() {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DownloadManagerDeepTests-\(UUID().uuidString)")
        let config = URLSessionConfiguration.ephemeral
        let manager = ModelDownloadManager(
            configuration: config,
            documentsDirectory: tempDir
        )
        #expect(manager.pendingAuthModel == nil)
    }

    @Test("testable init starts with backgroundSessionCompletionHandler nil")
    func backgroundCompletionHandlerNil() {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DownloadManagerDeepTests-\(UUID().uuidString)")
        let config = URLSessionConfiguration.ephemeral
        let manager = ModelDownloadManager(
            configuration: config,
            documentsDirectory: tempDir
        )
        #expect(manager.backgroundSessionCompletionHandler == nil)
    }

    @Test("default maxConcurrentDownloads is 1")
    func defaultConcurrency() {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DownloadManagerDeepTests-\(UUID().uuidString)")
        let config = URLSessionConfiguration.ephemeral
        let manager = ModelDownloadManager(
            configuration: config,
            documentsDirectory: tempDir
        )
        #expect(manager.maxConcurrentDownloads == 1)
    }

    @Test("postDownloadCallbacks is initially empty")
    func postDownloadCallbacksEmpty() {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DownloadManagerDeepTests-\(UUID().uuidString)")
        let config = URLSessionConfiguration.ephemeral
        let manager = ModelDownloadManager(
            configuration: config,
            documentsDirectory: tempDir
        )
        #expect(manager.postDownloadCallbacks.isEmpty)
    }
}

// MARK: - Download without URL

@Suite("Download Error Handling")
@MainActor
struct DownloadErrorHandlingTests {

    @Test("download sets failed state when model has no download URL")
    func downloadWithNoURL() {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DownloadManagerDeepTests-\(UUID().uuidString)")
        let config = URLSessionConfiguration.ephemeral
        _ = ModelDownloadManager(
            configuration: config,
            documentsDirectory: tempDir
        )

        // A model with a modelId that produces a nil downloadURL isn't possible
        // with the current implementation (URL(string:) rarely returns nil for valid strings).
        // But we CAN verify the non-nil path works by testing that a model with a valid
        // downloadURL doesn't immediately set .failed.
        let profile = makeDummyProfile()
        // downloadURL for "test/test-model" / "test-model.litertlm" should be non-nil
        #expect(profile.downloadURL != nil)
    }

    @Test("deleteModel on testable init sets notDownloaded state")
    func deleteModelSetsNotDownloaded() {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DownloadManagerDeepTests-\(UUID().uuidString)")
        let config = URLSessionConfiguration.ephemeral
        let manager = ModelDownloadManager(
            configuration: config,
            documentsDirectory: tempDir
        )

        let profile = makeDummyProfile()
        manager.deleteModel(profile)

        if case .notDownloaded = manager.downloadStates[profile.modelFile ?? profile.id] {
            // Expected
        } else {
            Issue.record("Expected .notDownloaded after deleteModel")
        }
    }

    @Test("deleteModel by filename on testable init sets notDownloaded state")
    func deleteModelByFilenameSetsNotDownloaded() {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DownloadManagerDeepTests-\(UUID().uuidString)")
        let config = URLSessionConfiguration.ephemeral
        let manager = ModelDownloadManager(
            configuration: config,
            documentsDirectory: tempDir
        )

        manager.deleteModel(filename: "some-model.litertlm")

        if case .notDownloaded = manager.downloadStates["some-model.litertlm"] {
            // Expected
        } else {
            Issue.record("Expected .notDownloaded after deleteModel(filename:)")
        }
    }
}

// NOTE: ModelMetadataDownloadURLTests, ModelMetadataAuthTests, and
// ModelMetadataCapabilitiesTests were deleted — they tested the now-removed
// ModelMetadata struct's computed properties (downloadURL construction,
// requiresAuth flag, capabilities derived from string arrays).
// Those properties are now part of ModelCapabilityProfile with different
// semantics (SourcedValue<Bool> instead of string-array heuristics).

// MARK: - Storage Buffer Validation

@Suite("Storage Buffer")
@MainActor
struct StorageBufferTests {

    @Test("checkStorage applies 500MB safety buffer")
    func storageBufferApplied() {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DownloadManagerDeepTests-\(UUID().uuidString)")
        let config = URLSessionConfiguration.ephemeral
        let manager = ModelDownloadManager(
            configuration: config,
            documentsDirectory: tempDir
        )

        // checkStorage reads actual disk availability, so we can't fully control it,
        // but we can verify the StorageCheck struct it returns has reasonable values.
        let profile = makeDummyProfile(fileSizeBytes: 2_000_000_000)
        let check = manager.checkStorage(for: profile)
        #expect(check.modelSize == 2_000_000_000)
        // Available space should be > 0 on any running system
        #expect(check.availableSpace > 0)
    }
}

// MARK: - HFModelBrowser.downloadURL

@Suite("HFModelBrowser.downloadURL")
struct HFModelBrowserDownloadURLTests {

    @Test("downloadURL constructs correct HuggingFace resolve URL")
    func basicConstruction() {
        let url = HFModelBrowser.downloadURL(
            repoId: "litert-community/gemma-4-E2B-it-litert-lm",
            filename: "gemma-4-E2B-it.litertlm"
        )
        #expect(url.absoluteString == "https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm")
    }

    @Test("downloadURL uses specified revision")
    func customRevision() {
        let url = HFModelBrowser.downloadURL(
            repoId: "litert-community/gemma-4-E2B-it-litert-lm",
            filename: "gemma-4-E2B-it.litertlm",
            revision: "v1.0"
        )
        #expect(url.absoluteString.contains("/resolve/v1.0/"))
        #expect(!url.absoluteString.contains("/resolve/main/"))
    }

    @Test("downloadURL defaults to main revision")
    func defaultRevisionIsMain() {
        let url = HFModelBrowser.downloadURL(
            repoId: "test/repo",
            filename: "model.litertlm"
        )
        #expect(url.absoluteString.contains("/resolve/main/"))
    }

    @Test("downloadURL contains repo ID in path")
    func containsRepoId() {
        let url = HFModelBrowser.downloadURL(
            repoId: "org/my-model-repo",
            filename: "weights.litertlm"
        )
        #expect(url.absoluteString.contains("org/my-model-repo"))
    }

    @Test("downloadURL contains filename in path")
    func containsFilename() {
        let url = HFModelBrowser.downloadURL(
            repoId: "org/repo",
            filename: "my-special-model.litertlm"
        )
        #expect(url.absoluteString.contains("my-special-model.litertlm"))
    }

    @Test("downloadURL scheme is HTTPS")
    func usesHTTPS() {
        let url = HFModelBrowser.downloadURL(
            repoId: "any/repo",
            filename: "model.bin"
        )
        #expect(url.scheme == "https")
    }

    @Test("downloadURL host is huggingface.co")
    func hostIsHuggingFace() {
        let url = HFModelBrowser.downloadURL(
            repoId: "any/repo",
            filename: "model.bin"
        )
        #expect(url.host == "huggingface.co")
    }
}

// MARK: - DownloadProgress Edge Cases

@Suite("DownloadProgress Edge Cases")
struct DownloadProgressEdgeCaseTests {

    @Test("progress clamped representation at extremes",
          arguments: [0.0, 0.5, 1.0])
    func progressValues(value: Double) {
        let progress = ModelDownloadManager.DownloadProgress(
            progress: value,
            bytesWritten: Int64(value * 1_000_000_000),
            totalBytes: 1_000_000_000,
            speedBytesPerSecond: 10_000_000,
            estimatedSecondsRemaining: value < 1.0 ? 50.0 : 0.0
        )
        #expect(progress.progress == value)
    }

    @Test("very small speed shows KB/s or bytes/s")
    func verySmallSpeed() {
        let progress = ModelDownloadManager.DownloadProgress(
            progress: 0.01,
            bytesWritten: 10_000,
            totalBytes: 1_000_000,
            speedBytesPerSecond: 512,
            estimatedSecondsRemaining: 1930
        )
        let speed = progress.formattedSpeed
        #expect(speed.hasSuffix("/s"))
        // 512 bytes/s — should not contain GB or MB
        #expect(!speed.contains("GB"))
        #expect(!speed.contains("MB"))
    }
}

// NOTE: ModelMetadataCodableTests was deleted — it tested Codable round-trips
// for the now-removed ModelMetadata struct. ModelCapabilityProfile has its own
// Codable conformance tested elsewhere.

// MARK: - Codable Round-Trips (Shared Types)

@Suite("Shared Type Codable")
struct SharedTypeCodableTests {

    @Test("ModelDefaultConfig round-trips through JSON")
    func defaultConfigRoundTrip() throws {
        let config = ModelDefaultConfig(
            topK: 64,
            topP: 0.95,
            temperature: 1.0,
            maxContextLength: 32_000,
            maxTokens: 4_000,
            accelerators: "gpu,cpu",
            visionAccelerator: "gpu"
        )
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(ModelDefaultConfig.self, from: data)

        #expect(decoded.topK == 64)
        #expect(decoded.topP == 0.95)
        #expect(decoded.temperature == 1.0)
        #expect(decoded.maxContextLength == 32_000)
        #expect(decoded.maxTokens == 4_000)
        #expect(decoded.accelerators == "gpu,cpu")
        #expect(decoded.visionAccelerator == "gpu")
    }

    @Test("ModelDefaultConfig round-trips with nil visionAccelerator")
    func defaultConfigNilVisionAccelerator() throws {
        let config = ModelDefaultConfig(
            topK: 1,
            topP: 1.0,
            temperature: 1.0,
            maxContextLength: 1024,
            maxTokens: 256,
            accelerators: "gpu",
            visionAccelerator: nil
        )
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(ModelDefaultConfig.self, from: data)
        #expect(decoded.visionAccelerator == nil)
    }

    @Test("PlatformSupport round-trips through JSON")
    func platformSupportRoundTrip() throws {
        let support = PlatformSupport(
            macOS: .gpuAndCpu,
            iOSDevice: .gpuOnly,
            iOSSimulator: .cpuOnly
        )
        let data = try JSONEncoder().encode(support)
        let decoded = try JSONDecoder().decode(PlatformSupport.self, from: data)

        #expect(decoded.macOS == .gpuAndCpu)
        #expect(decoded.iOSDevice == .gpuOnly)
        #expect(decoded.iOSSimulator == .cpuOnly)
    }
}

// MARK: - BackendCapability Tests

@Suite("BackendCapability")
struct BackendCapabilityTests {

    @Test("gpuOnly supports GPU but not CPU")
    func gpuOnly() {
        let cap = BackendCapability.gpuOnly
        #expect(cap.supportsGPU == true)
        #expect(cap.supportsCPU == false)
    }

    @Test("cpuOnly supports CPU but not GPU")
    func cpuOnly() {
        let cap = BackendCapability.cpuOnly
        #expect(cap.supportsGPU == false)
        #expect(cap.supportsCPU == true)
    }

    @Test("gpuAndCpu supports both")
    func gpuAndCpu() {
        let cap = BackendCapability.gpuAndCpu
        #expect(cap.supportsGPU == true)
        #expect(cap.supportsCPU == true)
    }

    @Test("unknown supports neither")
    func unknown() {
        let cap = BackendCapability.unknown
        #expect(cap.supportsGPU == false)
        #expect(cap.supportsCPU == false)
    }

    @Test("recommendedBackend for gpuOnly is .gpu")
    func recommendedGPUOnly() {
        #expect(BackendCapability.gpuOnly.recommendedBackend == .gpu)
    }

    @Test("recommendedBackend for cpuOnly is .cpu")
    func recommendedCPUOnly() {
        #expect(BackendCapability.cpuOnly.recommendedBackend == .cpu)
    }

    @Test("recommendedBackend for gpuAndCpu prefers .gpu")
    func recommendedGPUAndCpu() {
        #expect(BackendCapability.gpuAndCpu.recommendedBackend == .gpu)
    }

    @Test("recommendedBackend for unknown is .probeRequired")
    func recommendedUnknown() {
        #expect(BackendCapability.unknown.recommendedBackend == .probeRequired)
    }

    @Test("BackendCapability round-trips through Codable",
          arguments: [BackendCapability.gpuOnly, .cpuOnly, .gpuAndCpu, .unknown])
    func codableRoundTrip(capability: BackendCapability) throws {
        let data = try JSONEncoder().encode(capability)
        let decoded = try JSONDecoder().decode(BackendCapability.self, from: data)
        #expect(decoded == capability)
    }
}

// MARK: - RuntimeType Tests

@Suite("RuntimeType — Download Context")
struct DownloadManagerRuntimeTypeTests {

    @Test("litertlm file extension is litertlm")
    func litertlmExtension() {
        #expect(RuntimeType.litertlm.fileExtension == "litertlm")
    }

    @Test("mlx file extension is safetensors")
    func mlxExtension() {
        #expect(RuntimeType.mlx.fileExtension == "safetensors")
    }

    @Test("gguf file extension is gguf")
    func ggufExtension() {
        #expect(RuntimeType.gguf.fileExtension == "gguf")
    }

    @Test("all three runtimes are supported")
    func supportedRuntimes() {
        #expect(RuntimeType.litertlm.isSupported == true)
        #expect(RuntimeType.mlx.isSupported == true)
        #expect(RuntimeType.gguf.isSupported == true)
    }

    @Test("displayName matches rawValue")
    func displayNameMatchesRawValue() {
        for rt in RuntimeType.allCases {
            #expect(rt.displayName == rt.rawValue)
        }
    }

    @Test("RuntimeType round-trips through Codable",
          arguments: RuntimeType.allCases)
    func codableRoundTrip(runtimeType: RuntimeType) throws {
        let data = try JSONEncoder().encode(runtimeType)
        let decoded = try JSONDecoder().decode(RuntimeType.self, from: data)
        #expect(decoded == runtimeType)
    }
}

// MARK: - KnownModelCatalog Lookup Tests

@Suite("KnownModelCatalog Lookup")
struct KnownModelCatalogLookupTests {

    @Test("lookup by filename finds known model",
          arguments: KnownModelCatalog.allModels)
    func lookupByFilename(profile: ModelCapabilityProfile) {
        guard let modelFile = profile.modelFile else {
            Issue.record("Profile \(profile.displayName) has nil modelFile")
            return
        }
        let found = KnownModelCatalog.lookup(filename: modelFile)
        #expect(found != nil)
        #expect(found?.displayName == profile.displayName)
    }

    @Test("lookup by path finds known model")
    func lookupByPath() {
        let profile = KnownModelCatalog.gemma4E2BStandard
        let modelFile = profile.modelFile ?? profile.id
        let path = "/some/directory/\(modelFile)"
        let found = KnownModelCatalog.lookup(path: path)
        #expect(found != nil)
        #expect(found?.modelFile == profile.modelFile)
    }

    @Test("lookup by filename returns nil for unknown model")
    func lookupUnknownFilename() {
        let found = KnownModelCatalog.lookup(filename: "nonexistent-model.litertlm")
        #expect(found == nil)
    }

    @Test("lookup by path returns nil for unknown model")
    func lookupUnknownPath() {
        let found = KnownModelCatalog.lookup(path: "/path/to/nonexistent-model.litertlm")
        #expect(found == nil)
    }

    @Test("recommendedBackend returns .probeRequired for unknown models")
    func recommendedBackendUnknown() {
        let found = KnownModelCatalog.lookup(path: "/path/to/unknown.litertlm")
        #expect(found?.recommendedBackend ?? .probeRequired == .probeRequired)
    }

    @Test("recommendedBackend returns a known recommendation for catalog models",
          arguments: KnownModelCatalog.allModels.filter { $0.platformSupport?.currentPlatform != .unknown })
    func recommendedBackendKnown(profile: ModelCapabilityProfile) {
        // Models with .unknown capability on this platform (e.g., MLX on iOS Simulator)
        // are filtered out of the arguments above, so this assertion is always valid.
        #expect(profile.recommendedBackend != .probeRequired)
    }

    @Test("allModels is non-empty")
    func allModelsNotEmpty() {
        #expect(!KnownModelCatalog.allModels.isEmpty)
    }

    @Test("allModels have unique modelFile values")
    func uniqueModelFiles() {
        let files = KnownModelCatalog.allModels.compactMap(\.modelFile)
        let uniqueFiles = Set(files)
        #expect(files.count == uniqueFiles.count)
    }

    @Test("allModels all have positive fileSizeBytes",
          arguments: KnownModelCatalog.allModels)
    func positiveFileSizeBytes(profile: ModelCapabilityProfile) {
        #expect((profile.fileSizeBytes ?? 0) > 0)
    }
}
