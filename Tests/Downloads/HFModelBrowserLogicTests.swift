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

// MARK: - HFModelBrowserLogicTests

/// Pure-logic tests for `HFModelBrowser`, `HFModelInfo`, `HFModelFormat`,
/// and `HFModelBrowserError`. Complements the existing XCTest and Swift Testing
/// suites by covering additional edge cases in format detection priority chains,
/// modelSize aggregation, and Codable fidelity with LFS metadata.
@Suite("HFModelBrowser Logic")
struct HFModelBrowserLogicTests {

    // MARK: - Format Detection Priority Chain

    @Suite("Format detection priority")
    struct FormatDetectionPriority {

        @Test("litertlm sibling wins over mlx libraryName")
        @MainActor
        func litertlmSiblingOverMlxLibrary() {
            let browser = HFModelBrowser()
            let model = HFModelInfo(
                id: "org/ambiguous-model",
                author: "org",
                libraryName: "mlx",
                siblings: [
                    HFSibling(rfilename: "model.litertlm", size: 1_000_000, lfs: nil)
                ]
            )
            #expect(browser.detectFormat(model) == .litertlm)
        }

        @Test("mlx siblings win over litert libraryName")
        @MainActor
        func mlxSiblingsOverLitertLibrary() {
            let browser = HFModelBrowser()
            let model = HFModelInfo(
                id: "org/ambiguous-model",
                author: "org",
                libraryName: "litert",
                siblings: [
                    HFSibling(rfilename: "config.json", size: 512, lfs: nil),
                    HFSibling(rfilename: "weights.safetensors", size: 2_000_000, lfs: nil),
                ]
            )
            #expect(browser.detectFormat(model) == .mlx)
        }

        @Test("libraryName wins over tags when no siblings")
        @MainActor
        func libraryNameOverTags() {
            let browser = HFModelBrowser()
            let model = HFModelInfo(
                id: "org/model",
                author: "org",
                tags: ["mlx"],
                libraryName: "litert"
            )
            #expect(browser.detectFormat(model) == .litertlm)
        }

        @Test("Tags win over model ID naming convention")
        @MainActor
        func tagsOverModelId() {
            let browser = HFModelBrowser()
            // ID suggests mlx-community (fallback #4), but tag says litert (check #3)
            let model = HFModelInfo(
                id: "mlx-community/some-model",
                author: "mlx-community",
                tags: ["litert"]
            )
            #expect(browser.detectFormat(model) == .litertlm)
        }

        @Test("Case-insensitive libraryName detection", arguments: [
            ("LiteRT", HFModelFormat.litertlm),
            ("LITERT", HFModelFormat.litertlm),
            ("MLX", HFModelFormat.mlx),
            ("Mlx", HFModelFormat.mlx),
        ])
        @MainActor
        func caseInsensitiveLibraryName(libraryName: String, expected: HFModelFormat) {
            let browser = HFModelBrowser()
            let model = HFModelInfo(id: "org/model", author: "org", libraryName: libraryName)
            #expect(browser.detectFormat(model) == expected)
        }

        @Test("Empty siblings array falls through to metadata checks")
        @MainActor
        func emptySiblingsFallThrough() {
            let browser = HFModelBrowser()
            let model = HFModelInfo(
                id: "org/model",
                author: "org",
                libraryName: "litert",
                siblings: []
            )
            // Empty siblings won't match .litertlm or .mlx file patterns,
            // so it should fall through to libraryName
            #expect(browser.detectFormat(model) == .litertlm)
        }

        @Test("litert_lm underscore variant detected from ID")
        @MainActor
        func litertUnderscoreVariant() {
            let browser = HFModelBrowser()
            let model = HFModelInfo(id: "org/gemma-litert_lm-model", author: "org")
            #expect(browser.detectFormat(model) == .litertlm)
        }
    }

    // MARK: - Model Size Edge Cases

    @Suite("modelSize edge cases")
    struct ModelSizeEdgeCases {

        @Test("Mixed LFS and regular sizes returns largest overall")
        @MainActor
        func mixedLfsAndRegular() {
            let browser = HFModelBrowser()
            let lfs = HFLFSInfo(oid: "sha256hash", size: 1_500_000_000, pointerSize: 130)
            let model = HFModelInfo(
                id: "org/model",
                author: "org",
                siblings: [
                    // Regular file is larger than LFS file
                    HFSibling(rfilename: "big-file.bin", size: 3_000_000_000, lfs: nil),
                    HFSibling(rfilename: "model.litertlm", size: nil, lfs: lfs),
                ]
            )
            #expect(browser.modelSize(model) == 3_000_000_000)
        }

