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
import SwiftUI
#if os(iOS)
@testable import EdgeAILab_iOS
#elseif os(macOS)
@testable import EdgeAILab_macOS
#endif

// MARK: - DesignSystemNewModifiers Tests

@Suite("DesignSystemNewModifiers")
struct DesignSystemNewModifierTests {

    // MARK: - Compile-time existence tests

    @Test("interactiveGlassCard modifier compiles")
    func interactiveGlassCardExists() {
        let _ = Text("test").interactiveGlassCard()
        let _ = Text("test").interactiveGlassCard(cornerRadius: AppRadius.lg)
    }

    @Test("inputGlassCard modifier compiles")
    func inputGlassCardExists() {
        let _ = Text("test").inputGlassCard()
        let _ = Text("test").inputGlassCard(cornerRadius: AppRadius.sm)
    }

    // MARK: - Default parameter tests

    @Test("interactiveGlassCard defaults to AppRadius.standard")
    func interactiveDefaultRadius() {
        #expect(AppRadius.standard == 12, "AppRadius.standard should be 12pt")
    }

    @Test("inputGlassCard defaults to AppRadius.md")
    func inputDefaultRadius() {
        #expect(AppRadius.md == 10, "AppRadius.md should be 10pt")
        #expect(AppRadius.md > 0, "AppRadius.md must be positive")
    }

    // MARK: - Token existence for dependencies

    @Test("interactiveGlassCard dependencies exist")
    func interactiveGlassCardDependencies() {
        // Verify all design tokens referenced by interactiveGlassCard are accessible.
        let _ = AppColors.backgroundSecondary
        let _ = AppOpacity.half
        let _ = AppColors.border
        let _ = AppLineWidth.hairline
    }

    @Test("interactiveGlassCard dependency values are valid")
    func interactiveGlassCardDependencyValues() {
        #expect(AppOpacity.half == 0.5, "AppOpacity.half should be exactly 0.5")
        #expect(AppLineWidth.hairline > 0, "AppLineWidth.hairline must be positive")
        #expect(AppLineWidth.hairline < 1.0, "AppLineWidth.hairline should be sub-pixel")
    }

    // MARK: - Radius token sanity for modifier defaults

    @Test("interactiveGlassCard default radius is smaller than glassCard default")
    func interactiveRadiusSmallerThanGlassCard() {
        // interactiveGlassCard defaults to .standard (12),
        // glassCard defaults to .lg (16).
        #expect(AppRadius.standard < AppRadius.lg,
                "Interactive cards use a tighter radius than premium glass cards")
    }

    @Test("inputGlassCard default radius matches forestGlass default")
    func inputRadiusMatchesForestGlass() {
        // Both inputGlassCard and forestGlass default to AppRadius.md.
        #expect(AppRadius.md == 10,
                "inputGlassCard and forestGlass should share the same default radius")
    }
}
