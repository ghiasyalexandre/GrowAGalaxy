"""Showcase Dock (vanity): "shows off 3 favourite ships".

Built at its site off the deck's right side: a long platform with a bridge
back to the deck (game -x, which is Blender +X), dim gold edge strips,
railings, light pylons on the corners, a frame for the SHOWCASE sign
facing the deck, and behind each cradle a dark board with a big 1, 2 or 3.

The cradles ("Cradle1".."Cradle3", at game z -21, 0, 21) and the sign's
text are not part of this mesh: HangarBuilder builds them, because
HangarSystem stands the showcased ships on the cradles' exact shape.
"""

from kit import Building, look

CRADLES = (-21, 0, 21)
DECK = look("Platform", "#3A4050", "DiamondPlate")
LIP = look("Lip", "#22262F", "Metal")
EDGE = look("Accent_Edge", "#C8A040", "Neon")
RAIL = look("Rail", "#8C95A6", "Metal")
PYLON = look("Pylon", "#2E3442", "Metal")
LAMP = look("Accent_Lamp", "#E8E0C8", "Neon")
BOARD = look("Board", "#22262F", "Metal")
NUMBER = look("Number", "#D9A441", "Neon")
FRAME = look("Frame", "#3A4050", "Metal")


def build():
    b = Building("ShowcaseDock")
    b.box(DECK, (30, 66, 1.4), (0, 0, -0.7), bevel=0.4)
    b.box(LIP, (28, 64, 0.6), (0, 0, -1.6), bevel=0.2)
    b.box(DECK, (12, 8, 1.0), (21, 0, -0.5), bevel=0.3)
    for x in (-14.6, 14.6):
        b.box(EDGE, (0.3, 64, 0.1), (x, 0, 0.02), bevel=0.02)

    # Railing along the far side (game +x, Blender -X), and the near side
    # either side of the bridge and sign.
    b.tube(RAIL, [(-14.2, -32, 2.6), (-14.2, 32, 2.6)], 0.12)
    for y in range(-32, 33, 8):
        b.cyl(RAIL, 0.1, 2.6, (-14.2, y, 1.3), sides=8, bevel=0)
    for y0, y1 in ((-32, -10), (10, 32)):
        b.tube(RAIL, [(14.2, y0, 2.6), (14.2, y1, 2.6)], 0.12)
        for y in range(y0, y1 + 1, 11):
            b.cyl(RAIL, 0.1, 2.6, (14.2, y, 1.3), sides=8, bevel=0)

    # Light pylons on the corners.
    for x in (-14.2, 14.2):
        for y in (-32.5, 32.5):
            b.cyl(PYLON, 0.4, 7.0, (x, y, 3.5), sides=12)
            b.ball(LAMP, 0.6, (x, y, 7.4), segments=12)

    b.marker("Light_E8E0C8_30", (0, 0, 6))
    return b.finish()
