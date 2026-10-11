#!/usr/bin/env python3
"""Merges the render passes from tools/render_sprites.gd into the final game sprites.

For every sprite: shadow alpha is derived from how much darker the white ground got, the model is
composited over it, and the result is downsampled (supersampling AA). Unit directions are stitched
into one horizontal strip per unit and team. Writes assets/{buildings,units,minerals} and
assets/sprites.json.
"""
import json
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
RAW = ROOT / ".render"
OUT = ROOT / "assets"
SHADOW_STRENGTH = 0.6


def compose(base: str, ss: int) -> Image.Image:
    obj = np.asarray(Image.open(RAW / f"{base}_obj.png").convert("RGBA"), np.float32) / 255.0
    sh = np.asarray(Image.open(RAW / f"{base}_shadow.png").convert("RGB"), np.float32) / 255.0
    lum = sh @ np.array([0.299, 0.587, 0.114], np.float32)
    border = np.concatenate([lum[0], lum[-1], lum[:, 0], lum[:, -1]])
    lit = np.median(border)
    sa = np.clip((lit - lum) / max(lit, 1e-3) * 3.0, 0.0, 1.0) * SHADOW_STRENGTH
    oa = obj[..., 3]
    out_a = oa + sa * (1.0 - oa)
    # premultiplied colour (the shadow is black, so it adds no colour)
    prem = obj[..., :3] * oa[..., None]
    h, w = out_a.shape
    pm = Image.fromarray(np.clip(np.dstack([prem, out_a]) * 255, 0, 255).astype(np.uint8), "RGBA")
    pm = pm.resize((w // ss, h // ss), Image.LANCZOS)
    arr = np.asarray(pm, np.float32) / 255.0
    a = arr[..., 3:4]
    rgb = np.where(a > 1e-4, arr[..., :3] / np.maximum(a, 1e-4), 0.0)
    return Image.fromarray(np.clip(np.dstack([rgb, a]) * 255, 0, 255).astype(np.uint8), "RGBA")


def save(img: Image.Image, rel: str) -> None:
    path = OUT / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path)
    print("wrote", path.relative_to(ROOT), img.size)


def main() -> None:
    meta = json.loads((RAW / "meta.json").read_text())
    ss = 2
    for kind in meta["buildings"]:
        for team in (0, 1):
            save(compose(f"{kind}_{team}", ss), f"buildings/{kind}_{team}.png")
    for kind in meta["units"]:
        for team in (0, 1):
            frames = [compose(f"{kind}_{team}_{i:02d}", ss) for i in range(meta["dirs"])]
            fw, fh = frames[0].size
            strip = Image.new("RGBA", (fw * len(frames), fh), (0, 0, 0, 0))
            for i, fr in enumerate(frames):
                strip.paste(fr, (i * fw, 0))
            save(strip, f"units/{kind}_{team}.png")
    for v in range(meta["minerals"]["variants"]):
        save(compose(f"minerals_{v}", ss), f"minerals/minerals_{v}.png")
    (OUT / "sprites.json").write_text(json.dumps(meta, indent=2))
    print("wrote assets/sprites.json")


if __name__ == "__main__":
    main()
