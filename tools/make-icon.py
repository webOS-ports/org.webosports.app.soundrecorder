#!/usr/bin/env python3
# Makes the app icon and the dashboard icon from the record button
# (qml/images/record.svg, the legacy camera's, redrawn as vectors), so the
# icon is the button the app is used with. The SVG is rendered at the size
# each icon needs with Qt's SVG renderer, not scaled from a bitmap.
#
#   python3 -I tools/make-icon.py <svgcheck>
#
# svgcheck is built from tools/vectorize. Writes icon.png and
# icon-256x256.png (256x256) and qml/images/dashboard-icon.png (64x64).
import os
import subprocess
import sys
import tempfile

from PIL import Image

here = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
svgcheck = sys.argv[1] if len(sys.argv) > 1 else "svgcheck"
svg = os.path.join(here, "qml/images/record.svg")


def render(scale):
    with tempfile.TemporaryDirectory() as tmp:
        out = os.path.join(tmp, "r.png")
        subprocess.run([svgcheck, "render", svg, repr(scale), out], check=True)
        return Image.open(out).convert("RGBA")


def icon(canvas, box):
    # The button's extent at 1x, then a render where it is exactly box wide.
    bbox = render(1.0).getbbox()
    scale = box / max(bbox[2] - bbox[0], bbox[3] - bbox[1])
    img = render(scale)
    img = img.crop(img.getbbox())
    out = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    out.alpha_composite(img, ((canvas - img.width) // 2, (canvas - img.height) // 2))
    return out


big = icon(256, 240)
big.save(os.path.join(here, "icon.png"))
big.save(os.path.join(here, "icon-256x256.png"))
icon(64, 60).save(os.path.join(here, "qml/images/dashboard-icon.png"))
print("icon.png 256, dashboard-icon.png 64, from record.svg", file=sys.stderr)
