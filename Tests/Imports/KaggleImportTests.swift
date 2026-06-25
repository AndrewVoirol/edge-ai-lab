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

import XCTest
import Foundation

#if os(iOS)
@testable import EdgeAILab_iOS
#elseif os(macOS)
@testable import EdgeAILab_macOS
#endif

final class KaggleImportTests: XCTestCase {

  // MARK: - Basic URL Parsing

  func testParseBasicKaggleURL() {
    let handle = KaggleModelParser.parseURL("https://www.kaggle.com/models/google/gemma-3n")
    XCTAssertNotNil(handle)
    XCTAssertEqual(handle?.owner, "google")
    XCTAssertEqual(handle?.modelSlug, "gemma-3n")
    XCTAssertNil(handle?.framework)
    XCTAssertNil(handle?.variation)
    XCTAssertNil(handle?.version)
  }

  // MARK: - Full URL Parsing

  func testParseFullKaggleURL() {
    let handle = KaggleModelParser.parseURL(
      "https://www.kaggle.com/models/google/gemma/pyTorch/2b/1"
    )
    XCTAssertNotNil(handle)
    XCTAssertEqual(handle?.owner, "google")
    XCTAssertEqual(handle?.modelSlug, "gemma")
    XCTAssertEqual(handle?.framework, "pyTorch")
    XCTAssertEqual(handle?.variation, "2b")
    XCTAssertEqual(handle?.version, 1)
  }

  // MARK: - Trailing Slash

  func testParseKaggleURLWithTrailingSlash() {
    let handle = KaggleModelParser.parseURL(
      "https://www.kaggle.com/models/google/gemma-3n/"
    )
    XCTAssertNotNil(handle, "Expected trailing slash URL to parse successfully")
    XCTAssertEqual(handle?.owner, "google")
    XCTAssertEqual(handle?.modelSlug, "gemma-3n")
  }

  // MARK: - Reject Non-Kaggle URLs

  func testRejectNonKaggleURL() {
    let handle = KaggleModelParser.parseURL(
      "https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm"
    )
    XCTAssertNil(handle, "Expected non-Kaggle URL to return nil")
  }

  // MARK: - Reject Invalid Kaggle Paths

  func testRejectInvalidKagglePath() {
    let handle = KaggleModelParser.parseURL(
      "https://www.kaggle.com/datasets/zillow/zecon"
    )
    XCTAssertNil(handle, "Expected Kaggle datasets URL to return nil (only /models/ supported)")
  }

  func testRejectKaggleRootURL() {
    let handle = KaggleModelParser.parseURL("https://www.kaggle.com/")
    XCTAssertNil(handle, "Expected Kaggle root URL to return nil")
  }

  func testRejectKaggleModelsOnlyPath() {
    let handle = KaggleModelParser.parseURL("https://www.kaggle.com/models")
    XCTAssertNil(handle, "Expected /models with no owner/slug to return nil")
  }

  func testRejectEmptyString() {
    let handle = KaggleModelParser.parseURL("")
    XCTAssertNil(handle, "Expected empty string to return nil")
  }

  func testRejectGarbageString() {
    let handle = KaggleModelParser.parseURL("not a url at all")
    XCTAssertNil(handle, "Expected garbage string to return nil")
  }

  // MARK: - Parse Without WWW

  func testParseKaggleURLWithoutWWW() {
    let handle = KaggleModelParser.parseURL(
      "https://kaggle.com/models/google/gemma-3n"
    )
    XCTAssertNotNil(handle, "Expected kaggle.com (without www) to parse successfully")
    XCTAssertEqual(handle?.owner, "google")
    XCTAssertEqual(handle?.modelSlug, "gemma-3n")
  }

  // MARK: - Download URL Construction

  func testBuildDownloadURL_fullHandle() {
    let handle = KaggleModelHandle(
      owner: "google",
      modelSlug: "gemma",
      framework: "litert",
      variation: "gemma-3n-e4b-it",
      version: 1
    )
    let url = KaggleModelParser.buildDownloadURL(handle: handle)
    XCTAssertNotNil(url)
    XCTAssertEqual(
      url?.absoluteString,
      "https://www.kaggle.com/api/v1/models/google/gemma/litert/gemma-3n-e4b-it/1/download"
    )
  }

  func testBuildDownloadURL_basicHandle() {
    let handle = KaggleModelHandle(
      owner: "google",
      modelSlug: "gemma-3n",
      framework: nil,
      variation: nil,
      version: nil
    )
    let url = KaggleModelParser.buildDownloadURL(handle: handle)
    XCTAssertNil(url, "Expected nil when framework/variation/version are missing")
  }

  // MARK: - Auth Header

  func testBasicAuthHeader() {
    let header = KaggleModelParser.buildAuthHeader(username: "myuser", apiKey: "abc123key")
    // Expected: "Basic " + base64("myuser:abc123key")
    let expectedCredentials = Data("myuser:abc123key".utf8).base64EncodedString()
    XCTAssertEqual(header, "Basic \(expectedCredentials)")
  }

  func testBasicAuthHeader_encoding() {
    let header = KaggleModelParser.buildAuthHeader(username: "user", apiKey: "key")
    // "user:key" in base64 is "dXNlcjprZXk="
    XCTAssertEqual(header, "Basic dXNlcjprZXk=")
  }
}
