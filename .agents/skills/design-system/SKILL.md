---
name: design-system
description: Token architecture, naming conventions, palette theming, and exemption rules for EdgeAILab's visual design system in DesignSystem.swift. Activate when editing UI views, adding new visual elements, or changing the app's color palette.
---

# Design System

EdgeAILab uses a centralized semantic token architecture. All visual values — colors, typography, spacing, radii, line widths, sizes — are defined in `Sources/DesignSystem/DesignSystem.swift` as `enum` namespaces with `static let` properties. Color tokens are backed by Asset Catalog color sets in `Sources/Assets.xcassets/*.colorset/` with `Any` and `Dark` appearance variants.

## Core Principle: Intent Over Appearance

Token names describe **what they do**, not **what they look like**.

| ✅ Correct | ❌ Wrong | Why |
|------------|----------|-----|
| `AppColors.textPrimary` | `AppColors.white` | "Primary" stays correct when palette changes |
| `AppColors.warning` | `AppColors.amber` | "Warning" is intent; "amber" is a color |
| `AppSpacing.sm` | `AppSpacing.eightPoints` | Scale position survives value tweaks |
| `AppSize.dotXl` | `AppSize.eightPixelDot` | Size can change; tier position stays |

## Token Catalog

### AppColors — Semantic Color Palette
```
Backgrounds:  .backgroundPrimary, .backgroundSecondary, .backgroundTertiary
              .backgroundShowcaseEnd, .backgroundTertiarySubtle (0.3 opacity)
Text:         .textPrimary, .textSecondary, .textTertiary, .textQuaternary
Accents:      .accentPrimary, .accentSecondary
              .accentPrimaryTint (0.15), .accentPrimaryFaint (0.1), .accentPrimaryBorder (0.3)
Status:       .success, .warning, .destructive, .reasoning, .toolAction
Borders:      .border, .borderActive
Chat:         .userBubbleStart, .userBubbleEnd, .assistantBubble
Capability:   .capabilityVision, .capabilityAudio, .capabilityCD, .capabilityMTP, .capabilityThinking
Engine:       .engineLiteRT, .engineGGUF, .engineMLX (alias for accentSecondary)
```

### AppTypography — Dynamic Type Font Styles
```
Large:    .largeTitle, .title, .headline
Medium:   .cardTitle, .subtitle, .bodyLarge
Standard: .body, .caption, .captionSecondary
Weights:  .bodySemibold, .captionMedium, .captionSemibold
Special:  .metric, .metricLarge, .mono
```

### AppIconSize — SF Symbol Sizes (Dynamic Type–aware)
```
.xxs (caption2) → .xs (caption) → .sm (footnote) → .md (subheadline)
→ .lg (body) → .xl (title3) → .xxl (title) → .hero (largeTitle)
```

### AppSpacing — Layout Spacing Scale
```
.xxs (2pt) → .xs (4pt) → .listRowVertical (6pt) → .sm (8pt)
→ .md (12pt) → .lg (16pt) → .xl (20pt) → .xxl (24pt) → .xxxl (32pt)
```

### AppRadius — Corner Radius Scale
```
.xs (4pt) → .sm (8pt) → .standard (12pt) → .lg (16pt) → .card (24pt) → .pill (9999pt)
```

### AppLineWidth — Stroke Width Scale
```
.hairline (0.5pt) → .regular (1pt) → .medium (1.5pt) → .thick (2pt) → .heavy (3pt)
```

### AppSize — Indicator Dots & Tap Targets
```
.dotSm (5pt) → .dotMd (6pt) → .dotLg (7pt) → .dotXl (8pt) → .dotHero (10pt)
.tapTarget (44pt)
```

### AppOpacity — Semantic Opacity Tiers
```
whisper (0.03) → ghost (0.05) → mist (0.06) → tint (0.08) → faint (0.1)
→ fill (0.12) → rinse (0.15) → medium (0.3) → dim (0.4) → half (0.5)
→ prominent (0.6) → strong (0.7) → emphasis (0.8) → glass (0.85) → opaque (0.9)
```

### AppShadow — Semantic Shadow Tokens (via AppShadowStyle)
```
.cardPreview (black@0.4, R=20, Y=8)    — share sheet card depth
.floatingBar (bgPrimary@0.5, R=8, Y=-2) — input bar edge fade
.fab (accentPrimary@0.2, R=20, Y=4)     — hero icon glow
.ctaGlow (accentBorder@1.0, R=12, Y=4)  — CTA button glow
```

