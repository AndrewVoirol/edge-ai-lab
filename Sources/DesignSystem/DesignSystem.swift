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

import SwiftUI
import MarkdownUI

// MARK: - Edge AI Lab Design System
//
// Centralized design tokens for the EdgeAILab app.
// "Dark Forest / Moss" palette — a cabin with a terminal.
// Deep charcoals, muted greens, warm wood tones, soft cream text.
// Glass overlays let the forest palette bleed through frosted surfaces.

// MARK: - Color Palette

/// Curated color palette — Dark Forest / Moss.
/// Deep charcoals as the dominant base, warm cream for text,
/// moss green and amber as restrained accents.
/// No generic primary colors. Every color is intentional.
enum AppColors {

    // MARK: Backgrounds
    /// The deepest background — forest floor at night.
    static let backgroundPrimary = Color(red: 0.05, green: 0.07, blue: 0.06)
    /// Slightly elevated surface (cards, panels) — charcoal bark.
    static let backgroundSecondary = Color(red: 0.09, green: 0.12, blue: 0.10)
    /// Tertiary surface (input fields, wells) — dark moss.
    static let backgroundTertiary = Color(red: 0.13, green: 0.17, blue: 0.14)

    // MARK: Accent Colors
    /// Warm amber/wood for user actions and highlights — firelight.
    static let accentGold = Color(red: 0.76, green: 0.59, blue: 0.33)
    /// Living moss green for system/model indicators — the Lab's signature.
    /// Boosted for ≥ 4.5:1 on dark backgrounds with Liquid Glass.
    static let accentTeal = Color(red: 0.44, green: 0.73, blue: 0.52)
    /// Spring leaf green for active/interactive elements — brighter than moss.
    /// Boosted for ≥ 4.5:1 on dark backgrounds with Liquid Glass.
    static let accentCyan = Color(red: 0.43, green: 0.76, blue: 0.54)

    // MARK: Semantic
    /// Success / ready / healthy — spring leaf.
    /// Matches accentCyan; boosted for Liquid Glass contrast compliance.
    static let success = Color(red: 0.43, green: 0.76, blue: 0.54)
    /// Warning / caution — autumn amber.
    static let warning = Color(red: 0.77, green: 0.58, blue: 0.23)
    /// Error / critical / danger — clay terracotta.
    /// Boosted for ≥ 3:1 large-text contrast with Liquid Glass.
    static let danger = Color(red: 0.78, green: 0.39, blue: 0.31)
    /// Thinking / reasoning mode — sage green.
    static let thinking = Color(red: 0.36, green: 0.54, blue: 0.45)
    /// Tool calling / function execution — vivid amber.
    static let toolCall = Color(red: 0.95, green: 0.60, blue: 0.15)

    // MARK: Text
    /// Primary text — warm cream, high contrast on dark.
    static let textPrimary = Color(red: 0.91, green: 0.87, blue: 0.82)
    /// Secondary text — weathered wood, labels, captions.
    /// Tuned to ≥ 4.5:1 on backgroundPrimary/Secondary even with Liquid Glass (+15% bg lightening).
    static let textSecondary = Color(red: 0.71, green: 0.66, blue: 0.59)
    /// Tertiary text — deep shadow, timestamps, hints.
    /// Tuned to ≥ 4.5:1 contrast on backgroundPrimary even with Liquid Glass (+15% bg lightening).
    static let textTertiary = Color(red: 0.68, green: 0.63, blue: 0.58)

    // MARK: Chat Bubbles
    /// User message bubble gradient start — deep amber wood.
    static let userBubbleStart = Color(red: 0.28, green: 0.22, blue: 0.14)
    /// User message bubble gradient end — darker wood.
    static let userBubbleEnd = Color(red: 0.18, green: 0.15, blue: 0.10)
    /// Assistant message bubble — dark moss panel.
    static let assistantBubble = Color(red: 0.10, green: 0.14, blue: 0.11)

    // MARK: Borders
    /// Subtle divider/border — like bark grain.
    static let border = Color.white.opacity(0.06)
    /// Active/focused border — slightly brighter grain.
    static let borderActive = Color.white.opacity(0.12)

