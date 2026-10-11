#!/usr/bin/env python3
"""Procedurally generates material textures (for the 3D models) and the terrain tile.

Part of the asset pipeline, see tools/build_assets.sh. Requires Pillow and numpy.
"""
import math
import random
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

OUT = Path(__file__).resolve().parent.parent / "assets"
HAZARD = (232, 182, 36)


# --- Material textures for the 3D models -----------------------------------

def save(img, rel):
    path = OUT / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path)
    print("wrote", path.relative_to(OUT.parent), img.size)


def draw_metal():
    """Tileable panelled metal: seams, rivets, grain and grime (greyscale, tinted in-engine)."""
    n = 256
    rng = np.random.default_rng(11)
    base = 0.82 + 0.1 * tile_noise(n, 0.03, rng) + 0.05 * tile_noise(n, 0.3, rng)
    img = Image.fromarray((np.clip(base, 0, 1) * 255).astype(np.uint8), "L").convert("RGB")
    d = ImageDraw.Draw(img)
    for i in (0, 128):  # panel seams
        d.line([(i, 0), (i, n)], fill=(70, 70, 70), width=3)
        d.line([(0, i), (n, i)], fill=(70, 70, 70), width=3)
        d.line([(i + 3, 0), (i + 3, n)], fill=(235, 235, 235), width=1)
        d.line([(0, i + 3), (n, i + 3)], fill=(235, 235, 235), width=1)
    d.line([(64, 128), (64, 256)], fill=(95, 95, 95), width=2)
    d.line([(128, 192), (256, 192)], fill=(95, 95, 95), width=2)
    for x in range(10, n, 32):  # rivets along seams
        for y in (10, 118, 138, 246):
            d.ellipse([x - 3, y - 3, x + 3, y + 3], fill=(95, 95, 95))
            d.ellipse([x - 2, y - 2, x + 1, y + 1], fill=(240, 240, 240))
    save(img, "materials/metal.png")


def draw_hazard():
    n = 64
    img = Image.new("RGB", (n, n), HAZARD)
    d = ImageDraw.Draw(img)
    for i in range(-n, 2 * n, 32):
        d.polygon([(i, 0), (i + 16, 0), (i + 16 - n, n), (i - n, n)], fill=(28, 28, 30))
    save(img, "materials/hazard.png")


def draw_ribs():
    n = 128
    x = np.arange(n)
    prof = 0.6 + 0.4 * np.cos(x / n * math.tau * 8)  # 8 ribs per tile
    arr = np.tile(prof[None, :], (n, 1)) * (0.92 + 0.08 * tile_noise(n, 0.2, np.random.default_rng(5)))
    img = Image.fromarray((np.clip(arr, 0, 1) * 255).astype(np.uint8), "L").convert("RGB")
    save(img, "materials/ribs.png")


# --- Terrain ----------------------------------------------------------------

def tile_noise(n, cutoff, rng):
    """Seamless (periodic) noise via FFT low-pass filtering, normalised to 0..1."""
    f = np.fft.fftfreq(n)
    fx, fy = np.meshgrid(f, f)
    radius = np.sqrt(fx ** 2 + fy ** 2)
    spectrum = np.fft.fft2(rng.standard_normal((n, n))) * np.exp(-(radius / cutoff) ** 2)
    out = np.real(np.fft.ifft2(spectrum))
    return (out - out.min()) / (out.max() - out.min())


def draw_ground():
    n = 512
    rng = np.random.default_rng(7)
    low = tile_noise(n, 0.012, rng)
    mid = tile_noise(n, 0.05, rng)
    high = tile_noise(n, 0.25, rng)
    dirt = np.array((84, 74, 54), np.float32)
    dirt_dark = np.array((58, 52, 38), np.float32)
    moss = np.array((56, 72, 40), np.float32)
    m = np.clip((low - 0.45) * 3.0, 0, 1)[..., None]
    base = dirt * (1 - m) + moss * m
    d = np.clip((mid - 0.5) * 2.5, 0, 1)[..., None]
    base = base * (1 - d * 0.6) + dirt_dark * d * 0.6
    base *= (0.86 + 0.28 * high)[..., None]
    img = Image.fromarray(np.clip(base, 0, 255).astype(np.uint8), "RGB").convert("RGBA")
    dr = ImageDraw.Draw(img, "RGBA")
    rnd = random.Random(3)
    # pebbles (drawn with wrap-around so the tile stays seamless)
    for _ in range(120):
        x, y, r = rnd.uniform(0, n), rnd.uniform(0, n), rnd.uniform(1.0, 3.6)
        g = rnd.randint(78, 115)
        for ox in (-n, 0, n):
            for oy in (-n, 0, n):
                px, py = x + ox, y + oy
                dr.ellipse([px - r + 1, py - r + 1, px + r + 1, py + r + 1], fill=(20, 18, 12, 110))
                dr.ellipse([px - r, py - r, px + r, py + r], fill=(g, g - 6, g - 20, 255))
                dr.ellipse([px - r * 0.6, py - r * 0.7, px, py - r * 0.1], fill=(g + 40, g + 34, g + 20, 160))
    # cracks
    for _ in range(5):
        x, y = rnd.uniform(0, n), rnd.uniform(0, n)
        a = rnd.uniform(0, math.tau)
        pts = [(x, y)]
        for _ in range(rnd.randint(6, 14)):
            a += rnd.uniform(-0.7, 0.7)
            x += math.cos(a) * rnd.uniform(5, 12)
            y += math.sin(a) * rnd.uniform(5, 12)
            pts.append((x, y))
        for ox in (-n, 0, n):
            for oy in (-n, 0, n):
                dr.line([(px + ox, py + oy) for px, py in pts], fill=(34, 30, 20, 110), width=2)
    path = OUT / "terrain" / "ground.png"
    path.parent.mkdir(parents=True, exist_ok=True)
    img.convert("RGB").save(path)
    print("wrote", path.relative_to(OUT.parent), img.size)


def main():
    draw_metal()
    draw_hazard()
    draw_ribs()
    draw_ground()


if __name__ == "__main__":
    main()
