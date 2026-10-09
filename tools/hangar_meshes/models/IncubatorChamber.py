"""Incubator Chamber (the Incubator Bay's egg chambers, StationBuilder).

A life-support incubator. Four splayed feet and a ribbed, vented base
with a front status panel (a small screen and three lamps) carry a seal
collar. Inside the glass dome, a three-pronged claw cradle with a soft
pad holds the egg. A steel band rings the dome's middle, and on top a
heater cap with stacked coils feeds two coolant pipes that curve down the
back into the base. Hazard chevrons mark the front of the base.

Built by the game, not here: the chamber's base part (invisible over the
mesh; it carries the chamber's attributes and the Incubate prompt), the
glowing floor ring and the cap light (both tinted the hatching egg's
rarity colour, HatchController). Measured from the floor: base top 1.4,
egg resting on the cradle at 2.0, dome centre 3.5 (radius 2.3), cap top
6.1 (the cap light sits at 6.4). Front (-Y) faces the deck.
"""

import math

from kit import Building, look

DARK = look("Base", "#2A2F3E", "Metal")
STEEL = look("Steel", "#8C95A6", "Metal")
HULL = look("Hull", "#E8EAED")
GLASS = look("Glass", "#D8ECFF", "Glass")
PAD = look("Pad", "#F2D8E8", "Fabric")
VENT = look("Vent", "#14171E", "Metal")
SCREEN = look("Screen", "#2A8A9A", "Neon")
COIL = look("Coil", "#D9A441", "Metal")
COOLANT = look("Coolant", "#5FC8E8", "Glass")
HAZARD_Y = look("HazardYellow", "#E8B020")
LAMPS = ["#5CFF8A", "#FFB020", "#FF4A4A"]


def build():
    b = Building("IncubatorChamber")

    # Four splayed feet and the ribbed, vented base.
    for i in range(4):
        a = math.radians(45 + i * 90)
        c, s = math.cos(a), math.sin(a)
        b.box(DARK, (1.0, 0.5, 0.25), (c * 2.35, s * 2.35, 0.12), rot=(0, 0, math.degrees(a)), bevel=0.06)
    b.cyl(DARK, 2.5, 1.2, (0, 0, 0.75), sides=40, bevel=0.1)
    for i in range(16):
        a = math.radians(i * 22.5)
        b.box(STEEL, (0.12, 0.2, 1.0), (math.cos(a) * 2.52, math.sin(a) * 2.52, 0.75), rot=(0, 0, i * 22.5), bevel=0.02)
    for k in range(4):
        b.box(VENT, (1.2, 0.06, 0.08), (0, 2.5, 0.45 + k * 0.2), bevel=0.01)
    # Front status panel: a screen and three lamps, with hazard chevrons below.
    b.box(HULL, (1.6, 0.2, 0.9), (0, -2.45, 0.85), bevel=0.06)
    b.box(SCREEN, (0.9, 0.05, 0.4), (-0.25, -2.56, 0.95), bevel=0.01)
    for k, color in enumerate(LAMPS):
        b.ball(look(f"Lamp{k + 1}", color, "Neon"), 0.07, (0.45, -2.56, 1.15 - k * 0.2), segments=8)
    for k in range(3):
        b.box(HAZARD_Y, (0.3, 0.06, 0.08), (-0.5 + k * 0.5, -2.55, 0.42), rot=(0, 45, 0), bevel=0.01)

    # Seal collar and the claw cradle with its pad (egg rests at 2.0).
    b.cyl(HULL, 2.45, 0.2, (0, 0, 1.45), sides=40, bevel=0.06)
    b.torus(STEEL, 2.4, 0.08, (0, 0, 1.58), sides=48)
    b.cyl(STEEL, 0.55, 0.25, (0, 0, 1.68), sides=24, bevel=0.04)
    b.cyl(PAD, 0.45, 0.14, (0, 0, 1.86), sides=24, bevel=0.05)
    for i in range(3):
        a = math.radians(90 + i * 120)
        c, s = math.cos(a), math.sin(a)
        b.tube(STEEL, [(c * 0.45, s * 0.45, 1.75), (c * 0.9, s * 0.9, 2.0), (c * 0.85, s * 0.85, 2.55)], 0.06, sides=8)
        b.ball(DARK, 0.09, (c * 0.85, s * 0.85, 2.58), segments=8)

    # The glass dome with a steel band round its middle.
    b.ball(GLASS, 2.3, (0, 0, 3.5), segments=40)
    b.torus(STEEL, 2.32, 0.06, (0, 0, 3.5), sides=48)
    for i in range(4):
        a = math.radians(45 + i * 90)
        b.box(DARK, (0.25, 0.25, 0.3), (math.cos(a) * 2.32, math.sin(a) * 2.32, 3.5), rot=(0, 0, math.degrees(a)), bevel=0.04)

    # Heater cap with stacked coils.
    b.cyl(DARK, 1.0, 0.3, (0, 0, 5.6), sides=32, bevel=0.06)
    for k in range(3):
        b.torus(COIL, 0.82 - k * 0.12, 0.05, (0, 0, 5.8 + k * 0.1), sides=24)
    b.cyl(STEEL, 0.55, 0.2, (0, 0, 6.0), sides=24, bevel=0.04)

    # Two coolant pipes from the cap, curving down the back into the base.
    for side in (-1, 1):
        x = side * 0.6
        b.tube(
            COOLANT,
            [(x, 0.6, 5.7), (x, 1.6, 5.4), (x * 1.3, 2.55, 4.2), (x * 1.3, 2.75, 2.6), (x * 1.3, 2.6, 1.3)],
            0.13,
            sides=10,
        )
        b.cyl(STEEL, 0.2, 0.25, (x * 1.3, 2.6, 1.25), sides=12, bevel=0.03)

    b.marker("Light_FFD0EE_8", (0, 0, 3.5))
    return b.finish()