        @Test("Single file returns its size")
        @MainActor
        func singleFile() {
            let browser = HFModelBrowser()
            let model = HFModelInfo(
                id: "org/model",
                author: "org",
                siblings: [
                    HFSibling(rfilename: "model.bin", size: 42_000, lfs: nil)
                ]
            )
            #expect(browser.modelSize(model) == 42_000)
        }

        @Test("LFS size takes precedence over sibling.size for same file")
        @MainActor
        func lfsPreferredOverSiblingSize() {
            let browser = HFModelBrowser()
            // sibling.size is the pointer size, lfs.size is real content size
            let lfs = HFLFSInfo(oid: "abc", size: 5_000_000_000, pointerSize: 130)
            let model = HFModelInfo(
                id: "org/model",
                author: "org",
                siblings: [
                    HFSibling(rfilename: "weights.bin", size: 130, lfs: lfs)
                ]
            )
            #expect(browser.modelSize(model) == 5_000_000_000)
        }
    }

    // MARK: - HFModelInfo Computed Properties Edge Cases

    @Suite("HFModelInfo computed property edge cases")
    struct ModelInfoEdgeCases {

        @Test("displayName with multiple slashes returns everything after first")
        func multipleSlashes() {
            let model = HFModelInfo(id: "org/sub/deep/model", author: "org")
            #expect(model.displayName == "sub/deep/model")
        }

        @Test("orgName with multiple slashes returns only prefix before first")
        func orgNameMultipleSlashes() {
            let model = HFModelInfo(id: "org/sub/deep/model", author: "org")
            #expect(model.orgName == "org")
        }

        @Test("displayName for ID without slash returns full ID")
        func displayNameNoSlash() {
            let model = HFModelInfo(id: "standalone", author: "standalone")
            #expect(model.displayName == "standalone")
        }

        @Test("orgName for ID without slash returns full ID")
        func orgNameNoSlash() {
            let model = HFModelInfo(id: "standalone", author: "standalone")
            #expect(model.orgName == "standalone")
        }

        @Test("isGemma4 case-insensitive across all detection paths")
        func isGemma4CaseInsensitive() {
            let upper = HFModelInfo(id: "org/GEMMA-4-model", author: "org")
            #expect(upper.isGemma4)

            let mixed = HFModelInfo(id: "org/Gemma4Model", author: "org")
            #expect(mixed.isGemma4)

            let tagOnly = HFModelInfo(id: "org/other", author: "org", tags: ["GEMMA-4"])
            #expect(tagOnly.isGemma4)
        }

        @Test("isGemma4 false for gemma-3 models")
        func isGemma4FalseForGemma3() {
            let model = HFModelInfo(id: "org/gemma-3-model", author: "org", tags: ["gemma-3"])
            #expect(!model.isGemma4)
        }

        @Test("quantizationInfo with multiple patterns returns first match by priority")
        func quantizationPriority() {
            // bf16 appears before 4bit in the patterns array, so it should win
            let model = HFModelInfo(id: "org/model-bf16-4bit", author: "org")
            #expect(model.quantizationInfo == "bf16")
        }

        @Test("quantizationInfo nil for unrelated tags")
        func quantizationNilForUnrelatedTags() {
            let model = HFModelInfo(
                id: "org/plain-model",
                author: "org",
                tags: ["text-generation", "en", "gemma-4"]
            )
            #expect(model.quantizationInfo == nil)
        }

        @Test("quantizationInfo detects from tag when not in ID")
        func quantizationFromTag() {
            let model = HFModelInfo(
                id: "org/plain-model",
                author: "org",
                tags: ["fp16", "text-generation"]
            )
            #expect(model.quantizationInfo == "fp16")
        }

        @Test("Identifiable id matches the stored id property")
        func identifiableConformance() {
            let model = HFModelInfo(id: "test/id-check", author: "test")
            // Identifiable requires `id` — verify it's the string
            let identifiableId: String = model.id
            #expect(identifiableId == "test/id-check")
        }
    }

    // MARK: - HFModelFormat Sendable & Equatable

    @Suite("HFModelFormat properties")
    struct FormatProperties {

        @Test("All cases exist and are distinct")
        func allCasesDistinct() {
            let cases: [HFModelFormat] = [.litertlm, .mlx, .unknown]
            let rawValues = Set(cases.map(\.rawValue))
            #expect(rawValues.count == 3)
        }

