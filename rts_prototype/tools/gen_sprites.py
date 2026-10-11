#!/usr/bin/env python3
"""Procedurally generates building, mineral and terrain textures for the RTS prototype.

Usage (from the rts_prototype/ folder):  python3 tools/gen_sprites.py
Requires Pillow and numpy. Output goes to assets/.
"""
import math
import random
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

OUT = Path(__file__).resolve().parent.parent / "assets"
RES = 2   # texture pixels per game pixel (crisp when zoomed in)
SS = 3    # supersampling factor for anti-aliasing
K = RES * SS
PAD = 14  # game px of transparent margin around the footprint (room for the shadow)

TEAMS = {0: (70, 145, 255), 1: (240, 74, 58)}
SIZES = {"cc": (130, 100), "depot": (70, 70), "barracks": (110, 90), "factory": (120, 90)}

METAL = (112, 120, 130)
METAL_DARK = (70, 76, 86)
HAZARD = (232, 182, 36)


def mix(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def shade(c, f):
    return mix(c, (255, 255, 255), f) if f > 0 else mix(c, (0, 0, 0), -f)


def rgba(c, a=255):
    return (c[0], c[1], c[2], a)


def chamfer(x0, y0, x1, y1, c):
    return [(x0 + c, y0), (x1 - c, y0), (x1, y0 + c), (x1, y1 - c),
            (x1 - c, y1), (x0 + c, y1), (x0, y1 - c), (x0, y0 + c)]


class Canvas:
    """Drawing surface in game-pixel coordinates (0..w, 0..h = building footprint)."""

    def __init__(self, w, h, pad=PAD):
        self.w, self.h, self.pad = w, h, pad
        self.img = Image.new("RGBA", ((w + 2 * pad) * K, (h + 2 * pad) * K), (0, 0, 0, 0))
        self.d = ImageDraw.Draw(self.img, "RGBA")

    def p(self, x, y):
        return ((x + self.pad) * K, (y + self.pad) * K)

    def rect(self, x0, y0, x1, y1, fill, outline=None, width=1.0):
        self.d.rectangle([*self.p(x0, y0), *self.p(x1, y1)], fill=fill, outline=outline,
                         width=max(1, int(width * K)) if outline else 0)

    def poly(self, pts, fill, outline=None, width=1.0):
        self.d.polygon([self.p(*q) for q in pts], fill=fill)
        if outline:
            self.line(pts + [pts[0]], outline, width)

    def ellipse(self, cx, cy, rx, ry, fill, outline=None, width=1.0):
        self.d.ellipse([*self.p(cx - rx, cy - ry), *self.p(cx + rx, cy + ry)], fill=fill,
                       outline=outline, width=max(1, int(width * K)) if outline else 0)

    def circle(self, cx, cy, r, fill, outline=None, width=1.0):
        self.ellipse(cx, cy, r, r, fill, outline, width)

    def line(self, pts, fill, width=1.0):
        self.d.line([self.p(*q) for q in pts], fill=fill, width=max(1, int(width * K)), joint="curve")

    def layer(self):
        return Image.new("RGBA", self.img.size, (0, 0, 0, 0))

    def glow(self, cx, cy, r, col, strength=200):
        lay = self.layer()
        ImageDraw.Draw(lay).ellipse([*self.p(cx - r, cy - r), *self.p(cx + r, cy + r)], fill=rgba(col, strength))
        lay = lay.filter(ImageFilter.GaussianBlur(r * K * 0.5))
        self.img.alpha_composite(lay)

    def paste(self, tile, x0, y0):
        self.img.alpha_composite(tile, (int((x0 + self.pad) * K), int((y0 + self.pad) * K)))


# --- Building blocks --------------------------------------------------------

def panel(c, x0, y0, x1, y1, col, bev=2.0, cham=0.0):
    """Bevelled plate lit from the top-left."""
    c.poly(chamfer(x0, y0, x1, y1, cham), rgba(shade(col, -0.5)))
    c.poly(chamfer(x0, y0, x1 - bev, y1 - bev, max(0, cham - bev * 0.5)), rgba(shade(col, 0.3)))
    c.poly(chamfer(x0 + bev, y0 + bev, x1 - bev, y1 - bev, max(0, cham - bev)), rgba(col))


def hazard(c, x0, y0, x1, y1, step=3.0):
    w, h = int((x1 - x0) * K), int((y1 - y0) * K)
    t = Image.new("RGBA", (w, h), rgba(HAZARD))
    td = ImageDraw.Draw(t)
    s = step * K
    i = -h
    while i < w + h:
        td.polygon([(i, 0), (i + s, 0), (i + s - h, h), (i - h, h)], fill=(28, 28, 30, 255))
        i += 2 * s
    td.rectangle([0, 0, w - 1, h - 1], outline=(20, 20, 20, 255), width=max(1, K // 2))
    c.paste(t, x0, y0)


def vents(c, x0, y0, x1, y1, n, horizontal=True):
    c.rect(x0, y0, x1, y1, rgba((38, 40, 46)))
    for i in range(n):
        if horizontal:
            y = y0 + (i + 0.5) * (y1 - y0) / n
            c.line([(x0 + 1, y), (x1 - 1, y)], rgba((105, 110, 118)), 0.8)
        else:
            x = x0 + (i + 0.5) * (x1 - x0) / n
            c.line([(x, y0 + 1), (x, y1 - 1)], rgba((105, 110, 118)), 0.8)


def bolt(c, x, y, r=1.2):
    c.circle(x, y, r, rgba((40, 42, 48)))
    c.circle(x - r * 0.3, y - r * 0.3, r * 0.5, rgba((190, 196, 204)))


def light(c, x, y, col, r=2.2):
    c.glow(x, y, r * 3.0, col, 170)
    c.circle(x, y, r, rgba(shade(col, 0.45)))
    c.circle(x - r * 0.3, y - r * 0.3, r * 0.4, (255, 255, 255, 230))


def dome(c, cx, cy, r, col):
    """Glass dome: radial gradient with specular highlight."""
    size = int(2 * r * K)
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32)
    nx = (xx - size / 2) / (size / 2)
    ny = (yy - size / 2) / (size / 2)
    d = np.sqrt(nx ** 2 + ny ** 2)
    inside = d <= 1.0
    nz = np.sqrt(np.clip(1 - d ** 2, 0, 1))
    lx, ly, lz = -0.5, -0.6, 0.62
    lam = np.clip(nx * lx + ny * ly + nz * lz, 0, 1)
    spec = np.clip(nx * lx + ny * ly + nz * lz, 0, 1) ** 28
    base = np.array(shade(col, -0.55), np.float32)
    lit = np.array(shade(col, 0.15), np.float32)
    rgb = base[None, None, :] + (lit - base)[None, None, :] * lam[..., None] + 255 * spec[..., None] * 0.9
    alpha = np.where(inside, 255, 0)
    arr = np.dstack([np.clip(rgb, 0, 255), alpha]).astype(np.uint8)
    c.paste(Image.fromarray(arr, "RGBA"), cx - r, cy - r)


def finish(c, name, seed):
    """Grain, grime and drop shadow; then downsample and save."""
    rng = np.random.default_rng(seed)
    arr = np.array(c.img).astype(np.float32)
    h, w = arr.shape[:2]
    grain = rng.normal(1.0, 0.035, (h, w)).astype(np.float32)
    grime = Image.fromarray((rng.random((h // 24 + 1, w // 24 + 1)) * 255).astype(np.uint8)).resize((w, h), Image.BICUBIC)
    grime = 0.9 + 0.1 * np.asarray(grime, np.float32) / 255.0
    arr[..., :3] *= (grain * grime)[..., None]
    img = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")
    alpha = img.split()[3]
    shadow = Image.new("RGBA", img.size, (0, 0, 0, 0))
    shadow.putalpha(alpha.point(lambda a: int(a * 0.55)))
    shadow = shadow.transform(img.size, Image.AFFINE, (1, 0, -6 * K, 0, 1, -8 * K))
    shadow = shadow.filter(ImageFilter.GaussianBlur(3 * K))
    shadow.alpha_composite(img)
    out = shadow.resize((img.width // SS, img.height // SS), Image.LANCZOS)
    path = OUT / name
    path.parent.mkdir(parents=True, exist_ok=True)
    out.save(path)
    print("wrote", path.relative_to(OUT.parent), out.size)


# --- Buildings --------------------------------------------------------------

def draw_cc(c, tc):
    panel(c, 1, 1, 129, 99, METAL_DARK, 3, 16)
    hazard(c, 36, 92, 94, 97)
    panel(c, 12, 11, 118, 89, METAL, 2, 12)
    for y in (31, 69):
        c.line([(14, y), (116, y)], rgba(shade(METAL, -0.35)), 0.8)
    for x in (38, 92):
        c.line([(x, 13), (x, 87)], rgba(shade(METAL, -0.35)), 0.8)
    # side modules with vents and team paint
    for x0 in (3, 107):
        panel(c, x0, 30, x0 + 20, 70, shade(METAL_DARK, 0.1), 1.5, 3)
        vents(c, x0 + 4, 36, x0 + 16, 64, 6)
        c.rect(x0 + 1.5, 32, x0 + 3.5, 68, rgba(tc))
    # team bands along the top
    c.rect(30, 3, 100, 8, rgba(shade(tc, -0.2)))
    c.rect(30, 3, 100, 5, rgba(tc))
    # corner landing struts
    for (x, y) in ((16, 15), (114, 15), (16, 85), (114, 85)):
        c.circle(x, y, 6.5, rgba((44, 46, 52)), rgba((150, 156, 166)), 1)
        light(c, x, y, tc, 2.4)
    # central dome on a ring
    c.circle(65, 50, 31, rgba(shade(METAL, -0.45)))
    c.circle(64.3, 49.3, 30, rgba(shade(METAL, 0.35)))
    c.circle(65, 50, 28.5, rgba(METAL))
    for i in range(12):
        a = i * math.tau / 12
        bolt(c, 65 + math.cos(a) * 29.2, 50 + math.sin(a) * 29.2, 0.9)
    dome(c, 65, 50, 24, mix(tc, (255, 255, 255), 0.12))
    # antenna
    c.line([(100, 22), (109, 13)], rgba((60, 62, 70)), 1.4)
    light(c, 109, 13, (255, 80, 60), 1.4)
    for (x, y) in ((24, 22), (106, 22), (24, 78), (106, 78)):
        bolt(c, x, y)


def draw_depot(c, tc):
    panel(c, 1, 1, 69, 69, shade(METAL_DARK, 0.1), 3, 10)
    for b in ((8, 8, 62, 13), (8, 57, 62, 62), (8, 13, 13, 57), (57, 13, 62, 57)):
        hazard(c, *b, step=2.5)
    x0, y0, x1, y1, cx, cy = 14, 14, 56, 56, 35, 35
    c.poly([(x0, y0), (x1, y0), (cx, cy)], rgba(shade(METAL, 0.25)))
    c.poly([(x0, y0), (cx, cy), (x0, y1)], rgba(shade(METAL, 0.1)))
    c.poly([(x1, y0), (x1, y1), (cx, cy)], rgba(shade(METAL, -0.2)))
    c.poly([(x0, y1), (cx, cy), (x1, y1)], rgba(shade(METAL, -0.35)))
    seam = rgba((36, 38, 44))
    c.line([(x0, y0), (x1, y1)], seam, 1)
    c.line([(x1, y0), (x0, y1)], seam, 1)
    c.rect(x0, y0, x1, y1, None, seam, 1)
    c.circle(cx, cy, 7, rgba((50, 52, 58)), rgba((150, 156, 166)), 1)
    light(c, cx, cy, tc, 3.5)
    for (x, y) in ((5, 20), (5, 50), (65, 20), (65, 50), (20, 5), (50, 5), (20, 65), (50, 65)):
        bolt(c, x, y)


def draw_barracks(c, tc):
    panel(c, 0, 0, 110, 90, METAL_DARK, 3, 6)
    # side bunkers
    for x0 in (2, 100):
        panel(c, x0, 18, x0 + 8, 62, shade(METAL_DARK, -0.15), 1.2, 1)
        for y in (26, 40, 54):
            light(c, x0 + 4, y, tc, 1.3)
    # corrugated roof
    roof = (128, 133, 138)
    rx0, ry0, rx1, ry1 = 12, 7, 98, 72
    c.rect(rx0 - 1.5, ry0 - 1.5, rx1 + 1.5, ry1 + 1.5, rgba((34, 36, 40)))
    rib = 5.0
    x = rx0
    while x < rx1 - 0.1:
        xm = min(x + rib / 2, rx1)
        xe = min(x + rib, rx1)
        c.rect(x, ry0, xm, ry1, rgba(shade(roof, 0.18)))
        c.rect(xm, ry0, xe, ry1, rgba(shade(roof, -0.22)))
        x += rib
    # painted team band across the roof
    c.rect(rx0, 34, rx1, 45, rgba(shade(tc, -0.15), 235))
    c.rect(rx0, 34, rx1, 36, rgba(shade(tc, 0.25), 235))
    c.rect(rx0, 43.5, rx1, 45, rgba(shade(tc, -0.5), 235))
    # front door
    c.rect(36, 72, 74, 89, rgba((40, 42, 46)))
    for y in range(78, 89, 3):
        c.line([(37, y), (73, y)], rgba((80, 84, 90)), 0.8)
    hazard(c, 34, 71, 76, 75, 2.5)
    light(c, 31, 81, tc, 1.8)
    light(c, 79, 81, tc, 1.8)
    # satellite dish
    c.circle(95, 14, 10, rgba((50, 52, 58)))
    c.circle(94.4, 13.4, 9, rgba((205, 210, 216)))
    c.circle(95.5, 14.5, 6.5, rgba((165, 170, 178)))
    c.line([(95, 14), (100, 9)], rgba((60, 62, 70)), 1.2)
    c.circle(100, 9, 1.5, rgba((60, 62, 70)))


def draw_factory(c, tc):
    panel(c, 0, 0, 120, 90, shade(METAL_DARK, -0.05), 3, 6)
    warm = (124, 114, 100)
    panel(c, 7, 6, 85, 70, warm, 2, 3)
    # skylights
    for i in range(3):
        for j in range(2):
            x0, y0 = 13 + i * 24, 12 + j * 26
            c.rect(x0 - 1, y0 - 1, x0 + 19, y0 + 19, rgba((48, 46, 44)))
            c.rect(x0, y0, x0 + 18, y0 + 18, rgba((40, 70, 96)))
            c.poly([(x0, y0), (x0 + 10, y0), (x0, y0 + 10)], (170, 210, 240, 110))
            c.line([(x0 + 9, y0), (x0 + 9, y0 + 18)], rgba((48, 46, 44)), 0.8)
            c.line([(x0, y0 + 9), (x0 + 18, y0 + 9)], rgba((48, 46, 44)), 0.8)
    c.rect(7, 64, 85, 70, rgba(shade(tc, -0.15)))
    c.rect(7, 64, 85, 66, rgba(tc))
    # machinery block with chimneys and pipes
    panel(c, 88, 5, 115, 58, shade(METAL, -0.1), 1.5, 2)
    c.line([(84, 20), (92, 20)], rgba((70, 74, 80)), 3)
    c.line([(84, 42), (92, 42)], rgba((70, 74, 80)), 3)
    for (cy, r) in ((19, 8.5), (42, 7.5)):
        c.circle(102, cy, r + 1.2, rgba((40, 42, 46)))
        c.circle(101.4, cy - 0.6, r, rgba((150, 152, 156)))
        c.circle(102, cy, r * 0.62, rgba((24, 22, 22)))
        c.glow(102, cy, r * 0.5, (255, 120, 40), 90)
    # exhaust fan
    c.circle(101, 73, 11, rgba((40, 42, 46)))
    c.circle(101, 73, 9.5, rgba((70, 74, 80)))
    for i in range(5):
        a = i * math.tau / 5
        c.poly([(101, 73), (101 + math.cos(a) * 9, 73 + math.sin(a) * 9),
                (101 + math.cos(a + 0.7) * 8, 73 + math.sin(a + 0.7) * 8)], rgba((150, 156, 164)))
    c.circle(101, 73, 2.5, rgba((40, 42, 46)))
    # garage door
    c.rect(22, 73, 70, 89, rgba((40, 42, 46)))
    for y in range(76, 89, 3):
        c.line([(23, y), (69, y)], rgba((84, 88, 94)), 0.8)
    hazard(c, 20, 71, 72, 75, 2.5)
    light(c, 16, 80, tc, 1.8)
    light(c, 76, 80, tc, 1.8)


DRAW = {"cc": draw_cc, "depot": draw_depot, "barracks": draw_barracks, "factory": draw_factory}


# --- Minerals ---------------------------------------------------------------

def draw_minerals(variant):
    rnd = random.Random(100 + variant)
    s = 56
    c = Canvas(s, s, pad=0)
    c.ellipse(s / 2 + 3, s * 0.72, 22, 9, (0, 0, 0, 90))
    c.glow(s / 2, s * 0.55, 18, (80, 200, 255), 90)
    crystals = []
    for _ in range(rnd.randint(5, 7)):
        bx = s / 2 + rnd.uniform(-15, 15)
        by = s * 0.74 + rnd.uniform(-7, 5)
        crystals.append((by, bx, rnd.uniform(20, 36), rnd.uniform(8, 13), rnd.uniform(-0.45, 0.45)))
    for by, bx, h, w, a in sorted(crystals):
        up = (math.sin(a), -math.cos(a))
        perp = (math.cos(a), math.sin(a))
        tip = (bx + up[0] * h, by + up[1] * h)
        left = (bx - perp[0] * w / 2, by - perp[1] * w / 2)
        right = (bx + perp[0] * w / 2, by + perp[1] * w / 2)
        ridge = (bx + up[0] * h * 0.12 + perp[0] * w * 0.08, by + up[1] * h * 0.12)
        c.poly([left, tip, ridge], rgba((125, 225, 255)))
        c.poly([ridge, tip, right], rgba((38, 130, 215)))
        c.poly([left, ridge, right, (bx, by + 2)], rgba((25, 90, 170)))
        c.line([ridge, tip], (225, 250, 255, 230), 0.8)
        c.line([left, tip, right], (10, 40, 90, 200), 0.6)
    img = c.img.resize((c.img.width // SS, c.img.height // SS), Image.LANCZOS)
    path = OUT / "minerals" / f"minerals_{variant}.png"
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path)
    print("wrote", path.relative_to(OUT.parent), img.size)


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
    for kind, (w, h) in SIZES.items():
        for team, tc in TEAMS.items():
            c = Canvas(w, h)
            DRAW[kind](c, tc)
            finish(c, f"buildings/{kind}_{team}.png", seed=sum(map(ord, kind)) * 10 + team)
    for v in range(3):
        draw_minerals(v)
    draw_ground()


if __name__ == "__main__":
    main()
