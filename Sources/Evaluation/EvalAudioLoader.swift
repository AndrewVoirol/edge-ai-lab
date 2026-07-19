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

import Foundation
import os

// MARK: - Eval Audio Loader

/// Loads bundled audio test files for multimodal evaluation prompts.
///
/// Mirrors the `EvalImageLoader` pattern: an enum namespace with static methods
/// for loading audio data from the app bundle. Audio files are WAV format,
/// 16kHz PCM F32, generated via macOS `say` command for reproducibility.
///
/// ## Usage
/// ```swift
/// if let audioData = EvalAudioLoader.loadAudio(named: "spoken_english") {
///     let prompt = EvalPrompt(prompt: "What is being said?",
///                             expectedBehavior: .containsAny(["hello", "test"]),
///                             audioData: audioData)
/// }
/// ```
enum EvalAudioLoader {

    private static let logger = Logger(subsystem: "com.andrewvoirol.EdgeAILab", category: "evalAudioLoader")

    /// All bundled audio file names (without extension).
    ///
    /// Keep this list alphabetically sorted and in sync with
    /// `Tests/Resources/audio/` directory contents.
    static let allAudioNames: [String] = [
        "spoken_counting",
        "spoken_english",
        "spoken_question",
        "spoken_spanish",
    ]

    /// Load a single audio file by name (without extension).
    ///
    /// Uses a three-tier lookup strategy (same as `EvalImageLoader`):
    /// 1. Flat bundle lookup: `Bundle.main.url(forResource:withExtension:)`
    /// 2. Subdirectory lookup: `Bundle.main.url(forResource:withExtension:subdirectory: "audio")`
    /// 3. Enumerator fallback: walks the entire bundle for a matching filename
    ///
    /// - Parameter name: The audio file name without extension (e.g., "spoken_english").
    /// - Returns: The raw audio `Data`, or `nil` if the file was not found.
    static func loadAudio(named name: String) -> Data? {
        let bundle = Bundle.main

        // Strategy 1: Flat lookup
        if let url = bundle.url(forResource: name, withExtension: "wav") {
            let data = try? Data(contentsOf: url)
            logger.info("✅ Found '\(name, privacy: .public).wav' at \(url.lastPathComponent, privacy: .public) (\(data?.count ?? 0, privacy: .public) bytes)")
            return data
        }

        // Strategy 2: Subdirectory lookup
        if let url = bundle.url(forResource: name, withExtension: "wav", subdirectory: "audio") {
            let data = try? Data(contentsOf: url)
            logger.info("✅ Found '\(name, privacy: .public).wav' in audio/ (\(data?.count ?? 0, privacy: .public) bytes)")
            return data
        }

        // Strategy 3: Enumerator fallback — walk entire bundle
        if let enumerator = FileManager.default.enumerator(at: bundle.bundleURL, includingPropertiesForKeys: nil) {
            let targetFilename = "\(name).wav"
            while let fileURL = enumerator.nextObject() as? URL {
                if fileURL.lastPathComponent == targetFilename {
                    let data = try? Data(contentsOf: fileURL)
                    logger.info("✅ Found '\(name, privacy: .public).wav' via enumerator (\(data?.count ?? 0, privacy: .public) bytes)")
                    return data
                }
            }
        }

        logger.warning("Audio file '\(name, privacy: .public).wav' not found in bundle: \(bundle.bundleURL.path, privacy: .public)")
        return nil
    }

    /// Load all bundled audio files into a dictionary.
    ///
    /// - Returns: Dictionary mapping audio names to their `Data` contents.
    ///   Files that fail to load are omitted (no nil values).
    static func loadAllAudio() -> [String: Data] {
        var result: [String: Data] = [:]
        for name in allAudioNames {
            if let data = loadAudio(named: name) {
                result[name] = data
            }
        }
        return result
    }
}