        @Test("Invalid raw value returns nil")
        func invalidRawValue() {
            #expect(HFModelFormat(rawValue: "gguf") == nil)
            #expect(HFModelFormat(rawValue: "") == nil)
        }
    }

    // MARK: - HFModelBrowserError LocalizedError

    @Suite("HFModelBrowserError descriptions")
    struct ErrorDescriptions {

        @Test("httpStatusError is distinct from httpError")
        func httpStatusVsHttpError() {
            let statusError = HFModelBrowserError.httpStatusError(statusCode: 503)
            let httpError = HFModelBrowserError.httpError(statusCode: 503, repoId: "org/model")

            #expect(statusError.errorDescription != httpError.errorDescription)
            #expect(httpError.errorDescription?.contains("org/model") == true)
            #expect(statusError.errorDescription?.contains("org/model") != true)
        }

        @Test("invalidResponse has non-empty description")
        func invalidResponseNonEmpty() {
            let error = HFModelBrowserError.invalidResponse
            #expect(error.errorDescription?.isEmpty == false)
        }

        @Test("decodingFailed includes underlying error message")
        func decodingFailedIncludesMessage() {
            let underlying = NSError(
                domain: "TestDomain",
                code: 99,
                userInfo: [NSLocalizedDescriptionKey: "unexpected token"]
            )
            let error = HFModelBrowserError.decodingFailed(underlying: underlying)
            #expect(error.errorDescription?.contains("unexpected token") == true)
        }
    }

    // MARK: - HFModelInfo Codable with LFS Siblings

    @Suite("HFModelInfo Codable with LFS")
    struct CodableWithLFS {

        @Test("Round-trip preserves sibling LFS metadata")
        func lfsMetadataRoundTrip() throws {
            let lfs = HFLFSInfo(oid: "sha256abc123", size: 4_200_000_000, pointerSize: 134)
            let original = HFModelInfo(
                id: "org/lfs-model",
                author: "org",
                siblings: [
                    HFSibling(rfilename: "model.bin", size: nil, lfs: lfs),
                    HFSibling(rfilename: "README.md", size: 500, lfs: nil),
                ]
            )

            let data = try JSONEncoder().encode(original)
            let decoded = try JSONDecoder().decode(HFModelInfo.self, from: data)

            #expect(decoded.siblings?.count == 2)

            let lfsFile = decoded.siblings?.first { $0.rfilename == "model.bin" }
            #expect(lfsFile?.lfs?.oid == "sha256abc123")
            #expect(lfsFile?.lfs?.size == 4_200_000_000)
            #expect(lfsFile?.lfs?.pointerSize == 134)
            #expect(lfsFile?.size == nil)
        }

        @Test("Decoding from API JSON with pointer_size snake_case")
        func apiJsonSnakeCaseLFS() throws {
            let json = """
            {
                "id": "org/model",
                "siblings": [
                    {
                        "rfilename": "weights.bin",
                        "lfs": {
                            "oid": "abc",
                            "size": 1000000,
                            "pointer_size": 130
                        }
                    }
                ]
            }
            """
            let decoded = try JSONDecoder().decode(HFModelInfo.self, from: Data(json.utf8))
            #expect(decoded.siblings?.first?.lfs?.pointerSize == 130)
            #expect(decoded.siblings?.first?.lfs?.size == 1_000_000)
        }
    }

    // MARK: - Download URL Construction

    @Suite("downloadURL construction")
    struct DownloadURLConstruction {

        @Test("Default revision is 'main'")
        func defaultRevision() {
            let url = HFModelBrowser.downloadURL(
                repoId: "org/model",
                filename: "file.bin"
            )
            #expect(url.absoluteString.contains("/resolve/main/"))
        }

        @Test("Custom revision substituted correctly")
        func customRevision() {
            let url = HFModelBrowser.downloadURL(
                repoId: "org/model",
                filename: "file.bin",
                revision: "refs/pr/42"
            )
            #expect(url.absoluteString.contains("/resolve/refs/pr/42/"))
        }

        @Test("Filename preserved in URL path")
        func filenamePreserved() {
            let url = HFModelBrowser.downloadURL(
                repoId: "org/model",
                filename: "gemma-4-E2B-it.litertlm"
            )
            #expect(url.lastPathComponent == "gemma-4-E2B-it.litertlm")
        }
    }
}
