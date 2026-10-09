"""Galaxy Control (station deck machine, DeviceBuilder.galaxyControl).

A starship-bridge command table. An octagonal foundation with step plates
and recessed floor lights carries a sculpted pedestal, wrapped by four
glowing conduits, up to the round tabletop. The tabletop has a dark glass
surface ringed by eight slanted bezel panels, each with a lit status
screen, and an accent band. In the middle sits the projector: a stepped
lens stack inside three rings, with six small emitters round it.

Four articulated emitter arms rise from the rim and aim their heads at the
hologram. Two side monitors on stands lean in from the left and right, and
two rows of console buttons (Button1..8, blinked by the game) line the
front edge. The console pedestal at the front carries the code-built panel.

Contract with the game: the hologram (drawn by each client) is centred
DeviceBuilder.HOLO_HEIGHT = 5.15 studs above the floor. Front is -Y; game
+x is Blender -X.
"""

import math

from kit import Building, look

DARK = look("Base", "#2E3442", "Metal")
PLATE = look("Plate", "#3A4152", "DiamondPlate")
STEEL = look("Steel", "#8C95A6", "Metal")
HULL = look("Hull", "#E8EAED")
TOP = look("Tabletop", "#141821", "Glass")
BEZEL = look("Bezel", "#262B36", "Metal")
TRIM = look("Accent_Trim", "#8A5CD8", "Metal")
LENS = look("Lens", "#6A3FC8", "Neon")
EMIT = look("Accent_Emitter", "#8A5CD8", "Neon")
SCREEN = look("Screen", "#2A6A9A", "Neon")
CONDUIT = look("Conduit", "#5A3FA8", "Neon")
FLOOR_LIGHT = look("FloorLight", "#6A88C8", "Neon")
CABLE = look("Cable", "#23262E")

BUTTON_COLORS = ["#3FA8C8", "#C8A040", "#C85A9A", "#5CC87A"]


