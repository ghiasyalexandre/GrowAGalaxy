"""Galaxy Hologram (vanity): "a turning galaxy hologram over your deck".

Built at its site, 16 studs above the deck (z = 0 here is the hologram's
middle): a spiral galaxy of small glowing stars in two arms round a warm
core, over a faint force-field disc, all turning together (Spin_Holo_*).
On the deck below, a projector (a dark base with a purple lens ring)
beams a faint column up into it ("Beam": the game makes it see-through
and lets it breathe). Within 9 studs of the centre: truss arches pass
either side.
"""

import math

from kit import Building, look

DOWN = 16  # Config.Hangar HoloGalaxy site.y: the deck is this far below
COLORS = ["#4FB8D8", "#8A5CD8", "#C85A9A", "#D8B870"]
CORE = look("Spin_Holo_Core", "#E0C080", "Neon")
DISC = look("Spin_Holo_Disc", "#6A4FC8", "ForceField")
BASE = look("Base", "#22262F", "Metal")
RING = look("Accent_Ring", "#8C95A6", "Metal")
LENS = look("Lens", "#8A5CD8", "Neon")
BEAM = look("Beam", "#8A5CD8", "Neon")


def build():
    b = Building("HoloGalaxy")
    b.cyl(DISC, 8.5, 0.12, (0, 0, -0.2), sides=40, bevel=0)
    b.ball(CORE, 1.3, (0, 0, 0), scale=(1, 1, 0.7), segments=16)
    for arm in (0, 1):
        for step in range(1, 18):
            angle = arm * math.pi + step * 0.36
            r = 2.0 + step * 0.37
            color = COLORS[(step + arm) % len(COLORS)]
            star = look(f"Spin_Holo_Star{(step + arm) % len(COLORS)}", color, "Neon")
            size = 0.42 - step * 0.012
            b.ball(star, size, (math.cos(angle) * r, math.sin(angle) * r, (step % 3 - 1) * 0.25), segments=8)

    # The projector on the deck below, and its beam.
    deck = -DOWN
    b.cyl(BASE, 3.0, 0.6, (0, 0, deck + 0.3), sides=8, bevel=0.15)
    b.torus(RING, 2.2, 0.18, (0, 0, deck + 0.75), sides=24)
    b.cyl(LENS, 1.3, 0.3, (0, 0, deck + 0.8), sides=24, bevel=0.05)
    b.cyl(BEAM, 1.1, DOWN - 2.5, (0, 0, deck + 1 + (DOWN - 2.5) / 2), sides=16, top=0.6, bevel=0)

    b.marker("Light_8A5CD8_24", (0, 0, 0))
    return b.finish()
