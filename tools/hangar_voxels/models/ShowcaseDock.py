"""Showcase Dock (vanity): "shows off 3 favourite ships".

Built at its site off the deck's right side: a diamond-plate platform with
a bridge back to the deck (towards -x), gold edge strips, railings down both
long sides, a light tower on every corner and a framed sign facing the deck.
Behind each cradle a dark board shows a big glowing gold 1, 2 or 3.

The cradles themselves ("Cradle1".."Cradle3" and their glow rings) are not
voxels: HangarBuilder builds them as before, because HangarSystem stands
the showcased ships on their exact shape and orientation (z = -21, 0, 21).
Budget: 120 parts with the cradles and sign (tests/WorldSmoke).
"""

from vox import Vox

CRADLES = (-21, 0, 21)

PALETTE = {
    "Platform": {"color": "#4E5463", "material": "DiamondPlate"},
    "Lip": {"color": "#2A2E38", "material": "Metal"},
    "Edge": {"color": "#FFD36B", "material": "Neon", "collide": False, "name": "EdgeStrip"},
    "Rail": {"color": "#8D9099", "material": "Metal"},
    "RailLight": {"color": "#5FE3FF", "material": "Neon", "collide": False},
    "Tower": {"color": "#5A6070", "material": "Metal"},
    "TowerLamp": {"color": "#FFF4D6", "material": "Neon", "collide": False, "name": "TowerLamp"},
    "Number": {"color": "#FFD36B", "material": "Neon", "collide": False},
    "Board": {"color": "#2A2E38", "material": "Metal"},
    "Frame": {"color": "#3A4050", "material": "Metal", "collide": False},
    "FrameStar": {"color": "#FF6EC8", "material": "Neon", "collide": False},
}

DIGITS = {
    1: [".#.", "##.", ".#.", ".#.", "###"],
    2: ["##.", "..#", ".#.", "#..", "###"],
    3: ["##.", "..#", ".#.", "..#", "##."],
}


def build():
    v = Vox("ShowcaseDock", PALETTE)

    # The platform, a dark lip under its edge, and the bridge to the deck.
    v.box(-15, -1, -33, 14, -1, 32, "Platform")
    v.box(-14, -2, -32, 13, -2, 31, "Lip")
    v.box(-27, -1, -4, -16, -1, 3, "Platform")
    # Gold strips down both long edges.
    for x in (-15, 14):
        v.box(x, 0, -32, x, 0, 31, "Edge")

    # Railings down the long sides: posts, a top rail, a light strip under it.
    for x in (-15, 14):
        for z in range(-32, 33, 8):
            if x == -15 and -6 <= z <= 5:
                continue  # the bridge comes in here, and the sign stands here
            v.box(x, 1, z, x, 2, z, "Rail")
    v.box(14, 3, -32, 14, 3, 32, "Rail")
    v.box(14, 2, -31, 14, 2, -25, "RailLight")
    v.box(14, 2, -7, 14, 2, 7, "RailLight")
    v.box(14, 2, 25, 14, 2, 31, "RailLight")

    # Light towers on the corners.
    for x in (-15, 14):
        for z in (-33, 32):
            v.box(x, 0, z, x, 7, z, "Tower")
            v.box(x, 8, z, x, 8, z, "TowerLamp")

    # A big glowing number behind each cradle, facing the deck (seen from
    # the bridge, facing +x: +z is to the right). 2x2-voxel pixels.
    for n, z in enumerate(CRADLES, start=1):
        rows = DIGITS[n]
        for row, line in enumerate(rows):
            for col, ch in enumerate(line):
                if ch == "#":
                    y = 1 + 2 * (len(rows) - 1 - row)
                    zz = z - 3 + 2 * col
                    v.box(12, y, zz, 12, y + 1, zz + 1, "Number")
        v.box(13, 0, z - 4, 13, 11, z + 3, "Board")

    # The sign's frame, facing the deck (the sign itself is a text part).
    for z in (-9, 8):
        v.box(-15, 1, z, -15, 8, z, "Frame")
    v.box(-15, 9, -9, -15, 9, 8, "Frame")
    for z in (-9, 8):
        v.set(-15, 10, z, "FrameStar")
    return v
