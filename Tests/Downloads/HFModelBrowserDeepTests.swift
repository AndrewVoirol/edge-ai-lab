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

// MARK: - HFModelInfo Codable Tests

@Suite("HFModelInfo Codable")
struct HFModelInfoCodableTests {

    @Suite("Round-trip encoding/decoding")
    struct RoundTrip {

        @Test("Full model info round-trips through JSON")
        func fullRoundTrip() throws {
            let original = HFModelInfo(
                id: "litert-community/gemma-4-E2B-it-litert-lm",
                author: "litert-community",
                lastModified: "2026-06-01T12:00:00.000Z",
                downloads: 12345,
                likes: 42,
                tags: ["gemma-4", "litert", "text-generation"],
                pipelineTag: "text-generation",
                libraryName: "litert",
                siblings: [
                    HFSibling(rfilename: "model.litertlm", size: 500_000_000, lfs: nil),
                ]
            )

            let data = try JSONEncoder().encode(original)
            let decoded = try JSONDecoder().decode(HFModelInfo.self, from: data)

            #expect(decoded.id == original.id)
            #expect(decoded.author == original.author)
            #expect(decoded.lastModified == original.lastModified)
            #expect(decoded.downloads == original.downloads)
            #expect(decoded.likes == original.likes)
            #expect(decoded.tags == original.tags)
            #expect(decoded.pipelineTag == original.pipelineTag)
            #expect(decoded.libraryName == original.libraryName)
            #expect(decoded.siblings?.count == 1)
            #expect(decoded.siblings?.first?.rfilename == "model.litertlm")
        }

        @Test("Minimal model info round-trips (no optional fields)")
        func minimalRoundTrip() throws {
            let original = HFModelInfo(
                id: "org/repo",
                author: "org"
            )

            let data = try JSONEncoder().encode(original)
            let decoded = try JSONDecoder().decode(HFModelInfo.self, from: data)

            #expect(decoded.id == "org/repo")
            #expect(decoded.author == "org")
            #expect(decoded.lastModified == "")
            #expect(decoded.downloads == 0)
            #expect(decoded.likes == 0)
            #expect(decoded.tags.isEmpty)
            #expect(decoded.pipelineTag == nil)
            #expect(decoded.libraryName == nil)
            #expect(decoded.siblings == nil)
        }
    }

    @Suite("Custom decoder fallbacks")
    struct DecoderFallbacks {

        @Test("Missing author falls back to parsing from id")
        func authorFallbackFromId() throws {
            let json = """
            {"id": "my-org/some-model"}
            """
            let data = Data(json.utf8)
            let decoded = try JSONDecoder().decode(HFModelInfo.self, from: data)

            #expect(decoded.author == "my-org")
        }

        @Test("Missing author with no slash uses full id")
        func authorFallbackNoSlash() throws {
            let json = """
            {"id": "standalone-model-name"}
            """
            let data = Data(json.utf8)
            let decoded = try JSONDecoder().decode(HFModelInfo.self, from: data)

            #expect(decoded.author == "standalone-model-name")
        }

        @Test("Missing lastModified falls back to createdAt")
        func lastModifiedFallbackToCreatedAt() throws {
            let json = """
            {"id": "org/repo", "createdAt": "2026-01-15T10:00:00.000Z"}
            """
            let data = Data(json.utf8)
            let decoded = try JSONDecoder().decode(HFModelInfo.self, from: data)

            #expect(decoded.lastModified == "2026-01-15T10:00:00.000Z")
        }

        @Test("Missing both lastModified and createdAt falls back to empty string")
        func lastModifiedFallbackEmpty() throws {
            let json = """
            {"id": "org/repo"}
            """
            let data = Data(json.utf8)
            let decoded = try JSONDecoder().decode(HFModelInfo.self, from: data)

            #expect(decoded.lastModified == "")
        }

        @Test("Missing downloads defaults to zero")
        func downloadsDefaultZero() throws {
            let json = """
            {"id": "org/repo"}
            """
            let data = Data(json.utf8)
            let decoded = try JSONDecoder().decode(HFModelInfo.self, from: data)

            #expect(decoded.downloads == 0)
        }

