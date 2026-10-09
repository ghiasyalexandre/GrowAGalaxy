"""Stardust Silo: "Stars hold 50% more uncollected Stardust".

A sleek white capsule tank on a hex plinth, held by three swept fins. A
glass window down its front shows the softly glowing Stardust inside;
silver bands and a railed catwalk ring it; pipes run down into the plinth;
a funnel on top draws a thin stream from a small crystal star that turns
above it.
"""

import math

from kit import Building, look

HULL = look("Hull", "#E8EAED")
DARK = look("Base", "#2E3442", "Metal")
SILVER = look("Trim", "#9AA3B5", "Metal")
GOLD = look("Accent_Trim", "#D9A441", "Metal")
GLASS = look("Window", "#9FD6FF", "Glass")
CORE = look("Core", "#C98A1E", "Neon")
STAR = look("Spin_Star_Crystal", "#E0B040", "Neon")  # turns (HangarBuilder)
LAMP = look("Accent_Lamp", "#4FB8D8", "Neon")


def build():
    b = Building("StardustSilo")

    # Hex plinth with a raised inner deck and a gold edge.
    b.cyl(DARK, 5.4, 0.8, (0, 0, 0.4), sides=6, bevel=0.12)
    b.cyl(SILVER, 4.4, 0.3, (0, 0, 0.95), sides=6, bevel=0.06)
    b.cyl(GOLD, 5.5, 0.12, (0, 0, 0.82), sides=6, bevel=0.03)

    # Three swept fins holding the tank.
    for i in range(3):
        a = math.radians(90 + i * 120)
        x, y = math.cos(a), math.sin(a)
        b.box(HULL, (0.5, 2.6, 5.5), (x * 3.6, y * 3.6, 3.6), rot=(0, 0, math.degrees(a) + 90), bevel=0.2)
        b.box(DARK, (0.6, 1.2, 0.6), (x * 4.2, y * 4.2, 1.4), rot=(0, 0, math.degrees(a) + 90))

    # The tank: a capsule.
    b.cyl(HULL, 3.1, 8.5, (0, 0, 6.6), sides=32, bevel=0.05)
    b.ball(HULL, 3.1, (0, 0, 10.85), scale=(1, 1, 0.7), segments=28)
    b.cyl(HULL, 3.1, 1.4, (0, 0, 1.9), sides=32, top=3.1, bevel=0.05)
    b.ball(DARK, 1.6, (0, 0, 1.6), scale=(1, 1, 0.5))

    # The window and the Stardust glowing behind it.
    b.box(CORE, (1.2, 0.2, 6.2), (0, -3.02, 6.6), bevel=0.05)
    b.box(GLASS, (1.7, 0.25, 6.8), (0, -3.15, 6.6), bevel=0.1)
    b.box(SILVER, (2.1, 0.3, 0.3), (0, -3.2, 3.15), bevel=0.08)
    b.box(SILVER, (2.1, 0.3, 0.3), (0, -3.2, 10.05), bevel=0.08)

    # Silver bands.
    for z in (3.6, 9.6):
        b.torus(SILVER, 3.15, 0.16, (0, 0, z))

    # Catwalk with a railing.
    b.cyl(DARK, 4.3, 0.18, (0, 0, 7.4), sides=32, bevel=0.03)
    b.torus(SILVER, 4.1, 0.06, (0, 0, 8.4))
    for i in range(10):
        a = math.radians(i * 36 + 18)
        b.cyl(SILVER, 0.06, 1.0, (math.cos(a) * 4.1, math.sin(a) * 4.1, 7.9), sides=8, bevel=0)
    for i in range(4):
        a = math.radians(i * 90 + 45)
        b.cyl(LAMP, 0.12, 0.12, (math.cos(a) * 4.25, math.sin(a) * 4.25, 7.55), sides=12, bevel=0)

    # Pipes from the tank's side down into the plinth.
    for side in (-1, 1):
        b.tube(SILVER, [(side * 3.0, 1.2, 5.2), (side * 4.0, 1.2, 4.6), (side * 4.0, 1.2, 1.4), (side * 3.6, 1.2, 1.0)], 0.22)

    # Funnel and the crystal star turning above it.
    b.cyl(SILVER, 0.7, 1.6, (0, 0, 13.0), top=1.8, sides=32, bevel=0.04)
    b.torus(GOLD, 1.8, 0.1, (0, 0, 13.8))
    b.cyl(CORE, 0.12, 2.0, (0, 0, 14.9), sides=8, bevel=0)
    b.ball(STAR, 0.9, (0, 0, 16.6), scale=(1, 1, 1.5), segments=4)
    b.ball(STAR, 0.7, (0, 0, 16.6), scale=(1.5, 1.5, 0.6), segments=4)

    b.marker("Light_FFC860_14", (0, -3.4, 6.6))
    return b.finish()
