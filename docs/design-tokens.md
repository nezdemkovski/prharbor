# Design tokens

Every visual constant of the panel lives in `PRHarbor/Helpers/DesignTokens.swift`; views refer to token names instead of literals.

| Group | Holds |
|---|---|
| `Palette` | Colors, each with a light and a dark value; surfaces and text are translucent over the glass |
| `Typography` | Type sizes by role, used with `Font.ui(_:_:design:)` |
| `Spacing` | The spacing scale, 2 to 40 pt; panel content is inset by `Spacing.panel` |
| `Radius` | Corner radii; a nested shape's radius is its container's minus the inset |
| `Size` | Icons, buttons, avatars and markers |
| `Layout` | Heights and widths of specific regions, and the settings window |
| `Opacity` | Opacities by role, applied to the color they tint |
| `TimelineMetrics` | Panel width, label column and row area limits |

The settings window uses system controls and colors only.

## Contrast rules

Contrast follows WCAG 2.2 relative luminance:

- Text and icons that carry meaning reach at least 4.5:1 against every surface they are drawn on. This holds for 9.5 pt labels too, since nothing in the panel is large text.
- Fills that identify state reach at least 3:1 against the glass: freshness bars, dots and hatching.
- Lines are decorative and stay well below 3:1. Every bordered control also has a label or spacing that separates it.
- Translucent colors are checked after blending: a surface over the glass's base tone, then text over that surface. The base tone is the window background of each appearance, `#ECECEC` and `#1E1E1E`.

Freshness has two colors per level. `…Fill` is for bars and dots. `…Label`, darker in the light theme, is for text. Quiet-time text on a hatched track sits on a `raised` backing, so the hatching never runs through the glyphs.

Avatar initials pick white or `Palette.ink` at runtime, whichever contrasts more with the generated hue (`AvatarColors.initials(for:)`). White alone dropped to 1.3:1 on yellow hues.

The panel has no background of its own and sits on the popover's system glass. Surfaces, lines and text are black in the light appearance and white in the dark one at a set opacity (`Palette.overlay`), so they take on the glass behind them. The glass keeps its base tone over most wallpapers, but a busy or high-contrast wallpaper can shift the measured ratios.

## Checking

```bash
python3 Scripts/design-contrast.py
```

The script reads the colors from the Swift source and exits with status 1 when a pair falls below its minimum. `--markdown` prints the tables below.

## Results

### Light

| Foreground | Background | Ratio | Minimum | Use |
|---|---|---:|---:|---|
| `textPrimary` | `backdrop` | 14.43 | 4.5 | titles, counts |
| `textPrimary` | `track` | 13.55 | 4.5 | titles in segmented controls |
| `inverseText` | `textPrimary` | 17.04 | 4.5 | the Today marker |
| `textSecondary` | `raised` | 7.14 | 4.5 | facts in the details card |
| `textSecondary` | `backdrop` | 6.83 | 4.5 | subtitles, facts, headers |
| `textSecondary` | `track` | 6.54 | 4.5 | segment labels |
| `textSecondary` | `hover` | 6.57 | 4.5 | subtitles of a hovered row |
| `textSecondary` | `accentSoft` | 6.45 | 4.5 | subtitles of the selected row |
| `textTertiary` | `backdrop` | 4.72 | 4.5 | axis labels, counts, separators |
| `textTertiary` | `track` | 4.65 | 4.5 | tertiary text on the track |
| `textTertiary` | `hover` | 4.59 | 4.5 | tertiary text on a hovered row |
| `accent` | `backdrop` | 5.31 | 4.5 | links, accent icons |
| `accent` | `accentSoft` | 4.64 | 4.5 | search tokens, the / key |
| `onAccent` | `accentFill` | 5.16 | 4.5 | primary button, brush and cursor chips |
| `freshFill` | `backdrop` | 3.18 | 3.0 | fresh bars, dots, hatching |
| `freshLabel` | `backdrop` | 5.43 | 4.5 | fresh quiet-time label |
| `freshLabel` | `freshFill@0.15` | 4.61 | 4.5 | fresh label on its tint |
| `freshLabel` | `raised` | 6.14 | 4.5 | fresh label on its backing in the track |
| `agingFill` | `backdrop` | 3.17 | 3.0 | aging bars, dots, hatching |
| `agingLabel` | `backdrop` | 5.39 | 4.5 | aging quiet-time label |
| `agingLabel` | `agingFill@0.15` | 4.65 | 4.5 | aging label on its tint |
| `agingLabel` | `raised` | 6.10 | 4.5 | aging label on its backing in the track |
| `staleFill` | `backdrop` | 3.19 | 3.0 | stale bars, dots, hatching |
| `staleLabel` | `backdrop` | 5.43 | 4.5 | stale quiet-time label |
| `staleLabel` | `staleFill@0.15` | 4.62 | 4.5 | stale label on its tint |
| `staleLabel` | `raised` | 6.15 | 4.5 | stale label on its backing in the track |
| `rottingFill` | `backdrop` | 3.31 | 3.0 | rotting bars, dots, hatching |
| `rottingLabel` | `backdrop` | 5.55 | 4.5 | rotting quiet-time label |
| `rottingLabel` | `rottingFill@0.15` | 4.62 | 4.5 | rotting label on its tint |
| `rottingLabel` | `raised` | 6.28 | 4.5 | rotting label on its backing in the track |
| `success` | `backdrop` | 5.43 | 4.5 | checks passed |
| `warning` | `backdrop` | 5.39 | 4.5 | checks running |
| `failure` | `backdrop` | 5.55 | 4.5 | checks failed |
| `line` | `backdrop` | 1.17 | — | decorative |
| `strong` | `backdrop` | 1.28 | — | decorative |
| `active` | `backdrop` | 1.22 | — | decorative |

