"""Stardust Collector (station deck machine, DeviceBuilder.collector).

A heavy industrial condenser. A hexagonal foundation plate with corner
bolts, floor vents and a yellow-and-black hazard ring carries a stepped
pedestal. On it stands the tall glass tank between two machined collars,
held by six struts with clamp bands, and a vertical gauge column on its
left (Gauge1..6, lit by the game as the tank fills).

Above the tank sits the compressor: a finned drum (cooling fins all round),
a funnel crown with a lit lip, and four curved intake horns with flared
nozzles and accent lamp rings, reaching up to pull Stardust out of space.
Pressure pipes with valve wheels climb the right side, a cable bundle runs
down the back, a service ladder hangs on the back, and the console pedestal
at the front carries the code-built Collect panel.

Contract with the game (DeviceBuilder.COLLECTOR_TANK): the tank's inside is
radius 1.45 from 1.75 to 5.65 studs up; the game builds the Stardust fill
and the floating core there. Front is -Y; game +x is Blender -X.
"""

import math

from kit import Building, look

DARK = look("Base", "#2E3442", "Metal")
PLATE = look("Plate", "#3A4152", "DiamondPlate")
STEEL = look("Steel", "#8C95A6", "Metal")
HULL = look("Hull", "#E8EAED")
PANEL = look("Panel", "#C9CED9")
GLASS = look("Tank", "#BFE6FF", "Glass")
TRIM = look("Accent_Trim", "#D9A441", "Metal")
LAMP = look("Accent_Lamp", "#C8A040", "Neon")
GOLD = look("Gold", "#D9A441", "Metal")
HAZARD_Y = look("HazardYellow", "#E8B020")
HAZARD_K = look("HazardBlack", "#1C1C1C")
VENT = look("Vent", "#14171E", "Metal")
VALVE = look("Valve", "#C8402F", "Metal")
CABLE = look("Cable", "#23262E")
GLOW = look("CoreGlow", "#FFC860", "Neon")


