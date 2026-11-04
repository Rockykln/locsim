# App icon

A folded map in the colors of the website's morning sky with a coral pin. It has no
outline and carries its own colors, so the same motif works as the website logo.

`make.py` writes all sources; `make.py --export` also writes the PNGs (needs Firefox and
ImageMagick):

- `AppIcon-light.svg`, `AppIcon-dark.svg`: the icon on the light and the dark sky
  (1024 × 1024, no transparency).
- `AppIcon-tinted.svg`: grayscale on black, which iOS tints itself.
- `mark.svg`: the motif alone, used as `site/public/brand-light.svg` and `brand-dark.svg`.
- `layers/`: background, map and pin as separate layers for Icon Composer, so iOS 26 can
  add its glass effect and the clear and tinted looks.

The export writes `AppIcon-1024*.png` into `LocSim/Assets.xcassets/AppIcon.appiconset/`
and `apple-touch-icon.png`, `favicon-96.png`, `favicon.ico` and the brand logos into
`site/public/`.
