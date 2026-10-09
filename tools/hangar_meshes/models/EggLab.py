"""Planet Egg Lab (station deck machine, DeviceBuilder.eggLab).

A gleaming bio-lab. A round foundation with a hazard ring, a pink glow
ring and bolts carries a rounded white console with pink side panels,
louvred vents and cooling fins at the back. "PLANET EGG LAB" is lettered
across the front above the sloped control deck, under a row of six rarity
lamps (Common to Interstellar).

Two glass tanks of glowing egg fluid stand at the sides, wrapped in
heating coils, feeding pipes up into the dome. On top, a glowing pedestal
holds the egg under a big glass dome, gripped by three curved arms that
meet in a crown, where a ring of lamps turns (Spin_Crown).

Built by the game, not here (they work, so they stay parts): the ROLL and
KEEP keys with their collars on the control deck, the invisible
"EggConsole" box for the prompt, and the "EggSpot" where each client draws
the rolled egg (game floor space (0, 6.4, 0.3), Blender (0, 0.3, 6.4)).
Front is -Y; game +x is Blender -X.
"""

import math

from kit import Building, look

DARK = look("Base", "#2E3442", "Metal")
PLATE = look("Plate", "#3A4152", "DiamondPlate")
STEEL = look("Steel", "#8C95A6", "Metal")
HULL = look("Hull", "#F4ECF2")
PINK = look("Pink", "#E85AB4", "SmoothPlastic")
PINK_GLOW = look("PinkGlow", "#E060B0", "Neon")
PURPLE_GLOW = look("PurpleGlow", "#9A5CE0", "Neon")
DECK = look("Deck", "#262B36", "Metal")
GLASS = look("Glass", "#E8D8F8", "Glass")
LETTERS = look("Letters", "#E85AB4", "Neon")
VENT = look("Vent", "#14171E", "Metal")
HAZARD_Y = look("HazardYellow", "#E8B020")
HAZARD_K = look("HazardBlack", "#1C1C1C")
COIL = look("Coil", "#D9A441", "Metal")
CABLE = look("Cable", "#23262E")
TRIM = look("Accent_Trim", "#E85AB4", "Metal")

RARITY = ["#B8C2CC", "#5CFF8A", "#3FA9F5", "#B06BFF", "#FFB020", "#FF4FD8"]