def build():
    b = Building("StardustCollector")

    # Foundation: a hexagonal plate with bolts, vents and a hazard ring.
    b.cyl(PLATE, 3.5, 0.3, (0, 0, 0.15), sides=6, bevel=0.08)
    for i in range(6):
        a = math.radians(i * 60)
        b.cyl(STEEL, 0.14, 0.12, (math.cos(a) * 3.1, math.sin(a) * 3.1, 0.34), sides=8, bevel=0.02)
    for i in range(3):
        a = math.radians(30 + i * 120)
        c, s = math.cos(a), math.sin(a)
        for k in range(4):
            r = 2.45 + k * 0.18
            b.box(VENT, (0.1, 0.9, 0.05), (c * r, s * r, 0.32), rot=(0, 0, math.degrees(a)), bevel=0.01)
    for i in range(16):
        a = math.radians(i * 22.5)
        b.box(
            HAZARD_Y if i % 2 == 0 else HAZARD_K,
            (0.55, 0.32, 0.06),
            (math.cos(a) * 2.95, math.sin(a) * 2.95, 0.33),
            rot=(0, 0, i * 22.5 + 90),
            bevel=0.01,
        )

    # Stepped pedestal with an accent ring and bolt heads.
    b.cyl(DARK, 2.75, 0.45, (0, 0, 0.52), sides=32, bevel=0.1)
    b.cyl(STEEL, 2.35, 0.4, (0, 0, 0.95), sides=32, bevel=0.08)
    b.torus(TRIM, 2.38, 0.08, (0, 0, 1.15), sides=48)
    for i in range(12):
        a = math.radians(i * 30)
        b.cyl(STEEL, 0.09, 0.1, (math.cos(a) * 2.55, math.sin(a) * 2.55, 0.78), sides=6, bevel=0)
    b.cyl(HULL, 1.95, 0.5, (0, 0, 1.4), sides=32, bevel=0.12)

    # The glass tank between two machined collars.
    b.cyl(GLASS, 1.6, 4.0, (0, 0, 3.7), sides=40, bevel=0)
    for z in (1.65, 5.75):
        b.cyl(HULL, 1.85, 0.36, (0, 0, z), sides=40, bevel=0.1)
        b.torus(TRIM, 1.86, 0.07, (0, 0, z), sides=40)
        b.torus(STEEL, 1.9, 0.05, (0, 0, z + (0.2 if z > 3 else -0.2)), sides=40)
    # Six struts with clamp bands.
    for i in range(6):
        a = math.radians(30 + i * 60)
        x, y = math.cos(a) * 1.7, math.sin(a) * 1.7
        b.cyl(STEEL, 0.07, 4.0, (x, y, 3.7), sides=8, bevel=0)
        for z in (2.6, 3.7, 4.8):
            b.cyl(DARK, 0.12, 0.14, (x, y, z), sides=8, bevel=0.02)

    # Compressor drum with cooling fins, a funnel crown and a lit lip.
    b.cyl(DARK, 1.55, 0.7, (0, 0, 6.3), sides=32, bevel=0.08)
    for i in range(20):
        a = math.radians(i * 18)
        b.box(STEEL, (0.06, 0.32, 0.6), (math.cos(a) * 1.62, math.sin(a) * 1.62, 6.3), rot=(0, 0, i * 18), bevel=0.01)
    b.torus(GOLD, 1.58, 0.06, (0, 0, 6.68), sides=32)
    b.cyl(STEEL, 0.9, 0.9, (0, 0, 7.1), sides=32, top=1.45, bevel=0.04)
    b.torus(LAMP, 1.45, 0.06, (0, 0, 7.55), sides=40)
    b.cyl(GLOW, 0.5, 0.06, (0, 0, 6.68), sides=24, bevel=0)

    # Four curved intake horns with flared nozzles and lamp rings.
    for i in range(4):
        a = math.radians(45 + i * 90)
        c, s = math.cos(a), math.sin(a)
        pts = [
            (c * 1.2, s * 1.2, 6.6),
            (c * 1.9, s * 1.9, 7.1),
            (c * 2.4, s * 2.4, 7.9),
            (c * 2.5, s * 2.5, 8.6),
        ]
        b.tube(HULL, pts, 0.17, sides=10)
        b.tube(STEEL, [(c * 1.55, s * 1.55, 6.85), (c * 1.95, s * 1.95, 7.1)], 0.22, sides=10)
        b.cyl(STEEL, 0.2, 0.35, (c * 2.5, s * 2.5, 8.75), sides=16, top=0.34, bevel=0.02)
        b.torus(LAMP, 0.3, 0.05, (c * 2.5, s * 2.5, 8.95), sides=16)
        b.ball(LAMP, 0.12, (c * 2.5, s * 2.5, 9.0), segments=10)

    # Gauge column on the tank's left (game +x, Blender -X): six lamps.
    b.box(DARK, (0.55, 0.6, 4.4), (-2.3, 0, 3.7), bevel=0.12)
    b.box(PANEL, (0.08, 0.5, 4.1), (-2.6, 0, 3.7), bevel=0.02)
    for n in range(1, 7):
        b.box(look(f"Gauge{n}", "#3A3020", "Neon"), (0.12, 0.34, 0.5), (-2.66, 0, 1.95 + (n - 1) * 0.68), bevel=0.04)
    for z in (1.6, 5.8):
        b.tube(STEEL, [(-2.3, 0, z), (-1.85, 0, z)], 0.1)
    b.cyl(DARK, 0.18, 0.4, (-2.3, 0, 6.1), sides=12, bevel=0.03)
    b.ball(LAMP, 0.13, (-2.3, 0, 6.38), segments=10)

    # Pressure pipes with valve wheels up the right side.
    for y in (-0.7, 0.7):
        b.tube(STEEL, [(1.9, y, 1.0), (2.35, y, 1.4), (2.35, y, 5.4), (1.85, y, 5.75)], 0.12)
        b.cyl(VALVE, 0.08, 0.3, (2.55, y, 3.2), rot=(0, 90, 0), sides=8, bevel=0)
        b.torus(VALVE, 0.24, 0.04, (2.7, y, 3.2), rot=(0, 90, 0), sides=16)
    b.box(DARK, (0.4, 1.8, 0.3), (2.35, 0, 2.2), bevel=0.05)

    # Cable bundle down the back and a service ladder.
    for k, x in enumerate((-0.35, 0, 0.35)):
        b.tube(CABLE, [(x, 1.75, 6.0), (x, 2.2 + k * 0.05, 5.0), (x, 2.3, 1.2), (x, 2.9, 0.35)], 0.07)
    for x in (-0.9, -0.3):
        b.box(STEEL, (0.08, 0.08, 4.2), (x + 1.5, 2.15, 3.8), bevel=0)
    for k in range(8):
        b.box(STEEL, (0.65, 0.06, 0.06), (0.9, 2.15, 2.0 + k * 0.5), bevel=0)

    # Console pedestal at the front (the panel itself is built in game).
    b.box(DARK, (2.8, 1.1, 1.15), (0, -2.55, 0.58), bevel=0.15)
    b.box(HAZARD_Y, (2.9, 1.2, 0.08), (0, -2.55, 0.06), bevel=0.02)
    for x in (-1.1, 1.1):
        b.ball(LAMP, 0.1, (x, -3.12, 0.95), segments=8)

    b.marker("Light_FFC860_14", (0, 0, 4.0))
    return b.finish()
