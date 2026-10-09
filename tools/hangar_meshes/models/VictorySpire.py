"""Victory Spire (vanity): "a towering beacon spire seen across the galaxy".

Built at its site off the deck's side: an elegant lathed tower flaring
out at its base, with gold collars and slim window strips, three rings
turning round it (Spin_Ring1..3, alternate ways), and at the top a
trophy cup holding the beacon, which shoots a beam of light into the sky
(the game adds the beam at the Beam marker).
"""

import math

from kit import Building, look

TOWER = look("Tower", "#E8EAED")
BASE = look("Base", "#2E3442", "Metal")
GOLD = look("Gold", "#D9A441", "Metal")
WINDOW = look("Accent_Window", "#3FA8C8", "Neon")
CUP = look("Cup", "#D9A441", "Metal")
BEACON = look("Beacon", "#E0B040", "Neon")
RINGS = [(12, 7.5, "#3FA8C8"), (22, 6.4, "#D9A441"), (32, 5.4, "#3FA8C8")]


def radius_at(z):
    """The tower's radius at height z: a flared foot easing to a slim top."""
    return 1.5 + 4.5 * math.exp(-z / 6.0) + 0.9 * (1 - z / 42)


def build():
    b = Building("VictorySpire")
    b.cyl(BASE, 8.0, 1.0, (0, 0, 0.5), sides=8, bevel=0.2)
    b.cyl(GOLD, 8.1, 0.2, (0, 0, 1.05), sides=8, bevel=0.05)
    profile = [(radius_at(z), z) for z in (1, 2, 3.5, 5, 7, 10, 14, 19, 25, 31, 37, 42)]
    b.lathe(TOWER, profile, sides=24)
    for z in (9, 18, 27, 36):
        b.torus(GOLD, radius_at(z) + 0.1, 0.25, (0, 0, z), sides=24)
    # Window strips on the four faces between the collars.
    for z0, z1 in ((10.5, 16.5), (19.5, 25.5), (28.5, 34.5)):
        zm = (z0 + z1) / 2
        r = radius_at(zm) + 0.05
        for a in (0, 90, 180, 270):
            rad = math.radians(a)
            b.box(WINDOW, (0.5, 0.12, z1 - z0), (math.cos(rad) * r, math.sin(rad) * r, zm), rot=(0, 0, a + 90), bevel=0.04)

    # The trophy: stem, cup, handles, and the beacon in it.
    b.lathe(CUP, [(0.6, 42), (0.5, 43.5), (1.4, 44.2), (2.6, 46.5), (3.0, 48.2), (2.8, 48.4)], sides=24)
    for side in (-1, 1):
        b.torus(CUP, 1.0, 0.18, (side * 3.2, 0, 46.5), rot=(90, 0, 0), sides=16)
    b.ball(BEACON, 2.0, (0, 0, 49.6), segments=20)

    # The rings that turn round the tower.
    for i, (z, r, color) in enumerate(RINGS, start=1):
        b.torus(look(f"Spin_Ring{i}_Band", color, "Neon"), r, 0.22, (0, 0, z), sides=40)
        for k in range(6):
            a = math.radians(k * 60)
            b.box(look(f"Spin_Ring{i}_Pod", "#8C95A6", "Metal"), (0.9, 0.9, 0.6), (math.cos(a) * r, math.sin(a) * r, z), rot=(0, 0, k * 60), bevel=0.15)

    b.marker("Beam", (0, 0, 49.6))
    b.marker("Light_FFD36B_60", (0, 0, 49.6))
    return b.finish()
