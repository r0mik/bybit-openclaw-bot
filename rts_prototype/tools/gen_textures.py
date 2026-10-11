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


# --- Terrain layers (albedo + normal map) for the 3D ground shader ------------

def normal_from_height(h, strength):
    """Tangent-space normal map from a periodic height field (stays seamless)."""
    dx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * strength
    dy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * strength
    n = np.dstack([-dx, dy, np.ones_like(h)])
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    return Image.fromarray(((n * 0.5 + 0.5) * 255).astype(np.uint8), "RGB")


def colorize(h, dark, light, rng, grain=0.08):
    t = np.clip(h, 0, 1)[..., None]
    c = np.array(dark, np.float32) * (1 - t) + np.array(light, np.float32) * t
    c *= (1 - grain / 2 + grain * rng.random(h.shape))[..., None]
    return Image.fromarray(np.clip(c, 0, 255).astype(np.uint8), "RGB")


def draw_terrain_layers():
    n = 512
    rng = np.random.default_rng(21)
    # dirt: soft mounds + fine grit + pebbles
    h = 0.55 * tile_noise(n, 0.02, rng) + 0.3 * tile_noise(n, 0.08, rng) + 0.15 * tile_noise(n, 0.35, rng)
    peb = np.zeros((n, n), np.float32)
    yy, xx = np.mgrid[0:n, 0:n]
    for _ in range(140):
        cx, cy, r = rng.uniform(0, n), rng.uniform(0, n), rng.uniform(1.5, 5)
        dx = (xx - cx + n / 2) % n - n / 2
        dy = (yy - cy + n / 2) % n - n / 2
        peb = np.maximum(peb, np.clip(1 - (dx * dx + dy * dy) / (r * r), 0, 1) ** 0.5)
    hd = h + 0.6 * peb
    save(colorize(h + 0.35 * peb, (70, 56, 40), (150, 126, 96), rng), "terrain/dirt.png")
    save(normal_from_height(hd, 6.0), "terrain/dirt_n.png")
    # grass / moss: noisy clumps
    h = 0.4 * tile_noise(n, 0.05, rng) + 0.6 * tile_noise(n, 0.4, rng)
    save(colorize(h, (40, 44, 25), (92, 96, 54), rng, 0.15), "terrain/grass.png")
    save(normal_from_height(h, 4.0), "terrain/grass_n.png")
    # rock: layered plates with cracks
    base = 0.6 * tile_noise(n, 0.015, rng) + 0.4 * tile_noise(n, 0.12, rng)
    strata = np.abs(np.sin(base * 18.0))
    h = 0.6 * base + 0.4 * strata
    save(colorize(0.3 + 0.5 * h, (70, 66, 60), (138, 130, 118), rng, 0.05), "terrain/rock.png")
    save(normal_from_height(h, 5.0), "terrain/rock_n.png")


def main():
    draw_metal()
    draw_hazard()
    draw_ribs()
    draw_terrain_layers()


if __name__ == "__main__":
    main()