        @Test("Missing likes defaults to zero")
        func likesDefaultZero() throws {
            let json = """
            {"id": "org/repo"}
            """
            let data = Data(json.utf8)
            let decoded = try JSONDecoder().decode(HFModelInfo.self, from: data)

            #expect(decoded.likes == 0)
        }

        @Test("Missing tags defaults to empty array")
        func tagsDefaultEmpty() throws {
            let json = """
            {"id": "org/repo"}
            """
            let data = Data(json.utf8)
            let decoded = try JSONDecoder().decode(HFModelInfo.self, from: data)

            #expect(decoded.tags.isEmpty)
        }

        @Test("pipeline_tag maps to pipelineTag via CodingKeys")
        func pipelineTagSnakeCase() throws {
            let json = """
            {"id": "org/repo", "pipeline_tag": "text-generation"}
            """
            let data = Data(json.utf8)
            let decoded = try JSONDecoder().decode(HFModelInfo.self, from: data)

            #expect(decoded.pipelineTag == "text-generation")
        }

        @Test("library_name maps to libraryName via CodingKeys")
        func libraryNameSnakeCase() throws {
            let json = """
            {"id": "org/repo", "library_name": "mlx"}
            """
            let data = Data(json.utf8)
            let decoded = try JSONDecoder().decode(HFModelInfo.self, from: data)

            #expect(decoded.libraryName == "mlx")
        }

        @Test("All optional fields missing produces valid defaults")
        func allOptionalsMissing() throws {
            let json = """
            {"id": "solo"}
            """
            let data = Data(json.utf8)
            let decoded = try JSONDecoder().decode(HFModelInfo.self, from: data)

            #expect(decoded.id == "solo")
            #expect(decoded.author == "solo")
            #expect(decoded.lastModified == "")
            #expect(decoded.downloads == 0)
            #expect(decoded.likes == 0)
            #expect(decoded.tags.isEmpty)
            #expect(decoded.pipelineTag == nil)
            #expect(decoded.libraryName == nil)
            #expect(decoded.siblings == nil)
        }
    }

    @Test("Encoder uses pipeline_tag and library_name snake_case keys")
    func encoderUsesSnakeCaseKeys() throws {
        let model = HFModelInfo(
            id: "org/repo",
            author: "org",
            pipelineTag: "image-classification",
            libraryName: "transformers"
        )

        let data = try JSONEncoder().encode(model)
        let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        #expect(dict?["pipeline_tag"] as? String == "image-classification")
        #expect(dict?["library_name"] as? String == "transformers")
        // Ensure camelCase keys are NOT present
        #expect(dict?["pipelineTag"] == nil)
        #expect(dict?["libraryName"] == nil)
    }

    @Test("Encoder omits nil optional fields")
    func encoderOmitsNils() throws {
        let model = HFModelInfo(
            id: "org/repo",
            author: "org"
        )

        let data = try JSONEncoder().encode(model)
        let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        #expect(dict?["pipeline_tag"] == nil)
        #expect(dict?["library_name"] == nil)
        #expect(dict?["siblings"] == nil)
    }

    @Test("Decoding an array of models works")
    func decodeArray() throws {
        let json = """
        [
            {"id": "org/model-a", "downloads": 100},
            {"id": "org/model-b", "downloads": 200}
        ]
        """
        let data = Data(json.utf8)
        let models = try JSONDecoder().decode([HFModelInfo].self, from: data)

        #expect(models.count == 2)
        #expect(models[0].id == "org/model-a")
        #expect(models[0].downloads == 100)
        #expect(models[1].id == "org/model-b")
        #expect(models[1].downloads == 200)
    }
}

// MARK: - HFSibling Codable Tests

@Suite("HFSibling Codable")
struct HFSiblingCodableTests {

    @Test("Round-trips with all fields populated")
    func fullRoundTrip() throws {
        let lfs = HFLFSInfo(oid: "abc123sha256hash", size: 2_000_000_000, pointerSize: 132)
        let original = HFSibling(rfilename: "weights.safetensors", size: 2_000_000_000, lfs: lfs)

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(HFSibling.self, from: data)

        #expect(decoded.rfilename == original.rfilename)
        #expect(decoded.size == original.size)
        #expect(decoded.lfs?.oid == lfs.oid)
        #expect(decoded.lfs?.size == lfs.size)
        #expect(decoded.lfs?.pointerSize == lfs.pointerSize)
    }

