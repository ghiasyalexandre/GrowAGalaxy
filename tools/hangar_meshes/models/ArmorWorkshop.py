"""Armor Workshop: "+30% hull on every ship".

An open bay under an arched, ribbed roof crowned with a shield emblem.
Inside, a sleek blue ship sits on a lift, half clad in silver armour
plates, while a yellow robot arm welds on the next (sparks fly from its
torch). A rack of spare plates stands at the back. Stays within 4.5 studs
of the back line: a truss arch passes just behind it.
"""

import math

from kit import Building, look

SLAB = look("Slab", "#2E3442", "DiamondPlate")
HAZARD = look("Hazard", "#E0B12A")
RIB = look("Rib", "#8C95A6", "Metal")
ROOF = look("Roof", "#D9DEE6")
DARK = look("Dark", "#22262F", "Metal")
SHIP = look("Ship", "#3F6FD8")
GLASS = look("Canopy", "#9FD6FF", "Glass")
ARMOR = look("Armor", "#B8C0CC", "Metal")
ROBOT = look("Robot", "#E0B12A")
SHIELD = look("Shield", "#D9DEE6", "Metal")
EMBLEM = look("Accent_Emblem", "#2E8FD0", "Neon")
STRIP = look("Accent_Strip", "#C88A3A", "Neon")


def build():
    b = Building("ArmorWorkshop")
    b.box(SLAB, (12, 9.5, 0.6), (0, -0.5, 0.3), bevel=0.2)
    b.box(HAZARD, (10, 0.4, 0.08), (0, -5.0, 0.64), bevel=0.02)

    # Arched roof: three ribs and panels between them, open at the front.
    r = 5.6
    for y in (-4.0, 0.0, 4.0):
        for i in range(10):
            a = math.radians(i * 18 + 9)
            b.box(RIB, (1.8, 0.35, 0.35), (math.cos(a) * r, y, 0.6 + math.sin(a) * r), rot=(0, -(i * 18 + 9) + 90, 0), bevel=0.05)
    for i in range(1, 9):
        a = math.radians(i * 18 + 9)
        b.box(ROOF, (1.75, 7.6, 0.12), (math.cos(a) * (r - 0.1), 0.0, 0.6 + math.sin(a) * (r - 0.1)), rot=(0, -(i * 18 + 9) + 90, 0), bevel=0.02)
    b.box(STRIP, (6.0, 0.15, 0.1), (0, -3.9, 0.6 + r - 0.5), bevel=0.02)

    # Shield emblem on the roof's front.
    b.box(SHIELD, (2.6, 0.4, 1.8), (0, -3.9, r + 2.6), bevel=0.25)
    b.cyl(SHIELD, 1.83, 1.6, (0, -3.9, r + 1.0), rot=(90, 45, 0), sides=4, top=0.05, bevel=0)
    b.box(EMBLEM, (0.5, 0.1, 2.2), (0, -4.15, r + 2.0), bevel=0.05)
    b.box(EMBLEM, (1.8, 0.1, 0.5), (0, -4.15, r + 2.5), bevel=0.05)

    # The lift and the ship on it, nose to the front.
    b.cyl(DARK, 2.6, 0.5, (0, -0.4, 0.85), sides=24)
    b.cyl(HAZARD, 2.65, 0.15, (0, -0.4, 1.1), sides=24, bevel=0)
    b.ball(SHIP, 1.0, (0, -0.4, 2.2), scale=(1.1, 3.0, 0.75), segments=20)
    b.ball(GLASS, 0.6, (0, -1.4, 2.8), scale=(1, 1.8, 0.7), segments=16)
    for side in (-1, 1):
        b.box(SHIP, (2.4, 1.6, 0.18), (side * 1.6, 0.4, 2.0), rot=(0, side * -8, side * 12), bevel=0.06)
    b.cyl(DARK, 0.5, 0.8, (0, 2.6, 2.2), rot=(90, 0, 0), sides=16)
    # Armour already fitted on its right side (game -x, Blender +X).
    for i, y in enumerate((-1.6, -0.4, 0.8)):
        b.box(ARMOR, (0.15, 1.1, 0.9), (1.15, y, 2.25), rot=(0, 10, 0), bevel=0.05)

    # The robot arm on the left (game +x, Blender -X), torch at the hull.
    b.cyl(DARK, 0.7, 0.5, (-3.6, 0.6, 0.85), sides=16)
    b.box(ROBOT, (0.6, 0.6, 2.6), (-3.6, 0.6, 2.3), rot=(0, 15, 0), bevel=0.15)
    b.ball(DARK, 0.4, (-3.25, 0.6, 3.6))
    b.box(ROBOT, (2.0, 0.5, 0.5), (-2.4, 0.6, 3.3), rot=(0, 25, 0), bevel=0.12)
    b.cyl(DARK, 0.15, 0.6, (-1.5, 0.6, 2.85), rot=(0, 25, 0), sides=8, bevel=0)

    # Spare plates on a rack at the back.
    b.box(DARK, (3.4, 0.4, 0.3), (3.2, 3.6, 3.2), bevel=0.05)
    for x in (2.2, 3.2, 4.2):
        b.box(ARMOR, (0.8, 0.15, 2.2), (x, 3.4, 2.0), rot=(8, 0, 0), bevel=0.05)

    b.marker("Sparks", (-1.25, 0.6, 2.6))
    b.marker("Light_FFC870_10", (-1.25, 0.6, 2.8))
    b.marker("Light_2E8FD0_14", (0, -4.5, r + 2.2))
    return b.finish()
