#!/usr/bin/env python3
"""Renders App Store and website mockups from design/screenshots with headless Firefox.

App Store images get one generated sky panorama across all slides, so they join up in
the store. The README image and the website phones have no background: they are rendered
on black and on white and the transparency is taken from the difference.
Everything is drawn here; no stock photos or device artwork.

Usage: design/mockups/render.py [--readme-only|--web-assets]   (needs firefox, ImageMagick and optipng)
"""
import html
import json
import os
import random
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
SHOTS = os.path.join(REPO, "design", "screenshots")
FONTS = os.path.join(HERE, "fonts")
OUT = os.path.join(HERE, "out")
SITE = os.path.join(REPO, "site", "public", "img")
TITLED = os.path.join(OUT, "titled")
DOCS = os.path.join(REPO, "docs", "images")

WIDTH, HEIGHT = 1320, 2868          # App Store, 6.9" iPhone
TITLE_WIDTH = 1060
TITLE_MAX = 124

# Phone: screen in the screenshot's aspect ratio (1206 x 2622), bezel and metal edge around it.
SCREEN_W = 936
SCREEN_H = round(SCREEN_W * 2622 / 1206)
BEZEL, EDGE = 16, 7
PHONE_W = SCREEN_W + 2 * (BEZEL + EDGE)
PHONE_H = SCREEN_H + 2 * (BEZEL + EDGE)
PHONE_TOP = 650
PHONE_LEFT = (WIDTH - PHONE_W) // 2

THEMES = {
    "light": dict(
        title="#1d1030", subtitle="#3e2b58",
        sky=[(0, "#9d8bd3"), (0.32, "#bf98d6"), (0.62, "#eba5c8"), (0.86, "#ffc2b4"), (1, "#ffd9bd")],
        glow="#fff1d6", glow_opacity=0.75,
        cloud="#fff7f5", cloud_opacity=1, shade="#8a5d9c", shade_opacity=0.45,
        stars=0,
        metal="#e4e1ea, #8d899a 22%, #f1eff5 48%, #7a7688 74%, #d7d4de",
        shadow="0 70px 140px rgba(60, 20, 80, 0.38), 0 24px 48px rgba(60, 20, 80, 0.26)",
    ),
    "dark": dict(
        title="#ffffff", subtitle="#cdc4ea",
        sky=[(0, "#07081a"), (0.35, "#131236"), (0.68, "#2a1a4e"), (0.9, "#51275d"), (1, "#6e3463")],
        glow="#ff9a7a", glow_opacity=0.35,
        cloud="#6c4f9e", cloud_opacity=0.6, shade="#0b0920", shade_opacity=0.6,
        stars=420,
        metal="#5b5a64, #1d1d22 22%, #6a6973 48%, #18181c 74%, #4d4c55",
        shadow="0 70px 140px rgba(0, 0, 0, 0.6), 0 24px 48px rgba(0, 0, 0, 0.45)",
    ),
}

FONT_CSS = f"""
@font-face {{ font-family: "Mock"; font-style: normal; font-weight: 100 900;
  src: url("file://{FONTS}/Inter.ttf"); }}
@font-face {{ font-family: "Mock"; font-style: italic; font-weight: 100 900;
  src: url("file://{FONTS}/Inter-Italic.ttf"); }}
.title {{ font-family: "Mock"; font-style: italic; font-weight: 900; font-variation-settings: "opsz" 28;
  text-transform: uppercase; letter-spacing: 0; word-spacing: 0.06em; line-height: 1.02; white-space: pre; }}
"""