### AppAnimation — Animation Timing Tokens
```
.micro (0.1s ease) → .quick (0.15s ease) → .standard (0.25s easeInOut)
.spring (0.4/0.75) → .gentleSpring (0.5/0.85) → .messageEntrance (0.35/0.8)
```

### AppTransition — Enter/Exit Transition Tokens
```
.slideDown — opacity + move(top), detail panels
.slideUp — move(bottom) + opacity, floating controls
.contentReveal — asymmetric scale-in/fade-out, expandable sections
```

## Exemption Convention

When a value intentionally bypasses the design system, mark it with a comment:
```swift
VStack(spacing: 0) { // design-system-exempt: zero spacing for tight packing
```

Valid exemption reasons:
- **Zero spacing for tight packing** — structural `spacing: 0`
- **Image-export pixel-exact rendering** — `EvalBenchmarkCard` image export
- **Progress ring tracks** — `lineWidth: 10` for ring visuals
- **Structural layout dimensions** — column widths, panel sizes

## Changing the Palette

To retheme the entire app:
1. Edit the color values in `Sources/Assets.xcassets/*.colorset/Contents.json`
2. Each color set has `Any` (fallback) and `Dark` appearance variants — edit both
3. Build and verify — every view in the app will update automatically via `AppColors` tokens

No Swift code changes needed. This is the design system's primary value.

## Verification Commands

After editing UI code, verify no raw values leaked:
```bash
# Check for raw spacing
grep -rn "spacing: [0-9]" Sources/ --include="*.swift" | grep -v "AppSpacing\|design-system-exempt\|DesignSystem\.swift"

# Check for raw lineWidth
grep -rn "lineWidth: [0-9]" Sources/ --include="*.swift" | grep -v "AppLineWidth\|design-system-exempt\|DesignSystem\.swift"

# Check for raw cornerRadius
grep -rn "cornerRadius: [0-9]" Sources/ --include="*.swift" | grep -v "AppRadius\|design-system-exempt\|DesignSystem\.swift"

# Check for raw colors
grep -rn "Color(red:" Sources/ --include="*.swift" | grep -v "DesignSystem\.swift\|design-system-exempt"

# Check for raw font sizes
grep -rn "\.font(.system(size:" Sources/ --include="*.swift" | grep -v "DesignSystem\.swift\|design-system-exempt"

# Check for raw opacity values
grep -rn '\.opacity(0\.' Sources/ --include="*.swift" | grep -v "AppOpacity\|design-system-exempt\|DesignSystem\.swift\|BenchmarkCardView\.swift"

# Check for raw shadow calls
grep -rn '\.shadow(' Sources/ --include="*.swift" | grep -v "appShadow\|AppShadow\|design-system-exempt\|DesignSystem\.swift\|GlowModifier"
```

## Adding New Views

When creating a new SwiftUI view:
1. Use `AppColors` for all colors — never `Color.blue`, `Color(red:...)`, etc.
2. Use `AppTypography` for all fonts — never `.font(.system(size:))`
3. Use `AppSpacing` for all spacing/padding values
4. Use `AppRadius` for all corner radii
5. Use `AppLineWidth` for all stroke/border widths
6. Use `AppSize` for indicator dots and tap targets
7. Use `AppOpacity` for all opacity values — never `.opacity(0.3)`
8. Use `AppShadow` via `.appShadow()` for shadows — never raw `.shadow(color:radius:x:y:)`
9. Use `AppTransition` for transitions — never raw `.transition(.opacity.combined(with:))`
10. Layout `.frame()` values (column widths, panel sizes) stay as literals

If you need a value that doesn't exist in the token catalog, add a new token to the appropriate enum in `DesignSystem.swift` with a doc comment — don't use a raw literal.

## Dot-Syntax Convenience Pattern

When creating a new `App*` token enum whose values are consumed by a View extension method, Swift resolves leading-dot syntax against the **parameter type**, not the enum. You MUST add convenience static accessors on the parameter type.

```swift
// 1. Define the value type
struct AppShadowStyle { ... }

// 2. Define tokens on the App* enum
enum AppShadow {
    static let cardPreview = AppShadowStyle(...)
}

// 3. Define View extension taking the value type
extension View {
    func appShadow(_ style: AppShadowStyle) -> some View { ... }
}

// 4. REQUIRED: Bridge statics for dot-syntax
extension AppShadowStyle {
    static let cardPreview = AppShadow.cardPreview
}
// Now `.appShadow(.cardPreview)` works.
```

