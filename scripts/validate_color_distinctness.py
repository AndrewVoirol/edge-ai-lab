#!/usr/bin/env python3
"""validate_color_distinctness.py — CI-ready color audit for EdgeAILab.

Reads all .colorset/Contents.json files from the Asset Catalog, computes
CIE76 ΔE distances between colors in defined functional groups, and
verifies WCAG contrast ratios for text colors on backgrounds.

Exit code:
  0 — all checks pass
  1 — at least one check failed

Usage:
  python3 scripts/validate_color_distinctness.py

Intended to run in CI alongside xcodebuild tests. This catches value-level
problems (colors too similar) that the Swift tests also catch at runtime,
but this script runs without building the app.
"""

import json
import math
import os
import sys
from pathlib import Path


# ── Color math ──────────────────────────────────────────────────────

def srgb_to_linear(c: float) -> float:
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def rgb_to_lab(r: float, g: float, b: float) -> tuple[float, float, float]:
    rl, gl, bl = srgb_to_linear(r), srgb_to_linear(g), srgb_to_linear(b)
    x = (0.4124564 * rl + 0.3575761 * gl + 0.1804375 * bl) / 0.95047
    y = 0.2126729 * rl + 0.7151522 * gl + 0.0721750 * bl
    z = (0.0193339 * rl + 0.1191920 * gl + 0.9503041 * bl) / 1.08883

    def f(t):
        return t ** (1 / 3) if t > 0.008856 else 7.787 * t + 16 / 116

    L = 116 * f(y) - 16
    a = 500 * (f(x) - f(y))
    b_val = 200 * (f(y) - f(z))
    return L, a, b_val


def delta_e(c1: tuple, c2: tuple) -> float:
    L1, a1, b1 = rgb_to_lab(*c1)
    L2, a2, b2 = rgb_to_lab(*c2)
    return math.sqrt((L1 - L2) ** 2 + (a1 - a2) ** 2 + (b1 - b2) ** 2)


def relative_luminance(r: float, g: float, b: float) -> float:
    return (0.2126 * srgb_to_linear(r) + 0.7152 * srgb_to_linear(g) +
            0.0722 * srgb_to_linear(b))


def contrast_ratio(c1: tuple, c2: tuple) -> float:
    l1 = relative_luminance(*c1)
    l2 = relative_luminance(*c2)
    return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)


# ── Asset Catalog reader ───────────────────────────────────────────

def load_colorsets(xcassets_dir: str) -> dict[str, dict[str, tuple]]:
    """Load all .colorset entries, returning {name: {mode: (r,g,b)}}."""
    colors: dict[str, dict[str, tuple]] = {}

    for entry in Path(xcassets_dir).iterdir():
        if not entry.name.endswith(".colorset"):
            continue
        name = entry.name.removesuffix(".colorset")
        contents = json.loads((entry / "Contents.json").read_text())

        for c in contents.get("colors", []):
            comp = c["color"]["components"]
            r, g, b = float(comp["red"]), float(comp["green"]), float(comp["blue"])
            a = float(comp.get("alpha", "1"))

            appearances = c.get("appearances", [])
            mode = "dark" if any(
                ap.get("value") == "dark" for ap in appearances
            ) else "light"

            if name not in colors:
                colors[name] = {}
            colors[name][mode] = (r, g, b)

    return colors


# ── Validation rules ───────────────────────────────────────────────

DISTINCTNESS_RULES = [
    # (color_a, color_b, min_delta_e, description)

    # --- Text hierarchy (subtle differences OK) ---
    ("textSecondary", "textTertiary", 8.0, "Text hierarchy"),
    ("textPrimary", "textSecondary", 8.0, "Text hierarchy"),

    # --- Brand / Semantic (ΔE ≥ 20 — large UI elements) ---
    ("accentPrimary", "success", 20.0, "Brand vs success (green exclusivity)"),
    ("accentPrimary", "accentSecondary", 20.0, "Brand vs secondary accent"),
    ("accentSecondary", "warning", 12.0, "Secondary accent vs warning"),
    ("warning", "destructive", 12.0, "Warning vs destructive"),
    ("AccentColor", "accentPrimary", 0.0, "Identity sync (must match)"),

    # --- Capability badges (ΔE ≥ 25 — small badge size needs high separation) ---
    ("capabilityVision", "toolAction", 25.0, "Vision ↔ Tool (badge-size)"),
    ("capabilityAudio", "capabilityThinking", 25.0, "Audio ↔ Thinking (badge-size)"),
    ("capabilityAudio", "toolAction", 25.0, "Audio ↔ Tool (badge-size)"),
    ("capabilityVision", "capabilityAudio", 25.0, "Vision ↔ Audio (badge-size)"),
    ("capabilityThinking", "accentSecondary", 25.0, "Thinking ↔ Benchmark icon"),
    ("capabilityMTP", "accentPrimary", 15.0, "MTP ↔ brand (teal neighbors)"),
    ("capabilityMTP", "success", 15.0, "MTP ↔ success (cyan vs green)"),

    # --- Reasoning ↔ Thinking (same family, different usage layers) ---
    ("reasoning", "capabilityThinking", 20.0, "Reasoning ↔ Thinking badge"),
    ("reasoning", "accentPrimary", 20.0, "Reasoning ↔ brand"),
    ("reasoning", "toolAction", 15.0, "Reasoning ↔ tool (purple neighbors)"),

    # --- Engine badges (ΔE ≥ 15 — label gives context, moderate sep OK) ---
    ("engineLiteRT", "engineGGUF", 15.0, "Engine badges (mutual)"),
    ("engineLiteRT", "success", 15.0, "Engine vs status (not green)"),
    ("engineLiteRT", "accentPrimary", 15.0, "Engine vs brand (not green)"),
    ("engineLiteRT", "destructive", 15.0, "Engine vs error state"),
    ("engineGGUF", "accentPrimary", 15.0, "Engine vs brand"),
    ("engineGGUF", "toolAction", 15.0, "Engine vs tool (blue neighbors)"),
    ("engineGGUF", "capabilityVision", 15.0, "Engine vs vision (blue neighbors)"),

    # --- Chat surfaces (subtle tinting) ---
    ("assistantBubble", "backgroundSecondary", 4.0, "Chat surfaces"),
    ("userBubbleStart", "userBubbleEnd", 4.0, "Gradient visibility"),
]

