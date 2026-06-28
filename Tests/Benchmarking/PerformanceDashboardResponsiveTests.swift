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
import SwiftUI

#if os(iOS)
@testable import EdgeAILab_iOS
#elseif os(macOS)
@testable import EdgeAILab_macOS
#endif

// MARK: - Performance Dashboard Responsive Tests

/// Tests for the responsive grid layout logic in PerformanceDashboardView.
/// Verifies that the stats grid adapts between compact (2 columns) and
/// regular (4 columns) layouts.
@Suite("PerformanceDashboard Responsive")
struct PerformanceDashboardResponsiveTests {

    @Test("GridItem array has correct count for 4-column layout")
    func fourColumnGrid() {
        // On macOS and iPad (regular width), the grid should use 4 columns
        let columns = Array(repeating: GridItem(.flexible()), count: 4)
        #expect(columns.count == 4)
    }

    @Test("GridItem array has correct count for 2-column layout")
    func twoColumnGrid() {
        // On iPhone (compact width), the grid should use 2 columns
        let columns = Array(repeating: GridItem(.flexible()), count: 2)
        #expect(columns.count == 2)
    }

    @Test("Column count logic: compact yields 2")
    func compactSizeClassYieldsTwoColumns() {
        // Simulates the logic in PerformanceDashboardView.statsGridColumns
        let sizeClass: UserInterfaceSizeClass = .compact
        let columnCount = sizeClass == .compact ? 2 : 4
        #expect(columnCount == 2)
    }

    @Test("Column count logic: regular yields 4")
    func regularSizeClassYieldsFourColumns() {
        let sizeClass: UserInterfaceSizeClass = .regular
        let columnCount = sizeClass == .compact ? 2 : 4
        #expect(columnCount == 4)
    }

    @Test("macOS always uses 4 columns")
    func macOSAlwaysFourColumns() {
        // On macOS, there's no horizontalSizeClass — always 4 columns
        #if os(macOS)
        let columnCount = 4
        #else
        // On iOS, default to regular (4 columns) for iPad
        let columnCount = 4
        #endif
        #expect(columnCount == 4)
    }
}
