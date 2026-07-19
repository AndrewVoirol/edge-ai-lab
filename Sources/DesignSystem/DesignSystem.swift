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
// "Petrichor" palette — blue-slate stone, rain-fresh greens, cabin light through fog.
// Inspired by PNW rain on glass: vivid greens, cool slate, warm wood tones.
// Glass overlays let the petrichor palette breathe through frosted surfaces.

// MARK: - Color Palette

/// Curated color palette — Petrichor.
/// Blue-slate stone as the dominant base, bright overcast light for text.
/// Semantic color tokens — names describe PURPOSE, not appearance.
///
/// **Architecture:** All color values live in the Asset Catalog (`Assets.xcassets`).
/// Each color set has Any (fallback) and Dark appearance variants.
/// Both light and dark appearances are authored in the Asset Catalog.
/// Light values use warm neutrals; dark values use the forest palette.
/// All combinations verified ≥ WCAG AA contrast (4.5:1 text, 3:1 UI).
///
/// **Theming:** To change the app's palette, edit color values in the Asset Catalog.
/// No view file references a color directly — all go through these tokens.
///
/// **WCAG AA targets:** Body text ≥ 4.5:1, large text / UI components ≥ 3:1.
enum AppColors {

    // MARK: Backgrounds
    /// Deepest background layer.
    static let backgroundPrimary = Color("backgroundPrimary")
    /// Elevated surface (cards, panels).
    static let backgroundSecondary = Color("backgroundSecondary")
    /// Inset surface (input fields, wells).
    static let backgroundTertiary = Color("backgroundTertiary")

    // MARK: Accent Colors
    /// Primary brand accent — interactive elements, buttons, active states, progress indicators.
    /// 195° deep steel teal — intentionally NOT green to avoid collision with `success`.
    /// ΔE ≥ 68 from `success`, ≥ 73 from `accentSecondary`, ≥ 27 from `capabilityMTP`.
    /// Never use for: binary status indicators (use `success`), warnings/errors, thinking mode.
    /// History: Was 150° green until July 2026 retheme (green overload — brand and success both green).
    static let accentPrimary = Color("accentPrimary")
    /// Secondary accent — user-side actions, role labels, send button, code language tags, Benchmark icon.
    /// 38° gold/amber.
    /// Never use for: warnings (use `warning`), machine actions (use `toolAction`).
    /// Distinct from: `warning` (gold is warmer; warning is more orange with higher saturation).
    static let accentSecondary = Color("accentSecondary")

    // MARK: Semantic State
    /// Success / ready / healthy / downloaded / verified / passed.
    /// 91° lime-green — the ONLY green in the palette (brand moved to teal).
    /// Never use for: interactive buttons (use `accentPrimary`), navigation text, engine badges.
    static let success = Color("success")
    /// Warning / attention needed / loading / paused / beta / restart required.
    /// 22° orange — distinct from accentSecondary (38° gold) by higher saturation and lower hue.
    /// Distinct from: `destructive` (warning = something MIGHT go wrong; destructive = something IS wrong).
    static let warning = Color("warning")
    /// Error / critical / danger / delete / cancel / failed.
    /// Boosted for ≥ 3:1 large-text contrast with Liquid Glass.
    /// Never use for: decorative red, attention-getting non-errors.
    static let destructive = Color("destructive")
    /// Thinking / reasoning mode — active contemplation state.
    /// 307° dusty mauve — same hue family as `capabilityThinking` (341° pink).
    /// Used for chat bubble tint, thinking indicator text, toggle labels.
    /// Never use for: general success (use `success`), primary accent (use `accentPrimary`).
    static let reasoning = Color("reasoning")
    /// Tool calling / function execution / agent actions.
    /// 260° deep indigo — ΔE ≥ 31 from capabilityAudio, ≥ 41 from capabilityVision.
    /// Never use for: user actions (use `accentPrimary` or `accentSecondary`), warnings.
    static let toolAction = Color("toolAction")

    // MARK: Text
    /// Primary content text — headings, interactive labels.
    static let textPrimary = Color("textPrimary")
    /// Secondary text — descriptions, section labels.
    /// Tuned to ≥ 4.5:1 on backgroundPrimary/Secondary even with Liquid Glass.
    static let textSecondary = Color("textSecondary")
    /// Tertiary text — timestamps, hints, metadata, disabled states.
    /// 30° warm gray — 4.6:1 contrast on backgroundPrimary (WCAG AA). ΔE ≥ 8.5 from textSecondary.
    /// Never apply .opacity() to this — already the dimmest readable text. Use as-is.
    static let textTertiary = Color("textTertiary")