    @Test("Round-trips without LFS info")
    func noLfsRoundTrip() throws {
        let original = HFSibling(rfilename: "config.json", size: 1024, lfs: nil)

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(HFSibling.self, from: data)

        #expect(decoded.rfilename == "config.json")
        #expect(decoded.size == 1024)
        #expect(decoded.lfs == nil)
    }

    @Test("Round-trips without size field")
    func noSizeRoundTrip() throws {
        let original = HFSibling(rfilename: "README.md", size: nil, lfs: nil)

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(HFSibling.self, from: data)

        #expect(decoded.rfilename == "README.md")
        #expect(decoded.size == nil)
    }
}

// MARK: - HFLFSInfo Codable Tests

@Suite("HFLFSInfo Codable")
struct HFLFSInfoCodableTests {

    @Test("Round-trips through JSON")
    func roundTrip() throws {
        let original = HFLFSInfo(oid: "deadbeef1234567890", size: 4_000_000_000, pointerSize: 134)

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(HFLFSInfo.self, from: data)

        #expect(decoded.oid == original.oid)
        #expect(decoded.size == original.size)
        #expect(decoded.pointerSize == original.pointerSize)
    }

    @Test("pointer_size maps via CodingKeys")
    func pointerSizeSnakeCase() throws {
        let json = """
        {"oid": "abc", "size": 1000, "pointer_size": 132}
        """
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(HFLFSInfo.self, from: data)

        #expect(decoded.pointerSize == 132)
    }

    @Test("Encoder uses pointer_size key")
    func encoderUsesSnakeCaseKey() throws {
        let lfs = HFLFSInfo(oid: "abc", size: 1000, pointerSize: 132)
        let data = try JSONEncoder().encode(lfs)
        let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        #expect(dict?["pointer_size"] as? Int == 132)
        #expect(dict?["pointerSize"] == nil)
    }
}

// MARK: - HFModelInfo Convenience Extensions

@Suite("HFModelInfo convenience extensions")
struct HFModelInfoExtensionTests {

    @Suite("displayName")
    struct DisplayNameTests {

        @Test("Strips organization prefix from repo id")
        func stripsOrgPrefix() {
            let model = HFModelInfo(id: "litert-community/gemma-4-E2B-it-litert-lm", author: "litert-community")
            #expect(model.displayName == "gemma-4-E2B-it-litert-lm")
        }

        @Test("Returns full id when no slash is present")
        func noSlash() {
            let model = HFModelInfo(id: "standalone-model", author: "standalone-model")
            #expect(model.displayName == "standalone-model")
        }

        @Test("Handles deeply nested paths (only first slash)")
        func deepPath() {
            let model = HFModelInfo(id: "org/sub/path/model", author: "org")
            #expect(model.displayName == "sub/path/model")
        }
    }

    @Suite("orgName")
    struct OrgNameTests {

        @Test("Extracts organization before slash")
        func extractsOrg() {
            let model = HFModelInfo(id: "mlx-community/gemma-model", author: "mlx-community")
            #expect(model.orgName == "mlx-community")
        }

        @Test("Returns full id when no slash is present")
        func noSlash() {
            let model = HFModelInfo(id: "no-org-model", author: "no-org-model")
            #expect(model.orgName == "no-org-model")
        }
    }

    @Suite("isGemma4")
    struct IsGemma4Tests {

        @Test("True when id contains gemma-4")
        func idContainsGemma4() {
            let model = HFModelInfo(id: "org/gemma-4-E2B-it", author: "org")
            #expect(model.isGemma4 == true)
        }

        @Test("True when id contains gemma4 (no dash)")
        func idContainsGemma4NoDash() {
            let model = HFModelInfo(id: "org/gemma4-model", author: "org")
            #expect(model.isGemma4 == true)
        }

        @Test("True when tag contains gemma-4")
        func tagContainsGemma4() {
            let model = HFModelInfo(id: "org/some-model", author: "org", tags: ["gemma-4", "litert"])
            #expect(model.isGemma4 == true)
        }

        @Test("True when tag contains gemma4 (no dash)")
        func tagContainsGemma4NoDash() {
            let model = HFModelInfo(id: "org/some-model", author: "org", tags: ["Gemma4"])
            #expect(model.isGemma4 == true)
        }

