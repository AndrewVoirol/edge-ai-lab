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
```

## Adding New Views

When creating a new SwiftUI view:
1. Use `AppColors` for all colors — never `Color.blue`, `Color(red:...)`, etc.
2. Use `AppTypography` for all fonts — never `.font(.system(size:))`
3. Use `AppSpacing` for all spacing/padding values
4. Use `AppRadius` for all corner radii
5. Use `AppLineWidth` for all stroke/border widths
6. Use `AppSize` for indicator dots and tap targets
7. Layout `.frame()` values (column widths, panel sizes) stay as literals

If you need a value that doesn't exist in the token catalog, add a new token to the appropriate enum in `DesignSystem.swift` with a doc comment — don't use a raw literal.

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