PAGE = """<!doctype html><html><head><meta charset="utf-8"><style>
{fonts}
html, body {{ margin: 0; width: {w}px; height: {h}px; overflow: hidden; background: {page_bg}; }}
.sky {{ position: absolute; top: 0; left: {sky_left}px; }}
.title {{ position: absolute; top: 170px; left: 0; right: 0; text-align: center; font-size: {size}px; color: {title}; }}
.subtitle {{ position: absolute; top: {sub_top}px; left: 60px; right: 60px; text-align: center;
  font-family: "Mock"; font-weight: 500; font-size: 50px; line-height: 1.25; color: {subtitle}; }}
.phone {{ position: absolute; left: {pl}px; top: {pt}px; width: {pw}px; height: {ph}px; box-sizing: border-box;
  border-radius: {r_edge}px; background: linear-gradient(135deg, {metal}); box-shadow: {shadow}; }}
.bezel {{ position: absolute; inset: {edge}px; border-radius: {r_bezel}px; background: #050506; }}
.screen {{ position: absolute; inset: {bezel}px; border-radius: {r_screen}px; overflow: hidden; background: #d8dadf; }}
.screen img {{ width: 100%; height: 100%; display: block; }}
.island {{ position: absolute; top: {island_top}px; left: 50%; width: {island_w}px; height: {island_h}px;
  transform: translateX(-50%); border-radius: {island_r}px; background: #000; }}
.glare {{ position: absolute; inset: 0; background: linear-gradient(118deg, rgba(255,255,255,0.10) 0%, rgba(255,255,255,0) 32%); }}
.key {{ position: absolute; width: 8px; border-radius: 4px; background: linear-gradient(90deg, {metal}); }}
.placeholder {{ position: absolute; inset: 0; display: flex; align-items: center; justify-content: center;
  font-family: "Mock"; font-size: 56px; color: #8a8d93; }}
</style></head><body>
<div class="sky">{sky}</div>
<div class="title">{title_text}</div>
<div class="subtitle">{subtitle_text}</div>
<div class="phone">
  <div class="key" style="left:-6px; top:{k1}px; height:{k1h}px"></div>
  <div class="key" style="left:-6px; top:{k2}px; height:{k2h}px"></div>
  <div class="key" style="left:-6px; top:{k3}px; height:{k2h}px"></div>
  <div class="key" style="right:-6px; top:{k4}px; height:{k4h}px"></div>
  <div class="bezel"><div class="screen">{screen}<div class="island"></div><div class="glare"></div></div></div>
</div>
</body></html>"""


def cloud_filter(name, color):
    """Fractal noise thresholded into soft clouds in one flat color."""
    rgb = [int(color[i:i + 2], 16) / 255 for i in (1, 3, 5)]
    return (f'<filter id="{name}" x="0" y="0" width="100%" height="100%" color-interpolation-filters="sRGB">'
            '<feTurbulence type="fractalNoise" baseFrequency="0.0006 0.0015" numOctaves="6" seed="11"/>'
            f'<feColorMatrix type="matrix" values="0 0 0 0 {rgb[0]:.3f}  0 0 0 0 {rgb[1]:.3f}  '
            f'0 0 0 0 {rgb[2]:.3f}  4.4 0 0 0 -1.95"/><feGaussianBlur stdDeviation="4"/></filter>')


def sky_svg(theme, width):
    """Sky with clouds and, at night, stars."""
    c = THEMES[theme]
    stops = "".join(f'<stop offset="{o}" stop-color="{col}"/>' for o, col in c["sky"])
    rng = random.Random(41)
    stars = "".join(
        f'<circle cx="{rng.uniform(0, width):.0f}" cy="{rng.uniform(0, HEIGHT * 0.62):.0f}" '
        f'r="{rng.choice((1.2, 1.6, 2, 2.6, 3.4))}" fill="#fff" opacity="{rng.uniform(0.25, 0.9):.2f}"/>'
        for _ in range(c["stars"]))

    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{HEIGHT}" viewBox="0 0 {width} {HEIGHT}">
<defs>
  <linearGradient id="sky" x1="0" y1="0" x2="0.18" y2="1">{stops}</linearGradient>
  <radialGradient id="glow" cx="0.62" cy="1.02" r="0.55" gradientTransform="scale(1 2.2) translate(0 -0.55)">
    <stop offset="0" stop-color="{c['glow']}" stop-opacity="{c['glow_opacity']}"/>
    <stop offset="1" stop-color="{c['glow']}" stop-opacity="0"/>
  </radialGradient>
  <linearGradient id="fade" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#fff" stop-opacity="0.25"/>
    <stop offset="0.45" stop-color="#fff" stop-opacity="0.55"/>
    <stop offset="1" stop-color="#fff" stop-opacity="1"/>
  </linearGradient>
  <mask id="lower"><rect width="{width}" height="{HEIGHT}" fill="url(#fade)"/></mask>
  {cloud_filter("light", c["cloud"])}
  {cloud_filter("shade", c["shade"])}
</defs>
<rect width="{width}" height="{HEIGHT}" fill="url(#sky)"/>
<rect width="{width}" height="{HEIGHT}" fill="url(#glow)"/>
{stars}
<g mask="url(#lower)">
  <rect y="30" width="{width}" height="{HEIGHT}" filter="url(#shade)" opacity="{c['shade_opacity']}"/>
  <rect width="{width}" height="{HEIGHT}" filter="url(#light)" opacity="{c['cloud_opacity']}"/>
