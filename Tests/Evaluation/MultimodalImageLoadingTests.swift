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

import Foundation
import XCTest

#if os(iOS)
@testable import EdgeAILab_iOS
#elseif os(macOS)
@testable import EdgeAILab_macOS
#endif

/// Tests that all 12 multimodal test images load correctly from the test bundle
/// and that the prompt factory produces valid `EvalPrompt` instances.
///
/// **Note:** These tests require the test resource images to be available in the
/// test bundle. On physical devices, Tuist may not bundle test resources correctly,
/// so these tests are automatically skipped when images are unavailable.
final class MultimodalImageLoadingTests: XCTestCase {

    // MARK: - Constants

    /// Minimum expected file size for any test image (10 KB).
    /// All test images are real PNGs well above this threshold.
    private let minimumImageSizeBytes = 10_000

    /// Maximum expected file size for any test image (5 MB).
    /// Guards against accidentally bundling enormous assets.
    private let maximumImageSizeBytes = 5_000_000

    /// Expected number of test images.
    private let expectedImageCount = 12

    // MARK: - Setup

    override func setUpWithError() throws {
        // Skip all image tests if the test images aren't available in the bundle
        // (e.g., on physical device where Tuist resource bundling may differ)
        let sampleImage = MultimodalTestImageLoader.loadImage(named: "simple_red_apple")
        if sampleImage == nil {
            throw XCTSkip("Test images not available in bundle — skipping on this platform")
        }
    }

    // MARK: - Individual Image Loading

    func testLoadSimpleRedApple() throws {
        let data = try XCTUnwrap(
            MultimodalTestImageLoader.loadImage(named: "simple_red_apple"),
            "simple_red_apple.png should be loadable from the test bundle"
        )
        assertReasonableImageSize(data, name: "simple_red_apple")
    }

    func testLoadTextHelloWorld() throws {
        let data = try XCTUnwrap(
            MultimodalTestImageLoader.loadImage(named: "text_hello_world"),
            "text_hello_world.png should be loadable from the test bundle"
        )
        assertReasonableImageSize(data, name: "text_hello_world")
    }

    func testLoadThreeCats() throws {
        let data = try XCTUnwrap(
            MultimodalTestImageLoader.loadImage(named: "three_cats"),
            "three_cats.png should be loadable from the test bundle"
        )
        assertReasonableImageSize(data, name: "three_cats")
    }

    func testLoadStopSign() throws {
        let data = try XCTUnwrap(
            MultimodalTestImageLoader.loadImage(named: "stop_sign"),
            "stop_sign.png should be loadable from the test bundle"
        )
        assertReasonableImageSize(data, name: "stop_sign")
    }

    func testLoadBarChart() throws {
        let data = try XCTUnwrap(
            MultimodalTestImageLoader.loadImage(named: "bar_chart"),
            "bar_chart.png should be loadable from the test bundle"
        )
        assertReasonableImageSize(data, name: "bar_chart")
    }

    func testLoadYellowSchoolBus() throws {
        let data = try XCTUnwrap(
            MultimodalTestImageLoader.loadImage(named: "yellow_school_bus"),
            "yellow_school_bus.png should be loadable from the test bundle"
        )
        assertReasonableImageSize(data, name: "yellow_school_bus")
    }

    func testLoadTwoDice() throws {
        let data = try XCTUnwrap(
            MultimodalTestImageLoader.loadImage(named: "two_dice"),
            "two_dice.png should be loadable from the test bundle"
        )
        assertReasonableImageSize(data, name: "two_dice")
    }

    func testLoadSunflower() throws {
        let data = try XCTUnwrap(
            MultimodalTestImageLoader.loadImage(named: "sunflower"),
            "sunflower.png should be loadable from the test bundle"
        )
        assertReasonableImageSize(data, name: "sunflower")
    }

    func testLoadRedBicycle() throws {
        let data = try XCTUnwrap(
            MultimodalTestImageLoader.loadImage(named: "red_bicycle"),
            "red_bicycle.png should be loadable from the test bundle"
        )
        assertReasonableImageSize(data, name: "red_bicycle")
    }

    func testLoadBlueCoffeeCup() throws {
        let data = try XCTUnwrap(
            MultimodalTestImageLoader.loadImage(named: "blue_coffee_cup"),
            "blue_coffee_cup.png should be loadable from the test bundle"
        )
        assertReasonableImageSize(data, name: "blue_coffee_cup")
    }

    func testLoadFivePencils() throws {
        let data = try XCTUnwrap(
            MultimodalTestImageLoader.loadImage(named: "five_pencils"),
            "five_pencils.png should be loadable from the test bundle"
        )
        assertReasonableImageSize(data, name: "five_pencils")
    }

    func testLoadGoldenRetriever() throws {
        let data = try XCTUnwrap(
            MultimodalTestImageLoader.loadImage(named: "golden_retriever"),
            "golden_retriever.png should be loadable from the test bundle"
        )
        assertReasonableImageSize(data, name: "golden_retriever")
    }

    // MARK: - Bulk Loading

