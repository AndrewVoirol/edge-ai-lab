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

#if os(iOS)
@testable import EdgeAILab_iOS
#elseif os(macOS)
@testable import EdgeAILab_macOS
#endif

@MainActor
final class DeveloperAutomationHarnessTests: XCTestCase {

    func testSafeSamplerConfigReturnsFallbackOnInvalidInput() {
        // Attempting an invalid config (e.g. topP > 1.0) should not crash,
        // it should return a safe default.
        let config = DeveloperAutomationHarness.safeSamplerConfig(topK: 1, topP: 1.5, temperature: 1.0)
        XCTAssertEqual(config.topK, 1)
        XCTAssertEqual(config.topP, 1.0) // fallback value
    }

    func testSafeCachesDirectoryReturnsValidURL() {
        // We ensure that we can safely resolve a caches directory without a forced unwrap.
        let url = DeveloperAutomationHarness.safeCachesDirectory()
        XCTAssertNotNil(url)
        XCTAssertTrue(url.path.contains("Caches"))
    }
}