</g>
</svg>"""


def firefox(page_html, target, size, work):
    page = os.path.join(work, "page.html")
    with open(page, "w") as f:
        f.write(page_html)
    profile = tempfile.mkdtemp(dir=work)
    subprocess.run(
        ["firefox", "--headless", "--no-remote", "--profile", profile,
         f"--window-size={size[0]},{size[1]}", "--screenshot", target, f"file://{page}"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=120, check=False)
    shutil.rmtree(profile, ignore_errors=True)


def transparent(on_black, on_white, target, width=660):
    """Recovers color and alpha from renders on black and on white."""
    alpha = target + ".alpha.png"
    subprocess.run(["magick", on_black, on_white, "-alpha", "off", "-compose", "difference", "-composite",
                    "-colorspace", "gray", "-negate", alpha], check=True)
    subprocess.run(["magick", on_black, "(", alpha, "-colorspace", "sRGB", "-type", "TrueColor", ")",
                    "-alpha", "off", "-compose", "DivideSrc", "-composite", alpha, "-alpha", "off",
                    "-compose", "CopyOpacity", "-composite", "-trim", "+repage", "-resize", f"{width}x",
                    "-quality", "85", "-define", "webp:method=6", "-define", "webp:alpha-quality=90",
                    target], check=True)
    os.remove(alpha)


def title_sizes(slides, work):
    """Measures every title line at 100px and returns one font size per language."""
    lines = [(lang, line) for s in slides for lang in ("en", "de") for line in s[lang]["title"].split("\n")]
    row = 180
    body = "".join(f'<div class="title" style="height:{row}px;font-size:100px;padding-left:20px">'
                   f"{html.escape(line)}</div>" for _, line in lines)
    page = f"<!doctype html><html><head><meta charset='utf-8'><style>{FONT_CSS}" \
           f"body{{margin:0;background:#fff;color:#000}}</style></head><body>{body}</body></html>"
    shot = os.path.join(work, "measure.png")
    firefox(page, shot, (3200, row * len(lines)), work)
    widest = {}
    for i, (lang, _) in enumerate(lines):
        w = subprocess.run(["convert", shot, "-crop", f"3200x{row}+0+{i * row}", "+repage",
                            "-fuzz", "10%", "-trim", "-format", "%w", "info:"],
                           capture_output=True, text=True, check=True).stdout
        widest[lang] = max(widest.get(lang, 0), int(w))
    return {lang: min(TITLE_MAX, int(100 * TITLE_WIDTH / w)) for lang, w in widest.items()}


def screen_html(file, lang, theme, work):
    """Uses the most specific screenshot: <lang>/<theme>/, then <lang>/, then the top level."""
    for parts in ((lang, theme), (lang,), ()):
        shot = os.path.join(SHOTS, *parts, file)
        if os.path.exists(shot):
            name = "-".join(parts + (file,))
            shutil.copy(shot, os.path.join(work, name))
            return f'<img src="{html.escape(name)}" alt="">'
    return '<div class="placeholder">Screenshot</div>'


def slide_page(index, slide, lang, theme, size, sky, work, page_bg="#000", bare=False):
    c = THEMES[theme]
    text = dict(title="", subtitle="") if bare else slide[lang]
    lines = text["title"].count("\n") + 1
    r_screen = round(SCREEN_W * 0.137)
    s = SCREEN_W / 402
    return PAGE.format(
        fonts=FONT_CSS, page_bg=page_bg, w=WIDTH, h=HEIGHT, sky_left=-index * WIDTH, sky=sky, size=size,
        sub_top=round(170 + size * 1.02 * lines + 44),
        title=c["title"], subtitle=c["subtitle"], metal=c["metal"], shadow="none" if bare else c["shadow"],
        title_text=html.escape(text["title"]), subtitle_text=html.escape(text["subtitle"]),
        pl=PHONE_LEFT, pt=PHONE_TOP, pw=PHONE_W, ph=PHONE_H, edge=EDGE, bezel=BEZEL,
        r_screen=r_screen, r_bezel=r_screen + BEZEL, r_edge=r_screen + BEZEL + EDGE,
        island_top=round(11 * s), island_w=round(126 * s), island_h=round(37 * s), island_r=round(18.5 * s),
        k1=round(PHONE_H * 0.13), k1h=round(PHONE_H * 0.035),
        k2=round(PHONE_H * 0.2), k3=round(PHONE_H * 0.27), k2h=round(PHONE_H * 0.055),
        k4=round(PHONE_H * 0.22), k4h=round(PHONE_H * 0.085),
        screen=screen_html(slide["screenshot"], lang, theme, work))


def readme(slides):
    """Joins the English website images into one row per theme for the README."""
    os.makedirs(DOCS, exist_ok=True)
    for theme in THEMES:
        parts = []
        for i, slide in enumerate(slides):
            if i:
                parts += ["-size", "60x1", "xc:none"]
            parts.append(os.path.join(TITLED, f"{slide['id']}-en-{theme}.webp"))
        subprocess.run(["magick", "-background", "none", *parts, "-gravity", "center", "+append",
                        "-bordercolor", "none", "-border", "40", "-resize", "1600x", "-quality", "85", "-define", "webp:method=6",
                        "-define", "webp:alpha-quality=90", os.path.join(DOCS, f"screenshots-{theme}.webp")],
                       check=True)


def preview(slides):
    """One overview of all App Store images (en/de, light/dark) for the repo; out/ is not committed."""
    rows = []
    for lang in ("en", "de"):
        for theme in THEMES:
            rows.append(["(", *[os.path.join(OUT, f"{s['id']}-{lang}-{theme}.png") for s in slides],
                         "-resize", "400x", "+append", ")"])
    subprocess.run(["magick", *[a for row in rows for a in row], "-append", "-strip",
                    "-quality", "82", "-define", "webp:method=6", os.path.join(HERE, "preview.webp")], check=True)


def medium_display(path):
    """App Store Connect requires 1206 x 2622 (6.3") as well; written to out/6.3/."""
    target = os.path.join(OUT, "6.3", os.path.basename(path))
    os.makedirs(os.path.dirname(target), exist_ok=True)
    subprocess.run(["convert", path, "-resize", "1206x2622!", "-alpha", "off", "-strip", target], check=True)
    subprocess.run(["optipng", "-quiet", "-o2", target], check=True)


def web_assets(slides, work):
    """Website hero and feature images: the sky alone and each phone without text."""
    for theme in THEMES:
        sky = os.path.join(work, "sky.png")
        firefox(f"<!doctype html><html><body style='margin:0'>{sky_svg(theme, WIDTH * 3)}</body></html>",
                sky, (WIDTH * 3, HEIGHT), work)
        subprocess.run(["magick", sky, "-crop", f"{WIDTH * 3}x{HEIGHT}+0+0", "+repage", "-alpha", "off", "-resize",
                        "2400x", "-strip", "-quality", "78", "-define", "webp:method=6",
                        os.path.join(SITE, f"sky-{theme}.webp")], check=True)
        for slide in slides:
            for lang in ("en", "de"):
                shots = []
                for bg in ("#000", "#fff"):
                    shot = os.path.join(work, f"phone-{bg[1:]}.png")
                    firefox(slide_page(0, slide, lang, theme, 100, "", work, bg, bare=True), shot, (WIDTH, HEIGHT), work)
                    shots.append(shot)
                name = f"phone-{slide['id']}-{lang}-{theme}"
                transparent(*shots, os.path.join(SITE, f"{name}.webp"), width=900)
                print(name)


def main():
    readme_only = "--readme-only" in sys.argv[1:]
    slides = json.load(open(os.path.join(HERE, "slides.json")))
    os.makedirs(OUT, exist_ok=True)
    os.makedirs(SITE, exist_ok=True)
    os.makedirs(TITLED, exist_ok=True)
    with tempfile.TemporaryDirectory() as work:
        if "--web-assets" in sys.argv[1:]:
            return web_assets(slides, work)
        sizes = title_sizes(slides, work)
        for theme in THEMES:
            sky = sky_svg(theme, WIDTH * len(slides))
            for index, slide in enumerate(slides):
                for lang in ("en", "de"):
                    name = f"{slide['id']}-{lang}-{theme}"
                    if not readme_only:
                        target = os.path.join(OUT, f"{name}.png")
                        firefox(slide_page(index, slide, lang, theme, sizes[lang], sky, work),
                                target, (WIDTH, HEIGHT), work)
                        subprocess.run(["convert", target, "-crop", f"{WIDTH}x{HEIGHT}+0+0", "+repage",
                                        "-alpha", "off", "-strip", target], check=True)
                        subprocess.run(["optipng", "-quiet", "-o2", target], check=True)
                        medium_display(target)
                    shots = []
                    for bg in ("#000", "#fff"):
                        shot = os.path.join(work, f"site-{bg[1:]}.png")
                        firefox(slide_page(index, slide, lang, theme, sizes[lang], "", work, bg),
                                shot, (WIDTH, HEIGHT), work)
                        shots.append(shot)
                    transparent(*shots, os.path.join(TITLED, f"{name}.webp"))
                    print(name)
    readme(slides)
    if not readme_only:
        preview(slides)


if __name__ == "__main__":
    main()
