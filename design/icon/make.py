"""Writes the app icon sources and exports the PNGs for the app and the website.

    python3 design/icon/make.py           # SVG sources only
    python3 design/icon/make.py --export  # also the PNGs (needs firefox and magick)

The motif is a folded map in the colors of the website's morning sky with a coral pin.
It has no outline and its own colors, so it also stands on its own, e.g. as the site logo.
"""
import math
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
ICONSET = os.path.join(REPO, "LocSim", "Assets.xcassets", "AppIcon.appiconset")
SITE = os.path.join(REPO, "site", "public")

PANELS = [("#b9a9f0", "#9a86e6"), ("#f6d3ec", "#eeb6da"), ("#ffd2bd", "#ffb79c")]
PIN = ("#ff7a62", "#e8322e")
SKY = {
    "light": [(0, "#e9e6fb"), (0.55, "#fbe9f1"), (1, "#ffefe3")],
    "dark": [(0, "#0b0c24"), (0.5, "#1d1640"), (1, "#4a2358")],
}
GLOW = {"light": 0.25, "dark": 0.35}
# Centers the motif on the 1024 canvas at about 64 % of its width.
PLACE = 'transform="translate(-26 -4) scale(1.05)"'
# The pin sits a little above the road, so it does not look pinned onto the line.
# 15 px on the 1024 canvas, as set in Icon Composer.
PIN_LIFT = 15 / 1.05
# The motif alone, cropped for the website logo.
MARK_VIEW = (160, 150, 704, 660)


def pin_path(cx, cy, r, tip):
    phi = math.asin(r / (tip - cy))
    x, y = r * math.cos(phi), r * math.sin(phi)
    return f"M {cx} {tip} L {cx - x:.1f} {cy + y:.1f} A {r} {r} 0 1 1 {cx + x:.1f} {cy + y:.1f} Z"


def gradient(id, stops, x2=0, y2=1):
    s = "".join(f'<stop offset="{o}" stop-color="{c}"/>' for o, c in stops)
    return f'<linearGradient id="{id}" x1="0" y1="0" x2="{x2}" y2="{y2}">{s}</linearGradient>'


def svg(defs, body, view=(0, 0, 1024, 1024)):
    x, y, w, h = view
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="{x} {y} {w} {h}">'
            f"<defs>{defs}</defs>{body}</svg>\n")


def map_layer(gray=False):
    panels = PANELS if not gray else [("#8a8a8a", "#7a7a7a"), ("#d8d8d8", "#c8c8c8"), ("#b0b0b0", "#a0a0a0")]
    defs = "".join(gradient(f"p{i}", [(0, a), (1, b)]) for i, (a, b) in enumerate(panels))
    shapes = ["196,352 384,296 384,696 196,752", "384,296 640,352 640,752 384,696",
              "640,352 828,296 828,696 640,752"]
    # A stroke in the fill's own gradient rounds the corners.
    body = '<g stroke-linejoin="round" stroke-width="30">' + "".join(
        f'<polygon points="{p}" fill="url(#p{i})" stroke="url(#p{i})"/>' for i, p in enumerate(shapes)) + "</g>"
    body += ('<path d="M 205 610 C 320 560, 420 680, 520 625 S 720 555, 818 590" fill="none" '
             'stroke="#ffffff" stroke-opacity="0.85" stroke-width="30" stroke-linecap="round"/>')
    return defs, body


def pin_layer(gray=False, ground_shadow=True):
    top, bottom = PIN if not gray else ("#ffffff", "#e6e6e6")
    hole = "#ffffff" if not gray else "#6a6a6a"
    defs = gradient("pin", [(0, top), (1, bottom)])
    shadow = '<ellipse cx="512" cy="600" rx="78" ry="20" fill="#2a0f2a" opacity="0.28"/>' if ground_shadow else ""
    body = (f'<g transform="translate(0 {-PIN_LIFT:.2f})">' + shadow +
            f'<path d="{pin_path(512, 330, 150, 600)}" fill="url(#pin)" stroke="#ffffff" stroke-width="22" '
            'stroke-linejoin="round" paint-order="stroke"/>'
            f'<circle cx="512" cy="330" r="56" fill="{hole}"/></g>')
    return defs, body


