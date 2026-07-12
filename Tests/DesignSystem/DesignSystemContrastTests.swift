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

// MARK: - WCAG Contrast Verification Tests

/// Programmatic WCAG 2.1 AA contrast verification for all design system color pairings.
///
/// Ensures all documented foreground/background combinations meet:
/// - ≥ 4.5:1 for normal body text (AA normal)
/// - ≥ 3.0:1 for large text and UI components (AA large)
///
/// Uses the WCAG 2.1 relative luminance formula:
/// L = 0.2126 * R_lin + 0.7152 * G_lin + 0.0722 * B_lin
/// where R_lin = (R/255 ≤ 0.04045) ? R/12.92 : ((R+0.055)/1.055)^2.4
@Suite("Design System Contrast Verification")
struct DesignSystemContrastTests {

    // MARK: - WCAG Calculation Helpers

    /// Linearize a single sRGB channel value (0.0–1.0) for luminance calculation.
    private static func linearize(_ channel: CGFloat) -> CGFloat {
        if channel <= 0.04045 {
            return channel / 12.92
        } else {
            return pow((channel + 0.055) / 1.055, 2.4)
        }
    }

    /// Calculate WCAG 2.1 relative luminance from sRGB components (0.0–1.0).
    private static func relativeLuminance(red: CGFloat, green: CGFloat, blue: CGFloat) -> CGFloat {
        let rLin = linearize(red)
        let gLin = linearize(green)
        let bLin = linearize(blue)
        return 0.2126 * rLin + 0.7152 * gLin + 0.0722 * bLin
    }

    /// Calculate WCAG 2.1 contrast ratio between two luminance values.
    /// Result is always ≥ 1.0, with higher values indicating more contrast.
    private static func contrastRatio(l1: CGFloat, l2: CGFloat) -> CGFloat {
        let lighter = max(l1, l2)
        let darker = min(l1, l2)
        return (lighter + 0.05) / (darker + 0.05)
    }

    /// Extract RGBA components from a SwiftUI Color.
    /// Returns nil if the color cannot be resolved (e.g., dynamic colors in certain contexts).
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

    /// Calculate the effective color when a foreground with alpha is composited over a background.
    /// Uses the standard alpha compositing formula: result = fg * alpha + bg * (1 - alpha)
    private static func composite(
        foreground: (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat),
        over background: (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat)
    ) -> (red: CGFloat, green: CGFloat, blue: CGFloat) {
        let a = foreground.alpha
        return (
            red: foreground.red * a + background.red * (1 - a),
            green: foreground.green * a + background.green * (1 - a),
            blue: foreground.blue * a + background.blue * (1 - a)
        )
    }

    /// Calculate the WCAG contrast ratio between a foreground and background color.
    /// Handles alpha compositing for translucent foreground colors.
    private static func contrast(foreground: Color, background: Color) -> CGFloat? {
        guard let fg = extractComponents(from: foreground),
              let bg = extractComponents(from: background) else { return nil }

        // If foreground has alpha < 1, composite it over the background
        let effectiveFg: (red: CGFloat, green: CGFloat, blue: CGFloat)
        if fg.alpha < 1.0 {
            effectiveFg = composite(foreground: fg, over: bg)
        } else {
            effectiveFg = (fg.red, fg.green, fg.blue)
        }

        let fgL = relativeLuminance(red: effectiveFg.red, green: effectiveFg.green, blue: effectiveFg.blue)
        let bgL = relativeLuminance(red: bg.red, green: bg.green, blue: bg.blue)
        return contrastRatio(l1: fgL, l2: bgL)
    }

    // MARK: - Body Text Contrast (≥ 4.5:1 AA)

    @Test("textPrimary on backgroundPrimary meets AA body text (≥ 4.5:1)")
    func textPrimaryOnBackgroundPrimary() throws {
        let ratio = try #require(Self.contrast(foreground: AppColors.textPrimary, background: AppColors.backgroundPrimary))
        #expect(ratio >= 4.5, "textPrimary/backgroundPrimary contrast \(String(format: "%.2f", ratio)):1 is below WCAG AA 4.5:1")
    }

    @Test("textPrimary on backgroundSecondary meets AA body text (≥ 4.5:1)")
    func textPrimaryOnBackgroundSecondary() throws {
        let ratio = try #require(Self.contrast(foreground: AppColors.textPrimary, background: AppColors.backgroundSecondary))
        #expect(ratio >= 4.5, "textPrimary/backgroundSecondary contrast \(String(format: "%.2f", ratio)):1 is below WCAG AA 4.5:1")
    }

    @Test("textSecondary on backgroundPrimary meets AA body text (≥ 4.5:1)")
    func textSecondaryOnBackgroundPrimary() throws {
        let ratio = try #require(Self.contrast(foreground: AppColors.textSecondary, background: AppColors.backgroundPrimary))
        #expect(ratio >= 4.5, "textSecondary/backgroundPrimary contrast \(String(format: "%.2f", ratio)):1 is below WCAG AA 4.5:1")
    }

    @Test("textSecondary on backgroundSecondary meets AA body text (≥ 4.5:1)")
    func textSecondaryOnBackgroundSecondary() throws {
        let ratio = try #require(Self.contrast(foreground: AppColors.textSecondary, background: AppColors.backgroundSecondary))
        #expect(ratio >= 4.5, "textSecondary/backgroundSecondary contrast \(String(format: "%.2f", ratio)):1 is below WCAG AA 4.5:1")
    }

    @Test("textTertiary on backgroundPrimary meets AA body text (≥ 4.5:1)")
    func textTertiaryOnBackgroundPrimary() throws {
        let ratio = try #require(Self.contrast(foreground: AppColors.textTertiary, background: AppColors.backgroundPrimary))
        #expect(ratio >= 4.5, "textTertiary/backgroundPrimary contrast \(String(format: "%.2f", ratio)):1 is below WCAG AA 4.5:1")
    }

