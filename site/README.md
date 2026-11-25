# locsim.rockykln.com

Static pages for the product, setup guide, support, FAQ, privacy policy and imprint, served by a
Cloudflare Worker with static assets only (no script).

Every push to `main` deploys the site (Cloudflare Workers Builds). Deploying by hand is only
the fallback; it uploads the local `public/` folder as it is, including files that are not
committed:

```
cd site
npx wrangler@4 deploy
```

Cloudflare adds its own rules in front of `public/robots.txt` (Managed robots.txt), and Bot
Fight Mode adds a script to each page that the page's Content Security Policy blocks; both
are zone settings in the Cloudflare dashboard, not in this folder.

Pages are plain HTML in `public/` (English at `/`, German, French, Spanish, Italian, Brazilian Portuguese and Dutch at `/de/`, `/fr/`, `/es/`, `/it/`, `/pt/` and `/nl/`). Security
headers are set in `public/_headers`; the site loads no external resources. The
theme switch (auto, light, dark) is `public/theme.js` and stores the choice in the
browser only. The sky and phone images in `public/img/` come from
`design/mockups/render.py --web-assets`.

## App link

The website button in the app opens `locsim-app.rockykln.com`, a one-file Worker in
`app-link/` that only redirects to the site. Cloudflare's standard request metrics
for that hostname give a rough count: they include every request to the host, also from
bots and link previews, not only the button in the app.

The Worker is not deployed with the site; deploy it by hand after a change:

```
cd site/app-link
npx wrangler@4 deploy
```

## Adding a language

The list of languages is kept in three places: the pages in `public/` (including the
language menu, `hreflang` links and `sitemap.xml`), `sitePaths` in
`LocSim/Session/AppLinks.swift`, and the language pattern in `app-link/index.js`.
