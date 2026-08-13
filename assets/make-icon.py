#!/usr/bin/env python3
"""
Generate the DS-H Launcher app icon from the official DeepSeek whale logo.

Turns the DeepSeek blue whale into a BLACK whale (transparent background,
eyes/belly stay as transparent cutouts), then produces an Apple .icns.

Requires: Pillow (pip install pillow)
Usage:    python3 assets/make-icon.py
"""
from PIL import Image
from pathlib import Path
import shutil
import subprocess
import sys
import urllib.request

# Official DeepSeek AI GitHub organization avatar (blue whale).
AVATAR_URL = "https://github.com/deepseek-ai.png"
RAW_PNG = Path("/tmp/ds-org-avatar.png")
OUT_1024 = Path(__file__).resolve().parent / "icon-1024.png"
OUT_ICNS = Path(__file__).resolve().parent / "AppIcon.icns"
ICONSET_DIR = Path("/tmp/ds-icon.iconset")

SIZES = [
    (16,   "icon_16x16.png"),
    (32,   "icon_16x16@2x.png"),
    (32,   "icon_32x32.png"),
    (64,   "icon_32x32@2x.png"),
    (64,   "icon_64x64.png"),
    (128,  "icon_128x128.png"),
    (256,  "icon_128x128@2x.png"),
    (256,  "icon_256x256.png"),
    (512,  "icon_256x256@2x.png"),
    (512,  "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]


def download_avatar():
    if RAW_PNG.exists():
        return
    print(f"downloading {AVATAR_URL}")
    req = urllib.request.Request(AVATAR_URL, headers={"User-Agent": "ds-h-launcher-icon"})
    with urllib.request.urlopen(req, timeout=30) as r:
        RAW_PNG.write_bytes(r.read())


def to_black_whale(rgb):
    r, g, b = rgb
    # White / near-white -> transparent (background + eye + belly cutouts)
    if r >= 235 and g >= 235 and b >= 235:
        return (0, 0, 0, 0)
    # Blue-dominant (whale body) -> solid black
    if b >= 150 and b > r + 25 and b > g + 10:
        return (0, 0, 0, 255)
    # Anti-aliased edges: light pixels fade to transparent, rest go black
    edge = min(r, g, b)
    if edge >= 180:
        a = max(0, min(255, int((255 - edge) * 2.5)))
        return (0, 0, 0, a)
    return (0, 0, 0, 255)


def main():
    download_avatar()
    img = Image.open(RAW_PNG).convert("RGB")
    w, h = img.size
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    sp, op = img.load(), out.load()
    for y in range(h):
        for x in range(w):
            op[x, y] = to_black_whale(sp[x, y])

    out.resize((1024, 1024), Image.LANCZOS).save(OUT_1024, "PNG")
    print("wrote", OUT_1024)

    if ICONSET_DIR.exists():
        shutil.rmtree(ICONSET_DIR)
    ICONSET_DIR.mkdir(parents=True, exist_ok=True)
    for size, name in SIZES:
        out.resize((size, size), Image.LANCZOS).save(ICONSET_DIR / name, "PNG")

    if OUT_ICNS.exists():
        OUT_ICNS.unlink()
    rc = subprocess.run(
        ["iconutil", "-c", "icns", str(ICONSET_DIR), "-o", str(OUT_ICNS)],
        capture_output=True, text=True,
    )
    if rc.returncode != 0:
        print("iconutil failed:", rc.stderr, file=sys.stderr)
        sys.exit(1)
    print("wrote", OUT_ICNS, OUT_ICNS.stat().st_size, "bytes")


if __name__ == "__main__":
    main()
