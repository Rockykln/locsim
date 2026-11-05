#!/usr/bin/env python3
"""Renders App Store and website mockups from design/screenshots with headless Firefox.

App Store images get one generated sky panorama across all slides, so they join up in
the store. The README image and the website phones have no background: they are rendered
on black and on white and the transparency is taken from the difference.
Everything is drawn here; no stock photos or device artwork.

Usage: design/mockups/render.py [--readme-only|--web-assets|--social]
       [--lang en,de] [--slide 1-map,...] [--theme light] [--size 6.9,duo-inner] [--jobs N]
(needs firefox, ImageMagick 7 and oxipng or optipng)
"""
import argparse
import hashlib
import html
import json
import os
import pathlib
import random
import shutil
import subprocess
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor, as_completed

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
SHOTS = os.path.join(REPO, "design", "screenshots")
FONTS = os.path.join(HERE, "fonts")
OUT = os.path.join(HERE, "out")
CACHE = os.path.join(OUT, ".cache")
SITE = os.path.join(REPO, "site", "public", "img")
PUBLIC = os.path.join(REPO, "site", "public")
SOCIAL = os.path.join(REPO, "design", "social")
TITLED = os.path.join(OUT, "titled")
DOCS = os.path.join(REPO, "docs", "images")

# Set by check_tools(); on macOS firefox is usually not on PATH.
FIREFOX = "firefox"
FIREFOX_VERSION = ""
PROFILE = None  # warmed-up profile, copied for every render (about 1 s faster per start)

ALL_LANGS = ["en", "de", "fr", "es", "it"]
LANGS = list(ALL_LANGS)
WIDTH, HEIGHT = 1320, 2868          # App Store, 6.9" iPhone: the reference layout
TITLE_WIDTH = 1060
TITLE_MAX = 124

# App Store sizes. "shots" is the screenshot folder under <lang>/<theme>/ ("" = the iPhone
# screenshots), "aspect" the screen's width/height, "derive" smaller sizes scaled from it.
# Duo sizes: App Store Connect screenshot specifications; required from April 2027 for
# builds with the iOS 27.1 SDK. Island and corner radius of the Duo screens: check against
# the Duo simulator before the first upload.
SIZES = {
    "6.9": dict(canvas=(1320, 2868), shots="", aspect=1206 / 2622, island=True, derive=(1206, 2622)),
    "duo-inner": dict(canvas=(2007, 2853), shots="duo-inner", aspect=2007 / 2853, island=False),
    "duo-outer": dict(canvas=(1398, 2034), shots="duo-outer", aspect=1398 / 2034, island=False),
}

BEZEL, EDGE = 16, 7


def layout(size):
    """Phone and text geometry for one App Store size, scaled from the 6.9" layout."""
    spec = SIZES[size]
    w, h = spec["canvas"]
    k = h / HEIGHT
    screen_h = round(2035 * k)
    screen_w = min(round(screen_h * spec["aspect"]), round(w * 0.8))
    bezel, edge = round(BEZEL * k), round(EDGE * k)
    phone_w, phone_h = screen_w + 2 * (bezel + edge), screen_h + 2 * (bezel + edge)
    return dict(w=w, h=h, k=min(k, w / WIDTH), screen_w=screen_w, screen_h=screen_h, bezel=bezel, edge=edge,
                phone_w=phone_w, phone_h=phone_h, phone_top=round(650 * k), phone_left=(w - phone_w) // 2,
                title_top=round(170 * k), island=spec["island"])


