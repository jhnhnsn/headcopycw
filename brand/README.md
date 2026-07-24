# HeadCopy brand assets

The **HeadCopy** wordmark, rendered as vector outlines (no font dependency).
Set in Manrope ExtraBold, tightly tracked; the capital **C** carries the accent.

## Wordmark

| File | Use |
| --- | --- |
| `headcopy-wordmark.svg` | **Two-tone** — ink letters, amber `C`. The primary lockup for light backgrounds (README, store listing, web). |
| `headcopy-wordmark-mono.svg` | **One-color** — all paths use `currentColor`, so it takes whatever color you set (CSS `color:`, or a fill override). Use on dark grounds or when the accent can't be used. |

## App icon

The **HC** monogram — same Manrope ExtraBold, same accent as the wordmark:
ink **H**, amber **C**. Two grounds; pick per platform preference.

| File | Ground | Use |
| --- | --- | --- |
| `headcopy-icon.svg` / `headcopy-icon-1024.png` | paper `#F6F2EA` | Primary. Rounded square, ink H + amber C. |
| `headcopy-icon-square.svg` / `headcopy-icon-1024-square.png` | paper | Full-bleed (no corner rounding) for generators that apply their own mask. |
| `headcopy-icon-dark.svg` / `headcopy-icon-dark-1024.png` | dark `#17140F` | Alt. Paper H + amber C on the panel black. |

The `-1024.png` masters are ready to feed a launcher-icon generator
(e.g. `flutter_launcher_icons`) to fill the native Android/iOS slots.
These are **design masters only** — they are not yet wired in as the app's
launcher icon.

## Colors

- Ink `#1A1712` (brown-black)
- Amber `#EA6A1E` (dial amber accent)

## Notes

- The mark is a single word — camel-case `HeadCopy`. Never all-caps, never two words.
- Keep clear space of about one cap-height on every side.
- The SVGs are resolution-independent; scale to any size. They hold down to ~16 px tall.
- The app's in-UI title stays as text (the app bundles no assets by design). These
  files are for README / store / web / marketing use.