def background(mode):
    defs = gradient("sky", SKY[mode], 0.25, 1) + (
        '<radialGradient id="glow" cx="0.5" cy="1" r="0.7">'
        f'<stop offset="0" stop-color="#ff9a7a" stop-opacity="{GLOW[mode]}"/>'
        '<stop offset="1" stop-color="#ff9a7a" stop-opacity="0"/></radialGradient>')
    return defs, '<rect width="1024" height="1024" fill="url(#sky)"/><rect width="1024" height="1024" fill="url(#glow)"/>'


def sources():
    md, mb = map_layer()
    pd, pb = pin_layer()
    motif = f"<g {PLACE}>{mb}{pb}</g>"
    files = {}
    for mode in ("light", "dark"):
        bd, bb = background(mode)
        files[f"AppIcon-{mode}.svg"] = svg(bd + md + pd, bb + motif)
        files[f"layers/background-{mode}.svg"] = svg(bd, bb)
    gmd, gmb = map_layer(gray=True)
    gpd, gpb = pin_layer(gray=True)
    # iOS colors the tinted icon itself from a grayscale image on black.
    files["AppIcon-tinted.svg"] = svg(gmd + gpd, f'<rect width="1024" height="1024" fill="#000"/><g {PLACE}>{gmb}{gpb}</g>')
    files["layers/map.svg"] = svg(md, f"<g {PLACE}>{mb}</g>")
    # Icon Composer adds its own shadows, so the layer has none painted in.
    lpd, lpb = pin_layer(ground_shadow=False)
    files["layers/pin.svg"] = svg(lpd, f"<g {PLACE}>{lpb}</g>")
    # Standing alone, a soft shadow keeps the pale map apart from a light page.
    shadow = ('<filter id="lift" x="-10%" y="-10%" width="120%" height="130%">'
              '<feDropShadow dx="0" dy="10" stdDeviation="14" flood-color="#3a2060" flood-opacity="0.28"/></filter>')
    lifted = f'<g filter="url(#lift)">{mb}{pb}</g>'
    files["mark.svg"] = svg(md + pd + shadow, lifted, MARK_VIEW)
    # The same, centered in a square, for the favicons.
    x, y, w, h = MARK_VIEW
    side = max(w, h)
    files["layers/mark-square.svg"] = svg(md + pd + shadow, lifted, (x - (side - w) / 2, y - (side - h) / 2, side, side))
    for name, text in files.items():
        with open(os.path.join(HERE, name), "w") as f:
            f.write(text)
    return files


def find_firefox():
    """On macOS firefox is usually not on PATH; FIREFOX overrides both."""
    mac = "/Applications/Firefox.app/Contents/MacOS/firefox"
    return os.environ.get("FIREFOX") or shutil.which("firefox") or (mac if os.access(mac, os.X_OK) else None)


def check_tools():
    """Checked before anything is written, so a missing tool does not stop the run halfway."""
    missing = []
    if not find_firefox():
        missing.append("firefox (or set FIREFOX to its path)")
    if not shutil.which("magick"):
        missing.append("magick (ImageMagick 7; ImageMagick 6 only has convert)")
    if missing:
        sys.exit("make.py --export needs: " + ", ".join(missing))


def firefox(page, target, size, work):
    profile = tempfile.mkdtemp(dir=work)
    result = subprocess.run([find_firefox(), "--headless", "--no-remote", "--profile", profile,
                             f"--window-size={size[0]},{size[1]}", "--screenshot", target, f"file://{page}"],
                            stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True, check=False, timeout=120)
    shutil.rmtree(profile, ignore_errors=True)
    if not os.path.exists(target) or os.path.getsize(target) == 0:
        sys.exit(f"Firefox did not render {os.path.basename(target)}: {result.stderr.strip()[-400:]}")