        @Test("False when no gemma4 indicators")
        func notGemma4() {
            let model = HFModelInfo(id: "org/llama-3-model", author: "org", tags: ["llama"])
            #expect(model.isGemma4 == false)
        }

        @Test("Case-insensitive matching")
        func caseInsensitive() {
            let model = HFModelInfo(id: "org/GEMMA-4-model", author: "org")
            #expect(model.isGemma4 == true)
        }
    }

    @Suite("quantizationInfo")
    struct QuantizationInfoTests {

        @Test("Detects bf16 from id", arguments: [
            ("org/gemma-4-bf16", "bf16"),
            ("org/gemma-4-fp16", "fp16"),
            ("org/gemma-4-fp32", "fp32"),
            ("org/model-int4", "int4"),
            ("org/model-int8", "int8"),
            ("org/model-4bit", "4bit"),
            ("org/model-8bit", "8bit"),
            ("org/model-q4_0", "q4_0"),
            ("org/model-q4_k_m", "q4_k_m"),
            ("org/model-q8_0", "q8_0"),
        ])
        func detectsFromId(id: String, expected: String) {
            let model = HFModelInfo(id: id, author: "org")
            #expect(model.quantizationInfo == expected)
        }

        @Test("Detects quantization from tags when not in id")
        func detectsFromTags() {
            let model = HFModelInfo(id: "org/plain-model", author: "org", tags: ["4bit", "gemma"])
            #expect(model.quantizationInfo == "4bit")
        }

        @Test("Returns nil when no quantization info present")
        func noQuantization() {
            let model = HFModelInfo(id: "org/plain-model", author: "org", tags: ["text-generation"])
            #expect(model.quantizationInfo == nil)
        }

        @Test("Prefers id match over tag match")
        func idTakesPrecedence() {
            // bf16 in the id should be found before 4bit in tags
            let model = HFModelInfo(id: "org/model-bf16", author: "org", tags: ["4bit"])
            #expect(model.quantizationInfo == "bf16")
        }
    }

    @Test("Identifiable conformance uses id")
    func identifiable() {
        let model = HFModelInfo(id: "org/test-model", author: "org")
        #expect(model.id == "org/test-model")
    }
}

// MARK: - HFModelFormat Tests

@Suite("HFModelFormat")
struct HFModelFormatTests {

    @Test("Raw values match expected strings")
    func rawValues() {
        #expect(HFModelFormat.litertlm.rawValue == "litertlm")
        #expect(HFModelFormat.mlx.rawValue == "mlx")
        #expect(HFModelFormat.unknown.rawValue == "unknown")
    }

    @Test("All cases are initializable from raw value")
    func initFromRaw() {
        #expect(HFModelFormat(rawValue: "litertlm") == .litertlm)
        #expect(HFModelFormat(rawValue: "mlx") == .mlx)
        #expect(HFModelFormat(rawValue: "unknown") == .unknown)
        #expect(HFModelFormat(rawValue: "nonexistent") == nil)
    }
}

// MARK: - HFModelBrowserError Tests

@Suite("HFModelBrowserError")
struct HFModelBrowserErrorTests {

    @Test("invalidURL provides descriptive message")
    func invalidURLDescription() {
        let error = HFModelBrowserError.invalidURL("not-a-url")
        #expect(error.errorDescription?.contains("not-a-url") == true)
        #expect(error.errorDescription?.contains("Invalid") == true)
    }

    @Test("httpError includes status code and repo id")
    func httpErrorDescription() {
        let error = HFModelBrowserError.httpError(statusCode: 404, repoId: "org/model")
        let desc = error.errorDescription ?? ""
        #expect(desc.contains("404"))
        #expect(desc.contains("org/model"))
    }

    @Test("httpStatusError includes status code")
    func httpStatusErrorDescription() {
        let error = HFModelBrowserError.httpStatusError(statusCode: 500)
        #expect(error.errorDescription?.contains("500") == true)
    }

    @Test("invalidResponse has a message")
    func invalidResponseDescription() {
        let error = HFModelBrowserError.invalidResponse
        #expect(error.errorDescription != nil)
        #expect(error.errorDescription!.isEmpty == false)
    }

