"""Fuel Depot: "+25% boost time on every ship".

Three striped orange fuel tanks stacked on cradles at the back, a red
fuel pump with a glowing screen and a hose to its nozzle at the front,
two jerry cans, blue spare barrels, green gauges on the tank ends, a
yellow flammable sign, and a big cyan boost arrow on top that pulses.
Budget: 120 parts (tests/WorldSmoke).
"""

from vox import Vox

PALETTE = {
    "Slab": {"color": "#5A6070", "material": "Metal"},
    "Hazard": {"color": "#F2C230"},
    "Tank": {"color": "#FF8A3D"},
    "Stripe": {"color": "#F4F6FA"},
    "Cap": {"color": "#C7CCD4", "material": "Metal"},
    "Cradle": {"color": "#8D9099", "material": "Metal"},
    "Pump": {"color": "#E8413C"},
    "Screen": {"color": "#5FE3FF", "material": "Neon", "name": "Valve"},
    "Hose": {"color": "#22252E", "collide": False},
    "Nozzle": {"color": "#C7CCD4", "material": "Metal", "collide": False},
    "Can": {"color": "#D8322E"},
    "CanCap": {"color": "#FFD36B"},
    "Arrow": {
        "color": "#5FE3FF",
        "material": "Neon",
        "collide": False,
        "name": "BoostArrow",
        "pulse": (0, 0.45),
    },
    "Post": {"color": "#8D9099", "material": "Metal"},
    "Gauge": {"color": "#5CFF8A", "material": "Neon", "collide": False},
    "Warning": {"color": "#F2C230", "collide": False},
    "WarningMark": {"color": "#22252E", "collide": False},
    "Barrel": {"color": "#3F7BFF", "material": "Metal"},
    "FeedPipe": {"color": "#5A6070", "material": "Metal", "collide": False},
}


def tank(v, z0, y0, x0=-4, x1=3):
    """A 3x3 tank along x with rounded (plus-shaped) section, a white stripe
    round its middle and grey end caps."""
    zc, yc = z0 + 1, y0 + 1
    v.box(x0, yc, z0, x1, yc, z0 + 2, "Tank")
    v.box(x0, y0, zc, x1, y0 + 2, zc, "Tank")
    for x in (-1, 0):
        v.box(x, yc, z0, x, yc, z0 + 2, "Stripe")
        v.box(x, y0, zc, x, y0 + 2, zc, "Stripe")
    v.set(x0 - 1, yc, zc, "Cap")
    v.set(x1 + 1, yc, zc, "Cap")


def build():
    v = Vox("FuelDepot", PALETTE)

    # Slab with a hazard stripe along the front edge.
    v.box(-5, 0, -5, 4, 0, 4, "Slab")
    v.box(-5, 0, -5, 4, 0, -5, "Hazard")

    # Cradles and three stacked tanks at the back.
    for x in (-3, 2):
        v.box(x, 1, -1, x, 1, 4, "Cradle")
    tank(v, -1, 2)
    tank(v, 2, 2)
    tank(v, 0, 5)

    # The fuel pump, front left (+x is the building's left seen from the front).
    v.box(2, 1, -4, 3, 4, -3, "Pump")
    v.box(2, 3, -5, 3, 3, -5, "Screen")
    v.box(1, 2, -4, 1, 2, -4, "Hose")
    v.box(0, 1, -4, 0, 2, -4, "Hose")
    v.set(0, 3, -4, "Nozzle")

    # Two jerry cans, front right.
    for x in (-4, -2):
        v.box(x, 1, -4, x, 2, -3, "Can")
        v.set(x, 3, -3, "CanCap")

    # Gauges on the tank ends (green: full).
    for z, y in [(0, 3), (3, 3), (1, 6)]:
        v.set(-6, y, z, "Gauge")

    # A flammable warning sign on a post at the front left.
    v.box(5, 1, -5, 5, 3, -5, "Post")
    v.pattern([".#.", "#!#", "###"], 4, 4, -5, {"#": "Warning", "!": "WarningMark"})

    # Spare barrels at the back right, one with a gold lid.
    for x, z in [(-5, 4), (-5, 2)]:
        v.box(x, 1, z, x, 2, z, "Barrel")
    v.set(-5, 3, 4, "CanCap")

    # A feed pipe from the top tank down to the pump.
    v.box(2, 5, -1, 2, 6, -1, "FeedPipe")
    v.box(2, 5, -2, 2, 5, -2, "FeedPipe")

    # The boost arrow on a post above the tanks, facing the front.
    v.box(-1, 8, 1, 0, 9, 1, "Post")
    arrow = [
        "...##...",
        "..####..",
        ".######.",
        "########",
        "..####..",
        "..####..",
    ]
    v.text(arrow, -4, 10, 1, "Arrow")
    return v
