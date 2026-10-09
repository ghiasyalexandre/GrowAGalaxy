"""Cooling Tower: "+25% laser cooling on every ship".

A smooth hourglass cooling tower (a lathed hyperboloid) with icy blue
bands, a glowing coolant pool in its open top that steams, and a fan
turning over it; a frosted coolant pipe runs to a laser cannon whose
barrel is wrapped in radiator fins. Kept under 15 studs: the deck's middle
truss arch passes overhead.
"""

import math

from kit import Building, look

SLAB = look("Slab", "#2E3442", "DiamondPlate")
SHELL = look("Shell", "#C9CED6", "Concrete")
ICE = look("Accent_Band", "#7FC8E8")
POOL = look("Coolant", "#2E9FC8", "Neon")
STEEL = look("Steel", "#8C95A6", "Metal")
DARK = look("Dark", "#22262F", "Metal")
FAN = look("Spin_Fan_Blades", "#E8EAED")
FROST = look("Frost", "#DDF3FF", "Ice")


def radius_at(t):
    """The tower's radius at height share t (0 bottom, 1 top)."""
    return 2.6 + 2.1 * ((t - 0.62) / 0.62) ** 2


def build():
    b = Building("CoolingTower")
    b.box(SLAB, (12, 10.5, 0.6), (0, 0, 0.3), bevel=0.2)

    # The tower: narrows to a waist, flares at the top.
    profile = [(radius_at(i / 12), 0.6 + i / 12 * 12.6) for i in range(13)]
    b.lathe(SHELL, profile, at=(1.0, 1.0, 0), sides=32)
    for t in (0.12, 0.62):
        b.torus(ICE, radius_at(t) + 0.05, 0.16, (1.0, 1.0, 0.6 + t * 12.6), sides=32)
    b.torus(ICE, radius_at(1) - 0.05, 0.22, (1.0, 1.0, 13.2), sides=32)
    b.cyl(POOL, radius_at(1) - 0.35, 0.12, (1.0, 1.0, 13.28), sides=32, bevel=0)

    # The fan over the pool (turns).
    b.cyl(FAN, 0.35, 0.3, (1.0, 1.0, 13.9), sides=12, bevel=0)
    for a in (0, 90):
        b.box(FAN, (3.6, 0.5, 0.08), (1.0, 1.0, 13.9), rot=(10, 0, a), bevel=0.02)

    # Frosted pipe to the cannon at the front right (game -x, Blender +X).
    b.tube(FROST, [(3.2, -0.6, 1.4), (4.4, -1.6, 1.4), (4.4, -3.0, 1.4)], 0.2)
    # The cannon: base, turret, barrel with radiator fins.
    b.cyl(DARK, 1.3, 0.8, (4.4, -3.6, 1.0), sides=20)
    b.box(STEEL, (1.6, 1.6, 1.0), (4.4, -3.6, 1.9), bevel=0.2)
    tilt = math.radians(50)
    b.cyl(DARK, 0.3, 3.0, (4.4, -4.3, 3.2), rot=(-50, 0, 0), sides=12)
    for i in range(4):
        d = -0.6 + i * 0.4
        at = (4.4, -4.3 - d * math.sin(tilt), 3.2 + d * math.cos(tilt))
        b.cyl(ICE, 0.6, 0.08, at, rot=(-50, 0, 0), sides=12, bevel=0)

    b.marker("Steam", (1.0, 1.0, 13.3))
    b.marker("Light_5FE3FF_14", (1.0, 1.0, 13.6))
    return b.finish()
