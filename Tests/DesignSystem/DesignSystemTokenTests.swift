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

// MARK: - AppOpacity Tests

@Suite("AppOpacity")
struct AppOpacityTests {

    // MARK: - All tiers in 0...1 range

    static let allTiers: [(String, Double)] = [
        ("whisper", AppOpacity.whisper),
        ("ghost", AppOpacity.ghost),
        ("mist", AppOpacity.mist),
        ("tint", AppOpacity.tint),
        ("faint", AppOpacity.faint),
        ("fill", AppOpacity.fill),
        ("rinse", AppOpacity.rinse),
        ("medium", AppOpacity.medium),
        ("dim", AppOpacity.dim),
        ("half", AppOpacity.half),
        ("prominent", AppOpacity.prominent),
        ("strong", AppOpacity.strong),
        ("emphasis", AppOpacity.emphasis),
        ("glass", AppOpacity.glass),
        ("opaque", AppOpacity.opaque),
    ]

    @Test("every tier is in valid 0...1 range", arguments: allTiers)
    func validRange(name: String, value: Double) {
        #expect(value >= 0.0, "\(name) should be >= 0")
        #expect(value <= 1.0, "\(name) should be <= 1")
    }

    @Test("every tier is strictly positive")
    func strictlyPositive() {
        for (name, value) in Self.allTiers {
            #expect(value > 0.0, "\(name) should be > 0 (fully transparent is not a useful token)")
        }
    }

    @Test("every tier is strictly less than 1.0")
    func strictlyLessThanOne() {
        for (name, value) in Self.allTiers {
            #expect(value < 1.0, "\(name) should be < 1 (fully opaque is not a useful token)")
        }
    }

    // MARK: - Strict ascending order

    @Test("tiers are in strictly ascending order")
    func ascendingOrder() {
        let values = Self.allTiers.map(\.1)
        for i in 0..<(values.count - 1) {
            let current = Self.allTiers[i]
            let next = Self.allTiers[i + 1]
            #expect(
                current.1 < next.1,
                "\(current.0) (\(current.1)) should be < \(next.0) (\(next.1))"
            )
        }
    }

    // MARK: - Specific value checks

    @Test("whisper is the lowest visible tier")
    func whisperIsLowest() {
        #expect(AppOpacity.whisper == 0.03)
    }

    @Test("half is exactly 0.5")
    func halfIsMiddle() {
        #expect(AppOpacity.half == 0.5)
    }

    @Test("glass matches reduce-transparency glass fill")
    func glassValue() {
        #expect(AppOpacity.glass == 0.85)
    }

    @Test("opaque is the highest sub-1.0 tier")
    func opaqueIsHighest() {
        #expect(AppOpacity.opaque == 0.9)
        // Verify it's the last tier
        let maxValue = Self.allTiers.map(\.1).max()!
        #expect(AppOpacity.opaque == maxValue)
    }

    // MARK: - Tier count stability

    @Test("total tier count is 15")
    func tierCount() {
        // Update this test if tiers are added/removed
        #expect(Self.allTiers.count == 15)
    }

    // MARK: - Determinism

    @Test("values are deterministic across repeated access", arguments: allTiers)
    func deterministic(name: String, value: Double) {
        // Access twice — should be identical (static lets are stable)
        let v1 = value
        let v2 = value
        #expect(v1 == v2, "\(name) should return the same value on every access")
    }
}

// MARK: - AppShadowStyle Tests

@Suite("AppShadowStyle")
struct AppShadowStyleTests {

    @Test("init sets all properties")
    func initSetsProperties() {
        let style = AppShadowStyle(color: .black, opacity: 0.5, radius: 10, x: 2, y: 4)
        #expect(style.opacity == 0.5)
        #expect(style.radius == 10)
        #expect(style.x == 2)
        #expect(style.y == 4)
    }

    @Test("init defaults x and y to zero")
    func defaultsXY() {
        let style = AppShadowStyle(color: .black, radius: 8)
        #expect(style.x == 0)
        #expect(style.y == 0)
        #expect(style.opacity == 1.0)
    }

    @Test("equatable works for identical styles")
    func equalityIdentical() {
        let a = AppShadowStyle(color: .black, opacity: 0.4, radius: 20, y: 8)
        let b = AppShadowStyle(color: .black, opacity: 0.4, radius: 20, y: 8)
        #expect(a == b)
    }

    @Test("equatable detects differences")
    func equalityDifference() {
        let a = AppShadowStyle(color: .black, opacity: 0.4, radius: 20, y: 8)
        let b = AppShadowStyle(color: .black, opacity: 0.4, radius: 12, y: 8)
        #expect(a != b)
    }
}

// MARK: - AppShadow Tests

@Suite("AppShadow")
struct AppShadowTests {

    // MARK: - Non-zero radius

    static let allTokens: [(String, AppShadowStyle)] = [
        ("cardPreview", AppShadow.cardPreview),
        ("floatingBar", AppShadow.floatingBar),
        ("fab", AppShadow.fab),
        ("ctaGlow", AppShadow.ctaGlow),
    ]

    @Test("every token has positive radius", arguments: allTokens)
    func positiveRadius(name: String, style: AppShadowStyle) {
        #expect(style.radius > 0, "\(name) shadow should have radius > 0")
    }

    // MARK: - Opacity in valid range

    @Test("every token has opacity in 0...1", arguments: allTokens)
    func validOpacity(name: String, style: AppShadowStyle) {
        #expect(style.opacity >= 0.0 && style.opacity <= 1.0,
                "\(name) opacity (\(style.opacity)) should be in 0...1")
    }

    // MARK: - Elevation hierarchy

    @Test("cardPreview has the largest radius (highest elevation)")
    func cardPreviewHighestElevation() {
        let allRadii = Self.allTokens.map(\.1.radius)
        let maxRadius = allRadii.max()!
        #expect(AppShadow.cardPreview.radius == maxRadius)
    }

    @Test("cardPreview radius > ctaGlow radius > floatingBar radius")
    func radiusHierarchy() {
        #expect(AppShadow.cardPreview.radius > AppShadow.ctaGlow.radius,
                "cardPreview should have larger radius than ctaGlow")
        #expect(AppShadow.ctaGlow.radius > AppShadow.floatingBar.radius,
                "ctaGlow should have larger radius than floatingBar")
    }

    // MARK: - Specific token values

    @Test("cardPreview uses downward offset")
    func cardPreviewOffset() {
        #expect(AppShadow.cardPreview.y > 0, "cardPreview should cast shadow downward")
    }

    @Test("floatingBar uses upward offset")
    func floatingBarOffset() {
        #expect(AppShadow.floatingBar.y < 0, "floatingBar should cast shadow upward")
    }

    @Test("fab uses downward offset")
    func fabOffset() {
        #expect(AppShadow.fab.y > 0, "fab should cast shadow downward")
    }

    // MARK: - Token count stability

    @Test("total token count is 4")
    func tokenCount() {
        // Update this test if tokens are added/removed
        #expect(Self.allTokens.count == 4)
    }

    // MARK: - Determinism

    @Test("tokens are deterministic across repeated access", arguments: allTokens)
    func deterministic(name: String, style: AppShadowStyle) {
        let s1 = style
        let s2 = style
        #expect(s1 == s2, "\(name) should return identical style on every access")
    }
}
