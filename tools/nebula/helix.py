"""Paints the Helix Nebula backdrop layers (run with plain Python 3: numpy, Pillow).

    python tools/nebula/helix.py

Writes four 1024x1024 RGBA PNGs to assets/nebula/, stacked in game
(NebulaBuilder) from the bottom up, each a little above the last so the
nebula has depth as you fly over it:

    HelixHalo.png    the faint outer red halo and the wide, uneven red-orange
                     outer ring, threaded with dark dust lanes
    HelixRing.png    the bright inner ring: deep red outside through orange
                     and gold to green, with the "cometary knots" (bright
                     heads with tails pointing away from the star) on its
                     inner edge
    HelixCore.png    the blue-teal glowing gas filling the middle
    HelixGlow.png    the star's soft glow

Colours follow the real nebula (Hubble/Spitzer composites): blue-green
oxygen inside, a red hydrogen/nitrogen ring outside. The rings are slightly
elliptical and offset, like the two tilted rings that give the Helix its
look. Alpha carries the brightness, so the layers blend over black space.
Everything is seeded, so a rerun paints the same nebula.
"""

import math
import pathlib

import numpy as np
from PIL import Image

SIZE = 1024
OUT = pathlib.Path(__file__).resolve().parent.parent.parent / "assets" / "nebula"
rng = np.random.default_rng(7)

yy, xx = np.mgrid[0:SIZE, 0:SIZE].astype(np.float32)
X = (xx - SIZE / 2) / (SIZE / 2)
Y = (yy - SIZE / 2) / (SIZE / 2)


