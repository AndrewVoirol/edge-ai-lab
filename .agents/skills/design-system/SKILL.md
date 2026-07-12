---
name: design-system
description: Token architecture, naming conventions, palette theming, and exemption rules for EdgeAILab's visual design system in DesignSystem.swift. Activate when editing UI views, adding new visual elements, or changing the app's color palette.
---

# Design System

EdgeAILab uses a centralized semantic token architecture. All visual values — colors, typography, spacing, radii, line widths, sizes — are defined in `Sources/DesignSystem/DesignSystem.swift` as `enum` namespaces with `static let` properties.

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
Backgrounds:  .background, .surfaceElevated, .surfaceSecondary
Text:         .textPrimary, .textSecondary, .textTertiary
Accents:      .accentPrimary, .accentSecondary
Status:       .success, .warning, .error, .info
Borders:      .border
Chat:         .chatUser, .chatAssistant
```

### AppTypography — Dynamic Type Font Styles
```
Large:    .largeTitle, .title, .headline
Medium:   .cardTitle, .subtitle, .bodyLarge
Standard: .body, .caption, .captionSecondary
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
1. Open `Sources/DesignSystem/DesignSystem.swift`
2. Edit the `Color(red:green:blue:)` values in `AppColors`
3. Build and verify — every view in the app will update automatically

No other files need to change. This is the design system's primary value.

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