For system types (e.g., `AnyTransition`), extend the system type:
```swift
extension AnyTransition {
    static let slideDown = AppTransition.slideDown
}
// Now `.transition(.slideDown)` works.
```

Without the bridge extension, `.appShadow(.cardPreview)` fails with `'AppShadowStyle' has no member 'cardPreview'`.

## Light/Dark Palette Verification

When authoring or modifying colorset values, verify WCAG AA contrast for BOTH modes:

**Thresholds:**
- Text colors (`textPrimary`, `textSecondary`, `textTertiary`): ≥ 4.5:1 ratio
- UI components (accents, status, borders, capabilities): ≥ 3.0:1 ratio

**Verify against both background tiers** per mode:
- Light: `backgroundPrimary` (0.965, 0.960, 0.950) and `backgroundSecondary` (0.930, 0.925, 0.910)
- Dark: `backgroundPrimary` (0.05, 0.07, 0.06) and `backgroundSecondary` (0.09, 0.12, 0.10)

**Asset Catalog JSON structure:**
```json
{
  "colors": [
    {
      "color": { "components": { "red": "0.110", "green": "0.120", "blue": "0.130", "alpha": "1.000" }, "color-space": "srgb" },
      "idiom": "universal"
    },
    {
      "appearances": [{ "appearance": "luminosity", "value": "dark" }],
      "color": { "components": { "red": "0.910", "green": "0.870", "blue": "0.820", "alpha": "1.000" }, "color-space": "srgb" },
      "idiom": "universal"
    }
  ]
}
```

The **first entry** (no `appearances` key) is the light/universal value. The **second entry** (with `appearances: luminosity: dark`) is the dark value. Never set identical values in both — that defeats light/dark theming.

## Color Hue Map (July 2026 Redistribution)

All semantic colors are spaced across the full 360° hue wheel to prevent visual confusion, especially at small badge size. **The brand accent is deep steel teal (195°), NOT green.** Green is reserved exclusively for `success`/`done`/`healthy`.

```
  Hue°  Token                   Semantic Role
  ─────────────────────────────────────────────────────
    2°   destructive             Error / critical / danger
    9°   engineLiteRT            LiteRT engine format badge
   28°   warning                 Attention / caution / beta
   38°   accentSecondary         Gold accent / Benchmark icon
   55°   capabilityCD            Constrained Decoding badge
   91°   success                 Downloaded / ready / healthy (ONLY green)
  172°   capabilityMTP           Multi-Token Prediction badge
  195°   accentPrimary           Brand accent (buttons, links, selections)
  210°   capabilityVision        Vision capability badge
  225°   engineGGUF              GGUF engine format badge
  260°   toolAction              Tool calling / function execution
  300°   capabilityAudio         Audio capability badge
  307°   reasoning               Thinking mode state (chat bubbles, text)
  341°   capabilityThinking      Thinking capability badge
```

### ΔE Threshold Tiers

| Context | Min ΔE | Rationale |
|---------|--------|-----------|
| Badge-size elements (capabilities, engines) | ≥ 25 | Small elements need high chromatic separation |
| Brand vs semantic (brand ↔ success, brand ↔ accent) | ≥ 20 | Large elements with clear context |
| Neighbor colors (engines, MTP↔brand) | ≥ 15 | Labels provide context, moderate sep OK |
| Text hierarchy | ≥ 8 | Subtle but readable gradient |
| Surface layers (bubbles, backgrounds) | ≥ 4 | Intentionally subtle tinting |

### Reasoning ↔ Thinking Relationship

`reasoning` (307° dusty mauve) and `capabilityThinking` (341° hot pink) are in the same hue family **by design** — they represent the same concept at different UI layers:
- `capabilityThinking` = vivid badge for model capability tags
- `reasoning` = muted tint for chat bubble backgrounds, toggle labels, thinking indicators

They must maintain ΔE ≥ 20 despite the shared family. The separation comes from lightness/saturation differences, not hue.

## Validation (MANDATORY)

After ANY change to color assets or `DesignSystem.swift`:

1. Run `python3 scripts/validate_color_distinctness.py` — must show "All checks passed"
2. If adding a new color, add rules to BOTH the Python script AND `Tests/DesignSystem/DesignSystemDistinctnessTests.swift`
3. Check semantic balance: no hue family (120° arc) should carry more than 2 semantic concepts
4. Verify both light AND dark mode values are set and distinct

The validation script checks:
- 26 distinctness rules (CIE76 ΔE) in both modes
- 14 contrast ratio rules (WCAG AA) in both modes

It reads colorset JSON directly — no Xcode build required.

