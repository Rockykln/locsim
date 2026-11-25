# Social preview

`github-social-preview.png` (1280 × 640) is uploaded manually under the repository's
*Settings > General > Social preview*. The website uses `site/public/og.jpg` and
`og-de.jpg` (1200 × 630, JPEG so they stay small enough for messenger previews) through Open Graph tags.

All three are made by `design/mockups/render.py --social` (light, the default) or
`--social dark`, from the current screenshots in `design/screenshots/` and a generated sky,
laid out as HTML and rendered with headless Firefox. The texts per language are in
`social.json`.
