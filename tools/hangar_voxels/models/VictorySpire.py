"""Victory Spire (vanity): "a towering beacon spire seen across the galaxy".

Built at its site off the deck's side: a stepped white tower, each tier
narrower, with glowing cyan window strips on every face and gold trim
between tiers. Three rings of glowing blocks turn around it (alternate
ways), and at the top a giant gold trophy holds the pulsing beacon that
shoots a beam of light into the sky (the beam is added by HangarBuilder).
Gold stars sit on the plinth's corners. Budget: 120 parts.
"""

import math

from vox import Vox

PALETTE = {
    "Plinth": {"color": "#3A4050", "material": "Metal"},
    "Step": {"color": "#5A6070", "material": "Metal"},
    "Tower": {"color": "#E8EAED"},
    "Trim": {"color": "#FFD36B", "material": "Neon", "collide": False},
    "Window": {"color": "#5FE3FF", "material": "Neon", "collide": False},
    "Cup": {"color": "#FFC94A", "material": "Metal"},
    "CupRim": {"color": "#FFD36B", "material": "Neon", "collide": False},
    "Beacon": {"color": "#FFD36B", "material": "Neon", "collide": False, "pulse": (0, 0.5)},
    "CornerStar": {"color": "#FFD36B", "material": "Neon", "collide": False},
}
RINGS = [(8, 8, "#5FE3FF"), (19, 7, "#FFD36B"), (30, 6, "#5FE3FF")]
for i, (_y, _r, color) in enumerate(RINGS):
    PALETTE[f"Ring{i + 1}"] = {
        "color": color,
        "material": "Neon",
        "collide": False,
        "name": "Segment",
        "group": f"Ring{i + 1}",
    }


def windows(v, half, y0, y1):
    """A glowing strip down the middle of each face, one voxel proud."""
    v.box(-1, y0, -half - 1, 0, y1, -half - 1, "Window")
    v.box(-1, y0, half, 0, y1, half, "Window")
    v.box(-half - 1, y0, -1, -half - 1, y1, 0, "Window")
    v.box(half, y0, -1, half, y1, 0, "Window")


def build():
    v = Vox("VictorySpire", PALETTE)

    # Plinth and a step, with gold stars on the corners.
    v.octagon(-7, -7, 6, 6, 0, 0, "Plinth", cut=2)
    v.octagon(-6, -6, 5, 5, 1, 1, "Step", cut=2)
    for x, z in [(-6, -6), (5, -6), (-6, 5), (5, 5)]:
        v.box(x, 1, z, x, 2, z, "CornerStar")

    # Four tiers, narrowing, with gold trim between and windows on each.
    tiers = [(4, 2, 11), (3, 13, 22), (2, 24, 32), (1, 34, 40)]
    for i, (half, y0, y1) in enumerate(tiers):
        if half >= 3:
            v.octagon(-half, -half, half - 1, half - 1, y0, y1, "Tower")
        else:
            v.box(-half, y0, -half, half - 1, y1, half - 1, "Tower")
        if i < 3:
            windows(v, half, y0 + 2, y1 - 2)
            trim = half + 1 if half >= 3 else half
            if i < 2:
                v.octagon(-trim, -trim, trim - 1, trim - 1, y1 + 1, y1 + 1, "Trim")
            else:
                v.box(-trim, y1 + 1, -trim, trim - 1, y1 + 1, trim - 1, "Trim")

    # The trophy: stem, base, cup with handles and a glowing rim.
    v.box(-2, 41, -2, 1, 41, 1, "Cup")
    v.box(-1, 42, -1, 0, 43, 0, "Cup")
    v.octagon(-3, -3, 2, 2, 44, 46, "Cup")
    v.octagon(-3, -3, 2, 2, 47, 47, "CupRim")
    for x in (-5, 4):
        v.box(x, 44, -1, x, 46, 0, "Cup")
        v.box(min(x, 0) + (1 if x < 0 else -1), 46, -1, min(x, 0) + (1 if x < 0 else -1), 46, 0, "Cup")
    # The beacon in the cup.
    v.ball(0, 49.5, 0, 2.3, "Beacon")

    # Rings of glowing blocks around the tower.
    for i, (y, r, _color) in enumerate(RINGS):
        for s in range(8):
            a = s / 8 * 2 * math.pi
            x = math.floor(math.cos(a) * r - 0.5)
            z = math.floor(math.sin(a) * r - 0.5)
            v.box(x, y, z, x + 1, y, z + 1, f"Ring{i + 1}")
    return v
