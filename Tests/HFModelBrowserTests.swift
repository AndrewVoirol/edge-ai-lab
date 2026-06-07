import XCTest

#if os(iOS)
@testable import GemmaEdgeGallery_iOS
#elseif os(macOS)
@testable import GemmaEdgeGallery_macOS
#endif

// MARK: - HFModelBrowser Tests

final class HFModelBrowserTests: XCTestCase {

    // MARK: - HFModelInfo Struct Tests

    func test_hfModel_hasRequiredFields() {
        let model = makeTestModel(
            id: "litert-community/gemma-4-E2B-it-litert-lm",
            author: "litert-community",
            downloads: 12345
        )

        XCTAssertEqual(model.id, "litert-community/gemma-4-E2B-it-litert-lm")
        XCTAssertEqual(model.author, "litert-community")
        XCTAssertEqual(model.downloads, 12345)
        XCTAssertEqual(model.likes, 0)
        XCTAssertFalse(model.tags.isEmpty)
        XCTAssertEqual(model.lastModified, "2026-01-01T00:00:00.000Z")
    }

    // MARK: - HFModelBrowser Initial State

    func test_hfModelBrowser_initialState() {
        let browser = HFModelBrowser()

        XCTAssertTrue(browser.discoveredModels.isEmpty, "Discovered models should start empty")
        XCTAssertFalse(browser.isLoading, "Should not be loading initially")
        XCTAssertNil(browser.lastError, "Should have no error initially")
    }

    // MARK: - Format Detection

    func test_hfModelBrowser_formatDetection_litertlm() {
        let browser = HFModelBrowser()
        let model = makeTestModel(
            id: "litert-community/gemma-4-E2B-it-litert-lm",
            author: "litert-community",
            siblings: [
                HFSibling(rfilename: "gemma-4-E2B-it.litertlm", size: 1_000_000, lfs: nil),
                HFSibling(rfilename: "README.md", size: 500, lfs: nil),
            ]
        )

        let format = browser.detectFormat(model)
        XCTAssertEqual(format, .litertlm, "Model with .litertlm file should be detected as litertlm")
    }

    func test_hfModelBrowser_formatDetection_mlx() {
        let browser = HFModelBrowser()
        let model = makeTestModel(
            id: "mlx-community/gemma-4-E2B-it-4bit",
            author: "mlx-community",
            siblings: [
                HFSibling(rfilename: "config.json", size: 1024, lfs: nil),
                HFSibling(rfilename: "model.safetensors", size: 5_000_000, lfs: nil),
            ]
        )

        let format = browser.detectFormat(model)
        XCTAssertEqual(format, .mlx, "Model with config.json + .safetensors should be detected as mlx")
    }

    func test_hfModelBrowser_formatDetection_unknown() {
        let browser = HFModelBrowser()
        let model = makeTestModel(
            id: "some-org/some-model",
            author: "some-org",
            siblings: [
                HFSibling(rfilename: "README.md", size: 100, lfs: nil),
            ]
        )

        let format = browser.detectFormat(model)
        XCTAssertEqual(format, .unknown, "Model without known format files should be unknown")
    }

    func test_hfModelBrowser_formatDetection_noSiblings() {
        let browser = HFModelBrowser()
        let model = makeTestModel(
            id: "some-org/some-model",
            author: "some-org",
            siblings: nil
        )

        let format = browser.detectFormat(model)
        XCTAssertEqual(format, .unknown, "Model with nil siblings should be unknown")
    }

    // MARK: - Download URL Construction

    func test_hfModelBrowser_fetchURL_construction() {
        let url = HFModelBrowser.downloadURL(
            repoId: "litert-community/gemma-4-E2B-it-litert-lm",
            filename: "gemma-4-E2B-it.litertlm"
        )

        XCTAssertEqual(
            url.absoluteString,
            "https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm"
        )
    }

    func test_hfModelBrowser_fetchURL_customRevision() {
        let url = HFModelBrowser.downloadURL(
            repoId: "litert-community/gemma-4-E2B-it-litert-lm",
            filename: "gemma-4-E2B-it.litertlm",
            revision: "v2.0"
        )

        XCTAssertTrue(url.absoluteString.contains("/resolve/v2.0/"), "URL should use custom revision")
    }

    // MARK: - HFModelInfo Convenience Extensions