    // MARK: Badge Colors (distinct per capability — vivid & saturated)
    /// Vision badge — bright sky blue.
    static let badgeVision = Color(red: 0.29, green: 0.62, blue: 1.0)
    /// Audio badge — vivid purple.
    static let badgeAudio = Color(red: 0.75, green: 0.35, blue: 0.95)
    /// MTP badge — bright emerald green.
    static let badgeMTP = Color(red: 0.20, green: 0.78, blue: 0.45)
    /// Thinking badge — vivid violet-purple, clearly distinct from greens.
    static let badgeThinking = Color(red: 0.65, green: 0.42, blue: 0.95)
    /// Constrained Decoding badge — warm amber-orange.
    static let badgeCD = Color(red: 0.90, green: 0.62, blue: 0.20)
    /// Tool Calling badge — bright teal.
    static let badgeTools = Color(red: 0.30, green: 0.75, blue: 0.70)
}

// MARK: - Gradients

enum AppGradients {
    /// User chat bubble gradient — warm wood grain.
    static let userBubble = LinearGradient(
        colors: [AppColors.userBubbleStart, AppColors.userBubbleEnd],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Header/toolbar gradient — bark to shadow.
    static let toolbar = LinearGradient(
        colors: [
            AppColors.backgroundSecondary.opacity(0.95),
            AppColors.backgroundPrimary.opacity(0.98)
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    /// Accent shimmer for loading states — moss light filtering through canopy.
    static let shimmer = LinearGradient(
        colors: [AppColors.accentTeal, AppColors.accentCyan, AppColors.accentTeal],
        startPoint: .leading,
        endPoint: .trailing
    )

    /// Thinking mode glow — sage mist.
    static let thinking = LinearGradient(
        colors: [
            AppColors.thinking.opacity(0.3),
            AppColors.thinking.opacity(0.1),
            AppColors.thinking.opacity(0.3)
        ],
        startPoint: .leading,
        endPoint: .trailing
    )

    /// Model card background — layered bark.
    static let card = LinearGradient(
        colors: [
            AppColors.backgroundSecondary,
            AppColors.backgroundTertiary.opacity(0.7)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Sidebar/panel background — forest depth.
    static let sidebar = LinearGradient(
        colors: [
            AppColors.backgroundSecondary.opacity(0.6),
            AppColors.backgroundPrimary.opacity(0.8)
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    /// Showcase/dashboard background — deep forest with midnight sky tint.
    /// Used by PerformanceDashboardView and ModelShowcaseView.
    static let showcaseBackground = LinearGradient(
        colors: [
            AppColors.backgroundPrimary,
            Color(red: 0.1, green: 0.15, blue: 0.25)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

// MARK: - Shadows

enum AppShadow {
    /// Subtle depth shadow for cards.
    static func card(_ scheme: ColorScheme = .dark) -> (color: Color, radius: CGFloat, x: CGFloat, y: CGFloat) {
        (Color.black.opacity(0.3), 8, 0, 4)
    }

    /// Glow shadow for active elements — moss-tinted.
    static let activeGlow: (color: Color, radius: CGFloat) = (
        AppColors.accentTeal.opacity(0.25), 12
    )

    /// Warm glow for user interaction elements.
    static let warmGlow: (color: Color, radius: CGFloat) = (
        AppColors.accentGold.opacity(0.2), 10
    )
}

// MARK: - Typography

enum AppTypography {
    /// Chat message body.
    static let body: Font = .system(.body, design: .default)
    /// Monospaced for code/benchmarks.
    static let mono: Font = .system(.caption, design: .monospaced)
    /// Section headers.
    static let sectionHeader: Font = .system(.subheadline, design: .default, weight: .semibold)
    /// Stats and metrics.
    static let metric: Font = .system(.caption, design: .monospaced, weight: .medium)
    /// Large display numbers (e.g., decode speed).
    static let metricLarge: Font = .system(.title3, design: .monospaced, weight: .bold)
    /// Captions and labels.
    static let caption: Font = .system(.caption2, design: .default)
    /// Tool/badge labels.
    static let badge: Font = .system(.caption2, design: .rounded, weight: .medium)

    // MARK: Page & Section Headings
    /// View/page titles — prominent headings for top-level screens (~24pt bold).
    static let pageTitle: Font = .system(.title, design: .default, weight: .bold)
    /// Large section headings — group-level titles within a view (~20pt semibold).
    static let sectionTitle: Font = .system(.title3, design: .default, weight: .semibold)
    /// Card header titles — titles inside cards and panels (~18pt semibold).
    static let cardTitle: Font = .system(.headline, design: .default, weight: .semibold)
    /// Subtitles and emphasis text — secondary headings, callout labels (~16pt medium).
    static let subtitle: Font = .system(.subheadline, design: .default, weight: .medium)
    /// Tiny labels, chart axes, fine print (~9pt light).
    static let footnote: Font = .system(.caption2, design: .default, weight: .light)

    // MARK: iOS List
    /// List row title — system body for maximum readability at all Dynamic Type sizes.
    static let listTitle: Font = .system(.body, design: .default, weight: .regular)
    /// List row subtitle — secondary info line.
    static let listSubtitle: Font = .system(.subheadline, design: .default)
    /// List row tertiary — file sizes, timestamps.
    static let listTertiary: Font = .system(.footnote, design: .default)
}

// MARK: - Spacing

enum AppSpacing {
    /// Micro-spacing for tight layouts (badge padding, sub-row gaps).
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32

    // MARK: iOS List
    /// Standard list row content padding.
    static let listRowVertical: CGFloat = 6
    /// Standard list row horizontal insets.
    static let listRowHorizontal: CGFloat = 0  // List handles its own insets
}

// MARK: - Corner Radius

enum AppRadius {
    static let sm: CGFloat = 6
    static let md: CGFloat = 10
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    /// Shareable image cards (Open Graph export, benchmark cards).
    static let card: CGFloat = 24
    /// Chat bubble.
    static let bubble: CGFloat = 18
    /// Full pill shape.
    static let pill: CGFloat = 100
}

/// Dynamic Type–aware icon sizing for SF Symbols.
///
/// Use these instead of `.font(.system(size:))` on `Image(systemName:)`.
/// Each tier maps to a text style that scales with the user's preferred size.
///
/// Tier mapping (approximate default point sizes):
/// - `xxs` → caption2 (~11pt) — tiny metric indicators (bolt, timer)
/// - `xs`  → caption  (~12pt) — small inline icons (sparkle, copy)
/// - `sm`  → footnote (~13pt) — inline icons (category, checkbox)
/// - `md`  → subheadline (~15pt) — medium icons (chevron, feature chips)
/// - `lg`  → body (~17pt) — action icons (download states, model arch)
/// - `xl`  → title3 (~20pt) — card action buttons, section icons
/// - `xxl` → title (~28pt) — large state icons (success, failure)
/// - `hero` → largeTitle (~34pt) — empty state heroes, onboarding
enum AppIconSize {
    /// Tiny inline metric indicators (bolt, timer, stop).
    static let xxs: Font = .system(.caption2)
    /// Small inline icons (sparkle, copy, clock, pause).
    static let xs: Font = .system(.caption)
    /// Inline icons (category icons, branding, checkbox).
    static let sm: Font = .system(.footnote)
    /// Medium icons (chevron, feature highlights, clipboard).
    static let md: Font = .system(.subheadline)
    /// Action icons (download states, model architecture, active badges).
    static let lg: Font = .system(.body)
    /// Card action buttons, suite picker icons, section headers.
    static let xl: Font = .system(.title3)
    /// Large state icons (success/failure cards, model detail).
    static let xxl: Font = .system(.title)
    /// Empty state heroes, onboarding illustrations, welcome headers.
    static let hero: Font = .system(.largeTitle)
}

// MARK: - Animations

enum AppAnimation {
    /// Quick micro-interaction.
    static let quick = Animation.easeOut(duration: 0.15)
    /// Standard UI transition.
    static let standard = Animation.easeInOut(duration: 0.25)
    /// Smooth spring for bouncy elements.
    static let spring = Animation.spring(response: 0.4, dampingFraction: 0.75)
    /// Gentle spring for scroll/layout changes.
    static let gentleSpring = Animation.spring(response: 0.5, dampingFraction: 0.85)

    /// Message entrance.
    static let messageEntrance = Animation.spring(response: 0.35, dampingFraction: 0.8)
}

// MARK: - View Modifiers

/// Premium glass card surface — frosted glass in a forest.
/// The forest palette bleeds through the material for a warm, organic feel.
struct GlassCardModifier: ViewModifier {
    var cornerRadius: CGFloat = AppRadius.lg
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content
            .background {
                Group {
                    if reduceTransparency {
                        // Accessible: opaque fill preserves the forest palette
                        // without blur/translucency ("foggy PNW window" at 0.85)
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(AppColors.backgroundSecondary.opacity(0.85))
                    } else {
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(AppColors.backgroundSecondary.opacity(0.4))
                            .background(.ultraThinMaterial)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(AppColors.border, lineWidth: 0.5)
                )
            }
    }
}

/// Forest glass overlay — used for input bars, toolbars, and floating panels.
/// Slightly more opaque than the standard glass card for better readability.
struct ForestGlassModifier: ViewModifier {
    var cornerRadius: CGFloat = AppRadius.md
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content
            .background {
                Group {
                    if reduceTransparency {
                        // Accessible: opaque fill for input bars & toolbars
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(AppColors.backgroundSecondary.opacity(0.85))
                    } else {
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(AppColors.backgroundSecondary.opacity(0.55))
                            .background(.thinMaterial)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(AppColors.borderActive, lineWidth: 0.5)
                )
            }
    }
}

/// Subtle glow effect behind an element.
struct GlowModifier: ViewModifier {
    let color: Color
    var radius: CGFloat = 12
    var opacity: Double = 0.4

    func body(content: Content) -> some View {
        content
            .shadow(color: color.opacity(opacity), radius: radius, x: 0, y: 0)
    }
}

/// Pulsing glow animation for active indicators.
/// Uses PhaseAnimator + geometryGroup() for efficient, state-free cycling.
/// Disables animation under XCTest to prevent runloop saturation.
struct PulsingGlowModifier: ViewModifier {
    let color: Color

    /// Cached check: are we running inside an XCTest host?
    private static let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil || CommandLine.arguments.contains("-DisableAnimations")

    func body(content: Content) -> some View {
        if Self.isRunningTests {
            // Static shadow — no animation cycle to saturate the runloop
            content
                .shadow(color: color.opacity(0.3), radius: 8)
        } else {
            content
                .geometryGroup()  // Isolate animation from parent layout recalculations
                .phaseAnimator([false, true]) { view, isPulsing in
                    view.shadow(
                        color: color.opacity(isPulsing ? 0.5 : 0.15),
                        radius: isPulsing ? 12 : 4
                    )
                } animation: { _ in
                    .easeInOut(duration: 1.2)
                }
        }
    }
}

/// Entrance animation for chat messages.
struct MessageEntranceModifier: ViewModifier {
    @State private var appeared = false

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 12)
            .onAppear {
                withAnimation(AppAnimation.messageEntrance) {
                    appeared = true
                }
            }
    }
}

/// Badge/pill styling.
struct BadgeModifier: ViewModifier {
    let color: Color

    func body(content: Content) -> some View {
        content
            .font(AppTypography.badge)
            .foregroundStyle(color)
            .padding(.horizontal, AppSpacing.sm)
            .padding(.vertical, 3)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }
}

/// A subtle scaling and brightness hover effect for macOS interactive elements.
struct InteractiveHoverModifier: ViewModifier {
    @State private var isHovered = false
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(isHovered ? 1.02 : 1.0)
            .brightness(isHovered ? 0.05 : 0.0)
            .animation(AppAnimation.quick, value: isHovered)
            .onHover { hovering in
                isHovered = hovering
            }
    }
}

// MARK: - View Extensions

extension View {
    /// Apply premium glass card styling — frosted glass in a forest.
    func glassCard(cornerRadius: CGFloat = AppRadius.lg) -> some View {
        modifier(GlassCardModifier(cornerRadius: cornerRadius))
    }

    /// Apply forest glass overlay — for input bars, toolbars, floating panels.
    func forestGlass(cornerRadius: CGFloat = AppRadius.md) -> some View {
        modifier(ForestGlassModifier(cornerRadius: cornerRadius))
    }

    /// Add a subtle colored glow.
    func glow(_ color: Color, radius: CGFloat = 12, opacity: Double = 0.4) -> some View {
        modifier(GlowModifier(color: color, radius: radius, opacity: opacity))
    }

    /// Add a pulsing glow animation.
    func pulsingGlow(_ color: Color) -> some View {
        modifier(PulsingGlowModifier(color: color))
    }

    /// Animate entrance (fade + slide up).
    func messageEntrance() -> some View {
        modifier(MessageEntranceModifier())
    }

    /// Style as a colored badge/pill.
    func badge(_ color: Color) -> some View {
        modifier(BadgeModifier(color: color))
    }

    /// Apply the app's dark background.
    func appBackground() -> some View {
        self.background(AppColors.backgroundPrimary)
    }

    /// Add subtle scale and brightness on hover (macOS 26+ native feel).
    func interactiveHover() -> some View {
        #if os(macOS)
        modifier(InteractiveHoverModifier())
        #else
        self
        #endif
    }
}

// MARK: - Performance Tier Colors

/// Maps decode speed to a visual tier for instant comprehension.
/// Colors are mapped to the Dark Forest palette for consistency.
enum PerformanceTier {
    case excellent  // > 80 tok/s
    case great      // > 40 tok/s
    case good       // > 20 tok/s
    case fair       // > 10 tok/s
    case slow       // <= 10 tok/s

    init(decodeSpeed: Double) {
        switch decodeSpeed {
        case 80...:     self = .excellent
        case 40..<80:   self = .great
        case 20..<40:   self = .good
        case 10..<20:   self = .fair
        default:        self = .slow
        }
    }

    var color: Color {
        switch self {
        case .excellent: return AppColors.accentCyan     // Spring leaf — peak performance
        case .great:     return AppColors.success        // Living green
        case .good:      return AppColors.accentTeal     // Moss — solid
        case .fair:      return AppColors.warning        // Autumn amber — slowing
        case .slow:      return AppColors.danger         // Clay terracotta — needs attention
        }
    }

    var label: String {
        switch self {
        case .excellent: return "Blazing"
        case .great:     return "Fast"
        case .good:      return "Good"
        case .fair:      return "Fair"
        case .slow:      return "Slow"
        }
    }
}

// MARK: - Pass Rate Tier

/// Maps evaluation pass rate to a visual tier for instant comprehension.
/// Companion to `PerformanceTier` — centralizes the duplicated `passRateColor()` logic
/// previously copied across EvalRunnerView, EvalComparisonView, and EvalBenchmarkCard.
enum PassRateTier {
    case excellent  // > 80%
    case moderate   // > 50%
    case poor       // <= 50%

    init(rate: Double) {
        switch rate {
        case 0.8...:    self = .excellent
        case 0.5..<0.8: self = .moderate
        default:        self = .poor
        }
    }

    var color: Color {
        switch self {
        case .excellent: return AppColors.success
        case .moderate:  return AppColors.accentGold
        case .poor:      return AppColors.danger
        }
    }

    /// Convenience: get the color for a pass rate directly.
    static func color(for rate: Double) -> Color {
        PassRateTier(rate: rate).color
    }
}

// MARK: - Confidence Tier

/// Maps metadata confidence level to a visual color.
/// Centralizes the duplicated `confidenceColor()` logic previously copied across
/// iOSModelDetailView, iOSURLImportSheet, and macOSURLImportSheet.
enum ConfidenceTier {
    case verified
    case high
    case medium
    case low

    init(_ confidence: MetadataConfidence) {
        switch confidence {
        case .verified: self = .verified
        case .high:     self = .high
        case .medium:   self = .medium
        case .low:      self = .low
        }
    }

    var color: Color {
        switch self {
        case .verified: return AppColors.success
        case .high:     return AppColors.success
        case .medium:   return AppColors.warning
        case .low:      return AppColors.danger
        }
    }

    /// Convenience: get the color for a confidence level directly.
    static func color(for confidence: MetadataConfidence) -> Color {
        ConfidenceTier(confidence).color
    }
}

// MARK: - MarkdownUI Theme

extension Theme {
    /// A custom MarkdownUI theme that maps directly to the Dark Forest palette.
    static func appDefault(isUser: Bool) -> Theme {
        Theme()
            .text {
                ForegroundColor(isUser ? AppColors.textPrimary : AppColors.textPrimary)
                FontSize(.em(1.0)) // Uses base Dynamic Type size from SwiftUI environment
            }
            .code {
                FontFamilyVariant(.monospaced)
                ForegroundColor(AppColors.accentCyan)
                BackgroundColor(AppColors.backgroundTertiary.opacity(0.5))
            }
            .strong {
                FontWeight(.semibold)
            }
            .link {
                ForegroundColor(AppColors.accentGold)
            }
            .heading1 { configuration in
                VStack(alignment: .leading, spacing: 0) {
                    configuration.label
                        .font(.title.weight(.bold))
                        .foregroundStyle(AppColors.textPrimary)
                        .padding(.bottom, AppSpacing.sm)
                    Divider().overlay(AppColors.border)
                        .padding(.bottom, AppSpacing.sm)
                }
            }
            .heading2 { configuration in
                VStack(alignment: .leading, spacing: 0) {
                    configuration.label
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(AppColors.textPrimary)
                        .padding(.bottom, AppSpacing.xs)
                    Divider().overlay(AppColors.border)
                        .padding(.bottom, AppSpacing.sm)
                }
            }
            .heading3 { configuration in
                configuration.label
                    .font(.headline)
                    .foregroundStyle(AppColors.textPrimary)
                    .padding(.bottom, AppSpacing.xs)
            }
            .blockquote { configuration in
                HStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(AppColors.accentTeal)
                        .frame(width: 4)
                    configuration.label
                        .padding(.horizontal, AppSpacing.md)
                        .padding(.vertical, AppSpacing.sm)
                        .foregroundStyle(AppColors.textSecondary)
                }
                .background(AppColors.backgroundTertiary.opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm))
                .padding(.vertical, AppSpacing.xs)
            }
            .table { configuration in
                configuration.label
                    .padding(AppSpacing.sm)
                    .background(AppColors.backgroundSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppRadius.md)
                            .stroke(AppColors.border, lineWidth: 1)
                    )
            }
            .tableCell { configuration in
                configuration.label
                    .padding(AppSpacing.sm)
            }
            .listItem { configuration in
                configuration.label
                    .padding(.bottom, AppSpacing.xs)
            }
            .codeBlock { configuration in
                CodeBlockView(code: configuration.content, language: configuration.language)
            }
    }
}

// MARK: - App Notification Names

/// Cross-view communication notifications.
/// Used to decouple empty-state hint actions from input area behavior.
extension Notification.Name {
    /// Posted when the user requests focus on the prompt text field (e.g., from a hint card).
    static let focusPromptRequested = Notification.Name("com.andrewvoirol.EdgeAILab.focusPromptRequested")

    /// Posted when the user requests to show the photo picker (e.g., from an image hint card).
    static let showPhotoPickerRequested = Notification.Name("com.andrewvoirol.EdgeAILab.showPhotoPickerRequested")

    /// Posted when the keyboard should be dismissed (e.g., on tab switch away from Chat).
    static let dismissKeyboardRequested = Notification.Name("com.andrewvoirol.EdgeAILab.dismissKeyboardRequested")

    /// Posted when the user toggles the Canvas panel (⌘⇧K).
    static let toggleCanvasRequested = Notification.Name("com.andrewvoirol.EdgeAILab.toggleCanvasRequested")
}
