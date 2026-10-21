# Design tokens

Every visual constant of the panel lives in `PRHarbor/Helpers/DesignTokens.swift`; views refer to token names instead of literals.

| Group | Holds |
|---|---|
| `Palette` | Colors, each with a light and a dark value |
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
- Fills that identify state reach at least 3:1 against the panel: freshness bars, dots and hatching.
- Lines are decorative and stay well below 3:1. Every bordered control also has a label or spacing that separates it.
- Translucent surfaces are checked after blending over the panel. These are the hovered row (`hover` at 0.7), the selected row (`accentSoft` at 0.55) and a freshness tint (its fill at 0.15).

Freshness has two colors per level. `…Fill` is for bars and dots. `…Label`, darker in the light theme, is for text. Quiet-time text on a hatched track sits on a solid panel-colored backing, so the hatching never runs through the glyphs.

Avatar initials pick white or `Palette.ink` at runtime, whichever contrasts more with the generated hue (`AvatarColors.initials(for:)`). White alone dropped to 1.3:1 on yellow hues.

The popover background is system glass tinted with `Palette.panel`. The tables measure against the panel color itself.

## Checking

```bash
python3 Scripts/design-contrast.py
```

The script reads the colors from the Swift source and exits with status 1 when a pair falls below its minimum. `--markdown` prints the tables below.

## Results

### Light

| Foreground | Background | Ratio | Minimum | Use |
|---|---|---:|---:|---|
| `textPrimary` | `panel` | 17.77 | 4.5 | titles, counts |
| `textPrimary` | `track` | 16.86 | 4.5 | titles in segmented controls |
| `textSecondary` | `panel` | 6.44 | 4.5 | subtitles, facts, headers |
| `textSecondary` | `track` | 6.11 | 4.5 | segment labels |
| `textSecondary` | `hover@0.7` | 6.12 | 4.5 | subtitles of a hovered row |
| `textSecondary` | `accentSoft@0.55` | 5.99 | 4.5 | subtitles of the selected row |
| `textTertiary` | `panel` | 4.93 | 4.5 | axis labels, counts, separators |
| `textTertiary` | `track` | 4.68 | 4.5 | tertiary text on the track |
| `textTertiary` | `hover@0.7` | 4.69 | 4.5 | tertiary text on a hovered row |
| `accent` | `panel` | 5.16 | 4.5 | links, accent icons |
| `accent` | `accentSoft` | 4.54 | 4.5 | search tokens, the / key |
| `onAccent` | `accentFill` | 5.16 | 4.5 | primary button, brush and cursor chips |
| `freshFill` | `panel` | 3.23 | 3.0 | fresh bars, dots, hatching |
| `freshLabel` | `panel` | 5.61 | 4.5 | fresh quiet-time label |
| `freshLabel` | `freshFill@0.15` | 4.75 | 4.5 | fresh label on its tint |
| `agingFill` | `panel` | 3.22 | 3.0 | aging bars, dots, hatching |
| `agingLabel` | `panel` | 5.52 | 4.5 | aging quiet-time label |
| `agingLabel` | `agingFill@0.15` | 4.72 | 4.5 | aging label on its tint |
| `staleFill` | `panel` | 3.23 | 3.0 | stale bars, dots, hatching |
| `staleLabel` | `panel` | 5.60 | 4.5 | stale quiet-time label |
| `staleLabel` | `staleFill@0.15` | 4.74 | 4.5 | stale label on its tint |
| `rottingFill` | `panel` | 3.91 | 3.0 | rotting bars, dots, hatching |
| `rottingLabel` | `panel` | 5.76 | 4.5 | rotting quiet-time label |
| `rottingLabel` | `rottingFill@0.15` | 4.75 | 4.5 | rotting label on its tint |
| `success` | `panel` | 5.61 | 4.5 | checks passed |
| `warning` | `panel` | 5.52 | 4.5 | checks running |
| `failure` | `panel` | 5.76 | 4.5 | checks failed |
| `line` | `panel` | 1.14 | — | decorative |
| `strong` | `panel` | 1.25 | — | decorative |
| `active` | `panel` | 1.25 | — | decorative |

### Dark

| Foreground | Background | Ratio | Minimum | Use |
|---|---|---:|---:|---|
| `textPrimary` | `panel` | 14.80 | 4.5 | titles, counts |
| `textPrimary` | `track` | 13.87 | 4.5 | titles in segmented controls |
| `textSecondary` | `panel` | 5.99 | 4.5 | subtitles, facts, headers |
| `textSecondary` | `track` | 5.61 | 4.5 | segment labels |
| `textSecondary` | `hover@0.7` | 5.60 | 4.5 | subtitles of a hovered row |
| `textSecondary` | `accentSoft@0.55` | 5.48 | 4.5 | subtitles of the selected row |
| `textTertiary` | `panel` | 5.10 | 4.5 | axis labels, counts, separators |
| `textTertiary` | `track` | 4.78 | 4.5 | tertiary text on the track |
| `textTertiary` | `hover@0.7` | 4.77 | 4.5 | tertiary text on a hovered row |
| `accent` | `panel` | 6.26 | 4.5 | links, accent icons |
| `accent` | `accentSoft` | 5.24 | 4.5 | search tokens, the / key |
| `onAccent` | `accentFill` | 4.52 | 4.5 | primary button, brush and cursor chips |
| `freshFill` | `panel` | 6.22 | 3.0 | fresh bars, dots, hatching |
| `freshLabel` | `panel` | 6.22 | 4.5 | fresh quiet-time label |
| `freshLabel` | `freshFill@0.15` | 4.95 | 4.5 | fresh label on its tint |
| `agingFill` | `panel` | 7.29 | 3.0 | aging bars, dots, hatching |
| `agingLabel` | `panel` | 7.29 | 4.5 | aging quiet-time label |
| `agingLabel` | `agingFill@0.15` | 5.64 | 4.5 | aging label on its tint |
| `staleFill` | `panel` | 6.15 | 3.0 | stale bars, dots, hatching |
| `staleLabel` | `panel` | 6.15 | 4.5 | stale quiet-time label |
| `staleLabel` | `staleFill@0.15` | 4.95 | 4.5 | stale label on its tint |
| `rottingFill` | `panel` | 4.40 | 3.0 | rotting bars, dots, hatching |
| `rottingLabel` | `panel` | 5.64 | 4.5 | rotting quiet-time label |
| `rottingLabel` | `rottingFill@0.15` | 4.83 | 4.5 | rotting label on its tint |
| `success` | `panel` | 6.22 | 4.5 | checks passed |
| `warning` | `panel` | 7.29 | 4.5 | checks running |
| `failure` | `panel` | 5.64 | 4.5 | checks failed |
| `line` | `panel` | 1.17 | — | decorative |
| `strong` | `panel` | 1.34 | — | decorative |
| `active` | `panel` | 1.42 | — | decorative |

