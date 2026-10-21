#!/usr/bin/env python3
"""Check the WCAG 2.2 contrast of every Palette color pair in PRHarbor/Helpers/DesignTokens.swift.

Reads the light and dark values straight from the Swift source, prints a table per theme and
exits with status 1 when a pair is below its minimum. `--markdown` prints the tables used in
docs/design-tokens.md.
"""
import pathlib
import re
import sys

SOURCE = pathlib.Path(__file__).resolve().parent.parent / "PRHarbor/Helpers/DesignTokens.swift"

# Opacities the views apply to surfaces before text is drawn on them (see Opacity in the source).
TINT, ROW_SELECTED, ROW_HOVER = 0.15, 0.55, 0.7

# (foreground, background, minimum, role). Backgrounds may be "a@opacity" blended over the panel.
PAIRS = [
    ("textPrimary", "panel", 4.5, "titles, counts"),
    ("textPrimary", "track", 4.5, "titles in segmented controls"),
    ("textSecondary", "panel", 4.5, "subtitles, facts, headers"),
    ("textSecondary", "track", 4.5, "segment labels"),
    ("textSecondary", f"hover@{ROW_HOVER}", 4.5, "subtitles of a hovered row"),
    ("textSecondary", f"accentSoft@{ROW_SELECTED}", 4.5, "subtitles of the selected row"),
    ("textTertiary", "panel", 4.5, "axis labels, counts, separators"),
    ("textTertiary", "track", 4.5, "tertiary text on the track"),
    ("textTertiary", f"hover@{ROW_HOVER}", 4.5, "tertiary text on a hovered row"),
    ("accent", "panel", 4.5, "links, accent icons"),
    ("accent", "accentSoft", 4.5, "search tokens, the / key"),
    ("onAccent", "accentFill", 4.5, "primary button, brush and cursor chips"),
]
for name in ("fresh", "aging", "stale", "rotting"):
    PAIRS += [
        (f"{name}Fill", "panel", 3.0, f"{name} bars, dots, hatching"),
        (f"{name}Label", "panel", 4.5, f"{name} quiet-time label"),
        (f"{name}Label", f"{name}Fill@{TINT}", 4.5, f"{name} label on its tint"),
    ]
PAIRS += [
    ("success", "panel", 4.5, "checks passed"),
    ("warning", "panel", 4.5, "checks running"),
    ("failure", "panel", 4.5, "checks failed"),
]
# Below 3:1 on purpose: lines separate areas that are also separated by spacing or labels.
DECORATIVE = [("line", "panel"), ("strong", "panel"), ("active", "panel")]


def palette():
    text = SOURCE.read_text()
    constants = {m[1]: int(m[2], 16) for m in re.finditer(r"static let (\w+) = (0x[0-9a-fA-F]{6})\b", text)}
    value = lambda token: int(token, 16) if token.startswith("0x") else constants[token]
    themes = {"light": {"onAccent": 0xFFFFFF}, "dark": {"onAccent": 0xFFFFFF}}
    for m in re.finditer(r"static let (\w+) = color\((\w+)(?:, (\w+))?\)", text):
        themes["light"][m[1]] = value(m[2])
        themes["dark"][m[1]] = value(m[3] or m[2])
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


def resolve(theme, name):
    base, _, alpha = name.partition("@")
    return blend(theme[base], theme["panel"], float(alpha)) if alpha else theme[base]


def main():
    markdown = "--markdown" in sys.argv
    failures = 0
    for name, theme in palette().items():
        if markdown:
            print(f"### {name.capitalize()}\n\n| Foreground | Background | Ratio | Minimum | Use |\n|---|---|---:|---:|---|")
        else:
            print(f"== {name}")
        for fg, bg, minimum, role in PAIRS + [(f, b, 0, "decorative") for f, b in DECORATIVE]:
            ratio = contrast(resolve(theme, fg), resolve(theme, bg))
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
