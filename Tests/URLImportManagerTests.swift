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

import XCTest
import Foundation

#if os(iOS)
@testable import GemmaEdgeGallery_iOS
#elseif os(macOS)
@testable import GemmaEdgeGallery_macOS
#endif

final class URLImportManagerTests: XCTestCase {

  private var tempDir: URL!
  private var manager: URLImportManager!

  @MainActor
  override func setUp() {
    super.setUp()
    tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("URLImportTests-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    let browser = HFModelBrowser()
    let catalog = DynamicModelCatalog(storageDirectory: tempDir)
    manager = URLImportManager(browser: browser, catalog: catalog)
  }

  override func tearDown() {
    try? FileManager.default.removeItem(at: tempDir)
    super.tearDown()
  }

  // MARK: - Valid URLs

  @MainActor
  func testParseStandardURL() {
    let parsed = manager.parseHuggingFaceURL(
      "https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm"
    )
    XCTAssertNotNil(parsed)
    XCTAssertEqual(parsed?.org, "litert-community")
    XCTAssertEqual(parsed?.repo, "gemma-4-E2B-it-litert-lm")
    XCTAssertNil(parsed?.specificFile)
  }

  @MainActor
  func testParseShortURL() {
    let parsed = manager.parseHuggingFaceURL(
      "https://hf.co/litert-community/gemma-4-E2B-it-litert-lm"
    )
    XCTAssertNotNil(parsed, "Expected short hf.co URL to parse successfully")
    XCTAssertEqual(parsed?.org, "litert-community")
    XCTAssertEqual(parsed?.repo, "gemma-4-E2B-it-litert-lm")
  }

  @MainActor
  func testParseURLWithBlob() {
    let parsed = manager.parseHuggingFaceURL(
      "https://huggingface.co/org/repo/blob/main/model.litertlm"
    )
    XCTAssertNotNil(parsed)
    XCTAssertEqual(parsed?.org, "org")
    XCTAssertEqual(parsed?.repo, "repo")
    XCTAssertEqual(parsed?.specificFile, "model.litertlm")
  }

  @MainActor
  func testParseURLWithResolve() {
    let parsed = manager.parseHuggingFaceURL(
      "https://huggingface.co/org/repo/resolve/main/model.litertlm"
    )
    XCTAssertNotNil(parsed)
    XCTAssertEqual(parsed?.specificFile, "model.litertlm")
  }

  @MainActor
  func testParseURLWithTreeMain() {
    let parsed = manager.parseHuggingFaceURL(
      "https://huggingface.co/org/repo/tree/main"
    )
    XCTAssertNotNil(parsed)
    XCTAssertEqual(parsed?.org, "org")
    XCTAssertEqual(parsed?.repo, "repo")
    XCTAssertNil(parsed?.specificFile)
  }

  @MainActor
  func testParseWWWURL() {
    let parsed = manager.parseHuggingFaceURL(
      "https://www.huggingface.co/org/repo"
    )
    XCTAssertNotNil(parsed, "Expected www.huggingface.co URL to parse successfully")
    XCTAssertEqual(parsed?.org, "org")
    XCTAssertEqual(parsed?.repo, "repo")
  }

  @MainActor
  func testRepoId() {
    let parsed = manager.parseHuggingFaceURL(
      "https://huggingface.co/org/repo"
    )
    XCTAssertNotNil(parsed)
    XCTAssertEqual(parsed?.repoId, "org/repo")
  }

  // MARK: - Invalid URLs

  @MainActor
  func testParseInvalidHost() {
    let parsed = manager.parseHuggingFaceURL("https://github.com/org/repo")
    XCTAssertNil(parsed, "Expected non-HuggingFace host to return nil")
  }

  @MainActor
  func testParseNoRepo() {
    let parsed = manager.parseHuggingFaceURL("https://huggingface.co/org")
    XCTAssertNil(parsed, "Expected single path component to return nil")
  }

  @MainActor
  func testParseReservedPath() {
    let parsed = manager.parseHuggingFaceURL("https://huggingface.co/api/models")
    XCTAssertNil(parsed, "Expected reserved path 'api' to return nil")
  }

  @MainActor
  func testParseEmptyString() {
    let parsed = manager.parseHuggingFaceURL("")
    XCTAssertNil(parsed, "Expected empty string to return nil")
  }

  @MainActor
  func testParseGarbageString() {
    let parsed = manager.parseHuggingFaceURL("not a url")
    XCTAssertNil(parsed, "Expected garbage string to return nil")
  }

  @MainActor
  func testParseDatasetsReserved() {
    let parsed = manager.parseHuggingFaceURL("https://huggingface.co/datasets/something")
    XCTAssertNil(parsed, "Expected reserved path 'datasets' to return nil")
  }

  // MARK: - Initial state

  @MainActor
  func testInitialState() {
    if case .idle = manager.state {
      // Expected
    } else {
      XCTFail("Expected .idle state, got: \(manager.state)")
    }
  }

  @MainActor
  func testReset() {
    manager.reset()
    if case .idle = manager.state {
      // Expected
    } else {
      XCTFail("Expected .idle state after reset, got: \(manager.state)")
    }
  }
}
