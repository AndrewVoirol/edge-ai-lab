// DesignDecisions.md — Edge AI Lab Design System Reference
// This file documents every design token with its purpose, usage guidance, and distinctions.
// Last updated: Phase 1 Color Consolidation (July 2026)

# Design Token Reference — Petrichor Palette

> **Palette philosophy:** PNW rain on glass. Vivid greens, cool slate, warm wood tones.
> Glass overlays let the petrichor palette breathe through frosted surfaces.

---

## Color Tokens

### `moss` — The Lab's Signature Accent
- **Hex (dark):** `#4FC78C`
- **Purpose:** Primary accent green. Interactive elements, buttons, highlights, active states, decorative emphasis.
- **Use when:** Something is the app's brand color. Send button, active selections, primary action affordances, branding icons, search field accents, gradient endpoints.
- **Never use for:** Binary status indicators (use `sprout`), warnings/errors (use `caution`/`ember`), thinking mode (use `sage`).
- **Distinct from:** `sprout` (same hex in dark mode, but different semantic — `moss` is style, `sprout` is status). Will diverge in light mode.
- **History:** Merged from `accentTeal` + `accentCyan`, which were used interchangeably with no visible distinction.

### `sprout` — Status: Success / Ready / Healthy
- **Hex (dark):** `#4FC78C`
- **Purpose:** Semantic success indicator. Something is good, working, ready, verified, downloaded.
- **Use when:** Loaded model dots, downloaded checkmarks, pass/fail results, GPU readiness, thermal nominal, confidence verified/high.
- **Never use for:** Interactive buttons (use `moss`), navigation text, decorative emphasis.
- **Distinct from:** `moss` (same hex in dark mode, but tracks different intent — will diverge in light mode Phase 4).
- **History:** Renamed from `success`. The original `success` was the most coherently used green — its usage pattern was the most consistent.

### `amber` — Warm User Emphasis
- **Hex (dark):** `#D9AB59`
- **Purpose:** Warm accent for user-side elements and highlights. Cabin light through fog.
- **Use when:** User chat bubbles, user action highlights, gold accents, links in markdown, sampler settings emphasis, download count stats.
- **Never use for:** Warnings (use `caution`), machine actions (use `action`).
- **Distinct from:** `caution` (different hue — amber is warmer/goldier, caution is more yellow-orange).
- **History:** Renamed from `accentGold`.

### `caution` — Warning / Attention Needed
- **Hex (dark):** `#E0AB3D`
- **Purpose:** Semantic warning. Something needs attention but isn't critical.
- **Use when:** Performance degradation (Fair tier), GPU thermal throttling, missing optional data, medium confidence scores.
- **Never use for:** User emphasis (use `amber`), critical errors (use `ember`).
- **Distinct from:** `amber` (caution is a status signal, amber is a style choice).
- **History:** Renamed from `warning`.

### `ember` — Error / Critical / Danger
- **Hex (dark):** `#DB634F`
- **Purpose:** Semantic danger. Something is wrong, failed, or requires immediate attention.
- **Use when:** Error states, failed downloads, critical thermal, low confidence, delete actions, slow performance tier.
- **Never use for:** Decorative red, attention-getting non-errors.
- **Distinct from:** `caution` (ember = something IS wrong; caution = something MIGHT go wrong).
- **History:** Renamed from `danger`.

### `sage` — Thinking / Reasoning Mode
- **Hex (dark):** `#63A68C`
- **Purpose:** Thinking/reasoning mode indicator. Contemplative, muted green.
- **Use when:** Thinking mode is active. Thinking badges, thinking bubble backgrounds, reasoning step indicators.
- **Never use for:** General success (use `sprout`), primary accent (use `moss`).
- **Distinct from:** `moss` (sage is muted and desaturated; moss is vivid and saturated).
- **History:** Renamed from `thinking`. Usage was already coherent — thinking mode only.

### `action` — Tool Calling / Function Execution
- **Hex (dark):** `#6B8AFF`
- **Purpose:** Machine execution indicator. Cool indigo for tool calls, function invocations, agent actions.
- **Use when:** Tool calling badges, function execution indicators, agent action status, constrained decoding indicators.
- **Never use for:** User actions (use `moss` or `amber`), warnings (use `caution`).
- **Distinct from:** `caution` (action is cool/blue, caution is warm/amber — unmistakable).
- **History:** Changed from `toolCall` (which was amber #F29926). Moved to a completely different hue family to eliminate confusion with `caution`/`amber`.

---

## Badge Tokens (Capability Badges)

These are distinct, vivid colors for model capability indicators. They don't follow the general palette — they need to be immediately distinguishable from each other in small pill badges.

| Token | Color | Use |
|-------|-------|-----|
| `badgeVision` | Bright sky blue | Vision/image capability |
| `badgeAudio` | Vivid purple | Audio capability |
| `badgeMTP` | Bright emerald | Multi-Token Prediction |
| `badgeThinking` | Violet-purple | Thinking mode capability |
| `badgeCD` | Amber-orange | Constrained Decoding |
| `badgeTools` | Bright teal | Tool Calling capability |

---

## Performance Tier Colors

| Tier | Speed | Color Token | Visual |
|------|-------|-------------|--------|
| Blazing | >80 tok/s | `moss` | 🟢 Green |
| Fast | 40-80 tok/s | `moss` | 🟢 Green (label differentiates) |
| Good | 20-40 tok/s | `amber` | 🟡 Amber (shifting warm) |
| Fair | 10-20 tok/s | `caution` | 🟠 Orange-amber |
| Slow | <10 tok/s | `ember` | 🔴 Red |

The top two tiers share `moss` because they're both "healthy" — the label ("Blazing" vs "Fast") provides the distinction. The visual gradient goes green → amber → red for instant comprehension.

---

## Background Tokens

| Token | Metaphor | Use |
|-------|----------|-----|
| `backgroundPrimary` | Forest floor at night | Deepest surfaces |
| `backgroundSecondary` | Charcoal bark | Cards, panels, elevated surfaces |
| `backgroundTertiary` | Dark moss | Input fields, wells, inset areas |

---

## Text Tokens

| Token | Metaphor | Use |
|-------|----------|-----|
| `textPrimary` | Warm cream | High-contrast primary text |
| `textSecondary` | Weathered wood | Labels, captions, secondary info |
| `textTertiary` | Deep shadow | Timestamps, hints, fine print |

All text tokens tuned to ≥ 4.5:1 contrast on background tokens, including with Liquid Glass (+15% background lightening).
