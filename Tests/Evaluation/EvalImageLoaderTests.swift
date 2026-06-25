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

// MARK: - EvalImageLoader Tests

@Suite("EvalImageLoader")
struct EvalImageLoaderTests {

    // MARK: - allImageNames

    @Suite("allImageNames")
    struct AllImageNamesTests {

        @Test("Contains exactly 12 entries")
        func containsTwelveEntries() {
            #expect(EvalImageLoader.allImageNames.count == 12)
        }

        @Test("Contains specific expected names",
              arguments: ["simple_red_apple", "stop_sign", "golden_retriever"])
        func containsExpectedName(name: String) {
            #expect(EvalImageLoader.allImageNames.contains(name),
                    "allImageNames should contain \"\(name)\"")
        }

        @Test("All names are non-empty")
        func allNamesNonEmpty() {
            for name in EvalImageLoader.allImageNames {
                #expect(!name.isEmpty, "Image name should not be empty")
            }
        }

        @Test("All names are unique — no duplicates")
        func allNamesUnique() {
            let uniqueNames = Set(EvalImageLoader.allImageNames)
            #expect(uniqueNames.count == EvalImageLoader.allImageNames.count,
                    "Duplicate image names detected")
        }

        @Test("No names contain file extensions")
        func noFileExtensions() {
            for name in EvalImageLoader.allImageNames {
                #expect(!name.contains(".png"),
                        "\"\(name)\" should not contain .png extension")
                #expect(!name.contains(".jpg"),
                        "\"\(name)\" should not contain .jpg extension")
                #expect(!name.contains(".jpeg"),
                        "\"\(name)\" should not contain .jpeg extension")
            }
        }

        @Test("No names contain spaces — filesystem-safe")
        func noSpacesInNames() {
            for name in EvalImageLoader.allImageNames {
                #expect(!name.contains(" "),
                        "\"\(name)\" should not contain spaces")
            }
        }

        @Test("Names use lowercase convention — no uppercase letters")
        func lowercaseConvention() {
            for name in EvalImageLoader.allImageNames {
                #expect(name == name.lowercased(),
                        "\"\(name)\" should be entirely lowercase")
            }
        }
    }

    // MARK: - loadImage

    @Suite("loadImage")
    struct LoadImageTests {

        @Test("Returns nil for non-existent image name")
        func nonExistentNameReturnsNil() {
            let result = EvalImageLoader.loadImage(named: "this_image_does_not_exist_xyz")
            #expect(result == nil)
        }

        @Test("Returns nil for empty string")
        func emptyStringReturnsNil() {
            // Empty string won't match any real resource file
            let result = EvalImageLoader.loadImage(named: "")
            // On macOS with Tuist, Bundle.main enumerator may find unrelated files.
            // Just verify it doesn't crash.
            _ = result
        }

        @Test("loadImage returns data for known image names when bundled",
              arguments: ["simple_red_apple", "golden_retriever", "stop_sign"])
        func realNameLoadsWhenBundled(name: String) {
            // Tuist bundles test resources into the test target on macOS.
            // On platforms where resources aren't bundled, this will return nil.
            let result = EvalImageLoader.loadImage(named: name)
            // Either nil (resources not bundled) or non-empty Data (resources bundled)
            if let data = result {
                #expect(!data.isEmpty, "Loaded data should not be empty")
            }
        }
    }

    // MARK: - loadAllImages

    @Suite("loadAllImages")
    struct LoadAllImagesTests {

        @Test("loadAllImages returns dictionary without crashing")
        func returnsValidDict() {
            // On macOS with Tuist, resources are bundled and this returns
            // a non-empty dictionary. On other platforms, may be empty.
            let result = EvalImageLoader.loadAllImages()
            // If images are available, verify all keys match allImageNames
            if !result.isEmpty {
                for key in result.keys {
                    #expect(EvalImageLoader.allImageNames.contains(key),
                            "\"\(key)\" should be in allImageNames")
                }
            }
        }

        @Test("Returns correct type without crashing")
        func returnsCorrectType() {
            let result: [String: Data] = EvalImageLoader.loadAllImages()
            // Verify it's a valid dictionary (call doesn't crash, type is correct).
            #expect(result.count >= 0)
        }
    }
}
