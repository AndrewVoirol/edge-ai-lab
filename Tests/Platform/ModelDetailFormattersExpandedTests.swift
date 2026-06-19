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

@Suite("ModelDetailFormatters — Token & Download Count")
struct ModelDetailFormattersExpandedTests {

    // MARK: - formatTokenCount

    @Suite("formatTokenCount")
    struct TokenCountTests {
        @Test("Millions format correctly")
        func millions() {
            #expect(ModelDetailFormatters.formatTokenCount(1_000_000) == "1M")
            #expect(ModelDetailFormatters.formatTokenCount(2_500_000) == "2M")
        }

        @Test("Thousands format correctly")
        func thousands() {
            #expect(ModelDetailFormatters.formatTokenCount(128_000) == "128K")
            #expect(ModelDetailFormatters.formatTokenCount(256_000) == "256K")
            #expect(ModelDetailFormatters.formatTokenCount(32_000) == "32K")
            #expect(ModelDetailFormatters.formatTokenCount(1_000) == "1K")
        }

        @Test("Small values return raw number")
        func small() {
            #expect(ModelDetailFormatters.formatTokenCount(999) == "999")
            #expect(ModelDetailFormatters.formatTokenCount(0) == "0")
            #expect(ModelDetailFormatters.formatTokenCount(1) == "1")
        }
    }

    // MARK: - formatDownloadCount

    @Suite("formatDownloadCount")
    struct DownloadCountTests {
        @Test("Millions format with one decimal")
        func millions() {
            #expect(ModelDetailFormatters.formatDownloadCount(1_500_000) == "1.5M")
            #expect(ModelDetailFormatters.formatDownloadCount(1_000_000) == "1.0M")
        }

        @Test("Thousands format with one decimal")
        func thousands() {
            #expect(ModelDetailFormatters.formatDownloadCount(12_345) == "12.3K")
            #expect(ModelDetailFormatters.formatDownloadCount(1_000) == "1.0K")
        }

        @Test("Small values return raw number")
        func small() {
            #expect(ModelDetailFormatters.formatDownloadCount(999) == "999")
            #expect(ModelDetailFormatters.formatDownloadCount(0) == "0")
        }
    }
}