    @Test("decodingFailed wraps underlying error description")
    func decodingFailedDescription() {
        let underlying = NSError(domain: "TestDomain", code: 42,
                                 userInfo: [NSLocalizedDescriptionKey: "bad data"])
        let error = HFModelBrowserError.decodingFailed(underlying: underlying)
        #expect(error.errorDescription?.contains("bad data") == true)
    }
}

// MARK: - HFModelBrowser Instance Tests

@Suite("HFModelBrowser instance")
struct HFModelBrowserInstanceTests {

    @Suite("Initial state")
    struct InitialState {

        @Test("discoveredModels starts empty")
        @MainActor
        func discoveredModelsEmpty() {
            let browser = HFModelBrowser()
            #expect(browser.discoveredModels.isEmpty)
        }

        @Test("isLoading starts false")
        @MainActor
        func isLoadingFalse() {
            let browser = HFModelBrowser()
            #expect(browser.isLoading == false)
        }

        @Test("lastError starts nil")
        @MainActor
        func lastErrorNil() {
            let browser = HFModelBrowser()
            #expect(browser.lastError == nil)
        }
    }

    @Suite("detectFormat")
    struct DetectFormatTests {

        @Test("Detects litertlm from siblings with .litertlm file")
        @MainActor
        func detectLitertlmFromSiblings() {
            let browser = HFModelBrowser()
            let model = HFModelInfo(
                id: "org/model",
                author: "org",
                siblings: [
                    HFSibling(rfilename: "README.md", size: nil, lfs: nil),
                    HFSibling(rfilename: "model.litertlm", size: 500_000_000, lfs: nil),
                ]
            )
            #expect(browser.detectFormat(model) == .litertlm)
        }

        @Test("Detects mlx from siblings with config.json and .safetensors")
        @MainActor
        func detectMlxFromSiblings() {
            let browser = HFModelBrowser()
            let model = HFModelInfo(
                id: "org/model",
                author: "org",
                siblings: [
                    HFSibling(rfilename: "config.json", size: 512, lfs: nil),
                    HFSibling(rfilename: "model-00001-of-00002.safetensors", size: 1_000_000_000, lfs: nil),
                ]
            )
            #expect(browser.detectFormat(model) == .mlx)
        }

        @Test("Requires BOTH config.json and .safetensors for mlx")
        @MainActor
        func mlxRequiresBothFiles() {
            let browser = HFModelBrowser()

            // Only config.json, no safetensors
            let configOnly = HFModelInfo(
                id: "org/model",
                author: "org",
                siblings: [HFSibling(rfilename: "config.json", size: 512, lfs: nil)]
            )
            #expect(browser.detectFormat(configOnly) != .mlx)

            // Only safetensors, no config.json
            let safetensorsOnly = HFModelInfo(
                id: "org/model",
                author: "org",
                siblings: [HFSibling(rfilename: "weights.safetensors", size: 1_000_000, lfs: nil)]
            )
            #expect(browser.detectFormat(safetensorsOnly) != .mlx)
        }

        @Test("Falls back to libraryName when no siblings")
        @MainActor
        func fallbackToLibraryName() {
            let browser = HFModelBrowser()

            let litert = HFModelInfo(id: "org/model", author: "org", libraryName: "litert")
            #expect(browser.detectFormat(litert) == .litertlm)

            let mlx = HFModelInfo(id: "org/model", author: "org", libraryName: "mlx")
            #expect(browser.detectFormat(mlx) == .mlx)
        }

        @Test("Falls back to tags when no siblings or libraryName")
        @MainActor
        func fallbackToTags() {
            let browser = HFModelBrowser()

            let litert = HFModelInfo(id: "org/model", author: "org", tags: ["litert"])
            #expect(browser.detectFormat(litert) == .litertlm)

            let mlx = HFModelInfo(id: "org/model", author: "org", tags: ["mlx"])
            #expect(browser.detectFormat(mlx) == .mlx)
        }

        @Test("Falls back to model ID naming convention")
        @MainActor
        func fallbackToModelId() {
            let browser = HFModelBrowser()

            let litert = HFModelInfo(id: "org/gemma-litert-lm", author: "org")
            #expect(browser.detectFormat(litert) == .litertlm)

            let litertUnderscore = HFModelInfo(id: "org/gemma-litert_lm", author: "org")
            #expect(browser.detectFormat(litertUnderscore) == .litertlm)
        }

