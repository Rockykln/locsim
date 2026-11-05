# App icon

A folded map in the colors of the website's morning sky with a coral pin. It has no
outline and carries its own colors, so the same motif works as the website logo.

`make.py` writes all sources; `make.py --export` also writes the PNGs (needs Firefox and
ImageMagick 7; set `FIREFOX` if it is not on the PATH or in `/Applications`). The PNGs are
replaced only when all of them rendered:

- `AppIcon-light.svg`, `AppIcon-dark.svg`: the icon on the light and the dark sky
  (1024 × 1024, no transparency).
- `AppIcon-tinted.svg`: grayscale on black, which iOS tints itself.
- `mark.svg`: the motif alone, used as `site/public/brand-light.svg` and `brand-dark.svg`.
- `layers/`: map and pin as separate layers for Icon Composer (the backgrounds are only
  for the flat PNGs; in Icon Composer the sky is the icon's fill).
- `AppIcon.icon`: the Icon Composer file built from those layers, with the glass settings.
  iOS 26 uses it; older versions fall back to the PNGs in the asset catalog. Changes to
  the motif have to be made in both: here in `make.py`, and in Icon Composer by importing
  the new layers. Mind the pin's lift: `layers/pin.svg` is already lifted by 15 px, while
  the pin inside `AppIcon.icon` is not and gets its lift from a -15 pt offset set in Icon
  Composer. If you import `layers/pin.svg` there, set that offset to 0, or the pin is
  lifted twice.

The export writes `AppIcon-1024*.png` into `LocSim/Assets.xcassets/AppIcon.appiconset/`
and `apple-touch-icon.png`, `favicon-96.png`, `favicon.ico` and the brand logos into
`site/public/`.