def shot(svg_file, target, size, work):
    page = os.path.join(work, "page.html")
    with open(page, "w") as f:
        f.write(f"<!doctype html><html><body style='margin:0;background:transparent'>"
                f"<img src='file://{svg_file}' width='{size[0]}' height='{size[1]}'></body></html>")
    firefox(page, target, size, work)


def magick(*args):
    try:
        subprocess.run(["magick", *args], check=True)
    except subprocess.CalledProcessError as exc:
        sys.exit(f"magick failed (exit {exc.returncode})")


def export():
    # Everything is rendered into the work folder first and copied only when all of it
    # succeeded, so a failure does not leave a mix of new and old icons.
    with tempfile.TemporaryDirectory() as work:
        out = os.path.join(work, "out")
        os.mkdir(out)
        outputs = {}

        def target(dest):
            path = os.path.join(out, str(len(outputs)) + os.path.splitext(dest)[1])
            outputs[path] = dest
            return path

        for mode, name in (("light", "AppIcon-1024.png"), ("dark", "AppIcon-1024-dark.png"),
                           ("tinted", "AppIcon-1024-tinted.png")):
            png = os.path.join(work, f"{mode}.png")
            shot(os.path.join(HERE, f"AppIcon-{mode}.svg"), png, (1024, 1024), work)
            # App Store icons must have no alpha channel.
            icon = target(os.path.join(ICONSET, name))
            magick(png, "-crop", "1024x1024+0+0", "+repage", "-alpha", "off", "-strip", icon)
            if mode == "light":
                magick(icon, "-resize", "180x180", "-strip", target(os.path.join(SITE, "apple-touch-icon.png")))
        # Favicons: the motif alone; Firefox renders it on black and white to recover the alpha.
        mark = os.path.join(work, "mark.png")
        shot_alpha(os.path.join(HERE, "layers", "mark-square.svg"), mark, 512, work)
        magick(mark, "-resize", "96x96", "-strip", target(os.path.join(SITE, "favicon-96.png")))
        magick(mark, "-define", "icon:auto-resize=48,32,16", target(os.path.join(SITE, "favicon.ico")))
        for name in ("brand-light.svg", "brand-dark.svg"):
            shutil.copy(os.path.join(HERE, "mark.svg"), target(os.path.join(SITE, name)))
        for path, dest in outputs.items():
            shutil.copyfile(path, dest)


def shot_alpha(svg_file, target, size, work):
    layers = []
    for bg in ("#000", "#fff"):
        page = os.path.join(work, f"alpha-{bg[1:]}.html")
        with open(page, "w") as f:
            f.write(f"<!doctype html><html><body style='margin:0;background:{bg}'>"
                    f"<img src='file://{svg_file}' width='{size}' height='{size}'></body></html>")
        png = os.path.join(work, f"alpha-{bg[1:]}.png")
        firefox(page, png, (size, size), work)
        crop = os.path.join(work, f"crop-{bg[1:]}.png")
        magick(png, "-crop", f"{size}x{size}+0+0", "+repage", crop)
        layers.append(crop)
    # alpha = 1 - (white - black); color = black / alpha
    on_black, on_white = layers
    magick(on_black, on_white, "-alpha", "off",
           "(", "-clone", "0,1", "-compose", "difference", "-composite", "-negate", "-colorspace", "gray", ")",
           "(", "-clone", "0", "-clone", "2", "-compose", "divide_src", "-composite", ")",
           "-delete", "0,1", "+swap", "-compose", "copy_opacity", "-composite", target)


if __name__ == "__main__":
    if "--export" in sys.argv:
        check_tools()
    sources()
    if "--export" in sys.argv:
        export()
