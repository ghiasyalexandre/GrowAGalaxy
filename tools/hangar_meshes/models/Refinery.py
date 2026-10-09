"""Stardust Refinery: "+15% Stardust from your stars".

A rounded furnace drum with a glowing slit window, fed by a conveyor ramp
carrying raw purple star-rock, two striped chimneys (one smokes), and an
output chute dropping golden ingots into a tray. Kept under 15 studs: the
deck's middle truss arch passes overhead.
"""

import math

from kit import Building, look

SLAB = look("Slab", "#2E3442", "DiamondPlate")
HULL = look("Hull", "#D9DEE6")
BLUE = look("Accent_Trim", "#4A5BD8")
STEEL = look("Steel", "#8C95A6", "Metal")
DARK = look("Dark", "#22262F", "Metal")
GLOW = look("Furnace", "#C8641E", "Neon")
STRIPE = look("Stripe", "#C93A33")
ROCK = look("Rock", "#6E4CC8")
GOLD = look("Ingot", "#D9A441", "Metal")


def build():
    b = Building("Refinery")
    b.box(SLAB, (12, 10.5, 0.6), (0, 0, 0.3), bevel=0.2)

    # The furnace: a squat drum under a low dome, a blue base ring.
    b.cyl(HULL, 3.8, 4.0, (0.5, 1.0, 2.6), sides=32, bevel=0.15)
    b.ball(HULL, 3.8, (0.5, 1.0, 4.6), scale=(1, 1, 0.6), segments=28)
    b.cyl(BLUE, 3.9, 0.6, (0.5, 1.0, 0.9), sides=32, bevel=0.1)
    # Glowing slit window on the front, in a dark frame.
    b.box(DARK, (3.6, 0.4, 1.5), (0.5, -2.7, 3.0), bevel=0.15)
    b.box(GLOW, (3.0, 0.2, 0.8), (0.5, -2.88, 3.0), bevel=0.05)

    # Two striped chimneys behind.
    for x, h in ((2.4, 13.5), (-1.2, 11.5)):
        b.cyl(HULL, 0.9, h - 5.0, (x, 3.4, 5.0 + (h - 5.0) / 2), sides=20, bevel=0.05)
        for z in (h - 1.2, h - 3.0):
            b.cyl(STRIPE, 0.93, 0.6, (x, 3.4, z), sides=20, bevel=0.03)
        b.cyl(DARK, 1.05, 0.4, (x, 3.4, h), sides=20, bevel=0.05)

    # Conveyor ramp in from the right (game -x, Blender +X), rocks riding it.
    ramp = math.degrees(math.atan2(2.2, 4.8))
    b.box(DARK, (5.2, 1.6, 0.3), (5.2, -0.6, 2.0), rot=(0, ramp, 0), bevel=0.05)
    b.box(STEEL, (0.3, 0.3, 1.8), (7.0, -0.6, 0.9))
    for i, x in enumerate((6.6, 5.5, 4.4)):
        z = 1.2 + (7.6 - x) / 4.8 * 2.2 + 0.4
        b.ball(ROCK, 0.42, (x, -0.6 + (0.25 if i % 2 else -0.2), z), segments=8)

    # Output chute on the left (game +x, Blender -X) and an ingot tray.
    b.box(STEEL, (2.4, 1.2, 0.4), (-4.2, -1.2, 2.8), rot=(0, -25, 0), bevel=0.1)
    b.box(DARK, (2.6, 2.4, 0.5), (-4.4, -2.8, 0.85), bevel=0.15)
    for i, (x, y) in enumerate(((-4.9, -3.3), (-3.9, -3.3), (-4.4, -2.4))):
        b.box(GOLD, (0.8, 0.45, 0.35), (x, y, 1.3 + (0.35 if i == 2 else 0)), bevel=0.08)

    b.marker("Smoke", (2.4, 3.4, 13.9))
    b.marker("Light_FF9A2E_12", (0.5, -3.2, 3.0))
    return b.finish()