CONTRAST_RULES = [
    # (foreground, background, min_ratio, description)
    ("textPrimary", "backgroundPrimary", 4.5, "AA body text"),
    ("textSecondary", "backgroundPrimary", 4.5, "AA body text"),
    ("textTertiary", "backgroundPrimary", 4.5, "AA body text"),
    ("textPrimary", "assistantBubble", 4.5, "AA body text"),
    ("textPrimary", "userBubbleStart", 4.5, "AA body text"),
    ("accentPrimary", "backgroundPrimary", 3.0, "AA large text"),
    ("destructive", "backgroundPrimary", 3.0, "AA large text"),
    ("warning", "backgroundPrimary", 3.0, "AA large text"),
    ("success", "backgroundPrimary", 3.0, "AA large text"),
    ("toolAction", "backgroundPrimary", 3.0, "AA large text"),
    ("reasoning", "backgroundPrimary", 3.0, "AA reasoning text"),
    # Engine badges
    ("engineLiteRT", "backgroundSecondary", 3.0, "AA engine badge"),
    ("engineGGUF", "backgroundSecondary", 3.0, "AA engine badge"),
    # Capability badges
    ("capabilityAudio", "backgroundPrimary", 3.0, "AA capability badge"),
]



# ── Main ───────────────────────────────────────────────────────────

def main() -> int:
    # Find xcassets directory
    script_dir = Path(__file__).parent
    project_root = script_dir.parent
    xcassets = project_root / "Sources" / "Assets.xcassets"

    if not xcassets.exists():
        print(f"ERROR: Asset catalog not found at {xcassets}")
        return 1

    colors = load_colorsets(str(xcassets))
    failures = 0

    for mode in ("light", "dark"):
        print(f"\n{'=' * 60}")
        print(f"  {mode.upper()} MODE")
        print(f"{'=' * 60}")

        # Distinctness checks
        print(f"\n  Distinctness Checks:")
        for name_a, name_b, min_de, desc in DISTINCTNESS_RULES:
            if name_a not in colors or name_b not in colors:
                continue
            if mode not in colors[name_a] or mode not in colors[name_b]:
                continue

            ca, cb = colors[name_a][mode], colors[name_b][mode]
            de = delta_e(ca, cb)

            if min_de == 0.0:
                # Identity check: must be identical
                if de > 1.0:
                    print(f"    ❌ {name_a} ↔ {name_b}: ΔE={de:.1f} (must be ≤ 1.0) [{desc}]")
                    failures += 1
                else:
                    print(f"    ✅ {name_a} ↔ {name_b}: ΔE={de:.1f} [{desc}]")
            else:
                if de < min_de:
                    print(f"    ❌ {name_a} ↔ {name_b}: ΔE={de:.1f} < {min_de} [{desc}]")
                    failures += 1
                else:
                    print(f"    ✅ {name_a} ↔ {name_b}: ΔE={de:.1f} ≥ {min_de} [{desc}]")

        # Contrast checks
        print(f"\n  Contrast Ratio Checks:")
        for fg_name, bg_name, min_cr, desc in CONTRAST_RULES:
            if fg_name not in colors or bg_name not in colors:
                continue
            if mode not in colors[fg_name] or mode not in colors[bg_name]:
                continue

            fg, bg = colors[fg_name][mode], colors[bg_name][mode]
            cr = contrast_ratio(fg, bg)

            if cr < min_cr:
                print(f"    ❌ {fg_name} on {bg_name}: {cr:.1f}:1 < {min_cr}:1 [{desc}]")
                failures += 1
            else:
                print(f"    ✅ {fg_name} on {bg_name}: {cr:.1f}:1 ≥ {min_cr}:1 [{desc}]")

    print(f"\n{'=' * 60}")
    if failures > 0:
        print(f"  ❌ {failures} check(s) FAILED")
    else:
        print(f"  ✅ All checks passed")
    print(f"{'=' * 60}\n")

    return 1 if failures > 0 else 0


if __name__ == "__main__":
    sys.exit(main())
