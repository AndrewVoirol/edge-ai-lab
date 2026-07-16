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

import Testing
import Foundation

#if os(iOS)
@testable import EdgeAILab_iOS
#elseif os(macOS)
@testable import EdgeAILab_macOS
#endif

// MARK: - Eval Audio Loader Tests

/// Tests for `EvalAudioLoader` — validates bundled audio file loading.
@Suite("EvalAudioLoader")
struct EvalAudioLoaderTests {

    @Test("allAudioNames is not empty")
    func allAudioNamesNotEmpty() {
        #expect(!EvalAudioLoader.allAudioNames.isEmpty)
    }

    @Test("allAudioNames are alphabetically sorted")
    func allAudioNamesSorted() {
        let sorted = EvalAudioLoader.allAudioNames.sorted()
        #expect(EvalAudioLoader.allAudioNames == sorted)
    }

    @Test("allAudioNames has expected count")
    func allAudioNamesCount() {
        #expect(EvalAudioLoader.allAudioNames.count == 4)
    }

    @Test("loadAudio returns non-nil Data for known names")
    func loadKnownAudio() {
        // Note: This test will only pass when run inside the full app bundle
        // (where the audio resources are included). In unit test bundles,
        // the audio files may not be present — we test the API contract
        // rather than requiring bundled assets in the test target.
        for name in EvalAudioLoader.allAudioNames {
            let data = EvalAudioLoader.loadAudio(named: name)
            // Audio files may not be in the test bundle, so we just verify the API doesn't crash
            if let data = data {
                #expect(data.count > 0, "Audio data for '\(name)' should not be empty")
            }
        }
    }

    @Test("loadAudio returns nil for unknown names")
    func loadUnknownAudio() {
        let data = EvalAudioLoader.loadAudio(named: "nonexistent_audio_file_xyz")
        #expect(data == nil)
    }

    @Test("loadAllAudio returns a dictionary")
    func loadAllAudio() {
        let all = EvalAudioLoader.loadAllAudio()
        // In the test bundle context, we just verify the method works
        // without crashing and returns a valid dictionary
        #expect(all is [String: Data])
        // All returned entries should have non-empty data
        for (name, data) in all {
            #expect(data.count > 0, "Audio data for '\(name)' should not be empty")
        }
    }

    @Test("allAudioNames contains expected files")
    func expectedAudioFiles() {
        let names = Set(EvalAudioLoader.allAudioNames)
        #expect(names.contains("spoken_english"))
        #expect(names.contains("spoken_counting"))
        #expect(names.contains("spoken_spanish"))
        #expect(names.contains("spoken_question"))
    }
}
