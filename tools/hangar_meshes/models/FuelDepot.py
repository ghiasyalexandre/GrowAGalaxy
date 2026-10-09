"""Fuel Depot: "+25% boost time on every ship".

A big orange spherical fuel tank on four legs, two white capsule tanks
with orange stripes, a red pump kiosk with a glowing screen and a hose
coiled to its nozzle, and pipes linking them, all on a slab with hazard
strips along the front.
"""

import math

from kit import Building, look

SLAB = look("Slab", "#2E3442", "DiamondPlate")
HAZARD = look("Hazard", "#E0B12A")
ORANGE = look("Tank", "#E8742A")
WHITE = look("Hull", "#E8EAED")
STEEL = look("Steel", "#8C95A6", "Metal")
RED = look("Pump", "#C93A33")
SCREEN = look("Screen", "#3FA8C8", "Neon")
BAND = look("Accent_Band", "#E8EAED", "Metal")
HOSE = look("Hose", "#1E2129")


def build():
    b = Building("FuelDepot")
    b.box(SLAB, (11.5, 10.5, 0.6), (0, 0, 0.3), bevel=0.2)
    for x in (-3.8, 0, 3.8):
        b.box(HAZARD, (2.6, 0.5, 0.08), (x, -4.9, 0.64), bevel=0.02)

    # The spherical tank on legs, back left.
    b.ball(ORANGE, 3.0, (-2.2, 1.8, 5.0), segments=28)
    b.torus(BAND, 3.02, 0.14, (-2.2, 1.8, 5.0), sides=40)
    for i in range(4):
        a = math.radians(45 + i * 90)
        x, y = -2.2 + math.cos(a) * 2.3, 1.8 + math.sin(a) * 2.3
        b.cyl(STEEL, 0.22, 3.6, (x, y, 2.4), sides=10, bevel=0)
    b.cyl(STEEL, 0.5, 0.6, (-2.2, 1.8, 8.2), sides=16)

    # Two capsule tanks on cradles, right.
    for y in (-0.6, 2.6):
        b.cyl(WHITE, 1.15, 4.6, (3.0, y, 1.9), rot=(90, 0, 0), sides=24, bevel=0.03)
        for dy in (-2.3, 2.3):
            b.ball(WHITE, 1.15, (3.0, y + dy, 1.9), scale=(1, 0.5, 1))
        b.cyl(ORANGE, 1.18, 0.5, (3.0, y, 1.9), rot=(90, 0, 0), sides=24, bevel=0.02)
    for dy in (-1.8, 1.8):
        b.box(STEEL, (3.0, 0.4, 0.8), (3.0, 1.0 + dy, 0.9), bevel=0.08)

    # Pump kiosk at the front, with screen, hose and nozzle.
    b.box(RED, (1.8, 1.3, 2.8), (-3.4, -3.6, 2.0), bevel=0.2)
    b.box(STEEL, (2.0, 1.5, 0.25), (-3.4, -3.6, 3.5), bevel=0.08)
    b.box(SCREEN, (1.1, 0.08, 0.6), (-3.4, -4.27, 2.6), bevel=0.02)
    b.tube(HOSE, [(-2.5, -3.9, 2.2), (-1.9, -4.2, 1.6), (-1.6, -4.3, 1.1), (-1.4, -4.2, 0.9)], 0.11)
    b.box(STEEL, (0.3, 0.6, 0.3), (-1.4, -4.3, 1.2), bevel=0.05)

    # Pipes linking the tanks and the pump.
    b.tube(STEEL, [(-2.2, 1.8, 1.9), (-2.2, -1.5, 1.0), (-3.4, -2.9, 1.0)], 0.18)
    b.tube(STEEL, [(3.0, -2.9, 1.9), (3.0, -3.6, 1.0), (-2.5, -3.6, 1.0)], 0.15)

    b.marker("Light_7FD4FF_10", (-3.4, -4.5, 2.6))
    return b.finish()