    @Test("textPrimary on assistantBubble meets AA body text (≥ 4.5:1)")
    func textPrimaryOnAssistantBubble() throws {
        let ratio = try #require(Self.contrast(foreground: AppColors.textPrimary, background: AppColors.assistantBubble))
        #expect(ratio >= 4.5, "textPrimary/assistantBubble contrast \(String(format: "%.2f", ratio)):1 is below WCAG AA 4.5:1")
    }

    @Test("textPrimary on userBubbleStart meets AA body text (≥ 4.5:1)")
    func textPrimaryOnUserBubble() throws {
        let ratio = try #require(Self.contrast(foreground: AppColors.textPrimary, background: AppColors.userBubbleStart))
        #expect(ratio >= 4.5, "textPrimary/userBubbleStart contrast \(String(format: "%.2f", ratio)):1 is below WCAG AA 4.5:1")
    }

    // MARK: - Large Text / UI Component Contrast (≥ 3.0:1 AA)

    @Test("accentPrimary on backgroundPrimary meets AA large text (≥ 3:1)")
    func accentPrimaryOnBackgroundPrimary() throws {
        let ratio = try #require(Self.contrast(foreground: AppColors.accentPrimary, background: AppColors.backgroundPrimary))
        #expect(ratio >= 3.0, "accentPrimary/backgroundPrimary contrast \(String(format: "%.2f", ratio)):1 is below WCAG AA 3:1")
    }

    @Test("accentSecondary on backgroundPrimary meets AA large text (≥ 3:1)")
    func accentSecondaryOnBackgroundPrimary() throws {
        let ratio = try #require(Self.contrast(foreground: AppColors.accentSecondary, background: AppColors.backgroundPrimary))
        #expect(ratio >= 3.0, "accentSecondary/backgroundPrimary contrast \(String(format: "%.2f", ratio)):1 is below WCAG AA 3:1")
    }

    @Test("destructive on backgroundPrimary meets AA large text (≥ 3:1)")
    func destructiveOnBackgroundPrimary() throws {
        let ratio = try #require(Self.contrast(foreground: AppColors.destructive, background: AppColors.backgroundPrimary))
        #expect(ratio >= 3.0, "destructive/backgroundPrimary contrast \(String(format: "%.2f", ratio)):1 is below WCAG AA 3:1")
    }

    @Test("warning on backgroundPrimary meets AA large text (≥ 3:1)")
    func warningOnBackgroundPrimary() throws {
        let ratio = try #require(Self.contrast(foreground: AppColors.warning, background: AppColors.backgroundPrimary))
        #expect(ratio >= 3.0, "warning/backgroundPrimary contrast \(String(format: "%.2f", ratio)):1 is below WCAG AA 3:1")
    }

    @Test("success on backgroundPrimary meets AA large text (≥ 3:1)")
    func successOnBackgroundPrimary() throws {
        let ratio = try #require(Self.contrast(foreground: AppColors.success, background: AppColors.backgroundPrimary))
        #expect(ratio >= 3.0, "success/backgroundPrimary contrast \(String(format: "%.2f", ratio)):1 is below WCAG AA 3:1")
    }

    @Test("reasoning on backgroundPrimary meets AA large text (≥ 3:1)")
    func reasoningOnBackgroundPrimary() throws {
        let ratio = try #require(Self.contrast(foreground: AppColors.reasoning, background: AppColors.backgroundPrimary))
        #expect(ratio >= 3.0, "reasoning/backgroundPrimary contrast \(String(format: "%.2f", ratio)):1 is below WCAG AA 3:1")
    }

    @Test("toolAction on backgroundPrimary meets AA large text (≥ 3:1)")
    func toolActionOnBackgroundPrimary() throws {
        let ratio = try #require(Self.contrast(foreground: AppColors.toolAction, background: AppColors.backgroundPrimary))
        #expect(ratio >= 3.0, "toolAction/backgroundPrimary contrast \(String(format: "%.2f", ratio)):1 is below WCAG AA 3:1")
    }

    // MARK: - Pre-Composed Opacity Token Contrast (≥ 3.0:1 AA)
    // Verify that the new pre-composed tokens maintain readable contrast

    @Test("textQuaternary on backgroundPrimary meets AA large text (≥ 3:1)")
    func textQuaternaryOnBackgroundPrimary() throws {
        let ratio = try #require(Self.contrast(foreground: AppColors.textQuaternary, background: AppColors.backgroundPrimary))
        #expect(ratio >= 3.0, "textQuaternary/backgroundPrimary contrast \(String(format: "%.2f", ratio)):1 is below WCAG AA 3:1")
    }

    // MARK: - Capability Indicator Contrast (≥ 3.0:1 AA)
    // These appear as small colored pills — must be readable against backgrounds

    @Test("capabilityVision on backgroundSecondary meets AA large text (≥ 3:1)")
    func capabilityVisionContrast() throws {
        let ratio = try #require(Self.contrast(foreground: AppColors.capabilityVision, background: AppColors.backgroundSecondary))
        #expect(ratio >= 3.0, "capabilityVision/backgroundSecondary contrast \(String(format: "%.2f", ratio)):1 is below WCAG AA 3:1")
    }

    @Test("capabilityAudio on backgroundSecondary meets AA large text (≥ 3:1)")
    func capabilityAudioContrast() throws {
        let ratio = try #require(Self.contrast(foreground: AppColors.capabilityAudio, background: AppColors.backgroundSecondary))
        #expect(ratio >= 3.0, "capabilityAudio/backgroundSecondary contrast \(String(format: "%.2f", ratio)):1 is below WCAG AA 3:1")
    }
}