    func test_hfModelInfo_displayName() {
        let model = makeTestModel(
            id: "litert-community/gemma-4-E2B-it-litert-lm",
            author: "litert-community"
        )

        XCTAssertEqual(model.displayName, "gemma-4-E2B-it-litert-lm")
    }

    func test_hfModelInfo_orgName() {
        let model = makeTestModel(
            id: "litert-community/gemma-4-E2B-it-litert-lm",
            author: "litert-community"
        )

        XCTAssertEqual(model.orgName, "litert-community")
    }

    func test_hfModelInfo_isGemma4() {
        let gemma4Model = makeTestModel(
            id: "litert-community/gemma-4-E2B-it-litert-lm",
            author: "litert-community"
        )
        XCTAssertTrue(gemma4Model.isGemma4, "Model with 'gemma-4' in ID should be detected")

        let nonGemmaModel = makeTestModel(
            id: "some-org/llama-7b",
            author: "some-org",
            tags: ["llama"]
        )
        XCTAssertFalse(nonGemmaModel.isGemma4, "Non-Gemma model should not be detected as Gemma 4")
    }

    func test_hfModelInfo_quantizationInfo() {
        let model4bit = makeTestModel(
            id: "mlx-community/gemma-4-E2B-it-4bit",
            author: "mlx-community"
        )
        XCTAssertEqual(model4bit.quantizationInfo, "4bit")

        let modelBf16 = makeTestModel(
            id: "mlx-community/gemma-4-E2B-it-bf16",
            author: "mlx-community"
        )
        XCTAssertEqual(modelBf16.quantizationInfo, "bf16")

        let noQuant = makeTestModel(
            id: "litert-community/gemma-4-E2B-it-litert-lm",
            author: "litert-community"
        )
        XCTAssertNil(noQuant.quantizationInfo, "Model without quantization info should return nil")
    }

    // MARK: - Model Size

    func test_hfModelBrowser_modelSize() {
        let browser = HFModelBrowser()
        let model = makeTestModel(
            id: "litert-community/gemma-4-E2B-it-litert-lm",
            author: "litert-community",
            siblings: [
                HFSibling(rfilename: "README.md", size: 500, lfs: nil),
                HFSibling(rfilename: "gemma-4-E2B-it.litertlm", size: nil, lfs: HFLFSInfo(oid: "abc123", size: 2_000_000_000, pointerSize: 130)),
            ]
        )

        let size = browser.modelSize(model)
        XCTAssertEqual(size, 2_000_000_000, "Should return the largest file size (LFS preferred)")
    }

    func test_hfModelBrowser_modelSize_nilSiblings() {
        let browser = HFModelBrowser()
        let model = makeTestModel(
            id: "some-org/some-model",
            author: "some-org",
            siblings: nil
        )

        XCTAssertNil(browser.modelSize(model), "Should return nil when siblings is nil")
    }

    // MARK: - HFModelBrowserError

    func test_hfModelBrowserError_descriptions() {
        let invalidURL = HFModelBrowserError.invalidURL("bad://url")
        XCTAssertTrue(invalidURL.localizedDescription.contains("Invalid"))

        let httpError = HFModelBrowserError.httpError(statusCode: 404, repoId: "test/model")
        XCTAssertTrue(httpError.localizedDescription.contains("404"))
        XCTAssertTrue(httpError.localizedDescription.contains("test/model"))

        let decodeError = HFModelBrowserError.decodingFailed(underlying: NSError(domain: "Test", code: 0))
        XCTAssertTrue(decodeError.localizedDescription.contains("decode"))
    }

    // MARK: - HFModelFormat Raw Values

    func test_hfModelFormat_rawValues() {
        XCTAssertEqual(HFModelFormat.litertlm.rawValue, "litertlm")
        XCTAssertEqual(HFModelFormat.mlx.rawValue, "mlx")
        XCTAssertEqual(HFModelFormat.unknown.rawValue, "unknown")
    }

    // MARK: - Helpers

    private func makeTestModel(
        id: String,
        author: String,
        downloads: Int = 0,
        tags: [String] = ["gemma-4"],
        siblings: [HFSibling]? = nil
    ) -> HFModelInfo {
        HFModelInfo(
            id: id,
            author: author,
            lastModified: "2026-01-01T00:00:00.000Z",
            downloads: downloads,
            likes: 0,
            tags: tags,
            pipelineTag: "text-generation",
            libraryName: "litert",
            siblings: siblings
        )
    }
}
