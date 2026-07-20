---
name: liquid-glass
description: "Liquid Glass adoption guide for EdgeAILab. Verified SwiftUI APIs, design philosophy, VibrantBackgroundView migration, and testing checklist. Activate when modifying navigation chrome, toolbars, sidebars, tab bars, or system appearance settings."
---

# Liquid Glass Adoption Guide

## Verified APIs (July 2026 — from SDK headers, not docs)

All APIs verified against:
`/Applications/Xcode-beta.app/.../SwiftUICore.swiftmodule/arm64e-apple-macos.swiftinterface`

### View Modifiers

| API | Signature | Purpose |
|-----|-----------|---------|
| `.glassEffect()` | `.glassEffect(_ glass: Glass = .regular, in shape: some Shape)` | Apply glass to any view |
| `.glassEffectID()` | `.glassEffectID(_ id: some Hashable, in namespace: Namespace.ID)` | Identity for animation within container |
| `.glassEffectTransition()` | `.glassEffectTransition(_ transition: GlassEffectTransition)` | Transition style for glass elements |
| `.glassEffectUnion()` | `.glassEffectUnion(id: some Hashable, namespace: Namespace.ID)` | Merge glass effects across views |

### Types

| Type | Members | Notes |
|------|---------|-------|
| `Glass` | `.regular`, `.clear` | Static properties |
| `Glass` | `.tint(_ color: Color?)`, `.interactive(_ isEnabled: Bool)` | Instance methods |
| `GlassEffectContainer<Content>` | SwiftUI View | Groups glass elements for morphing/performance |
| `GlassEffectTransition` | `.matchedGeometry`, `.materialize`, `.identity` | Transition styles |
| `DefaultGlassEffectShape` | Shape | Default shape used when no shape specified |

## Design Philosophy for EdgeAILab

### Glass for Navigation Chrome
- Sidebar, toolbars, tab bars, sheets → use system glass (automatic on macOS 27 / iOS 27)
- Sidebar section headers → `.glassEffect(.clear)`
- Toolbar action buttons → standard placement, let system handle glass

### Custom Palette for Content Areas
- Chat bubbles, cards, settings panels → keep `AppColors` custom palette
- `AppColors.backgroundPrimary/Secondary/Tertiary` → content areas only
- `AppColors.textPrimary/Secondary/Tertiary` → fine on content, use semantic `.primary`/`.secondary` on glass surfaces

## Migration Checklist

### ✅ RESOLVED: `.preferredColorScheme(.dark)` Removal (July 2026)
All per-view `.preferredColorScheme(.dark)` calls have been removed. Zero references remain in Sources/.

### ✅ RESOLVED: `VibrantBackgroundView` Removal (July 2026)
All `VibrantBackgroundView` instances have been removed from the codebase. Zero references remain in Sources/.

### Existing `.glassEffect` Usage (already adopted)
1. `Sources/Views/SidebarView.swift` — active model row ✅
2. `Sources/Views/DetailColumnView.swift` — detail card ✅
3. `Sources/Platform/iOS/iOSModelHubView.swift` — model hub card ✅

### ✅ RESOLVED: `.onDrop` Multi-Format Support (July 2026)
`ContentView.swift` `.onDrop` handler already accepts both `.litertlm` and `.gguf` extensions.

## Testing Checklist

- [ ] Dark mode: glass renders on sidebar, toolbar, tab bar
- [ ] Light mode: glass renders correctly, content areas use custom palette
- [ ] Reduce Transparency: app remains usable with accessibility setting
- [ ] GPU pressure: profile with Instruments during active inference — glass rendering doesn't add latency
- [ ] No custom backgrounds on navigation chrome elements
- [ ] Existing `.glassEffect` usage still works correctly
- [ ] ForestGreen/moss palette visible in content areas, not nav chrome