def build():
    b = Building("EggLab")

    # Foundation: plate, hazard ring, pink glow ring, bolts.
    b.cyl(PLATE, 3.45, 0.3, (0, 0, 0.15), sides=40, bevel=0.06)
    for i in range(20):
        a = math.radians(i * 18)
        b.box(
            HAZARD_Y if i % 2 == 0 else HAZARD_K,
            (0.65, 0.3, 0.05),
            (math.cos(a) * 3.15, math.sin(a) * 3.15, 0.31),
            rot=(0, 0, i * 18 + 90),
            bevel=0.01,
        )
    b.torus(PINK_GLOW, 2.75, 0.06, (0, 0, 0.32), sides=48)
    for i in range(8):
        a = math.radians(22.5 + i * 45)
        b.cyl(STEEL, 0.12, 0.1, (math.cos(a) * 2.45, math.sin(a) * 2.45, 0.35), sides=6, bevel=0)

    # The console: rounded white body, pink side panels, vents, back fins.
    b.box(HULL, (4.4, 3.2, 3.6), (0, 0.3, 2.4), bevel=0.35)
    b.box(TRIM, (4.5, 3.3, 0.12), (0, 0.3, 4.15), bevel=0.04)
    for side in (-1, 1):
        x = side * 2.22
        b.box(PINK, (0.1, 2.4, 2.6), (x, 0.3, 2.3), bevel=0.06)
        for k in range(5):
            b.box(VENT, (0.06, 1.6, 0.12), (x + side * 0.05, 0.3, 1.5 + k * 0.32), bevel=0.01)
    for k in range(7):
        b.box(STEEL, (0.1, 0.5, 2.6), (-1.5 + k * 0.5, 2.0, 2.3), bevel=0.02)

    # Sloped control deck (the ROLL and KEEP keys are built in game) with
    # a hazard edge strip, and the lettering above it.
    b.box(DECK, (4.4, 1.8, 0.4), (0, -1.85, 2.6), rot=(35, 0, 0), bevel=0.08)
    b.box(HAZARD_Y, (4.4, 0.14, 0.1), (0, -2.62, 2.1), rot=(35, 0, 0), bevel=0.02)
    b.text(LETTERS, "PLANET EGG LAB", (0, -1.33, 3.62), size=0.42, depth=0.06)

    # Rarity lamps along the top front edge, Common to Interstellar.
    for index, color in enumerate(RARITY):
        x = -(-1.6 + index * 0.64)  # game x -> Blender -X
        b.cyl(DARK, 0.2, 0.1, (x, -1.25, 4.25), sides=12, bevel=0.02)
        b.ball(look(f"Rarity{index + 1}", color, "Neon"), 0.17, (x, -1.25, 4.32), segments=12)

    # Fluid tanks at the sides with heating coils and feed pipes to the dome.
    for side, fluid in ((1, PINK_GLOW), (-1, PURPLE_GLOW)):
        x = side * 3.0
        b.cyl(STEEL, 0.75, 0.35, (x, 0.8, 0.78), sides=24, bevel=0.06)
        b.cyl(GLASS, 0.6, 4.0, (x, 0.8, 2.95), sides=24, bevel=0)
        b.cyl(fluid, 0.36, 3.6, (x, 0.8, 2.9), sides=16, bevel=0)
        b.cyl(STEEL, 0.75, 0.4, (x, 0.8, 5.1), sides=24, bevel=0.06)
        coil = []
        for k in range(61):
            t = k / 60
            a = t * 2 * math.pi * 6
            coil.append((x + math.cos(a) * 0.66, 0.8 + math.sin(a) * 0.66, 1.15 + t * 3.6))
        b.tube(COIL, coil, 0.04, sides=6)
        b.tube(STEEL, [(x, 0.8, 5.3), (x * 0.85, 0.6, 5.9), (x * 0.55, 0.4, 5.6), (x * 0.4, 0.35, 4.75)], 0.11)

    # Pedestal, dome collar and the glass dome.
    b.cyl(DARK, 0.95, 0.5, (0, 0.3, 4.45), sides=32, bevel=0.06)
    b.cyl(STEEL, 0.75, 0.55, (0, 0.3, 4.95), sides=32, top=0.55, bevel=0.04)
    b.torus(PINK_GLOW, 0.62, 0.05, (0, 0.3, 5.25), sides=32)
    b.torus(STEEL, 2.15, 0.16, (0, 0.3, 4.4), sides=48)
    b.torus(TRIM, 2.3, 0.06, (0, 0.3, 4.45), sides=48)
    b.ball(GLASS, 2.15, (0, 0.3, 6.35), scale=(1, 1, 1.05), segments=40)

    # Three curved arms over the dome, meeting in the crown.
    for i in range(3):
        a = math.radians(90 + i * 120)
        c, s = math.cos(a), math.sin(a)
        pts = []
        for k in range(13):
            t = k / 12
            ang = t * math.pi / 2
            r = 2.35 * math.cos(ang) + 0.25 * math.sin(ang)
            pts.append((c * r, 0.3 + s * r, 4.45 + 4.1 * math.sin(ang)))
        b.tube(STEEL, pts, 0.09, sides=8)
        b.ball(DARK, 0.17, (c * 2.35, 0.3 + s * 2.35, 4.45), segments=10)
    b.cyl(DARK, 0.5, 0.45, (0, 0.3, 8.6), sides=24, bevel=0.06)
    b.cyl(STEEL, 0.2, 0.6, (0, 0.3, 9.1), sides=12, top=0.08, bevel=0)
    # The turning crown: a ring with three lamps.
    b.torus(look("Spin_Crown_Ring", "#E060B0", "Neon"), 0.75, 0.05, (0, 0.3, 8.95), sides=32)
    for i in range(3):
        a = math.radians(i * 120)
        b.ball(look("Spin_Crown_Lamp", "#FFD0EE", "Neon"), 0.1, (math.cos(a) * 0.75, 0.3 + math.sin(a) * 0.75, 8.95), segments=8)

    # Cable hoses down the back.
    for k, x in enumerate((-1.2, 0, 1.2)):
        b.tube(CABLE, [(x, 1.95, 3.8), (x, 2.4, 3.0), (x * 1.1, 2.6, 0.9), (x * 1.2, 3.1, 0.3)], 0.07)

    b.marker("Light_E060B0_14", (0, 0.3, 6.4))
    return b.finish()
