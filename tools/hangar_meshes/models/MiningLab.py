"""Mining Lab: "+15% laser power on every ship".

A white drum lab under a glass dome with a glowing test crystal and a roof
dish, and beside it a mining laser on a yellow turret firing a dim red
beam up into a captured asteroid (with purple ore) that turns slowly above
the pad. Stays within 4.5 studs of the back line: a truss arch passes just
behind it.
"""

import math
import random

from kit import Building, look

SLAB = look("Slab", "#2E3442", "DiamondPlate")
HULL = look("Hull", "#E8EAED")
BLUE = look("Accent_Trim", "#4A5BD8")
GLASS = look("Dome", "#9FD6FF", "Glass")
CRYSTAL = look("Crystal", "#8A4FD8", "Neon")
YELLOW = look("Turret", "#E0B12A")
DARK = look("Dark", "#22262F", "Metal")
STEEL = look("Steel", "#8C95A6", "Metal")
BEAM = look("Laser", "#B8402E", "Neon")
ROCK = look("Spin_Asteroid_Rock", "#6E7380", "Slate")
ORE = look("Spin_Asteroid_Ore", "#9A6BE0", "Neon")


def build():
    b = Building("MiningLab")
    b.box(SLAB, (12, 9.5, 0.6), (0, -0.5, 0.3), bevel=0.2)

    # Lab on the right (game -x, Blender +X): drum, blue band, glass dome.
    b.cyl(HULL, 3.0, 3.2, (2.8, 0.5, 2.2), sides=32, bevel=0.15)
    b.cyl(BLUE, 3.05, 0.4, (2.8, 0.5, 3.5), sides=32, bevel=0.05)
    b.ball(GLASS, 2.7, (2.8, 0.5, 3.8), scale=(1, 1, 0.8), segments=24)
    b.ball(CRYSTAL, 0.6, (2.8, 0.5, 4.6), scale=(1, 1, 2.0), segments=6)
    b.box(DARK, (1.2, 0.3, 2.0), (2.8, -2.55, 1.6), bevel=0.1)
    # Roof dish on a mast.
    b.cyl(STEEL, 0.1, 1.6, (4.6, 2.2, 4.6), sides=8, bevel=0)
    b.ball(HULL, 0.9, (4.4, 2.0, 5.5), scale=(1, 1, 0.3), segments=16)

    # The laser turret on the left (game +x, Blender -X).
    b.cyl(DARK, 1.6, 0.8, (-3.0, -0.8, 1.0), sides=24)
    b.box(YELLOW, (2.0, 2.0, 1.4), (-3.0, -0.8, 2.1), bevel=0.3)
    b.cyl(DARK, 0.45, 4.0, (-3.0, -0.8, 4.6), sides=16)
    for z in (3.6, 5.2):
        b.torus(STEEL, 0.5, 0.1, (-3.0, -0.8, z), sides=16)
    b.cyl(BEAM, 0.14, 4.2, (-3.0, -0.8, 8.7), sides=8, bevel=0)

    # The asteroid: a lumpy rock with ore, turning above the beam.
    rng = random.Random(7)
    centre = (-3.0, -0.8, 13.0)
    b.ball(ROCK, 2.6, centre, scale=(1.2, 1.0, 0.85), segments=12)
    for _ in range(5):
        a, e = rng.uniform(0, 2 * math.pi), rng.uniform(-0.6, 0.6)
        d = (math.cos(a) * math.cos(e) * 2.4, math.sin(a) * math.cos(e) * 2.0, math.sin(e) * 1.9)
        b.ball(ROCK, rng.uniform(0.8, 1.3), tuple(c + o for c, o in zip(centre, d)), segments=8)
    for _ in range(4):
        a, e = rng.uniform(0, 2 * math.pi), rng.uniform(-0.5, 0.5)
        d = (math.cos(a) * 2.9, math.sin(a) * 2.4, math.sin(e) * 2.0)
        b.ball(ORE, 0.35, tuple(c + o for c, o in zip(centre, d)), scale=(1, 1, 1.8), segments=6)

    b.marker("Light_B06BFF_12", (2.8, 0.5, 4.6))
    b.marker("Light_FF6A3D_12", (-3.0, -0.8, 10.4))
    return b.finish()
