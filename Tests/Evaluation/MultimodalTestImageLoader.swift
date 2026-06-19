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
import XCTest

#if os(iOS)
@testable import EdgeAILab_iOS
#elseif os(macOS)
@testable import EdgeAILab_macOS
#endif

// MARK: - Bundle Anchor

/// Anchor class used to locate the test resource bundle.
/// This class lives in the test target, so `Bundle(for:)` returns the test bundle.
private class BundleAnchor: NSObject {}

// MARK: - MultimodalTestImageLoader

/// Helper to load test images from the test resource bundle and create
/// multimodal eval prompts with real image data.
///
/// The 12 test images are bundled in the **test target** (not the app target),
/// so this loader must be used from test code — it cannot be called from
/// production `Sources/` code.
///
/// ## Usage
/// ```swift
/// let prompts = MultimodalTestImageLoader.multimodalPromptsWithImages()
/// let suite = EvalSuite(
///     name: "Multimodal (Real Images)",
///     description: "...",
///     category: .multimodal,
///     prompts: prompts
/// )
/// ```
struct MultimodalTestImageLoader {

    // MARK: - Image Names

    /// All 12 test image filenames (without extension).
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

    // MARK: - Image Loading

    /// Loads a test image from the test resource bundle.
    ///
    /// - Parameter name: The image filename without extension (e.g. `"simple_red_apple"`).
    /// - Returns: The raw image data, or `nil` if the resource was not found.
    ///
    /// **Note:** Tuist may place resources in different subdirectory structures depending on
    /// the platform. This method tries multiple lookup strategies:
    /// 1. Flat lookup (macOS often flattens resources into the bundle root)
    /// 2. With `images/` subdirectory (mirrors the source directory structure)
    static func loadImage(named name: String) -> Data? {
        let bundle = Bundle(for: BundleAnchor.self)

        // Strategy 1: Flat lookup (works on macOS and some iOS configurations)
        if let url = bundle.url(forResource: name, withExtension: "png") {
            return try? Data(contentsOf: url)
        }

        // Strategy 2: Subdirectory lookup (mirrors Tests/Resources/images/ structure)
        if let url = bundle.url(forResource: name, withExtension: "png", subdirectory: "images") {
            return try? Data(contentsOf: url)
        }

        // Strategy 3: Search all .png files in the bundle
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

    /// Loads all 12 test images and returns a dictionary keyed by filename.
    ///
    /// - Returns: `[imageName: Data]` for every image that loaded successfully.
    static func loadAllImages() -> [String: Data] {
        var result: [String: Data] = [:]
        for name in allImageNames {
            if let data = loadImage(named: name) {
                result[name] = data
            }
        }
        return result
    }

    // MARK: - Prompt Definitions

    /// Image-to-prompt mapping: `(imageName, promptText, expectedBehavior)`.
    private static let promptDefinitions: [(imageName: String, prompt: String, expectedBehavior: ExpectedBehavior)] = [
        (
            imageName: "simple_red_apple",
            prompt: "What fruit is in this image?",
            expectedBehavior: .containsText("apple")
        ),
        (
            imageName: "text_hello_world",
            prompt: "What text is shown in this image?",
            expectedBehavior: .containsText("hello")
        ),
        (
            imageName: "three_cats",
            prompt: "How many cats are in this image?",
            expectedBehavior: .matchesRegex("3|three")
        ),
        (
            imageName: "stop_sign",
            prompt: "What type of sign is this?",
            expectedBehavior: .containsText("stop")
        ),
        (
            imageName: "bar_chart",
            prompt: "What type of chart is shown?",
            expectedBehavior: .containsText("bar")
        ),
        (
            imageName: "yellow_school_bus",
            prompt: "What vehicle is in this image?",
            expectedBehavior: .containsText("bus")
        ),
        (
            imageName: "two_dice",
            prompt: "What objects are shown?",
            expectedBehavior: .containsText("dice")
        ),
        (
            imageName: "sunflower",
            prompt: "What flower is in this image?",
            expectedBehavior: .containsText("sunflower")
        ),
        (
            imageName: "red_bicycle",
            prompt: "What is leaning against the wall?",
            expectedBehavior: .containsText("bicycle")
        ),
        (
            imageName: "blue_coffee_cup",
            prompt: "What is in the cup?",
            expectedBehavior: .containsText("coffee")
        ),
        (
            imageName: "five_pencils",
            prompt: "How many pencils are there?",
            expectedBehavior: .matchesRegex("5|five")
        ),
        (
            imageName: "golden_retriever",
            prompt: "What breed of dog is this?",
            expectedBehavior: .containsText("retriever")
        ),
    ]

    // MARK: - Prompt Factory

    /// Returns multimodal eval prompts with real images loaded from the test bundle.
    ///
    /// Each prompt is paired with its corresponding test image. If an image fails
    /// to load, that prompt is still included but with `imageData: nil` (the eval
    /// runner will mark it as failed with a descriptive reason).
    ///
    /// - Returns: An array of 12 `EvalPrompt` instances with real image data.
    static func multimodalPromptsWithImages() -> [EvalPrompt] {
        promptDefinitions.map { definition in
            let imageData = loadImage(named: definition.imageName)
            return EvalPrompt(
                prompt: definition.prompt,
                expectedBehavior: definition.expectedBehavior,
                imageData: imageData,
                timeoutSeconds: 90
            )
        }
    }

    /// Returns a full eval suite with real multimodal test images.
    ///
    /// This is a convenience wrapper around `multimodalPromptsWithImages()` that
    /// builds a complete `EvalSuite` ready for use in test runs.
    static func multimodalSuiteWithImages() -> EvalSuite {
        EvalSuite(
            name: "Multimodal (Real Images)",
            description: "Tests vision capabilities with 12 real test images covering object identification, counting, OCR, and scene understanding.",
            category: .multimodal,
            prompts: multimodalPromptsWithImages()
        )
    }
}
