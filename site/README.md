# locsim.rockykln.com

Static pages for the product, setup guide, support and the privacy policy, served by a
Cloudflare Worker with static assets only (no script).

```
cd site
npx wrangler@4 deploy
```

Pages are plain HTML in `public/` (English at `/`, German at `/de/`). Security
headers are set in `public/_headers`; the site loads no external resources. The
theme switch (auto, light, dark) is `public/theme.js` and stores the choice in the
browser only. The sky and phone images in `public/img/` come from
`design/mockups/render.py --web-assets`.

## App link

The website button in the app opens `locsim-app.rockykln.com`, a one-file Worker in
`app-link/` that only redirects to the site. Cloudflare's standard request metrics
for that hostname show how often it is opened.

```
cd site/app-link
npx wrangler@4 deploy
```
