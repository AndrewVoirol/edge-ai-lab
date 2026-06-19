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
import Testing

#if os(iOS)
@testable import EdgeAILab_iOS
#elseif os(macOS)
@testable import EdgeAILab_macOS
#endif

@Suite("ModelDetailFormatters")
struct ModelDetailFormattersTests {

    // MARK: - formattedContextWindow

    @Test(
        "formattedContextWindow formats sizes correctly",
        arguments: [
            (0, "0 ctx"),
            (500, "500 ctx"),
            (1_000, "1K ctx"),
            (8_192, "8K ctx"),
            (32_768, "32K ctx"),
            (1_000_000, "1M ctx"),
            (2_000_000, "2M ctx"),
        ] as [(Int, String)]
    )
    func formattedContextWindow(size: Int, expected: String) {
        #expect(ModelDetailFormatters.formattedContextWindow(size) == expected)
    }

    @Test("formattedContextWindow handles negative value")
    func formattedContextWindowNegative() {
        // Negative values fall through to the else branch.
        let result = ModelDetailFormatters.formattedContextWindow(-1)
        #expect(result == "-1 ctx")
    }

    @Test("formattedContextWindow handles Int.max")
    func formattedContextWindowIntMax() {
        let result = ModelDetailFormatters.formattedContextWindow(Int.max)
        #expect(result.hasSuffix("M ctx"))
    }

    // MARK: - formattedSize

    @Test(
        "formattedSize formats byte counts correctly",
        arguments: [
            (Int64(0), "KB"),
            (Int64(1_024), "KB"),
            (Int64(1_048_576), "MB"),
            (Int64(5_368_709_120), "GB"),
        ] as [(Int64, String)]
    )
    func formattedSize(bytes: Int64, expectedUnit: String) {
        let result = ModelDetailFormatters.formattedSize(bytes)
        #expect(result.contains(expectedUnit), "Expected '\(result)' to contain '\(expectedUnit)'")
    }

    @Test("formattedSize handles negative bytes")
    func formattedSizeNegative() {
        // ByteCountFormatter handles negatives; just ensure no crash.
        let result = ModelDetailFormatters.formattedSize(-1)
        #expect(!result.isEmpty)
    }

    @Test("formattedSize handles Int64.max")
    func formattedSizeMax() {
        let result = ModelDetailFormatters.formattedSize(Int64.max)
        #expect(!result.isEmpty)
    }
}
