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

// MARK: - Perceptual Distinctness Tests

/// Verifies that semantically distinct colors in the design system are
/// perceptually distinguishable, using CIE76 ΔE in L*a*b* color space.
///
/// Thresholds:
/// - Functional groups (status colors, capability badges): ΔE ≥ 12
/// - Text hierarchy: ΔE ≥ 8
/// - Surface layers: ΔE ≥ 4 (intentionally close, but still separable)
///
/// Added July 2026 after audit found 5 color pairs below their thresholds.
@Suite("Design System Perceptual Distinctness")
struct DesignSystemDistinctnessTests {

    // MARK: - CIE76 ΔE Calculation

    /// Linearize a single sRGB channel value (0.0–1.0).
    private static func linearize(_ c: CGFloat) -> CGFloat {
        c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    /// Convert sRGB (0–1) to CIE L*a*b* via XYZ (D65 illuminant).
    private static func toLab(r: CGFloat, g: CGFloat, b: CGFloat) -> (L: CGFloat, a: CGFloat, b: CGFloat) {
        let rl = linearize(r), gl = linearize(g), bl = linearize(b)
        let x = (0.4124564 * rl + 0.3575761 * gl + 0.1804375 * bl) / 0.95047
        let y = 0.2126729 * rl + 0.7151522 * gl + 0.0721750 * bl  // yn = 1.0
        let z = (0.0193339 * rl + 0.1191920 * gl + 0.9503041 * bl) / 1.08883

        func f(_ t: CGFloat) -> CGFloat {
            t > 0.008856 ? pow(t, 1.0 / 3.0) : 7.787 * t + 16.0 / 116.0
        }
        let L = 116.0 * f(y) - 16.0
        let a = 500.0 * (f(x) - f(y))
        let bVal = 200.0 * (f(y) - f(z))
        return (L, a, bVal)
    }

    /// CIE76 ΔE between two sRGB colors.
    private static func deltaE(_ c1: Color, _ c2: Color) -> CGFloat? {
        guard let comp1 = extractComponents(from: c1),
              let comp2 = extractComponents(from: c2) else { return nil }
        let lab1 = toLab(r: comp1.red, g: comp1.green, b: comp1.blue)
        let lab2 = toLab(r: comp2.red, g: comp2.green, b: comp2.blue)
        let dL = lab1.L - lab2.L
        let da = lab1.a - lab2.a
        let db = lab1.b - lab2.b
        return sqrt(dL * dL + da * da + db * db)
    }

    /// Extract RGBA from a SwiftUI Color.
    private static func extractComponents(from color: Color) -> (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat)? {
        #if os(macOS)
        guard let nsColor = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        nsColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (r, g, b, a)
        #elseif os(iOS)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        let uiColor = UIColor(color)
        guard uiColor.getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        return (r, g, b, a)
        #endif
    }

    // MARK: - AccentColor / accentPrimary Identity (Issue 1)

    @Test("AccentColor asset matches accentPrimary — must stay in sync")
    func accentColorSyncedWithAccentPrimary() throws {
        let accent = Color("AccentColor")
        let primary = AppColors.accentPrimary

        #if os(macOS)
        guard let a = NSColor(accent).usingColorSpace(.sRGB),
              let p = NSColor(primary).usingColorSpace(.sRGB) else {
            Issue.record("Could not resolve AccentColor or accentPrimary to sRGB")
            return
        }
        var aR: CGFloat = 0, aG: CGFloat = 0, aB: CGFloat = 0, aA: CGFloat = 0
        var pR: CGFloat = 0, pG: CGFloat = 0, pB: CGFloat = 0, pA: CGFloat = 0
        a.getRed(&aR, green: &aG, blue: &aB, alpha: &aA)
        p.getRed(&pR, green: &pG, blue: &pB, alpha: &pA)
        #elseif os(iOS)
        let a = UIColor(accent)
        let p = UIColor(primary)
        var aR: CGFloat = 0, aG: CGFloat = 0, aB: CGFloat = 0, aA: CGFloat = 0
        var pR: CGFloat = 0, pG: CGFloat = 0, pB: CGFloat = 0, pA: CGFloat = 0
        guard a.getRed(&aR, green: &aG, blue: &aB, alpha: &aA),
              p.getRed(&pR, green: &pG, blue: &pB, alpha: &pA) else {
            Issue.record("Could not extract components from AccentColor or accentPrimary")
            return
        }
        #endif

        #expect(abs(aR - pR) < 0.005, "AccentColor red \(aR) != accentPrimary red \(pR)")
        #expect(abs(aG - pG) < 0.005, "AccentColor green \(aG) != accentPrimary green \(pG)")
        #expect(abs(aB - pB) < 0.005, "AccentColor blue \(aB) != accentPrimary blue \(pB)")
    }

    // MARK: - Text Hierarchy (Issue 2) — min ΔE ≥ 8

    @Test("textSecondary ↔ textTertiary perceptually distinct (ΔE ≥ 8)")
    func textSecondaryVsTertiaryDistinct() throws {
        let de = try #require(Self.deltaE(AppColors.textSecondary, AppColors.textTertiary))
        #expect(de >= 8.0, "textSecondary ↔ textTertiary ΔE \(String(format: "%.1f", de)) is below minimum 8.0")
    }

    @Test("textPrimary ↔ textSecondary perceptually distinct (ΔE ≥ 8)")
    func textPrimaryVsSecondaryDistinct() throws {
        let de = try #require(Self.deltaE(AppColors.textPrimary, AppColors.textSecondary))
        #expect(de >= 8.0, "textPrimary ↔ textSecondary ΔE \(String(format: "%.1f", de)) is below minimum 8.0")
    }

    // MARK: - Capability Badges — min ΔE ≥ 25 (badge-size needs high separation)

    @Test("capabilityVision ↔ toolAction perceptually distinct (ΔE ≥ 25)")
    func capabilityVisionVsToolActionDistinct() throws {
        let de = try #require(Self.deltaE(AppColors.capabilityVision, AppColors.toolAction))
        #expect(de >= 25.0, "capabilityVision ↔ toolAction ΔE \(String(format: "%.1f", de)) is below minimum 25.0")
    }

    @Test("capabilityAudio ↔ capabilityThinking perceptually distinct (ΔE ≥ 25)")
    func capabilityAudioVsThinkingDistinct() throws {
        let de = try #require(Self.deltaE(AppColors.capabilityAudio, AppColors.capabilityThinking))
        #expect(de >= 25.0, "capabilityAudio ↔ capabilityThinking ΔE \(String(format: "%.1f", de)) is below minimum 25.0")
    }

    @Test("capabilityAudio ↔ toolAction perceptually distinct (ΔE ≥ 25)")
    func capabilityAudioVsToolActionDistinct() throws {
        let de = try #require(Self.deltaE(AppColors.capabilityAudio, AppColors.toolAction))
        #expect(de >= 25.0, "capabilityAudio ↔ toolAction ΔE \(String(format: "%.1f", de)) is below minimum 25.0")
    }

    @Test("capabilityVision ↔ capabilityAudio perceptually distinct (ΔE ≥ 25)")
    func capabilityVisionVsAudioDistinct() throws {
        let de = try #require(Self.deltaE(AppColors.capabilityVision, AppColors.capabilityAudio))
        #expect(de >= 25.0, "capabilityVision ↔ capabilityAudio ΔE \(String(format: "%.1f", de)) is below minimum 25.0")
    }

    @Test("capabilityThinking ↔ accentSecondary perceptually distinct (ΔE ≥ 25)")
    func capabilityThinkingVsBenchmarkDistinct() throws {
        let de = try #require(Self.deltaE(AppColors.capabilityThinking, AppColors.accentSecondary))
        #expect(de >= 25.0, "capabilityThinking ↔ accentSecondary ΔE \(String(format: "%.1f", de)) is below minimum 25.0 — badge must not look like benchmark icon")
    }

    @Test("capabilityMTP ↔ accentPrimary perceptually distinct (ΔE ≥ 15)")
    func capabilityMTPVsBrandDistinct() throws {
        let de = try #require(Self.deltaE(AppColors.capabilityMTP, AppColors.accentPrimary))
        #expect(de >= 15.0, "capabilityMTP ↔ accentPrimary ΔE \(String(format: "%.1f", de)) is below minimum 15.0 — teal neighbors")
    }

    // MARK: - Semantic Status Colors — min ΔE ≥ 20 (brand) / ≥ 12 (status chain)

    @Test("accentPrimary ↔ success perceptually distinct (ΔE ≥ 20)")
    func accentPrimaryVsSuccessDistinct() throws {
        let de = try #require(Self.deltaE(AppColors.accentPrimary, AppColors.success))
        #expect(de >= 20.0, "accentPrimary ↔ success ΔE \(String(format: "%.1f", de)) is below minimum 20.0 — brand must not look like success green")
    }

    @Test("accentSecondary ↔ warning perceptually distinct (ΔE ≥ 12)")
    func accentSecondaryVsWarningDistinct() throws {
        let de = try #require(Self.deltaE(AppColors.accentSecondary, AppColors.warning))
        #expect(de >= 12.0, "accentSecondary ↔ warning ΔE \(String(format: "%.1f", de)) is below minimum 12.0")
    }

    @Test("warning ↔ destructive perceptually distinct (ΔE ≥ 12)")
    func warningVsDestructiveDistinct() throws {
        let de = try #require(Self.deltaE(AppColors.warning, AppColors.destructive))
        #expect(de >= 12.0, "warning ↔ destructive ΔE \(String(format: "%.1f", de)) is below minimum 12.0")
    }

    // MARK: - Reasoning ↔ Thinking — min ΔE ≥ 20 (same family, different layers)

    @Test("reasoning ↔ capabilityThinking perceptually distinct (ΔE ≥ 20)")
    func reasoningVsThinkingDistinct() throws {
        let de = try #require(Self.deltaE(AppColors.reasoning, AppColors.capabilityThinking))
        #expect(de >= 20.0, "reasoning ↔ capabilityThinking ΔE \(String(format: "%.1f", de)) is below minimum 20.0 — same concept, different usage layers")
    }

    @Test("reasoning ↔ accentPrimary perceptually distinct (ΔE ≥ 20)")
    func reasoningVsBrandDistinct() throws {
        let de = try #require(Self.deltaE(AppColors.reasoning, AppColors.accentPrimary))
        #expect(de >= 20.0, "reasoning ↔ accentPrimary ΔE \(String(format: "%.1f", de)) is below minimum 20.0")
    }

    // MARK: - Chat Bubble Surfaces — min ΔE ≥ 4

    @Test("assistantBubble ↔ backgroundSecondary perceptually distinct (ΔE ≥ 4)")
    func assistantBubbleVsBackgroundSecondary() throws {
        let de = try #require(Self.deltaE(AppColors.assistantBubble, AppColors.backgroundSecondary))
        #expect(de >= 4.0, "assistantBubble ↔ backgroundSecondary ΔE \(String(format: "%.1f", de)) is below minimum 4.0")
    }

    @Test("userBubbleStart ↔ userBubbleEnd gradient visible (ΔE ≥ 4)")
    func userBubbleGradientVisible() throws {
        let de = try #require(Self.deltaE(AppColors.userBubbleStart, AppColors.userBubbleEnd))
        #expect(de >= 4.0, "userBubbleStart ↔ userBubbleEnd ΔE \(String(format: "%.1f", de)) is below minimum 4.0 — gradient invisible")
    }

    // MARK: - Engine Badge Colors — min ΔE ≥ 15

    @Test("engineLiteRT ↔ engineGGUF perceptually distinct (ΔE ≥ 15)")
    func engineLiteRTVsGGUFDistinct() throws {
        let de = try #require(Self.deltaE(AppColors.engineLiteRT, AppColors.engineGGUF))
        #expect(de >= 15.0, "engineLiteRT ↔ engineGGUF ΔE \(String(format: "%.1f", de)) is below minimum 15.0")
    }

    @Test("engineLiteRT ↔ success distinct — engine ≠ status (ΔE ≥ 15)")
    func engineLiteRTVsSuccessDistinct() throws {
        let de = try #require(Self.deltaE(AppColors.engineLiteRT, AppColors.success))
        #expect(de >= 15.0, "engineLiteRT ↔ success ΔE \(String(format: "%.1f", de)) is below minimum 15.0")
    }

    @Test("engineLiteRT ↔ accentPrimary distinct — engine ≠ brand (ΔE ≥ 15)")
    func engineLiteRTVsBrandDistinct() throws {
        let de = try #require(Self.deltaE(AppColors.engineLiteRT, AppColors.accentPrimary))
        #expect(de >= 15.0, "engineLiteRT ↔ accentPrimary ΔE \(String(format: "%.1f", de)) is below minimum 15.0")
    }

    @Test("engineGGUF ↔ accentPrimary distinct — engine ≠ brand (ΔE ≥ 15)")
    func engineGGUFVsBrandDistinct() throws {
        let de = try #require(Self.deltaE(AppColors.engineGGUF, AppColors.accentPrimary))
        #expect(de >= 15.0, "engineGGUF ↔ accentPrimary ΔE \(String(format: "%.1f", de)) is below minimum 15.0")
    }

    @Test("engineLiteRT ↔ destructive distinct — engine ≠ error (ΔE ≥ 15)")
    func engineLiteRTVsDestructiveDistinct() throws {
        let de = try #require(Self.deltaE(AppColors.engineLiteRT, AppColors.destructive))
        #expect(de >= 15.0, "engineLiteRT ↔ destructive ΔE \(String(format: "%.1f", de)) is below minimum 15.0")
    }
}
