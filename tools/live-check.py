#!/usr/bin/env python3
"""Tells whether a Lock Screen shot shows the Live Activity lit, for tools/screenshots.sh.

Usage: live-check.py <shot.bmp> [previous level]
Prints "<state> <level>": state is "none" (no activity on the screen yet), "dim" (Always On),
"moving", "hint" (lit, but iOS still shows "Swipe up to open" below) or "lit"; level is the activity's mean brightness, to pass to the next call.

The activity's text gives many sharp edges, the blurred wallpaper almost none.

In Always On the activity has a dark fill and blends into the wallpaper next to it; lit, the
glass is clearly brighter. After waking, iOS sometimes keeps drawing the Always On version for
a while, and the change to the lit one fades in, so a shot only counts once two in a row match.
Positions are fractions of the screen, measured on an iPhone 17 with the activity at the bottom.
"""
import struct
import sys

GLASS = (0.06, 0.09, 0.77, 0.82)       # left edge inside the activity, under the icon
WALLPAPER = (0.06, 0.09, 0.88, 0.92)   # the same column below the activity
ACTIVITY = (0.08, 0.92, 0.72, 0.83)    # the whole activity, text included
HINT = (0.25, 0.75, 0.90, 0.955)       # "Swipe up to open" above the home indicator
TEXT = 15       # sharp edges per 1000 pixels from which the activity counts as shown
LIT = 10        # glass this much brighter than the wallpaper next to it
STILL = 0.5     # largest change in level between two shots that counts as finished


def load(path):
    data = open(path, "rb").read()
    if data[:2] != b"BM":
        sys.exit("not a BMP file: " + path)
    offset = struct.unpack_from("<I", data, 10)[0]
    width, height = struct.unpack_from("<ii", data, 18)
    bits = struct.unpack_from("<H", data, 28)[0]
    if bits not in (24, 32):
        sys.exit("unsupported BMP: %d bits" % bits)
    step = bits // 8
    row = (width * step + 3) // 4 * 4
    top_down = height < 0
    height = abs(height)

    def mean(box):
        x0, x1 = int(box[0] * width), int(box[1] * width)
        y0, y1 = int(box[2] * height), int(box[3] * height)
        total = count = 0
        for y in range(y0, y1):
            line = offset + (y if top_down else height - 1 - y) * row
            for x in range(x0, x1, 2):
                p = line + x * step
                total += data[p] + data[p + 1] + data[p + 2]
                count += 3
        return total / count

    def edges(box):
        x0, x1 = int(box[0] * width), int(box[1] * width)
        y0, y1 = int(box[2] * height), int(box[3] * height)
        sharp = count = 0
        for y in range(y0, y1, 2):
            line = offset + (y if top_down else height - 1 - y) * row
            last = None
            for x in range(x0, x1, 2):
                p = line + x * step
                value = data[p] + data[p + 1] + data[p + 2]
                if last is not None:
                    sharp += abs(value - last) > 90
                    count += 1
                last = value
        return 1000 * sharp / count

    return mean, edges


def main():
    mean, edges = load(sys.argv[1])
    level = mean(ACTIVITY)
    if edges(ACTIVITY) < TEXT:
        state = "none"
    elif mean(GLASS) - mean(WALLPAPER) < LIT:
        state = "dim"
    elif len(sys.argv) <= 2 or abs(level - float(sys.argv[2])) > STILL:
        state = "moving"
    elif edges(HINT) >= TEXT:
        state = "hint"
    else:
        state = "lit"
    print("%s %.2f" % (state, level))


main()