    // MARK: Chat Bubbles
    /// User message bubble gradient start — lighter warm neutral.
    /// Gradient ΔE ≥ 5.9 from userBubbleEnd (light), ≥ 10.8 (dark).
    static let userBubbleStart = Color("userBubbleStart")
    /// User message bubble gradient end — darker warm neutral.
    static let userBubbleEnd = Color("userBubbleEnd")
    /// Assistant message bubble background.
    /// 138° green tint at 33% saturation (light) / 36% (dark) — distinct from warm neutral surfaces.
    /// ΔE ≥ 5.7 from backgroundSecondary (light), ≥ 10.3 (dark).
    static let assistantBubble = Color("assistantBubble")

    // MARK: Borders
    /// Default border / divider.
    static let border = Color("border")
    /// Active / focused border.
    static let borderActive = Color("borderActive")

    // MARK: Capability Indicators (distinct per model feature)
    // July 2026 redistribution: spaced across full hue wheel with ≥30° gaps.
    // Each badge must be visually distinct at small badge size (≥25 ΔE between neighbors).

    /// Vision capability — 210° vivid sky blue. ΔE ≥ 29 from engineGGUF, ≥ 41 from toolAction.
    static let capabilityVision = Color("capabilityVision")
    /// Audio capability — 300° orchid purple. ΔE ≥ 31 from toolAction (260°), ≥ 34 from thinking (341°).
    static let capabilityAudio = Color("capabilityAudio")
    /// Multi-Token Prediction capability — 172° teal-cyan. ΔE ≥ 27 from brand (195°).
    static let capabilityMTP = Color("capabilityMTP")
    /// Thinking/reasoning capability — 341° hot pink. ΔE ≥ 34 from audio (300°), ≥ 35 from reasoning (307°).
    static let capabilityThinking = Color("capabilityThinking")
    /// Constrained Decoding capability.
    /// 55° yellow — distinct from accentSecondary (38°) and warning (22°).
    static let capabilityCD = Color("capabilityCD")

    // MARK: Engine Badge Colors (distinct per runtime format)
    // Engine badges identify the inference runtime/format — NOT status.
    // These MUST be outside the green family to avoid collapsing with
    // accentPrimary (brand green) and success (status green).
    //
    // July 2026: Previously LiteRT used `success` and GGUF used `accentPrimary`,
    // causing model cards to show three green elements (badge + download + brand).

    /// LiteRT runtime badge — warm coral/terra cotta (15° hue).
    /// ΔE ≥ 30 from accentPrimary, ≥ 25 from success, ≥ 20 from destructive.
    /// Never use for: status indicators (use `success`/`destructive`).
    static let engineLiteRT = Color("engineLiteRT")
    /// GGUF (llama.cpp) format badge — muted slate-blue (225° hue).
    /// ΔE ≥ 15 from toolAction (248°), ≥ 20 from capabilityVision (214°).
    /// Never use for: capability indicators or interactive elements.
    static let engineGGUF = Color("engineGGUF")
    /// MLX runtime badge — reuses accentSecondary (gold/amber, 38° hue).
    /// Already visually distinct from green family. No separate asset needed.
    static let engineMLX = accentSecondary

    // MARK: Gradient Support
    /// Deep midnight-sky tint for showcase/dashboard gradient endpoint.
    static let backgroundShowcaseEnd = Color("backgroundShowcaseEnd")

    // MARK: Pre-Composed Opacity Variants
    // These capture high-frequency opacity patterns as named tokens.
    // Derived from base tokens — automatically adapt when base colors change.

    /// Accent primary at 15% opacity — badge backgrounds, selected fills, tinted surfaces.
    static let accentPrimaryTint = accentPrimary.opacity(0.15)
    /// Accent primary at 10% — faint hover states, subtle row highlights.
    static let accentPrimaryFaint = accentPrimary.opacity(0.1)
    /// Accent primary at 30% — borders on accent elements, ring strokes.
    static let accentPrimaryBorder = accentPrimary.opacity(0.3)
    /// Background tertiary at 30% — blockquote fills, code block backgrounds, subtle surface tints.
    static let backgroundTertiarySubtle = backgroundTertiary.opacity(0.3)

