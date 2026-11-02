# Mockups

`render.py` builds App Store screenshots (1320 × 2868) and smaller website images
from the device screenshots in `design/screenshots/`, with the texts from
`slides.json`, in English and German, light and dark.

The sky, clouds, stars and phone frame are generated, so there are no stock
photos or device artwork to license. The background is one panorama across all
slides and joins up in the App Store. Title font: Inter (`fonts/`, SIL OFL 1.1).

1. On the Mac, run `tools/screenshots.sh`. It builds a Debug build for the iOS
   Simulator, sets the status bar to 9:41 and saves the screens in English and German,
   light and dark, to `design/screenshots/<lang>/<theme>/` (not committed). The app runs in demo mode
   (`-demo map|search|favorites`): sample places and an active location, no device
   connection, nothing saved. Release builds ignore the argument.
2. Run `design/mockups/render.py` (needs Firefox, ImageMagick and optipng). Titles
   are measured and get one size per language.
3. App Store images land in `design/mockups/out/` (6.9") and `out/6.3/` (not committed), website images
   as transparent WebP (no sky) in `site/public/img/`.

`preview.webp` shows all App Store images at a glance (rows: en light, en dark,
de light, de dark) and is updated with every full render.

![All App Store images](preview.webp)

Screenshots directly in `design/screenshots/` work for all variants. Missing ones are
rendered as a grey placeholder.