### Dark

| Foreground | Background | Ratio | Minimum | Use |
|---|---|---:|---:|---|
| `textPrimary` | `backdrop` | 14.24 | 4.5 | titles, counts |
| `textPrimary` | `track` | 12.54 | 4.5 | titles in segmented controls |
| `inverseText` | `textPrimary` | 15.18 | 4.5 | the Today marker |
| `textSecondary` | `raised` | 6.85 | 4.5 | facts in the details card |
| `textSecondary` | `backdrop` | 7.86 | 4.5 | subtitles, facts, headers |
| `textSecondary` | `track` | 7.17 | 4.5 | segment labels |
| `textSecondary` | `hover` | 6.85 | 4.5 | subtitles of a hovered row |
| `textSecondary` | `accentSoft` | 6.67 | 4.5 | subtitles of the selected row |
| `textTertiary` | `backdrop` | 5.78 | 4.5 | axis labels, counts, separators |
| `textTertiary` | `track` | 5.36 | 4.5 | tertiary text on the track |
| `textTertiary` | `hover` | 5.13 | 4.5 | tertiary text on a hovered row |
| `accent` | `backdrop` | 6.07 | 4.5 | links, accent icons |
| `accent` | `accentSoft` | 4.78 | 4.5 | search tokens, the / key |
| `onAccent` | `accentFill` | 4.52 | 4.5 | primary button, brush and cursor chips |
| `freshFill` | `backdrop` | 6.02 | 3.0 | fresh bars, dots, hatching |
| `freshLabel` | `backdrop` | 6.02 | 4.5 | fresh quiet-time label |
| `freshLabel` | `freshFill@0.15` | 4.81 | 4.5 | fresh label on its tint |
| `freshLabel` | `raised` | 4.91 | 4.5 | fresh label on its backing in the track |
| `agingFill` | `backdrop` | 7.07 | 3.0 | aging bars, dots, hatching |
| `agingLabel` | `backdrop` | 7.07 | 4.5 | aging quiet-time label |
| `agingLabel` | `agingFill@0.15` | 5.41 | 4.5 | aging label on its tint |
| `agingLabel` | `raised` | 5.75 | 4.5 | aging label on its backing in the track |
| `staleFill` | `backdrop` | 5.96 | 3.0 | stale bars, dots, hatching |
| `staleLabel` | `backdrop` | 5.96 | 4.5 | stale quiet-time label |
| `staleLabel` | `staleFill@0.15` | 4.74 | 4.5 | stale label on its tint |
| `staleLabel` | `raised` | 4.85 | 4.5 | stale label on its backing in the track |
| `rottingFill` | `backdrop` | 4.26 | 3.0 | rotting bars, dots, hatching |
| `rottingLabel` | `backdrop` | 5.68 | 4.5 | rotting quiet-time label |
| `rottingLabel` | `rottingFill@0.15` | 4.86 | 4.5 | rotting label on its tint |
| `rottingLabel` | `raised` | 4.62 | 4.5 | rotting label on its backing in the track |
| `success` | `backdrop` | 6.02 | 4.5 | checks passed |
| `warning` | `backdrop` | 7.07 | 4.5 | checks running |
| `failure` | `backdrop` | 5.68 | 4.5 | checks failed |
| `line` | `backdrop` | 1.30 | — | decorative |
| `strong` | `backdrop` | 1.61 | — | decorative |
| `active` | `backdrop` | 1.49 | — | decorative |
