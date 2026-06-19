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

import Foundation

// MARK: - Eval Image Loader

/// Runtime image loader for multimodal eval prompts.
///
/// Loads test images from the **app bundle** at runtime so that the built-in
/// multimodal eval suite can include real image data when running evals from
/// the app UI.
///
/// This is the production-code counterpart to ``MultimodalTestImageLoader``
/// (which lives in the test target and loads from the test bundle). Both loaders
/// reference the same 12 images; the difference is which bundle they search.
///
/// ## Bundle Location
///
/// Images are bundled via `Project.swift` resource glob `"Tests/Resources/images/**"`.
/// Tuist copies them into the app bundle, typically at the bundle root or in an
/// `images/` subdirectory depending on the platform.
///
/// ## Usage
///
/// ```swift
/// if let data = EvalImageLoader.loadImage(named: "simple_red_apple") {
///     let prompt = EvalPrompt(
///         prompt: "What fruit is this?",
///         expectedBehavior: .containsText("apple"),
///         imageData: data
///     )
/// }
/// ```
enum EvalImageLoader {

    // MARK: - Image Names

    /// All 12 eval test image filenames (without extension).
    ///
    /// These must match the filenames in `Tests/Resources/images/`.
    static let allImageNames: [String] = [
        "simple_red_apple",
        "text_hello_world",
        "three_cats",
        "stop_sign",
        "bar_chart",
        "yellow_school_bus",
        "two_dice",
        "sunflower",
        "red_bicycle",
        "blue_coffee_cup",
        "five_pencils",
        "golden_retriever",
    ]

    // MARK: - Loading

    /// Loads an eval test image from the app bundle.
    ///
    /// - Parameter name: The image filename without extension (e.g., `"simple_red_apple"`).
    /// - Returns: The raw image data, or `nil` if the image was not found in the bundle.
    ///
    /// Tries multiple lookup strategies to handle platform-specific bundle layouts:
    /// 1. Flat lookup (macOS often flattens resources into the bundle root)
    /// 2. With `images/` subdirectory (mirrors the source directory structure)
    /// 3. Full bundle enumeration as a last resort
    static func loadImage(named name: String) -> Data? {
        let bundle = Bundle.main

        // Strategy 1: Flat lookup
        if let url = bundle.url(forResource: name, withExtension: "png") {
            return try? Data(contentsOf: url)
        }

        // Strategy 2: Subdirectory lookup
        if let url = bundle.url(forResource: name, withExtension: "png", subdirectory: "images") {
            return try? Data(contentsOf: url)
        }

        // Strategy 3: Enumerate all .png files in the bundle
        if let resourcePath = bundle.resourcePath {
            let fm = FileManager.default
            if let enumerator = fm.enumerator(atPath: resourcePath) {
                while let file = enumerator.nextObject() as? String {
                    if file.hasSuffix("/\(name).png") || file == "\(name).png" {
                        let fullPath = (resourcePath as NSString).appendingPathComponent(file)
                        return fm.contents(atPath: fullPath)
                    }
                }
            }
        }

        return nil
    }

    /// Loads all available eval test images.
    ///
    /// - Returns: A dictionary mapping image name to its raw data, for every image
    ///   that was successfully loaded from the bundle.
    static func loadAllImages() -> [String: Data] {
        var result: [String: Data] = [:]
        for name in allImageNames {
            if let data = loadImage(named: name) {
                result[name] = data
            }
        }
        return result
    }
}
