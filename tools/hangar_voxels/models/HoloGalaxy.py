"""Galaxy Hologram (vanity): "a turning galaxy hologram over your deck".

Built at its site, 16 studs above the deck (y = 0 here is the hologram's
middle): a voxel spiral galaxy, a glowing gold core, two arms of coloured
voxel stars, two tiny planets and a faint force-field disc, all turning
together ("Hologram"). On the deck below, a projector (a dark base with a
purple lens ring) beams a faint pulsing column up into it.
Kept within 9 studs of its centre in z: truss arches pass either side.
Budget: 120 parts (tests/WorldSmoke).
"""

import math

from vox import Vox

DOWN = 16  # Config.Hangar HoloGalaxy site.y: the deck is this far below
STAR_COLORS = ["#5FE3FF", "#B06BFF", "#FF6EC8", "#FFE6A3"]

PALETTE = {
    "Core": {"color": "#FFE6A3", "material": "Neon", "collide": False, "group": "Hologram"},
    "CoreGlow": {"color": "#FFB347", "material": "Neon", "collide": False, "group": "Hologram"},
    "Disc": {
        "color": "#8C6BFF",
        "material": "ForceField",
        "transparency": 0.2,
        "collide": False,
        "group": "Hologram",
    },
    "PlanetA": {"color": "#5CFF8A", "material": "Neon", "collide": False, "group": "Hologram"},
    "PlanetB": {"color": "#FF9A3D", "material": "Neon", "collide": False, "group": "Hologram"},
    "Base": {"color": "#2A2E38", "material": "Metal"},
    "BaseTrim": {"color": "#5A6070", "material": "Metal"},
    "Lens": {"color": "#B06BFF", "material": "Neon", "collide": False, "name": "Projector"},
    "Beam": {
        "color": "#B06BFF",
        "material": "Neon",
        "transparency": 0.85,
        "collide": False,
        "name": "Beam",
        "pulse": (0.75, 0.92),
    },
}
for i, color in enumerate(STAR_COLORS):
    PALETTE[f"Star{i}"] = {
        "color": color,
        "material": "Neon",
        "collide": False,
        "name": "Star",
        "group": "Hologram",
    }


def build():
    v = Vox("HoloGalaxy", PALETTE)

    # The faint disc, then the stars and core over it.
    v.cyl(0, 0, 8.4, -1, -1, "Disc")
    for arm in (0, 1):
        for step in range(1, 18):
            angle = arm * math.pi + step * 0.36
            r = 2.0 + step * 0.38
            x = math.floor(math.cos(angle) * r)
            z = math.floor(math.sin(angle) * r)
            y = 0 if step % 3 else 1
            v.set(x, y, z, f"Star{(step + arm) % len(STAR_COLORS)}")
    v.ball(0, 0.5, 0, 1.9, "CoreGlow")
    v.ball(0, 0.5, 0, 1.2, "Core")
    # Two tiny planets out on the rim.
    v.box(6, 0, 3, 6, 1, 3, "PlanetA")
    v.box(-7, 0, -2, -7, 0, -2, "PlanetB")

    # The projector on the deck below, and its beam.
    deck = -DOWN
    v.octagon(-3, -3, 2, 2, deck, deck, "Base")
    v.octagon(-2, -2, 1, 1, deck + 1, deck + 1, "BaseTrim")
    v.box(-1, deck + 2, -1, 0, deck + 2, 0, "Lens")
    v.box(-1, deck + 3, -1, 0, -3, 0, "Beam")
    return v