        @Test("Falls back to mlx-community author")
        @MainActor
        func fallbackToMlxCommunityAuthor() {
            let browser = HFModelBrowser()
            let model = HFModelInfo(id: "mlx-community/some-model", author: "mlx-community")
            #expect(browser.detectFormat(model) == .mlx)
        }

        @Test("Returns unknown when nothing matches")
        @MainActor
        func unknownFormat() {
            let browser = HFModelBrowser()
            let model = HFModelInfo(id: "org/mystery-model", author: "org")
            #expect(browser.detectFormat(model) == .unknown)
        }

        @Test("Siblings take priority over libraryName")
        @MainActor
        func siblingsPriorityOverLibrary() {
            let browser = HFModelBrowser()
            // Siblings say litertlm, but libraryName says mlx — siblings win
            let model = HFModelInfo(
                id: "org/model",
                author: "org",
                libraryName: "mlx",
                siblings: [
                    HFSibling(rfilename: "model.litertlm", size: 500_000, lfs: nil),
                ]
            )
            #expect(browser.detectFormat(model) == .litertlm)
        }
    }

    @Suite("modelSize")
    struct ModelSizeTests {

        @Test("Returns nil when siblings is nil")
        @MainActor
        func nilSiblings() {
            let browser = HFModelBrowser()
            let model = HFModelInfo(id: "org/model", author: "org", siblings: nil)
            #expect(browser.modelSize(model) == nil)
        }

        @Test("Returns nil when siblings is empty")
        @MainActor
        func emptySiblings() {
            let browser = HFModelBrowser()
            let model = HFModelInfo(id: "org/model", author: "org", siblings: [])
            #expect(browser.modelSize(model) == nil)
        }

        @Test("Returns the largest file size from siblings")
        @MainActor
        func largestFileSize() {
            let browser = HFModelBrowser()
            let model = HFModelInfo(
                id: "org/model",
                author: "org",
                siblings: [
                    HFSibling(rfilename: "config.json", size: 1024, lfs: nil),
                    HFSibling(rfilename: "model.safetensors", size: 2_000_000_000, lfs: nil),
                    HFSibling(rfilename: "tokenizer.json", size: 5000, lfs: nil),
                ]
            )
            #expect(browser.modelSize(model) == 2_000_000_000)
        }

        @Test("Prefers LFS size over regular size")
        @MainActor
        func prefersLfsSize() {
            let browser = HFModelBrowser()
            let lfs = HFLFSInfo(oid: "abc", size: 3_000_000_000, pointerSize: 132)
            let model = HFModelInfo(
                id: "org/model",
                author: "org",
                siblings: [
                    // Regular size is smaller than LFS size
                    HFSibling(rfilename: "model.bin", size: 100, lfs: lfs),
                ]
            )
            #expect(browser.modelSize(model) == 3_000_000_000)
        }

        @Test("Skips siblings with no size info")
        @MainActor
        func skipsSiblingsWithoutSize() {
            let browser = HFModelBrowser()
            let model = HFModelInfo(
                id: "org/model",
                author: "org",
                siblings: [
                    HFSibling(rfilename: "README.md", size: nil, lfs: nil),
                    HFSibling(rfilename: "model.bin", size: 500_000, lfs: nil),
                ]
            )
            #expect(browser.modelSize(model) == 500_000)
        }

        @Test("Returns nil when all siblings have nil size and no LFS")
        @MainActor
        func allNilSizes() {
            let browser = HFModelBrowser()
            let model = HFModelInfo(
                id: "org/model",
                author: "org",
                siblings: [
                    HFSibling(rfilename: "README.md", size: nil, lfs: nil),
                    HFSibling(rfilename: "config.json", size: nil, lfs: nil),
                ]
            )
            #expect(browser.modelSize(model) == nil)
        }
    }

    @Suite("downloadURL")
    struct DownloadURLTests {

        @Test("Constructs correct URL with default revision")
        func defaultRevision() {
            let url = HFModelBrowser.downloadURL(
                repoId: "litert-community/gemma-4-E2B-it-litert-lm",
                filename: "gemma-4-E2B-it.litertlm"
            )
            #expect(url.absoluteString == "https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm")
        }