def smoothstep(a, b, t):
    t = np.clip((t - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def value_noise(scale, seed):
    """Smooth value noise at `scale` cells across, tileable enough here."""
    g = np.random.default_rng(seed).random((scale + 2, scale + 2)).astype(np.float32)
    fx = (xx / SIZE) * scale
    fy = (yy / SIZE) * scale
    ix, iy = fx.astype(int), fy.astype(int)
    tx, ty = fx - ix, fy - iy
    tx = tx * tx * (3 - 2 * tx)
    ty = ty * ty * (3 - 2 * ty)
    a = g[iy, ix]
    b = g[iy, ix + 1]
    c = g[iy + 1, ix]
    d = g[iy + 1, ix + 1]
    return (a * (1 - tx) + b * tx) * (1 - ty) + (c * (1 - tx) + d * tx) * ty


def noise_at(u, v, seed, cells=64):
    """Smooth value noise at arbitrary (u, v) coordinates (wrapping)."""
    g = np.random.default_rng(seed).random((cells, cells)).astype(np.float32)
    iu, iv = np.floor(u).astype(int), np.floor(v).astype(int)
    tu, tv = u - iu, v - iv
    tu = tu * tu * (3 - 2 * tu)
    tv = tv * tv * (3 - 2 * tv)
    i0, i1 = iu % cells, (iu + 1) % cells
    j0, j1 = iv % cells, (iv + 1) % cells
    a, b = g[j0, i0], g[j0, i1]
    c, d = g[j1, i0], g[j1, i1]
    return (a * (1 - tu) + b * tu) * (1 - tv) + (c * (1 - tu) + d * tu) * tv


def polar_fbm(octaves, angular, radial, seed, gain=0.55):
    """Noise stretched along the radius: irregular filaments that stream
    out from the star (wraps cleanly round the circle)."""
    r = np.sqrt(X * X + Y * Y)
    t = (np.arctan2(Y, X) / (2 * math.pi) + 0.5)
    total = np.zeros_like(X)
    amp, norm = 1.0, 0.0
    for o in range(octaves):
        cells = angular * 2**o
        total += amp * noise_at(t * cells, r * radial * 2**o, seed + o * 13, cells=cells)
        norm += amp
        amp *= gain
    return total / norm


def fbm(octaves, base, seed, gain=0.55):
    total = np.zeros_like(X)
    amp, norm = 1.0, 0.0
    for o in range(octaves):
        total += amp * value_noise(base * 2**o, seed + o * 31)
        norm += amp
        amp *= gain
    return total / norm


def ellipse_r(cx, cy, sx, sy, angle):
    c, s = math.cos(angle), math.sin(angle)
    dx, dy = X - cx, Y - cy
    u = (dx * c + dy * s) / sx
    v = (-dx * s + dy * c) / sy
    return np.sqrt(u * u + v * v), np.arctan2(v, u)


def save(name, rgb, alpha):
    rgb = np.clip(rgb, 0, 1)
    alpha = np.clip(alpha, 0, 1)
    # Fade everything out before the square's edge.
    edge = 1 - smoothstep(0.88, 1.0, np.sqrt(X * X + Y * Y))
    alpha = alpha * edge
    img = np.dstack([rgb, alpha[..., None]])
    Image.fromarray((img * 255).astype(np.uint8), "RGBA").save(OUT / name)


def mix(c1, c2, t):
    t = t[..., None]
    return np.array(c1, np.float32) * (1 - t) + np.array(c2, np.float32) * t


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    warp = fbm(5, 3, 11)
    detail = fbm(6, 6, 23)
    fine = fbm(5, 24, 41)
    # Radial streaks (dust and gas flowing out from the star).
    streaks = smoothstep(0.25, 0.85, polar_fbm(5, 48, 2.5, 59))
    clumps = smoothstep(0.3, 0.8, fbm(6, 4, 131)) ** 1.4

    # --- Halo and outer ring --------------------------------------------
    r_out, _ = ellipse_r(0.04, -0.03, 0.86, 0.74, math.radians(-25))
    r_out = r_out + (warp - 0.5) * 0.18
    outer_ring = np.exp(-((r_out - 0.9) / 0.13) ** 2)
    halo = np.exp(-((r_out - 1.05) / 0.3) ** 2) * 0.35
    gas = 0.45 + 0.75 * detail
    dust = smoothstep(0.35, 0.75, fbm(5, 8, 77))  # dark lanes
    a_halo = (outer_ring * gas * (0.45 + 0.55 * streaks) * (0.5 + 0.7 * clumps) + halo * gas) * (1 - 0.6 * dust)
    rgb_halo = mix((0.75, 0.13, 0.08), (1.0, 0.45, 0.22), np.clip(detail * 1.2 - 0.1, 0, 1))
    save("HelixHalo.png", rgb_halo, a_halo * 0.8)

    # --- Inner ring with cometary knots ---------------------------------
    r_in, ang_in = ellipse_r(-0.02, 0.02, 0.6, 0.5, math.radians(-15))
    r_in = r_in + (warp - 0.5) * 0.12 + (fine - 0.5) * 0.05
    ring = np.exp(-((r_in - 0.86) / 0.2) ** 2)
    ring_gas = (0.3 + 0.9 * detail) * (0.45 + 0.55 * streaks) * (0.45 + 0.8 * clumps)
    # Colour across the ring: green-gold inside, orange, deep red outside.
    t = np.clip((r_in - 0.6) / 0.45, 0, 1)
    rgb_ring = np.where(
        (t < 0.4)[..., None],
        mix((0.55, 0.9, 0.45), (1.0, 0.75, 0.3), t / 0.4),
        mix((1.0, 0.6, 0.25), (0.85, 0.12, 0.1), (t - 0.4) / 0.6),
    )
    a_ring = np.clip(ring * ring_gas * 1.7, 0, 1) * (1 - 0.4 * dust)
    # Cometary knots: small bright heads on the inner edge, tails outward.
    knots = np.zeros_like(X)
    for _ in range(900):
        ang = rng.uniform(-math.pi, math.pi)
        rad = rng.uniform(0.6, 0.86) ** 0.8
        # Back to image space along the inner ellipse.
        e_ang = math.radians(-15)
        u, v = math.cos(ang) * rad * 0.6, math.sin(ang) * rad * 0.5
        kx = -0.02 + u * math.cos(e_ang) - v * math.sin(e_ang)
        ky = 0.02 + u * math.sin(e_ang) + v * math.cos(e_ang)
        dirx, diry = kx, ky
        norm = math.hypot(dirx, diry) or 1
        dirx, diry = dirx / norm, diry / norm
        px = int((kx + 1) * SIZE / 2)
        py = int((ky + 1) * SIZE / 2)
        x0, x1 = max(px - 24, 0), min(px + 24, SIZE)
        y0, y1 = max(py - 24, 0), min(py + 24, SIZE)
        dx = X[y0:y1, x0:x1] - kx
        dy = Y[y0:y1, x0:x1] - ky
        along = dx * dirx + dy * diry
        across = -dx * diry + dy * dirx
        size = rng.uniform(0.0016, 0.0032)
        head = np.exp(-(dx * dx + dy * dy) / (2 * size**2))
        tail = (
            np.exp(-(across**2) / (2 * (size * 0.6) ** 2))
            * np.exp(-np.clip(along, 0, None) / rng.uniform(0.015, 0.035))
            * (along > 0)
        )
        knots[y0:y1, x0:x1] += (head * 0.8 + tail * 0.4) * rng.uniform(0.25, 0.9)
    knots = np.clip(knots, 0, 1)
    rgb_ring = rgb_ring * (1 - knots[..., None]) + np.array((1.0, 0.85, 0.6), np.float32) * knots[..., None]
    save("HelixRing.png", rgb_ring, np.maximum(a_ring, knots * 0.95))

    # --- Blue-teal core ---------------------------------------------------
    r_core, _ = ellipse_r(0.0, 0.0, 0.6, 0.5, math.radians(-15))
    r_core = r_core + (fine - 0.5) * 0.08
    fill = smoothstep(0.95, 0.35, r_core)
    core_gas = (0.3 + 0.8 * fbm(6, 5, 91)) * (0.75 + 0.35 * polar_fbm(4, 24, 2, 93))
    a_core = fill * core_gas * 0.75
    rgb_core = mix((0.25, 0.75, 0.95), (0.55, 0.95, 0.85), np.clip(fbm(4, 4, 97) * 1.3 - 0.15, 0, 1))
    save("HelixCore.png", rgb_core, a_core)

    # --- The star's glow --------------------------------------------------
    r = np.sqrt(X * X + Y * Y)
    glow = np.exp(-((r / 0.05) ** 2)) + 0.35 * np.exp(-((r / 0.16) ** 2))
    rgb_glow = mix((0.75, 0.9, 1.0), (1.0, 1.0, 1.0), np.clip(glow, 0, 1))
    save("HelixGlow.png", rgb_glow, glow)

    # A flattened preview of the whole stack, for checking by eye.
    preview = np.zeros((SIZE, SIZE, 3), np.float32)
    for name in ("HelixHalo.png", "HelixRing.png", "HelixCore.png", "HelixGlow.png"):
        layer = np.asarray(Image.open(OUT / name)).astype(np.float32) / 255
        a = layer[..., 3:4]
        preview = preview * (1 - a) + layer[..., :3] * a
    Image.fromarray((preview * 255).astype(np.uint8), "RGB").save(OUT / "HelixPreview.png")


if __name__ == "__main__":
    main()
