"""Stardust Silo: "Stars hold 50% more uncollected Stardust".

A chunky white silo on a plinth with hazard corners. A gauge down its front
shows glowing Stardust inside (glass above the fill line), two gold bands
hoop it, a chute on its left drops Stardust into a blue hopper, a hatch
door sits at the front, a ladder climbs its left side, a blue control
booth with a lit window stands at the front left, and a gold star turns on the stepped roof.
Budget: 120 parts (tests/WorldSmoke).
"""

from vox import Vox

PALETTE = {
    "Plinth": {"color": "#5A6070", "material": "Metal"},
    "Hazard": {"color": "#F2C230"},
    "Hull": {"color": "#E8EAED"},
    "Roof": {"color": "#C7CCD4"},
    "Band": {"color": "#FFD36B", "material": "Neon", "collide": False},
    "Stardust": {"color": "#FFC94A", "material": "Neon", "name": "Core"},
    "Sparkle": {"color": "#FF6EC8", "material": "Neon", "collide": False},
    "Glass": {"color": "#A9DCFF", "material": "Glass", "transparency": 0.35},
    "Pipe": {"color": "#8D9099", "material": "Metal"},
    "Hopper": {"color": "#5B8CFF"},
    "Door": {"color": "#3A4050", "material": "Metal"},
    "DoorLight": {"color": "#5FE3FF", "material": "Neon", "collide": False},
    "Ladder": {"color": "#8D9099", "material": "Metal", "collide": False},
    "Booth": {"color": "#5B8CFF"},
    "BoothWindow": {"color": "#7FD4FF", "material": "Neon", "collide": False},
    "Star": {"color": "#FFD36B", "material": "Neon", "collide": False, "group": "TopStar"},
}


def octagon(v, half, y0, y1, key):
    """A chamfered square (two crossed boxes), `half` voxels out from centre."""
    v.box(-half, y0, -half + 1, half - 1, y1, half - 2, key)
    v.box(-half + 1, y0, -half, half - 2, y1, half - 1, key)


def build():
    v = Vox("StardustSilo", PALETTE)

    # Plinth with hazard corner blocks.
    v.box(-5, 0, -5, 4, 0, 4, "Plinth")
    for x, z in [(-5, -5), (4, -5), (-5, 4), (4, 4)]:
        v.set(x, 1, z, "Hazard")

    # The silo body and a stepped roof.
    octagon(v, 4, 1, 10, "Hull")
    octagon(v, 4, 11, 11, "Roof")
    v.box(-2, 12, -2, 1, 12, 1, "Roof")
    v.box(-1, 13, -1, 0, 13, 0, "Roof")

    # Two gold bands hooping it (one voxel proud of the hull).
    for y in (3, 8):
        v.box(-3, y, -5, 2, y, -5, "Band")
        v.box(-3, y, 4, 2, y, 4, "Band")
        v.box(-5, y, -3, -5, y, 2, "Band")
        v.box(4, y, -3, 4, y, 2, "Band")

    # The gauge on the front: Stardust up to the fill line, glass above.
    v.box(-1, 2, -5, 0, 7, -5, "Stardust")
    v.box(-1, 9, -5, 0, 10, -5, "Glass")
    v.set(-1, 7, -5, "Glass")
    v.set(0, 7, -5, "Glass")
    v.set(0, 5, -5, "Sparkle")
    for y in (3, 8):
        v.box(-1, y, -5, 0, y, -5, "Band")

    # Hatch door, front right.
    v.box(2, 1, -5, 2, 2, -5, "Door")
    v.set(2, 3, -5, "DoorLight")

    # Chute off the left side, down into a hopper of nuggets.
    v.box(-6, 9, -1, -5, 9, -1, "Pipe")
    v.box(-6, 5, -1, -6, 8, -1, "Pipe")
    v.box(-8, 1, -4, -6, 1, -2, "Hopper")
    v.box(-8, 2, -4, -8, 2, -2, "Hopper")
    v.box(-6, 2, -4, -6, 2, -2, "Hopper")
    v.box(-7, 2, -3, -7, 3, -3, "Stardust")
    v.set(-7, 2, -4, "Sparkle")
    v.set(-6, 3, -1, "Stardust")  # a nugget dropping from the chute

    # Ladder up the left side (+x), to the roof.
    for z in (-2, 1):
        v.box(5, 1, z, 5, 12, z, "Ladder")
    for y in (2, 5, 7, 10, 12):
        v.box(5, y, -1, 5, y, 0, "Ladder")

    # A little control booth at the front left, with a lit window.
    # (Kept behind z = -6: the name plate stands just in front of that.)
    v.box(3, 1, -6, 5, 3, -5, "Booth")
    v.box(6, 2, -6, 6, 2, -5, "BoothWindow")
    v.box(3, 4, -6, 5, 4, -5, "Roof")
    v.set(4, 5, -6, "Sparkle")

    # Mast and a chunky star that turns.
    v.box(-1, 14, -1, 0, 15, 0, "Pipe")
    star = [
        "...##...",
        "########",
        ".######.",
        "..####..",
        ".##..##.",
    ]
    v.text(star, -4, 16, -1, "Star")
    v.text(star, -4, 16, 0, "Star")
    return v
