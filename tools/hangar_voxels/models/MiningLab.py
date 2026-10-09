"""Mining Lab: "+15% laser power on every ship".

A white lab with a stepped glass dome over a glowing test crystal, a dish on
its roof and a case of crystal samples out front. Beside it a mining laser
fires a pulsing red beam up into a captured asteroid (purple crystals
poking out) that turns slowly above the pad. Everything stays within 4
studs of the pad's back line: a truss arch passes just behind it.
Budget: 120 parts (tests/WorldSmoke).
"""

import math

from vox import Vox

PALETTE = {
    "Slab": {"color": "#4A505E", "material": "Metal"},
    "SlabTrim": {"color": "#B06BFF", "material": "Neon", "collide": False},
    "Lab": {"color": "#E8EAED"},
    "LabTrim": {"color": "#5B6CFF"},
    "Dome": {"color": "#A9DCFF", "material": "Glass", "transparency": 0.45},
    "Crystal": {"color": "#B06BFF", "material": "Neon", "collide": False},
    "Door": {"color": "#3A4050", "material": "Metal"},
    "DoorLight": {"color": "#B06BFF", "material": "Neon", "collide": False},
    "Dish": {"color": "#D9DEE6", "collide": False},
    "DishArm": {"color": "#8D9099", "material": "Metal", "collide": False},
    "Case": {"color": "#A9DCFF", "material": "Glass", "transparency": 0.4, "collide": False},
    "Base": {"color": "#3A4050", "material": "Metal"},
    "Cable": {"color": "#22252E", "collide": False},
    "Head": {"color": "#F2C230"},
    "Barrel": {"color": "#2A2E38", "material": "Metal"},
    "BarrelRing": {"color": "#FF4A4A", "material": "Neon", "collide": False},
    "Laser": {
        "color": "#FF4A3D",
        "material": "Neon",
        "collide": False,
        "transparency": 0.2,
        "name": "LaserTip",
        "pulse": (0.05, 0.5),
    },
    "Rock": {"color": "#7A7F8C", "material": "Slate", "group": "Asteroid"},
    "RockDark": {"color": "#5A5F6B", "material": "Slate", "group": "Asteroid"},
    "Ore": {"color": "#C49BFF", "material": "Neon", "collide": False, "group": "Asteroid"},
}


def build():
    v = Vox("MiningLab", PALETTE)

    # Slab with a purple light strip along the front.
    v.box(-6, 0, -5, 5, 0, 4, "Slab")
    v.box(-6, 0, -5, 5, 0, -5, "SlabTrim")

    # The lab on the right (-x): walls, a blue trim line, a stepped dome.
    v.box(-6, 1, -3, -1, 4, 4, "Lab")
    v.box(-6, 4, -3, -1, 4, 4, "LabTrim")
    v.box(-5, 5, -2, -2, 5, 3, "Dome")
    v.box(-4, 6, -1, -3, 6, 2, "Dome")
    v.box(-4, 5, 0, -3, 6, 1, "Crystal")  # the test crystal under the dome
    v.box(-3, 1, -3, -2, 3, -3, "Door")
    v.box(-3, 4, -4, -2, 4, -4, "DoorLight")

    # Roof dish, tilted towards the asteroid.
    v.box(-6, 5, 3, -6, 6, 3, "DishArm")
    v.box(-6, 7, 2, -5, 7, 4, "Dish")
    v.box(-5, 8, 2, -5, 8, 4, "Dish")
    v.set(-5, 8, 3, "DishArm")

    # Sample case out front with crystals inside.
    v.box(-6, 1, -5, -4, 2, -4, "Case")
    v.set(-5, 1, -5, "Crystal")
    v.box(-5, 1, -4, -5, 2, -4, "Crystal")

    # The mining laser on the left (+x): base, yellow head, banded barrel.
    v.octagon(1, -3, 5, 1, 1, 2, "Base")
    v.box(2, 3, -2, 4, 4, 0, "Head")
    def plus(y0, y1, key):
        v.box(2, y0, -1, 4, y1, -1, key)
        v.box(3, y0, -2, 3, y1, 0, key)

    plus(5, 9, "Barrel")
    plus(6, 6, "BarrelRing")
    plus(8, 8, "BarrelRing")
    v.box(3, 10, -1, 3, 10, -1, "Barrel")
    # Its beam, up into the asteroid.
    v.box(3, 11, -1, 3, 13, -1, "Laser")
    v.box(-1, 2, -2, 1, 2, -2, "Cable")  # power cable from the lab

    # The asteroid: a lumpy ball of rock with glowing ore.
    cx, cy, cz = 3.5, 16.5, -0.5
    for x in range(-1, 9):
        for y in range(13, 21):
            for z in range(-5, 5):
                d = math.dist((x + 0.5, (y + 0.5 - cy) * 1.15 + cy, z + 0.5), (cx, cy, cz))
                lump = 0.5 * math.sin(x * 1.7 + z * 2.3) + 0.4 * math.cos(y * 1.3)
                if d <= 3.2 + lump:
                    v.set(x, y, z, "Rock")
    # A few dark craters on its surface.
    for x, y, z in [(1, 15, -3), (5, 18, -3), (6, 15, 0), (2, 19, 0)]:
        if (x, y, z) in v.cells:
            v.set(x, y, z, "RockDark")
    v.box(3, 13, -1, 3, 13, -1, "Laser")  # beam meets the rock
    for x, y, z in [(0, 16, -1), (6, 17, -1), (3, 19, -1), (3, 16, -4), (3, 17, 2), (1, 18, 1)]:
        v.set(x, y, z, "Ore")
    return v