THEMES = {
    # A bright morning sky: the same hues as the dark night sky, but pale, so the light
    # screenshots read as light at a glance.
    "light": dict(
        title="#1d1030", subtitle="#4b3f63",
        sky=[(0, "#cdc3f3"), (0.3, "#ddcdf3"), (0.6, "#f3cfe2"), (0.85, "#ffd8c7"), (1, "#ffe6d4")],
        glow="#fff6ea", glow_opacity=0.8,
        cloud="#ffffff", cloud_opacity=0.9, shade="#b29fdc", shade_opacity=0.38,
        stars=0,
        metal="#e4e1ea, #8d899a 22%, #f1eff5 48%, #7a7688 74%, #d7d4de",
        shadow="0 70px 140px rgba(70, 40, 110, 0.22), 0 24px 48px rgba(70, 40, 110, 0.16)",
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

# Link previews are small and sit on white chat backgrounds: the light sky a step more
# saturated, so it does not read as a white box.
SOCIAL_SKY = dict(THEMES["light"], sky=[(0, "#b8abef"), (0.3, "#ccb8f0"), (0.6, "#eeb9d8"), (0.85, "#ffc6ae"),
                                        (1, "#ffd9c0")], cloud_opacity=0.75, shade_opacity=0.45)

FONT_CSS = f"""
@font-face {{ font-family: "Mock"; font-style: normal; font-weight: 100 900;
  src: url("{pathlib.Path(FONTS, 'Inter.ttf').as_uri()}"); }}
@font-face {{ font-family: "Mock"; font-style: italic; font-weight: 100 900;
  src: url("{pathlib.Path(FONTS, 'Inter-Italic.ttf').as_uri()}"); }}
.title {{ font-family: "Mock"; font-style: italic; font-weight: 900; font-variation-settings: "opsz" 28;
  text-transform: uppercase; letter-spacing: 0; word-spacing: 0.06em; line-height: 1.02; white-space: pre; }}
"""

PAGE = """<!doctype html><html lang="{lang}"><head><meta charset="utf-8"><style>
{fonts}
html, body {{ margin: 0; width: {w}px; height: {h}px; overflow: hidden; background: {page_bg}; }}
.sky {{ position: absolute; top: 0; left: {sky_left}px; }}
.title {{ position: absolute; top: {title_top}px; left: 0; right: 0; text-align: center; font-size: {size}px; color: {title}; }}
.subtitle {{ position: absolute; top: {sub_top}px; left: {sub_side}px; right: {sub_side}px; text-align: center;
  font-family: "Mock"; font-weight: 500; font-size: {sub_size}px; line-height: 1.25; color: {subtitle};
  text-wrap: balance; }}
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
  <div class="bezel"><div class="screen">{screen}{island}<div class="glare"></div></div></div>
</div>
</body></html>"""


def digest(*parts, script=True):
    """Cache key: Firefox, the fonts, this script (unless script=False) and whatever else
    the output depends on."""
    h = hashlib.sha256()
    for part in (FIREFOX_VERSION, open(__file__, "rb").read() if script else b"",
                 *[open(os.path.join(FONTS, f), "rb").read() for f in ("Inter.ttf", "Inter-Italic.ttf")], *parts):
        h.update(part if isinstance(part, bytes) else str(part).encode())
        h.update(b"\0")
    return h.hexdigest()[:20]


def cloud_filter(name, color):
    """Fractal noise thresholded into soft clouds in one flat color."""
    rgb = [int(color[i:i + 2], 16) / 255 for i in (1, 3, 5)]
    return (f'<filter id="{name}" x="0" y="0" width="100%" height="100%" color-interpolation-filters="sRGB">'
            '<feTurbulence type="fractalNoise" baseFrequency="0.0006 0.0015" numOctaves="6" seed="11"/>'
            f'<feColorMatrix type="matrix" values="0 0 0 0 {rgb[0]:.3f}  0 0 0 0 {rgb[1]:.3f}  '
            f'0 0 0 0 {rgb[2]:.3f}  4.4 0 0 0 -1.95"/><feGaussianBlur stdDeviation="4"/></filter>')


def sky_svg(theme, width, height=HEIGHT):
    """Sky with clouds and, at night, stars. theme is a THEMES key or a theme dict."""
    c = THEMES[theme] if isinstance(theme, str) else theme
    stops = "".join(f'<stop offset="{o}" stop-color="{col}"/>' for o, col in c["sky"])
    rng = random.Random(41)
    stars = "".join(
        f'<circle cx="{rng.uniform(0, width):.0f}" cy="{rng.uniform(0, height * 0.62):.0f}" '
        f'r="{rng.choice((1.2, 1.6, 2, 2.6, 3.4))}" fill="#fff" opacity="{rng.uniform(0.25, 0.9):.2f}"/>'
        for _ in range(c["stars"]))

    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">
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
  <mask id="lower"><rect width="{width}" height="{height}" fill="url(#fade)"/></mask>
  {cloud_filter("light", c["cloud"])}
  {cloud_filter("shade", c["shade"])}
</defs>
<rect width="{width}" height="{height}" fill="url(#sky)"/>
<rect width="{width}" height="{height}" fill="url(#glow)"/>
{stars}
<g mask="url(#lower)">
  <rect y="30" width="{width}" height="{height}" filter="url(#shade)" opacity="{c['shade_opacity']}"/>
  <rect width="{width}" height="{height}" filter="url(#light)" opacity="{c['cloud_opacity']}"/>
</g>
</svg>"""


def warm_profile(work):
    """One Firefox start with a fresh profile, kept as the template for all renders."""
    global PROFILE
    PROFILE = os.path.join(work, "profile")
    os.makedirs(PROFILE)
    page = os.path.join(work, "blank.html")
    with open(page, "w") as f:
        f.write("<!doctype html><body></body>")
    subprocess.run([FIREFOX, "--headless", "--no-remote", "--profile", PROFILE, "--window-size=100,100",
                    "--screenshot", os.path.join(work, "blank.png"), pathlib.Path(page).as_uri()],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=180, check=False)
    for lock in ("lock", ".parentlock"):
        if os.path.lexists(os.path.join(PROFILE, lock)):
            os.remove(os.path.join(PROFILE, lock))


def firefox(page_html, target, size, work):
    """Renders a page; fails loudly instead of leaving an older image of the same name in place."""
    page = os.path.join(work, "page.html")
    with open(page, "w") as f:
        f.write(page_html)
    if os.path.exists(target):
        os.remove(target)
    profile = tempfile.mkdtemp(dir=work)
    if PROFILE:
        shutil.copytree(PROFILE, profile, dirs_exist_ok=True)
    result = subprocess.run(
        [FIREFOX, "--headless", "--no-remote", "--profile", profile,
         f"--window-size={size[0]},{size[1]}", "--screenshot", target, f"file://{page}"],
        stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True, timeout=180, check=False)
    shutil.rmtree(profile, ignore_errors=True)
    if not os.path.exists(target) or os.path.getsize(target) == 0:
        raise RuntimeError(f"Firefox did not render {os.path.basename(target)}: {result.stderr.strip()[-400:]}")
    w, h = subprocess.run(["magick", "identify", "-format", "%w %h", target],
                          capture_output=True, text=True, check=True).stdout.split()
    if int(w) < size[0] or int(h) < size[1]:
        raise RuntimeError(f"{os.path.basename(target)} is {w}x{h}, expected {size[0]}x{size[1]}")


def optimize(png, level="2"):
    """oxipng is multithreaded and much faster; optipng is the fallback."""
    if shutil.which("oxipng"):
        subprocess.run(["oxipng", "-q", "-o", level, "--strip", "safe", png], check=True)
    else:
        subprocess.run(["optipng", "-quiet", f"-o{level}", png], check=True)


def keep_if_same(new, target, fuzz="0.5%"):
    """Moves new to target unless target already looks the same, so re-renders on another
    machine (other Firefox, other font rasterizer) do not show up as git changes."""
    if os.path.exists(target):
        same = subprocess.run(["magick", "compare", "-metric", "AE", "-fuzz", fuzz, new, target, "null:"],
                              capture_output=True, text=True)
        # AE = pixels that differ by more than fuzz; a few hundred is anti-aliasing noise.
        try:
            differ = float(same.stderr.split()[0]) if same.returncode in (0, 1) else float("inf")
        except (IndexError, ValueError):
            differ = float("inf")
        if differ < 500:
            os.remove(new)
            return False
    os.replace(new, target)
    return True


def transparent(on_black, on_white, target, work, width=660):
    """Recovers color and alpha from renders on black and on white."""
    # In the work folder, so nothing is left next to the target (e.g. in site/public) on failure.
    alpha = os.path.join(work, "alpha.png")
    new = os.path.join(work, "new-" + os.path.basename(target))
    subprocess.run(["magick", on_black, on_white, "-alpha", "off", "-compose", "difference", "-composite",
                    "-colorspace", "gray", "-negate", alpha], check=True)
    # -respect-parentheses: otherwise -type TrueColor stays set for the second read of alpha.png.
    subprocess.run(["magick", "-respect-parentheses", on_black, "(", alpha, "-colorspace", "sRGB", "-type", "TrueColor", ")",
                    "-alpha", "off", "-compose", "DivideSrc", "-composite", alpha, "-alpha", "off",
                    "-compose", "CopyOpacity", "-composite", "-trim", "+repage", "-resize", f"{width}x",
                    "-quality", "85", "-define", "webp:method=6", "-define", "webp:alpha-quality=90",
                    new], check=True)
    os.remove(alpha)
    keep_if_same(new, target)


def title_sizes(slides, work):
    """Measures every title line at 100px and returns one font size per language.
    Cached: only a change of text, font or this script measures again."""
    lines = [(lang, line) for s in slides for lang in LANGS for line in s[lang]["title"].split("\n")]
    cached = os.path.join(CACHE, f"titles-{digest(json.dumps(lines))}.json")
    if os.path.exists(cached):
        return json.load(open(cached))
    row = 180
    body = "".join(f'<div class="title" lang="{lang}" style="height:{row}px;font-size:100px;padding-left:20px">'
                   f"{html.escape(line)}</div>" for lang, line in lines)
    page = f"<!doctype html><html><head><meta charset='utf-8'><style>{FONT_CSS}" \
           f"body{{margin:0;background:#fff;color:#000}}</style></head><body>{body}</body></html>"
    shot = os.path.join(work, "measure.png")
    firefox(page, shot, (3200, row * len(lines)), work)
    # One magick call: -crop WxH without offset tiles the image into one frame per row.
    out = subprocess.run(["magick", shot, "-crop", f"3200x{row}", "+repage", "-fuzz", "10%", "-trim",
                          "-format", "%w\\n", "info:"], capture_output=True, text=True, check=True).stdout.split()
    if len(out) != len(lines):
        raise RuntimeError(f"measured {len(out)} title lines, expected {len(lines)}")
    widest = {}
    for (lang, _), w in zip(lines, out):
        widest[lang] = max(widest.get(lang, 0), int(w))
    sizes = {lang: min(TITLE_MAX, int(100 * TITLE_WIDTH / w)) for lang, w in widest.items()}
    os.makedirs(CACHE, exist_ok=True)
    json.dump(sizes, open(cached, "w"))
    return sizes


def check_subtitles(slides, work):
    """Fails when a subtitle needs more than two lines: a third one runs into the phone."""
    items = [(s["id"], lang, s[lang]["subtitle"]) for s in slides for lang in LANGS]
    stamp = os.path.join(CACHE, f"subtitles-{digest(json.dumps(items))}.ok")
    if os.path.exists(stamp):
        return
    row = 240
    body = "".join(f'<div lang="{lang}" style="height:{row}px"><div class="subtitle">{html.escape(text)}</div></div>'
                   for _, lang, text in items)
    page = (f"<!doctype html><html><head><meta charset='utf-8'><style>{FONT_CSS}"
            "body{margin:0;background:#fff;color:#000} .subtitle{width:1200px;text-align:center;font-family:'Mock';"
            "font-weight:500;font-size:50px;line-height:1.25;text-wrap:balance}</style></head>"
            f"<body>{body}</body></html>")
    shot = os.path.join(work, "subtitles.png")
    firefox(page, shot, (1200, row * len(items)), work)
    heights = subprocess.run(["magick", shot, "-crop", f"1200x{row}", "+repage", "-fuzz", "10%", "-trim",
                              "-format", "%h\\n", "info:"], capture_output=True, text=True, check=True).stdout.split()
    # Two lines of 50px text are about 110px high from cap height to descender, three about 170px.
    long = [f"{sid} ({lang})" for (sid, lang, _), h in zip(items, heights) if int(h) > 140]
    if long:
        raise RuntimeError("subtitle longer than two lines: " + ", ".join(long))
    open(stamp, "w").close()


# The Simulator's Lock Screen shows the Control Center grabber below the status icons, at first
# with a switch icon under it; a real iPhone hides both once Control Center was used. Both are
# covered with the mirrored strip of wallpaper below them.
GRABBER = dict(x=890, y=126, w=190, h=106)


def hide_grabber(path):
    size = subprocess.run(["magick", "identify", "-format", "%wx%h", path],
                          capture_output=True, text=True, check=True).stdout
    if size != "1206x2622":
        return
    g = GRABBER
    subprocess.run(["magick", path,
                    "(", "+clone", "-crop", f"{g['w']}x{g['h']}+{g['x']}+{g['y'] + g['h']}", "+repage", "-flip", ")",
                    "-geometry", f"+{g['x']}+{g['y']}", "-composite", path], check=True)


def screen_html(file, lang, theme, work, shots=""):
    """Uses the most specific screenshot: <lang>/<theme>/, then <lang>/, then the top level.
    shots is the size's subfolder; a Duo size never falls back to iPhone screenshots."""
    for parts in ((lang, theme), (lang,), ()):
        shot = os.path.join(SHOTS, *parts, shots, file)
        if os.path.exists(shot):
            name = "-".join(parts + ((shots,) if shots else ()) + (file,))
            shutil.copy(shot, os.path.join(work, name))
            if file == "4-live.png":
                hide_grabber(os.path.join(work, name))
            return f'<img src="{html.escape(name)}" alt="">', shot
    return '<div class="placeholder">Screenshot</div>', None


def slide_page(index, slide, lang, theme, size, sky, work, page_bg="#000", bare=False, app_size="6.9"):
    c = THEMES[theme]
    g = layout(app_size)
    k = g["k"]
    text = dict(title="", subtitle="") if bare else slide[lang]
    lines = text["title"].count("\n") + 1
    size = round(size * k)
    r_screen = round(g["screen_w"] * 0.137)
    s = g["screen_w"] / 402
    ph = g["phone_h"]
    screen, _ = screen_html(slide["screenshot"], lang, theme, work, SIZES[app_size]["shots"])
    island = (f'<div class="island"></div>' if g["island"] else "")
    return PAGE.format(
        fonts=FONT_CSS, lang=lang, page_bg=page_bg, w=g["w"], h=g["h"], sky_left=-index * g["w"], sky=sky,
        size=size, title_top=g["title_top"], sub_top=round(g["title_top"] + size * 1.02 * lines + 44 * k),
        sub_side=round(60 * k), sub_size=round(50 * k),
        title=c["title"], subtitle=c["subtitle"], metal=c["metal"], shadow="none" if bare else c["shadow"],
        title_text=html.escape(text["title"]), subtitle_text=html.escape(text["subtitle"]),
        pl=g["phone_left"], pt=g["phone_top"], pw=g["phone_w"], ph=ph, edge=g["edge"], bezel=g["bezel"],
        r_screen=r_screen, r_bezel=r_screen + g["bezel"], r_edge=r_screen + g["bezel"] + g["edge"],
        island=island,
        island_top=round(11 * s), island_w=round(126 * s), island_h=round(37 * s), island_r=round(18.5 * s),
        k1=round(ph * 0.13), k1h=round(ph * 0.035),
        k2=round(ph * 0.2), k3=round(ph * 0.27), k2h=round(ph * 0.055),
        k4=round(ph * 0.22), k4h=round(ph * 0.085),
        screen=screen)


def readme_slides(slides):
    """The slides marked "readme", or all of them if none is marked."""
    return [s for s in slides if s.get("readme")] or slides


def readme(slides, work):
    """Joins the English images of the README slides into one row per theme, plus a
    narrow version with the first and the last of them for phones, where three are too small."""
    os.makedirs(DOCS, exist_ok=True)
    picked = readme_slides(slides)
    narrow = [picked[0], picked[-1]] if len(picked) > 2 else picked
    for theme in THEMES:
        for chosen, suffix, width in ((picked, "", "1600x"), (narrow, "-narrow", "900x")):
            parts = []
            for i, slide in enumerate(chosen):
                if i:
                    parts += ["-size", "60x1", "xc:none"]
                parts.append(os.path.join(TITLED, f"{slide['id']}-en-{theme}.webp"))
            new = os.path.join(work, f"screenshots-{theme}{suffix}.webp")
            subprocess.run(["magick", "-background", "none", *parts, "-gravity", "center", "+append",
                            "-bordercolor", "none", "-border", "40", "-resize", width, "-quality", "85",
                            "-define", "webp:method=6", "-define", "webp:alpha-quality=90", new], check=True)
            keep_if_same(new, os.path.join(DOCS, f"screenshots-{theme}{suffix}.webp"))


def preview(slides, work):
    """One overview of all App Store images (each language, light and dark); out/ is not committed."""
    rows = []
    for lang in LANGS:
        for theme in THEMES:
            rows.append(["(", *[os.path.join(OUT, f"{s['id']}-{lang}-{theme}.png") for s in slides],
                         "-resize", "400x", "+append", ")"])
    new = os.path.join(work, "preview.webp")
    subprocess.run(["magick", *[a for row in rows for a in row], "-append", "-strip",
                    "-quality", "82", "-define", "webp:method=6", new], check=True)
    keep_if_same(new, os.path.join(HERE, "preview.webp"))


def medium_display(path, size):
    """App Store Connect requires 1206 x 2622 (6.3") as well; written to out/6.3/."""
    target = os.path.join(OUT, "6.3", os.path.basename(path))
    os.makedirs(os.path.dirname(target), exist_ok=True)
    subprocess.run(["magick", path, "-resize", f"{size[0]}x{size[1]}!", "-alpha", "off", "-strip", target],
                   check=True)
    # out/ is not committed: -o 1 is 40 % faster than -o 2 for 8 % larger files.
    optimize(target, "1")


def run_jobs(fn, items, jobs):
    """Runs fn on each item in parallel and prints what it returns. The first failure cancels
    the jobs that have not started yet and ends the run with an error."""
    results = []
    with ThreadPoolExecutor(max_workers=jobs) as pool:
        futures = [pool.submit(fn, item) for item in items]
        try:
            for future in as_completed(futures):
                result = future.result()
                results.append(result)
                if isinstance(result, str):
                    print(result, flush=True)
        except BaseException as exc:
            pool.shutdown(wait=True, cancel_futures=True)
            if isinstance(exc, Exception):
                sys.exit(f"render failed: {exc}")
            raise
    return results


def panorama(theme, app_size, count, work_root):
    """The sky across all slides of one size; cached, since it takes the longest to draw."""
    w, h = SIZES[app_size]["canvas"]
    svg = sky_svg(theme, w * count, h)
    cached = os.path.join(CACHE, f"sky-{digest(svg, script=False)}.png")
    if not os.path.exists(cached):
        work = tempfile.mkdtemp(dir=work_root)
        shot = os.path.join(work, "sky.png")
        firefox(f"<!doctype html><html><body style='margin:0'>{svg}</body></html>", shot, (w * count, h), work)
        os.makedirs(CACHE, exist_ok=True)
        os.replace(shot, cached)
        shutil.rmtree(work, ignore_errors=True)
    return (theme, app_size), f'<img src="{pathlib.Path(cached).as_uri()}" width="{w * count}" height="{h}" alt="">'


def web_sky(theme, work_root):
    work = tempfile.mkdtemp(dir=work_root)
    sky = os.path.join(work, "sky.png")
    firefox(f"<!doctype html><html><body style='margin:0'>{sky_svg(theme, WIDTH * 3)}</body></html>",
            sky, (WIDTH * 3, HEIGHT), work)
    name = f"sky-{theme}"
    new = os.path.join(work, f"{name}.webp")
    subprocess.run(["magick", sky, "-crop", f"{WIDTH * 3}x{HEIGHT}+0+0", "+repage", "-alpha", "off", "-resize",
                    "2400x", "-strip", "-quality", "78", "-define", "webp:method=6", new], check=True)
    keep_if_same(new, os.path.join(SITE, f"{name}.webp"))
    shutil.rmtree(work, ignore_errors=True)
    return name


def web_phone(theme, slide, lang, work_root, target=None, width=900):
    work = tempfile.mkdtemp(dir=work_root)
    shots = []
    for bg in ("#000", "#fff"):
        shot = os.path.join(work, f"phone-{bg[1:]}.png")
        firefox(slide_page(0, slide, lang, theme, 100, "", work, bg, bare=True), shot, (WIDTH, HEIGHT), work)
        shots.append(shot)
    name = f"phone-{slide['id']}-{lang}-{theme}"
    transparent(*shots, target or os.path.join(SITE, f"{name}.webp"), work, width=width)
    shutil.rmtree(work, ignore_errors=True)
    return name


def web_assets(slides, jobs, work):
    """Website hero and feature images: the sky alone and each phone without text.
    Only the slides the website shows ("site": true in slides.json)."""
    todo = [lambda t=theme: web_sky(t, work) for theme in THEMES]
    todo += [lambda t=theme, s=slide, l=lang: web_phone(t, s, l, work)
             for theme in THEMES for slide in slides if slide.get("site") for lang in LANGS]
    run_jobs(lambda job: job(), todo, jobs)


SOCIAL_PAGE = """<!doctype html><html lang="{lang}"><head><meta charset="utf-8"><style>
@font-face {{ font-family: "Mock"; font-weight: 100 900; src: url("{font}"); }}
html, body {{ margin: 0; width: {w}px; height: {h}px; overflow: hidden; font-family: "Mock"; background: {bg}; }}
.sky {{ position: absolute; inset: 0; }}
.text {{ position: absolute; left: 80px; top: 0; bottom: 0; width: 560px; display: flex; flex-direction: column;
  justify-content: center; color: {fg}; }}
.brand {{ display: flex; align-items: center; gap: 14px; font-size: 34px; font-weight: 700; margin-bottom: 40px; }}
.brand img {{ height: 46px; }}
.kicker {{ font-size: 19px; font-weight: 600; letter-spacing: 0.06em; text-transform: uppercase; color: {accent}; }}
h1 {{ margin: 10px 0 14px; font-size: {title_size}px; font-weight: 800; letter-spacing: -0.02em; line-height: 1.05; }}
p {{ margin: 0; font-size: 23px; line-height: 1.45; color: {muted}; text-wrap: balance; }}
.features {{ margin-top: 26px; font-size: 20px; color: {muted}; }}
.phones img {{ position: absolute; height: {phone_h}px; }}
</style></head><body>
<div class="sky">{sky}</div>
<div class="text">
  <div class="brand"><img src="{logo}" alt="">LocSim</div>
  <div class="kicker">{kicker}</div><h1>{title}</h1><p>{body}</p><div class="features">{features}</div>
</div>
<div class="phones"><img src="{phone1}" style="left:{p1x}px; top:{p1y}px"><img src="{phone2}" style="left:{p2x}px; top:{p2y}px"></div>
</body></html>"""

SOCIAL_COLORS = {
    "light": dict(fg="#1d1030", muted="#4b3f63", accent="#c2410c", logo="brand-light.svg"),
    "dark": dict(fg="#ffffff", muted="#cdc4ea", accent="#ff9a7a", logo="brand-dark.svg"),
}


def social(slides, theme, jobs, work):
    """Link previews (og.jpg, og-de.jpg) and the GitHub social preview: logo, text and two phones."""
    texts = json.load(open(os.path.join(SOCIAL, "social.json")))
    by_id = {s["id"]: s for s in slides}
    langs = [lang for lang in texts if lang in LANGS]
    jobs_list = [(lang, sid) for lang in langs for sid in texts[lang]["phones"]]

    def phone(job):
        lang, sid = job
        web_phone(theme, by_id[sid], lang, work, os.path.join(work, f"social-{sid}-{lang}.webp"), width=700)
    run_jobs(phone, jobs_list, jobs)
    sky_theme = SOCIAL_SKY if theme == "light" else THEMES["dark"]
    c = SOCIAL_COLORS[theme]
    for lang in langs:
        t = texts[lang]
        for target, (w, h) in t["targets"].items():
            k = h / 630
            p1, p2 = (os.path.join(work, f"social-{sid}-{lang}.webp") for sid in t["phones"])
            page = SOCIAL_PAGE.format(
                lang=lang, font=pathlib.Path(FONTS, "Inter.ttf").as_uri(), w=w, h=h, bg="#000",
                sky=sky_svg(sky_theme, round(w * 2.2), round(h * 2.2)).replace("<svg ", '<svg style="width:100%;height:100%" preserveAspectRatio="xMidYMax slice" ', 1),
                fg=c["fg"], muted=c["muted"], accent=c["accent"], logo=pathlib.Path(PUBLIC, c["logo"]).as_uri(),
                title_size=round(60 * k), kicker=html.escape(t["kicker"]), title=html.escape(t["title"]),
                body=html.escape(t["body"]), features=" &nbsp;·&nbsp; ".join(map(html.escape, t["features"])),
                phone_h=round(470 * k), phone1=pathlib.Path(p1).as_uri(), phone2=pathlib.Path(p2).as_uri(),
                p1x=w - round(490 * k), p1y=round(110 * k), p2x=w - round(290 * k), p2y=round(50 * k))
            shot = os.path.join(work, f"social-{lang}.png")
            firefox(page, shot, (w, h), work)
            out = os.path.join(REPO, target)
            new = os.path.join(work, os.path.basename(target))
            if target.endswith(".jpg"):
                # Messengers (Discord) drop previews above ~500 KB; 4:2:0 and q 88 stay far below.
                subprocess.run(["magick", shot, "-crop", f"{w}x{h}+0+0", "+repage", "-alpha", "off", "-strip",
                                "-colorspace", "sRGB", "-sampling-factor", "4:2:0", "-quality", "88",
                                "-interlace", "JPEG", new], check=True)
                if os.path.getsize(new) > 450_000:
                    raise RuntimeError(f"{target} is {os.path.getsize(new) // 1000} KB, more than 450 KB")
            else:
                subprocess.run(["magick", shot, "-crop", f"{w}x{h}+0+0", "+repage", "-alpha", "off", "-strip", new],
                               check=True)
                optimize(new)
            keep_if_same(new, out)
            print(target, flush=True)


def render_slide(job, sizes, skies, readme_only, readme_ids, work_root):
    """One App Store image (and, for the README, its version without background).
    Skipped when the image, its screenshot and this script are unchanged since the last run."""
    theme, index, slide, lang, app_size = job
    work = tempfile.mkdtemp(dir=work_root)
    suffix = "" if app_size == "6.9" else f"{app_size}/"
    name = f"{slide['id']}-{lang}-{theme}"
    g = layout(app_size)
    if not readme_only:
        target = os.path.join(OUT, suffix + f"{name}.png")
        os.makedirs(os.path.dirname(target), exist_ok=True)
        page = slide_page(index, slide, lang, theme, sizes[lang], skies[(theme, app_size)], work, app_size=app_size)
        _, shot = screen_html(slide["screenshot"], lang, theme, work, SIZES[app_size]["shots"])
        key = digest(page.replace(work, ""), open(shot, "rb").read() if shot else b"")
        stamp = os.path.join(CACHE, "slides", suffix + name)
        if os.path.exists(target) and os.path.exists(stamp) and open(stamp).read() == key:
            name += " (unchanged)"
        else:
            firefox(page, target, (g["w"], g["h"]), work)
            subprocess.run(["magick", target, "-crop", f"{g['w']}x{g['h']}+0+0", "+repage",
                            "-alpha", "off", "-strip", target], check=True)
            optimize(target, "1")
            if SIZES[app_size].get("derive"):
                medium_display(target, SIZES[app_size]["derive"])
            os.makedirs(os.path.dirname(stamp), exist_ok=True)
            open(stamp, "w").write(key)
    # Only the README uses the images without background: English, README slides, 6.9".
    if lang == "en" and slide["id"] in readme_ids and app_size == "6.9":
        shots = []
        for bg in ("#000", "#fff"):
            shot = os.path.join(work, f"site-{bg[1:]}.png")
            firefox(slide_page(index, slide, lang, theme, sizes[lang], "", work, bg), shot, (WIDTH, HEIGHT), work)
            shots.append(shot)
        transparent(*shots, os.path.join(TITLED, f"{slide['id']}-en-{theme}.webp"), work)
    shutil.rmtree(work, ignore_errors=True)
    return suffix + name


def code_list(known, what):
    def parse(value):
        # Deduplicated: the same job twice would render into the same file at once.
        codes = list(dict.fromkeys(code.strip() for code in value.split(",") if code.strip()))
        unknown = [code for code in codes if code not in known]
        if unknown or not codes:
            raise argparse.ArgumentTypeError(
                f"unknown {what}: {', '.join(unknown) or 'none given'} (known: {','.join(known)})")
        return codes
    return parse


def job_count(value):
    try:
        n = int(value)
    except ValueError:
        n = 0
    if n < 1:
        raise argparse.ArgumentTypeError(f"needs a whole number of at least 1, not {value!r}")
    return n


def check_tools():
    """Checks for every tool up front, so a missing one does not show up halfway through."""
    global FIREFOX
    mac = "/Applications/Firefox.app/Contents/MacOS/firefox"
    FIREFOX = os.environ.get("FIREFOX") or shutil.which("firefox") or (mac if os.access(mac, os.X_OK) else None)
    missing = []
    if not FIREFOX:
        missing.append("firefox (or set FIREFOX to its path)")
    if not shutil.which("magick"):
        missing.append("magick (ImageMagick 7; ImageMagick 6 only has convert)")
    if not (shutil.which("oxipng") or shutil.which("optipng")):
        missing.append("oxipng or optipng")
    # Without them Firefox silently falls back to a system font and every title is measured wrong.
    missing += [f"fonts/{f}" for f in ("Inter.ttf", "Inter-Italic.ttf") if not os.path.isfile(os.path.join(FONTS, f))]
    if missing:
        sys.exit("render.py needs: " + ", ".join(missing))
    global FIREFOX_VERSION
    FIREFOX_VERSION = subprocess.run([FIREFOX, "--version"], capture_output=True, text=True).stdout.strip()


def main():
    global LANGS
    slides = json.load(open(os.path.join(HERE, "slides.json")))
    parser = argparse.ArgumentParser(description="Renders the App Store, README and website mockups.")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--readme-only", action="store_true", help="only the README image (English)")
    mode.add_argument("--web-assets", action="store_true", help="only the website sky and phones")
    mode.add_argument("--social", choices=list(THEMES), nargs="?", const="light",
                      help="only the link previews and GitHub social preview (default: light)")
    parser.add_argument("--lang", type=code_list(ALL_LANGS, "language"), metavar="en,de,...",
                        help=f"languages to render (default: all of {','.join(ALL_LANGS)})")
    parser.add_argument("--slide", type=code_list([s["id"] for s in slides], "slide"), metavar="1-map,...",
                        help="App Store slides to render (default: all)")
    parser.add_argument("--theme", type=code_list(list(THEMES), "theme"), metavar="light,dark",
                        help="themes to render (default: both)")
    parser.add_argument("--size", type=code_list(list(SIZES), "size"), metavar="6.9,duo-inner,...",
                        help="App Store sizes (default: 6.9, which also writes out/6.3/; Duo sizes need Duo screenshots)")
    parser.add_argument("--jobs", type=job_count, metavar="N",
                        default=max(1, min(4, (os.cpu_count() or 2) // 2)),
                        help="images rendered at once (default: half the CPU cores, at most 4)")
    args = parser.parse_args()
    if args.lang:
        LANGS = args.lang
    themes = args.theme or list(THEMES)
    # The Duo sizes only once there are Duo screenshots; until then they would show placeholders.
    sizes_wanted = args.size or ["6.9"]
    if args.readme_only and "en" not in LANGS:
        parser.error("--readme-only renders the English README image; include en in --lang")
    check_tools()
    missing = [f"{s['id']} ({lang})" for s in slides for lang in LANGS if lang not in s]
    if missing:
        sys.exit(f"slides.json has no text for: {', '.join(missing)}")
    readme_ids = {s["id"] for s in readme_slides(slides)}
    # README and preview need every slide and theme at 6.9"; a partial run leaves them alone.
    complete = not (args.slide or args.theme) and "6.9" in sizes_wanted
    for d in (OUT, SITE, TITLED, CACHE):
        os.makedirs(d, exist_ok=True)
    with tempfile.TemporaryDirectory() as work:
        warm_profile(work)
        if args.social:
            return social(slides, args.social, args.jobs, work)
        if args.web_assets:
            return web_assets(slides, args.jobs, work)
        # Titles and panoramas first, in parallel; both are cached between runs.
        sky_jobs = [] if args.readme_only else [(t, z) for t in themes for z in sizes_wanted]
        pre = run_jobs(lambda j: j(), [lambda: ("titles", title_sizes(slides, work)),
                                       lambda: ("subtitles", check_subtitles(slides, work))] +
                       [lambda t=t, z=z: panorama(t, z, len(slides), work) for t, z in sky_jobs], args.jobs)
        found = dict(pre)
        sizes = found.pop("titles")
        found.pop("subtitles")
        skies = found
        todo = [(theme, index, slide, lang, z) for z in sizes_wanted for theme in themes
                for index, slide in enumerate(slides) for lang in LANGS
                if not args.slide or slide["id"] in args.slide]
        if args.readme_only:
            todo = [j for j in todo if j[3] == "en" and j[2]["id"] in readme_ids and j[4] == "6.9"]
        if "en" in LANGS and complete:
            # Every README image is rendered again below; older ones (renamed or unmarked
            # slides) must not end up in the README.
            for old in os.listdir(TITLED):
                os.remove(os.path.join(TITLED, old))
        run_jobs(lambda j: render_slide(j, sizes, skies, args.readme_only, readme_ids, work), todo, args.jobs)
        if "en" in LANGS and complete:
            readme(slides, work)
        if not args.readme_only and set(LANGS) == set(ALL_LANGS) and complete:
            preview(slides, work)


if __name__ == "__main__":
    # Failures outside run_jobs (title measuring, panoramas, README, preview) end with a message too.
    try:
        main()
    except (RuntimeError, OSError, subprocess.SubprocessError) as exc:
        sys.exit(f"render failed: {exc}")
