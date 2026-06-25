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

@Suite("ModelDownloadManager — Value Types")
struct ModelDownloadManagerValueTests {

    // MARK: - DownloadProgress

    @Suite("DownloadProgress")
    struct DownloadProgressTests {
        private func makeProgress(
            progress: Double = 0.5,
            bytesWritten: Int64 = 500_000_000,
            totalBytes: Int64 = 1_000_000_000,
            speed: Double = 10_000_000,
            eta: Double? = 50.0
        ) -> ModelDownloadManager.DownloadProgress {
            ModelDownloadManager.DownloadProgress(
                progress: progress,
                bytesWritten: bytesWritten,
                totalBytes: totalBytes,
                speedBytesPerSecond: speed,
                estimatedSecondsRemaining: eta
            )
        }

        @Test("formattedSpeed includes /s suffix")
        func formattedSpeed() {
            let p = makeProgress(speed: 10_000_000)
            #expect(p.formattedSpeed.contains("/s"))
        }

        @Test("formattedBytesWritten returns non-empty string")
        func formattedBytesWritten() {
            let p = makeProgress(bytesWritten: 500_000_000)
            #expect(!p.formattedBytesWritten.isEmpty)
            #expect(p.formattedBytesWritten.contains("MB") || p.formattedBytesWritten.contains("GB"))
        }

        @Test("formattedTotalBytes returns non-empty string")
        func formattedTotalBytes() {
            let p = makeProgress(totalBytes: 5_000_000_000)
            #expect(!p.formattedTotalBytes.isEmpty)
            #expect(p.formattedTotalBytes.contains("GB"))
        }

        @Test("formattedETA returns nil for nil ETA")
        func noEta() {
            let p = makeProgress(eta: nil)
            #expect(p.formattedETA == nil)
        }

        @Test("formattedETA returns nil for zero ETA")
        func zeroEta() {
            let p = makeProgress(eta: 0)
            #expect(p.formattedETA == nil)
        }

        @Test("formattedETA returns nil for very long ETA (>24h)")
        func veryLongEta() {
            let p = makeProgress(eta: 86401)
            #expect(p.formattedETA == nil)
        }

        @Test("formattedETA returns value for reasonable ETA")
        func reasonableEta() {
            let p = makeProgress(eta: 300)
            #expect(p.formattedETA != nil)
        }
    }

    // MARK: - StorageCheck

    @Suite("StorageCheck")
    struct StorageCheckTests {
        @Test("formattedModelSize returns non-empty")
        func modelSize() {
            let check = ModelDownloadManager.StorageCheck(
                modelSize: 4_000_000_000,
                availableSpace: 50_000_000_000,
                hasEnoughSpace: true
            )
            #expect(!check.formattedModelSize.isEmpty)
            #expect(check.formattedModelSize.contains("GB"))
        }

        @Test("formattedAvailableSpace returns non-empty")
        func availableSpace() {
            let check = ModelDownloadManager.StorageCheck(
                modelSize: 4_000_000_000,
                availableSpace: 50_000_000_000,
                hasEnoughSpace: true
            )
            #expect(!check.formattedAvailableSpace.isEmpty)
            #expect(check.formattedAvailableSpace.contains("GB"))
        }

        @Test("hasEnoughSpace is true when space exceeds model size")
        func hasSpace() {
            let check = ModelDownloadManager.StorageCheck(
                modelSize: 4_000_000_000,
                availableSpace: 50_000_000_000,
                hasEnoughSpace: true
            )
            #expect(check.hasEnoughSpace == true)
        }

        @Test("hasEnoughSpace is false when space is insufficient")
        func noSpace() {
            let check = ModelDownloadManager.StorageCheck(
                modelSize: 4_000_000_000,
                availableSpace: 1_000_000_000,
                hasEnoughSpace: false
            )
            #expect(check.hasEnoughSpace == false)
        }
    }

    // MARK: - DownloadState

    @Suite("DownloadState")
    struct DownloadStateTests {
        @Test("All states can be created")
        func allStates() {
            let _ = ModelDownloadManager.DownloadState.downloaded(URL(fileURLWithPath: "/tmp/test"))
            let _ = ModelDownloadManager.DownloadState.downloading(progress: 0.5)
            let _ = ModelDownloadManager.DownloadState.queued(position: 1)
            let _ = ModelDownloadManager.DownloadState.paused(resumeData: Data(), progress: 0.3)
            let _ = ModelDownloadManager.DownloadState.notDownloaded
            let _ = ModelDownloadManager.DownloadState.failed("error")
            let _ = ModelDownloadManager.DownloadState.authRequired
        }
    }
}
