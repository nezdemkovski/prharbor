#!/usr/bin/env python3
"""Check the WCAG 2.2 contrast of every Palette color pair in PRHarbor/DesignSystem/DesignTokens.swift.

Reads the light and dark values straight from the Swift source, prints a table per theme and
exits with status 1 when a pair is below its minimum. Translucent colors are blended over the
background they sit on, and the panel itself over BACKDROP, the base tone of the popover's
system glass (the window background color of each appearance). `--markdown` prints the tables used in
docs/design-tokens.md.
"""
import pathlib
import re
import sys

SOURCE = pathlib.Path(__file__).resolve().parent.parent / "PRHarbor/DesignSystem/DesignTokens.swift"

BACKDROP = {"light": 0xECECEC, "dark": 0x1E1E1E}
# Opacity the views apply to a freshness fill behind its label (Opacity.tintFill in the source).
TINT = 0.15

# (foreground, background, minimum, role). Backgrounds may be "a@opacity" blended over the panel.
PAIRS = [
    ("textPrimary", "backdrop", 4.5, "titles, counts"),
    ("textPrimary", "track", 4.5, "titles in segmented controls"),
    ("inverseText", "textPrimary", 4.5, "the Today marker"),
    ("textSecondary", "raised", 4.5, "facts in the details card"),
    ("textSecondary", "backdrop", 4.5, "subtitles, facts, headers"),
    ("textSecondary", "track", 4.5, "segment labels"),
    ("textSecondary", "hover", 4.5, "subtitles of a hovered row"),
    ("textSecondary", "accentSoft", 4.5, "subtitles of the selected row"),
    ("textTertiary", "backdrop", 4.5, "axis labels, counts, separators"),
    ("textTertiary", "track", 4.5, "tertiary text on the track"),
    ("textTertiary", "hover", 4.5, "tertiary text on a hovered row"),
    ("accent", "backdrop", 4.5, "links, accent icons"),
    ("accent", "accentSoft", 4.5, "search tokens, the / key"),
    ("onAccent", "accentFill", 4.5, "primary button, brush and cursor chips"),
]
for name in ("fresh", "aging", "stale", "rotting"):
    PAIRS += [
        (f"{name}Fill", "backdrop", 3.0, f"{name} bars, dots, hatching"),
        (f"{name}Label", "backdrop", 4.5, f"{name} quiet-time label"),
        (f"{name}Label", f"{name}Fill@{TINT}", 4.5, f"{name} label on its tint"),
        (f"{name}Label", "raised", 4.5, f"{name} label on its backing in the track"),
    ]
PAIRS += [
    ("success", "backdrop", 4.5, "checks passed"),
    ("warning", "backdrop", 4.5, "checks running"),
    ("failure", "backdrop", 4.5, "checks failed"),
]
# Below 3:1 on purpose: lines separate areas that are also separated by spacing or labels.
DECORATIVE = [("line", "backdrop"), ("strong", "backdrop"), ("active", "backdrop")]


def palette():
    """Each token as (rgb, alpha) per appearance."""
    text = SOURCE.read_text()
    constants = {m[1]: int(m[2], 16) for m in re.finditer(r"static let (\w+) = (0x[0-9a-fA-F]{6})\b", text)}
    value = lambda token: int(token, 16) if token.startswith("0x") else constants[token]
    themes = {name: {"onAccent": (0xFFFFFF, 1.0), "backdrop": (color, 1.0)} for name, color in BACKDROP.items()}
    for m in re.finditer(r"static let (\w+) = color\((\w+)(?:, (\w+))?(?:, alpha: ([\d.]+))?(?:, darkAlpha: ([\d.]+))?\)", text):
        alpha = float(m[4] or 1)
        themes["light"][m[1]] = (value(m[2]), alpha)
        themes["dark"][m[1]] = (value(m[3] or m[2]), float(m[5] or alpha))
    for m in re.finditer(r"static let (\w+) = overlay\(([\d.]+), ([\d.]+)\)", text):
        themes["light"][m[1]] = (0x000000, float(m[2]))
        themes["dark"][m[1]] = (0xFFFFFF, float(m[3]))
    for m in re.finditer(r"static let (\w+) = (\w+)$", text, re.M):
        if m[2] in themes["light"]:
            for theme in themes.values():
                theme[m[1]] = theme[m[2]]
    return themes


def luminance(color):
    def channel(c):
        c /= 255
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
    r, g, b = (color >> 16) & 255, (color >> 8) & 255, color & 255
    return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)


def contrast(a, b):
    high, low = sorted((luminance(a), luminance(b)), reverse=True)
    return (high + 0.05) / (low + 0.05)


def blend(fg, bg, alpha):
    return sum(round(((fg >> s) & 255) * alpha + ((bg >> s) & 255) * (1 - alpha)) << s for s in (16, 8, 0))


def resolve(theme, name, over=None):
    """The opaque color of `name` drawn over `over`, or over the backdrop."""
    base, _, extra = name.partition("@")
    color, alpha = theme[base]
    alpha *= float(extra) if extra else 1
    return blend(color, theme["backdrop"][0] if over is None else over, alpha)


def main():
    markdown = "--markdown" in sys.argv
    failures = 0
    for name, theme in palette().items():
        if markdown:
            print(f"### {name.capitalize()}\n\n| Foreground | Background | Ratio | Minimum | Use |\n|---|---|---:|---:|---|")
        else:
            print(f"== {name}")
        for fg, bg, minimum, role in PAIRS + [(f, b, 0, "decorative") for f, b in DECORATIVE]:
            background = resolve(theme, bg)
            ratio = contrast(resolve(theme, fg, background), background)
            ok = ratio >= minimum
            failures += not ok
            if markdown:
                print(f"| `{fg}` | `{bg}` | {ratio:.2f} | {minimum or '—'} | {role} |")
            else:
                print(f"  {'ok  ' if ok else 'FAIL'} {ratio:5.2f} ≥ {minimum:<3} {fg} on {bg} ({role})")
        print()
    if failures and not markdown:
        print(f"{failures} pair(s) below the minimum", file=sys.stderr)
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