        @Test("Constructs correct URL with custom revision")
        func customRevision() {
            let url = HFModelBrowser.downloadURL(
                repoId: "org/model",
                filename: "weights.safetensors",
                revision: "v2.0"
            )
            #expect(url.absoluteString == "https://huggingface.co/org/model/resolve/v2.0/weights.safetensors")
        }

        @Test("URL host is huggingface.co")
        func correctHost() {
            let url = HFModelBrowser.downloadURL(repoId: "org/model", filename: "file.bin")
            #expect(url.host == "huggingface.co")
        }

        @Test("URL uses HTTPS scheme")
        func httpsScheme() {
            let url = HFModelBrowser.downloadURL(repoId: "org/model", filename: "file.bin")
            #expect(url.scheme == "https")
        }
    }

    @Test("clearCache does not crash on empty cache")
    @MainActor
    func clearCacheEmpty() {
        let browser = HFModelBrowser()
        // Should not crash
        browser.clearCache()
        #expect(browser.discoveredModels.isEmpty)
    }
}

// MARK: - Realistic API Response Decoding

@Suite("Realistic API response decoding")
struct RealisticAPIResponseTests {

    @Test("Decodes a realistic model detail JSON response")
    func realisticDetailResponse() throws {
        let json = """
        {
            "id": "litert-community/gemma-4-E2B-it-litert-lm",
            "author": "litert-community",
            "lastModified": "2026-06-01T12:00:00.000Z",
            "downloads": 12345,
            "likes": 42,
            "tags": ["gemma-4", "litert", "text-generation", "en"],
            "pipeline_tag": "text-generation",
            "library_name": "litert",
            "siblings": [
                {
                    "rfilename": "README.md",
                    "size": null,
                    "lfs": null
                },
                {
                    "rfilename": "gemma-4-E2B-it.litertlm",
                    "size": 1500000000,
                    "lfs": {
                        "oid": "abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890",
                        "size": 1500000000,
                        "pointer_size": 132
                    }
                }
            ]
        }
        """
        let data = Data(json.utf8)
        let model = try JSONDecoder().decode(HFModelInfo.self, from: data)

        #expect(model.id == "litert-community/gemma-4-E2B-it-litert-lm")
        #expect(model.author == "litert-community")
        #expect(model.displayName == "gemma-4-E2B-it-litert-lm")
        #expect(model.orgName == "litert-community")
        #expect(model.downloads == 12345)
        #expect(model.likes == 42)
        #expect(model.tags.count == 4)
        #expect(model.pipelineTag == "text-generation")
        #expect(model.libraryName == "litert")
        #expect(model.isGemma4 == true)

        let siblings = try #require(model.siblings)
        #expect(siblings.count == 2)

        let modelFile = siblings[1]
        #expect(modelFile.rfilename == "gemma-4-E2B-it.litertlm")
        #expect(modelFile.size == 1_500_000_000)

        let lfs = try #require(modelFile.lfs)
        #expect(lfs.size == 1_500_000_000)
        #expect(lfs.pointerSize == 132)
    }

    @Test("Decodes a realistic list endpoint JSON (minimal fields)")
    func realisticListResponse() throws {
        let json = """
        [
            {
                "id": "litert-community/gemma-4-E2B-it-litert-lm",
                "downloads": 5000,
                "likes": 10,
                "tags": ["gemma-4", "litert"],
                "pipeline_tag": "text-generation",
                "library_name": "litert"
            },
            {
                "id": "mlx-community/gemma-4-E2B-it-4bit",
                "downloads": 3000,
                "likes": 8,
                "tags": ["gemma-4", "mlx"],
                "pipeline_tag": "text-generation",
                "library_name": "mlx"
            }
        ]
        """
        let data = Data(json.utf8)
        let models = try JSONDecoder().decode([HFModelInfo].self, from: data)

        #expect(models.count == 2)

        // First model — author should fall back to parsing from id
        #expect(models[0].author == "litert-community")
        #expect(models[0].lastModified == "")
        #expect(models[0].siblings == nil)

        // Second model
        #expect(models[1].author == "mlx-community")
        #expect(models[1].quantizationInfo == "4bit")
    }
}