    // MARK: Accessible Dim Text
    /// Quaternary text — divider dots, watermarks, deeply de-emphasized decorative text.
    /// Dimmer than textTertiary but still WCAG AA compliant at ≥ 3:1 on backgroundPrimary.
    /// Opacity 0.80 (not 0.70) — calibrated after textTertiary lightened in July 2026 audit.
    /// Use instead of applying .opacity() to textTertiary (which drops below readable contrast).
    static let textQuaternary = textTertiary.opacity(0.80)
}

// MARK: - Gradients

enum AppGradients {
    /// User chat bubble gradient — warm wood grain.
    static let userBubble = LinearGradient(
        colors: [AppColors.userBubbleStart, AppColors.userBubbleEnd],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Showcase/dashboard background — deep forest with midnight sky tint.
    /// Used by PerformanceDashboardView and ModelShowcaseView.
    static let showcaseBackground = LinearGradient(
        colors: [
            AppColors.backgroundPrimary,
            AppColors.backgroundShowcaseEnd
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
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

    // MARK: Weight Variants
    /// Caption with medium weight — for inline labels needing subtle emphasis.
    static let captionMedium: Font = .system(.caption2, design: .default, weight: .medium)
    /// Caption with semibold weight — for active/interactive caption labels.
    static let captionSemibold: Font = .system(.caption2, design: .default, weight: .semibold)
    /// Body with semibold weight — for emphasized body text in tables/comparisons.
    static let bodySemibold: Font = .system(.body, design: .default, weight: .semibold)

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
    /// Extra-small corners (inline chips, tight controls).
    static let xs: CGFloat = 4
    static let sm: CGFloat = 6
    static let md: CGFloat = 10
    /// Standard panel/card corners.
    static let standard: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    /// Shareable image cards (Open Graph export, benchmark cards).
    static let card: CGFloat = 24
    /// Chat bubble.
    static let bubble: CGFloat = 18
    /// Full pill shape.
    static let pill: CGFloat = 100
}

// MARK: - Line Width

/// Semantic stroke widths for borders, dividers, and outlines.
enum AppLineWidth {
    /// Hairline dividers and subtle separators.
    static let hairline: CGFloat = 0.5
    /// Standard borders and outlines.
    static let regular: CGFloat = 1
    /// Slightly emphasized borders (e.g., active states).
    static let medium: CGFloat = 1.5
    /// Thick borders for strong emphasis.
    static let thick: CGFloat = 2
    /// Heavy strokes (e.g., progress ring tracks).
    static let heavy: CGFloat = 3
}

// MARK: - Standard Sizes

/// Fixed-size design tokens for indicators, dots, and tap targets.
///
/// Only values that represent a **design concept** belong here (status dots,
/// touch targets). Layout-specific dimensions (column widths, panel sizes,
/// window constraints) remain inline as they are context-dependent.
enum AppSize {
    /// Tiny status dot (inactive/secondary model indicators). 5×5
    static let dotSm: CGFloat = 5
    /// Small status dot (capability dots, status indicators). 6×6
    static let dotMd: CGFloat = 6
    /// Streaming/animation dot (chat typing indicator). 7×7
    static let dotLg: CGFloat = 7
    /// Standard status dot (active model, legend entries). 8×8
    static let dotXl: CGFloat = 8
    /// Large indicator dot (onboarding page dots). 10×10
    static let dotHero: CGFloat = 10
    /// Apple HIG minimum tap target. 44×44
    static let tapTarget: CGFloat = 44
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
    /// Instant tactile feedback — button press, tap scale.
    static let micro = Animation.easeInOut(duration: 0.1)
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

// MARK: - Transitions

/// Semantic transition tokens for consistent enter/exit animations.
///
/// Usage: `.transition(.slideDown)` instead of
/// `.transition(.opacity.combined(with: .move(edge: .top)))`.
enum AppTransition {
    /// Content sliding down from top with fade — expanding detail panels, status banners.
    static let slideDown: AnyTransition = .opacity.combined(with: .move(edge: .top))
    /// Content sliding up from bottom with fade — floating controls, agent status bars.
    static let slideUp: AnyTransition = .move(edge: .bottom).combined(with: .opacity)
    /// Asymmetric content reveal — subtle scale-in on insert, fade on remove.
    /// Used for expandable sections in cards and chat bubbles.
    static let contentReveal: AnyTransition = .asymmetric(
        insertion: .opacity.combined(with: .scale(scale: 0.95, anchor: .top)),
        removal: .opacity
    )
}

// Convenience accessors on AnyTransition for dot-syntax in `.transition(.slideDown)`.
// Swift resolves the leading dot against AnyTransition, not AppTransition.
extension AnyTransition {
    static let slideDown = AppTransition.slideDown
    static let slideUp = AppTransition.slideUp
    static let contentReveal = AppTransition.contentReveal
}

// MARK: - Opacity

/// Semantic opacity tiers — named intent instead of magic numbers.
///
/// Usage: `someColor.opacity(AppOpacity.faint)` instead of `someColor.opacity(0.1)`.
/// Values are strictly ascending: whisper < ghost < mist < tint < subtle < faint < fill < rinse
///   < medium < dim < half < prominent < strong < emphasis < glass < opaque.
///
/// Not every `.opacity()` call should use these — exemptions include:
/// - Image-export contexts (ImageRenderer) — pixel-exact values
/// - Animation keyframe pairs (e.g., `isGlowing ? 0.6 : 0.2`) — animation-specific
/// - Binary show/hide (e.g., `appeared ? 1 : 0`) — boolean toggle
/// - Pre-composed color tokens (accentPrimaryTint, etc.) — already named
enum AppOpacity {
    /// Barely-visible sheen — glass highlights, faint gradient stops.
    static let whisper: Double = 0.03
    /// Faint row highlights — failed-state backgrounds, reasoning tints.
    static let ghost: Double = 0.05
    /// Subtle tint — unsupported badge backgrounds, faint card fills.
    static let mist: Double = 0.06
    /// Block backgrounds — reasoning/tool/tier sections, capability card fills.
    static let tint: Double = 0.08
    /// Border strokes — faint accents, pill/badge backgrounds, row highlights.
    static let faint: Double = 0.1
    /// Badge backgrounds — section fills, active-model fills, code badges.
    static let fill: Double = 0.12
    /// Badge borders — warning section backgrounds, tag pill fills.
    static let rinse: Double = 0.15
    /// Borders — glow base, gradient stops, glass fills, ring strokes.
    static let medium: Double = 0.3
    /// Shadows — disabled foreground, selection borders, glass fills.
    static let dim: Double = 0.4
    /// Disabled states — border fills, glass fills, dimmed elements.
    static let half: Double = 0.5
    /// Foreground styles — chart fills, icon tints, glass fills.
    static let prominent: Double = 0.6
    /// Strong foreground — typing indicators, icon emphasis, delete icons.
    static let strong: Double = 0.7
    /// Warning/destructive foreground — status emphasis, alert icons.
    static let emphasis: Double = 0.8
    /// Reduce-transparency glass fills — accessible opaque fallbacks.
    static let glass: Double = 0.85
    /// Near-opaque overlays — search result backgrounds, frosted surfaces.
    static let opaque: Double = 0.9
}

// MARK: - Shadows

/// A value type describing a shadow's visual properties.
/// Used by `AppShadow` tokens and the `.appShadow()` modifier.
struct AppShadowStyle: Equatable, Sendable {
    let color: Color
    /// Opacity applied to the color. Use 1.0 when the color already includes opacity.
    let opacity: Double
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat

    init(color: Color, opacity: Double = 1.0, radius: CGFloat, x: CGFloat = 0, y: CGFloat = 0) {
        self.color = color
        self.opacity = opacity
        self.radius = radius
        self.x = x
        self.y = y
    }
}

/// Semantic shadow tokens — named elevation intent instead of ad-hoc parameters.
///
/// Usage: `.appShadow(.cardPreview)` instead of `.shadow(color: .black.opacity(0.4), radius: 20, y: 8)`.
///
/// Image-export shadows (BenchmarkCardView hero metric glows) are exempt — they use dynamic
/// color parameters and require pixel-exact values for ImageRenderer output.
enum AppShadow {
    /// Floating card preview in share sheets — deep black drop shadow for depth.
    /// Used by BenchmarkCardShareSheet and EvalBenchmarkCard share previews.
    static let cardPreview = AppShadowStyle(color: .black, opacity: AppOpacity.dim, radius: 20, y: 8)

    /// Input bar floating above scrollable content — upward-cast background-colored shadow.
    /// Creates a content fade at the input area's top edge.
    static let floatingBar = AppShadowStyle(color: AppColors.backgroundPrimary, opacity: AppOpacity.half, radius: 8, y: -2)

    /// Large hero elements (FAB circles, empty-state icons) — subtle accent-colored depth.
    static let fab = AppShadowStyle(color: AppColors.accentPrimary, opacity: 0.2, radius: 20, y: 4)

    /// Primary CTA buttons — focused accent glow beneath interactive elements.
    /// Color uses accentPrimaryBorder (pre-composed 30% opacity accent) at full strength.
    static let ctaGlow = AppShadowStyle(color: AppColors.accentPrimaryBorder, opacity: 1.0, radius: 12, y: 4)
}

// Convenience accessors on AppShadowStyle for dot-syntax in `.appShadow(.cardPreview)`.
// Swift resolves the leading dot against the parameter type (AppShadowStyle), not AppShadow.
extension AppShadowStyle {
    static let cardPreview = AppShadow.cardPreview
    static let floatingBar = AppShadow.floatingBar
    static let fab = AppShadow.fab
    static let ctaGlow = AppShadow.ctaGlow
}

/// Applies a semantic shadow token to a view.
struct ShadowModifier: ViewModifier {
    let style: AppShadowStyle

    func body(content: Content) -> some View {
        content
            .shadow(
                color: style.color.opacity(style.opacity),
                radius: style.radius,
                x: style.x,
                y: style.y
            )
    }
}

// MARK: - View Modifiers

/// Glass card background — frosted glass in a dark forest.
/// The forest palette bleeds through the material for a warm, organic feel.
///
/// ⚠️ Do NOT combine with `.glassEffect()` — use one or the other, never both.
/// Stacking produces a double-glass sandwich with over-blurred, muddy results.
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
                        .stroke(AppColors.border, lineWidth: AppLineWidth.hairline)
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
                        .stroke(AppColors.borderActive, lineWidth: AppLineWidth.hairline)
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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if Self.isRunningTests || reduceMotion {
            // Static shadow — no animation cycle to saturate the runloop
            // or when user has enabled Reduce Motion accessibility preference
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
            .padding(.vertical, 3) // design-system-exempt: badge internal vertical padding — no matching token
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

    /// Glass card with interactive affordances — slightly more opaque fill
    /// and subtle accent border tint on hover. Use for clickable surfaces.
    func interactiveGlassCard(cornerRadius: CGFloat = AppRadius.standard) -> some View {
        self
            .background {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(AppColors.backgroundSecondary.opacity(AppOpacity.half))
                    .background(.ultraThinMaterial)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(AppColors.border, lineWidth: AppLineWidth.hairline)
            }
            .interactiveHover()
    }

    /// Glass card for input fields (URL paste, search, text entry).
    /// Alias for forestGlass with standard radius.
    func inputGlassCard(cornerRadius: CGFloat = AppRadius.md) -> some View {
        self.forestGlass(cornerRadius: cornerRadius)
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

    /// Apply a semantic shadow token from `AppShadow`.
    func appShadow(_ style: AppShadowStyle) -> some View {
        modifier(ShadowModifier(style: style))
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
        case .excellent: return AppColors.accentPrimary   // Peak performance
        case .great:     return AppColors.accentPrimary   // Still healthy — label differentiates
        case .good:      return AppColors.accentSecondary // Performance fading
        case .fair:      return AppColors.warning         // Slowing — attention
        case .slow:      return AppColors.destructive     // Needs attention
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
        case .moderate:  return AppColors.accentSecondary
        case .poor:      return AppColors.destructive
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
        case .low:      return AppColors.destructive
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
                ForegroundColor(isUser ? AppColors.textPrimary : AppColors.textSecondary)
                FontSize(.em(1.0)) // Uses base Dynamic Type size from SwiftUI environment
            }
            .code {
                FontFamilyVariant(.monospaced)
                ForegroundColor(AppColors.accentPrimary)
                BackgroundColor(AppColors.backgroundTertiary.opacity(0.5)) // design-system-exempt: code block needs more density than backgroundTertiarySubtle (0.3)
            }
            .strong {
                FontWeight(.semibold)
            }
            .link {
                ForegroundColor(AppColors.accentSecondary)
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
                        .fill(AppColors.accentPrimary)
                        .frame(width: 4)
                    configuration.label
                        .padding(.horizontal, AppSpacing.md)
                        .padding(.vertical, AppSpacing.sm)
                        .foregroundStyle(AppColors.textSecondary)
                }
                .background(AppColors.backgroundTertiarySubtle)
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
                            .stroke(AppColors.border, lineWidth: AppLineWidth.regular)
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