def build():
    b = Building("GalaxyControl")

    # Octagonal foundation: plate, step and recessed floor lights.
    b.cyl(PLATE, 3.4, 0.25, (0, 0, 0.125), sides=8, bevel=0.06)
    b.cyl(DARK, 2.8, 0.35, (0, 0, 0.42), sides=8, bevel=0.08)
    for i in range(8):
        a = math.radians(22.5 + i * 45)
        b.box(FLOOR_LIGHT, (0.5, 0.12, 0.04), (math.cos(a) * 3.05, math.sin(a) * 3.05, 0.27), rot=(0, 0, i * 45 + 112.5), bevel=0.01)
    for i in range(8):
        a = math.radians(i * 45)
        b.cyl(STEEL, 0.1, 0.08, (math.cos(a) * 2.5, math.sin(a) * 2.5, 0.62), sides=6, bevel=0)

    # Sculpted pedestal with four glowing conduits.
    b.lathe(
        HULL,
        [(1.3, 0.6), (1.15, 0.9), (0.85, 1.3), (0.8, 2.0), (1.0, 2.4), (1.6, 2.75)],
        sides=32,
    )
    for i in range(4):
        a = math.radians(45 + i * 90)
        c, s = math.cos(a), math.sin(a)
        b.tube(CONDUIT, [(c * 1.25, s * 1.25, 0.6), (c * 0.95, s * 0.95, 1.3), (c * 0.92, s * 0.92, 2.0), (c * 1.25, s * 1.25, 2.6)], 0.07)
        b.box(STEEL, (0.25, 0.25, 0.3), (c * 1.28, s * 1.28, 0.75), rot=(0, 0, math.degrees(a)), bevel=0.04)

    # The table: glass top, eight slanted bezel panels with status screens.
    b.cyl(DARK, 2.95, 0.3, (0, 0, 2.85), sides=48, bevel=0.08)
    b.cyl(TOP, 2.45, 0.08, (0, 0, 3.04), sides=48, bevel=0)
    b.torus(TRIM, 2.98, 0.1, (0, 0, 2.85), sides=48)
    for i in range(8):
        deg = 22.5 + i * 45
        a = math.radians(deg)
        c, s = math.cos(a), math.sin(a)
        # Lying round the rim, outer edge raised.
        b.box(BEZEL, (1.75, 0.55, 0.16), (c * 2.7, s * 2.7, 3.12), rot=(18, 0, deg - 90), bevel=0.04)
        if i % 2 == 1:
            b.box(SCREEN, (1.25, 0.35, 0.04), (c * 2.7, s * 2.7, 3.21), rot=(18, 0, deg - 90), bevel=0.01)

    # Projector: a stepped lens stack inside three rings, six emitters round it.
    b.cyl(DARK, 1.0, 0.18, (0, 0, 3.12), sides=32, bevel=0.03)
    b.torus(STEEL, 0.95, 0.05, (0, 0, 3.24), sides=32)
    b.torus(STEEL, 0.7, 0.05, (0, 0, 3.32), sides=32)
    b.torus(TRIM, 0.5, 0.05, (0, 0, 3.4), sides=32)
    b.cyl(LENS, 0.42, 0.14, (0, 0, 3.36), sides=32, top=0.28, bevel=0)
    for i in range(6):
        a = math.radians(i * 60)
        b.cyl(STEEL, 0.07, 0.22, (math.cos(a) * 1.2, math.sin(a) * 1.2, 3.25), sides=8, bevel=0)
        b.ball(EMIT, 0.07, (math.cos(a) * 1.2, math.sin(a) * 1.2, 3.4), segments=8)

    # Four articulated emitter arms aiming at the hologram (5.15 up).
    for i in range(4):
        a = math.radians(45 + i * 90)
        c, s = math.cos(a), math.sin(a)
        base, elbow, head = (c * 2.55, s * 2.55, 3.0), (c * 2.75, s * 2.75, 4.2), (c * 2.25, s * 2.25, 5.0)
        b.tube(STEEL, [base, elbow], 0.08)
        b.tube(STEEL, [elbow, head], 0.07)
        b.ball(DARK, 0.15, elbow, segments=10)
        tilt = math.degrees(math.atan2(0.15, 2.25))
        b.cyl(DARK, 0.2, 0.45, head, rot=(0, -90 + tilt, math.degrees(a)), sides=12, top=0.12, bevel=0.03)
        b.ball(EMIT, 0.11, (c * 2.05, s * 2.05, 5.05), segments=10)

    # Side monitors on stands, leaning in from both sides.
    for side in (-1, 1):
        x = side * 3.6
        b.box(DARK, (0.6, 0.6, 0.12), (x, 0.4, 0.06), bevel=0.03)
        b.cyl(STEEL, 0.08, 2.6, (x, 0.4, 1.35), sides=10, bevel=0)
        b.box(BEZEL, (0.15, 1.5, 1.0), (x, 0.4, 2.9), rot=(0, side * 20, 0), bevel=0.05)
        b.box(SCREEN, (0.04, 1.3, 0.8), (x - side * 0.09, 0.4, 2.9), rot=(0, side * 20, 0), bevel=0.01)
        b.tube(CABLE, [(x, 0.7, 0.1), (side * 3.0, 0.9, 0.08), (side * 1.4, 0.9, 0.5)], 0.05)

    # Console buttons along the front edge, in two rows.
    for n in range(1, 9):
        row, col = (n - 1) // 4, (n - 1) % 4
        color = BUTTON_COLORS[(n - 1) % len(BUTTON_COLORS)]
        x = -1.05 + col * 0.7
        b.box(look(f"Button{n}", color, "Neon"), (0.4, 0.28, 0.08), (x, -2.2 + row * 0.4, 3.15), bevel=0.03)

    # Console pedestal at the front (the panel itself is built in game).
    b.box(DARK, (2.6, 1.0, 1.6), (0, -3.0, 0.8), bevel=0.15)
    b.box(STEEL, (2.7, 1.1, 0.12), (0, -3.0, 1.62), bevel=0.03)

    b.marker("Light_8A5CD8_12", (0, 0, 4.5))
    return b.finish()