    func testLoadAllImagesReturnsExpectedCount() {
        let allImages = MultimodalTestImageLoader.loadAllImages()
        XCTAssertEqual(
            allImages.count,
            expectedImageCount,
            "loadAllImages() should return all \(expectedImageCount) test images"
        )
    }

    func testLoadAllImagesContainsEveryExpectedKey() {
        let allImages = MultimodalTestImageLoader.loadAllImages()
        for name in MultimodalTestImageLoader.allImageNames {
            XCTAssertNotNil(
                allImages[name],
                "loadAllImages() should contain an entry for '\(name)'"
            )
        }
    }

    func testAllImagesHaveReasonableSizes() {
        let allImages = MultimodalTestImageLoader.loadAllImages()
        for (name, data) in allImages {
            assertReasonableImageSize(data, name: name)
        }
    }

    // MARK: - Image Header Validation

    /// Validates that every test image has a recognized image file header (PNG or JPEG).
    /// Note: The `generate_image` tool may produce JPEG data saved with a `.png` extension,
    /// so both formats are accepted.
    func testAllImagesHaveValidImageHeader() {
        let pngHeader: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        let jpegHeader: [UInt8] = [0xFF, 0xD8, 0xFF]
        let allImages = MultimodalTestImageLoader.loadAllImages()

        for (name, data) in allImages {
            XCTAssertGreaterThanOrEqual(
                data.count,
                pngHeader.count,
                "'\(name)' should be large enough to contain an image header"
            )
            let headerBytes = [UInt8](data.prefix(pngHeader.count))
            let isPNG = headerBytes == pngHeader
            let isJPEG = Array(headerBytes.prefix(jpegHeader.count)) == jpegHeader
            XCTAssertTrue(
                isPNG || isJPEG,
                "'\(name)' should have a valid PNG or JPEG file header, got: \(headerBytes)"
            )
        }
    }

    // MARK: - Nonexistent Image

    func testLoadNonexistentImageReturnsNil() {
        let data = MultimodalTestImageLoader.loadImage(named: "this_image_does_not_exist")
        XCTAssertNil(data, "Loading a nonexistent image name should return nil")
    }

    // MARK: - Prompt Factory

    func testMultimodalPromptsWithImagesCount() {
        let prompts = MultimodalTestImageLoader.multimodalPromptsWithImages()
        XCTAssertEqual(
            prompts.count,
            expectedImageCount,
            "multimodalPromptsWithImages() should return \(expectedImageCount) prompts"
        )
    }

    func testMultimodalPromptsAllHaveImageData() {
        let prompts = MultimodalTestImageLoader.multimodalPromptsWithImages()
        for (index, prompt) in prompts.enumerated() {
            XCTAssertNotNil(
                prompt.imageData,
                "Prompt at index \(index) ('\(prompt.truncatedPrompt)') should have non-nil imageData"
            )
        }
    }

    func testMultimodalPromptsAllHaveNonEmptyPromptText() {
        let prompts = MultimodalTestImageLoader.multimodalPromptsWithImages()
        for (index, prompt) in prompts.enumerated() {
            XCTAssertFalse(
                prompt.prompt.isEmpty,
                "Prompt at index \(index) should have non-empty prompt text"
            )
        }
    }

    func testMultimodalPromptsAllAreMultimodal() {
        let prompts = MultimodalTestImageLoader.multimodalPromptsWithImages()
        for (index, prompt) in prompts.enumerated() {
            XCTAssertTrue(
                prompt.isMultimodal,
                "Prompt at index \(index) should be marked as multimodal"
            )
            XCTAssertTrue(
                prompt.isImagePrompt,
                "Prompt at index \(index) should be marked as an image prompt"
            )
        }
    }

    func testMultimodalPromptsHaveExpectedTimeout() {
        let prompts = MultimodalTestImageLoader.multimodalPromptsWithImages()
        for prompt in prompts {
            XCTAssertEqual(
                prompt.timeoutSeconds,
                90,
                "Multimodal prompts should have a 90-second timeout"
            )
        }
    }

    // MARK: - Suite Factory

    func testMultimodalSuiteWithImages() {
        let suite = MultimodalTestImageLoader.multimodalSuiteWithImages()
        XCTAssertEqual(suite.name, "Multimodal (Real Images)")
        XCTAssertEqual(suite.category, .multimodal)
        XCTAssertEqual(suite.prompts.count, expectedImageCount)
        XCTAssertTrue(suite.hasMultimodalPrompts)
    }

    // MARK: - Helpers

    /// Asserts that the image data falls within the expected size range.
    private func assertReasonableImageSize(_ data: Data, name: String) {
        XCTAssertGreaterThan(
            data.count,
            minimumImageSizeBytes,
            "'\(name)' should be larger than \(minimumImageSizeBytes) bytes (got \(data.count))"
        )
        XCTAssertLessThan(
            data.count,
            maximumImageSizeBytes,
            "'\(name)' should be smaller than \(maximumImageSizeBytes) bytes (got \(data.count))"
        )
    }
}
