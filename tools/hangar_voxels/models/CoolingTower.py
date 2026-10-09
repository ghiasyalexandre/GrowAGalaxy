"""Cooling Tower: "+25% laser cooling on every ship".

A stepped voxel cooling tower that pinches at the waist and flares at the
rim, banded in icy cyan with a snowflake on its front. Icicles hang from
the rim, a glowing coolant pool fills the top (steam rises from it) with a
fan turning over it, and a frosty coolant pipe runs to a little laser
turret it keeps chilled. Kept under 16 studs tall: the deck's middle truss
arch passes overhead. Budget: 120 parts (tests/WorldSmoke).
"""

from vox import Vox

PALETTE = {
    "Slab": {"color": "#4A505E", "material": "Metal"},
    "Frost": {"color": "#DDF6FF", "material": "Snow"},
    "Shell": {"color": "#C9CED6", "material": "Concrete"},
    "ShellDark": {"color": "#A9B0BC", "material": "Concrete"},
    "Stripe": {"color": "#5FE3FF", "material": "Neon", "collide": False},
    "Flake": {"color": "#F4FCFF", "material": "Neon", "collide": False},
    "Ice": {"color": "#BFF3FF", "material": "Ice", "transparency": 0.15, "collide": False},
    "Coolant": {"color": "#3FD8FF", "material": "Neon", "name": "Vent"},
    "FanHub": {"color": "#8D9099", "material": "Metal", "collide": False, "group": "Fan"},
    "FanBlade": {"color": "#E8EAED", "collide": False, "group": "Fan"},
    "Pipe": {"color": "#7FD4FF", "material": "Neon", "collide": False, "name": "CoolantPipe"},
    "Turret": {"color": "#5A6070", "material": "Metal"},
    "Barrel": {"color": "#2A2E38", "material": "Metal"},
    "Muzzle": {"color": "#FF6A3D", "material": "Neon", "collide": False},
    "Door": {"color": "#3A4050", "material": "Metal"},
    "DoorLight": {"color": "#5FE3FF", "material": "Neon", "collide": False},
}


def build():
    v = Vox("CoolingTower", PALETTE)

    # Slab with frosted corners.
    v.box(-6, 0, -5, 5, 0, 5, "Slab")
    for x, z in [(-6, -5), (5, -5), (-6, 5), (5, 5)]:
        v.set(x, 0, z, "Frost")

    # The tower, bottom to top: wide base, narrow waist, flared rim.
    v.octagon(-5, -4, 4, 5, 1, 2, "ShellDark", cut=2)
    v.octagon(-4, -3, 3, 4, 3, 4, "Shell")
    v.octagon(-3, -2, 2, 3, 5, 9, "Shell")
    v.octagon(-4, -3, 3, 4, 10, 11, "Shell")
    v.octagon(-5, -4, 4, 5, 12, 13, "ShellDark", cut=2)
    # Cyan bands at the base and the waist.
    v.octagon(-4, -3, 3, 4, 4, 4, "Stripe")
    v.octagon(-3, -2, 2, 3, 9, 9, "Stripe")
    # The glowing coolant pool in the open top.
    v.octagon(-3, -2, 2, 3, 13, 13, "Coolant")

    # Snowflake on the waist's front.
    flake = [
        "#.#.#",
        ".###.",
        "##.##",
        ".###.",
        "#.#.#",
    ]
    v.text(flake, -3, 5, -3, "Flake")

    # Icicles under the rim's overhang.
    for x, z, length in [(-2, -4, 2), (1, -4, 1), (-5, 0, 2), (4, 2, 1), (-2, 5, 1), (4, -1, 2)]:
        v.box(x, 12 - length, z, x, 11, z, "Ice")

    # Fan over the pool, turning.
    v.set(-1, 14, 1, "FanHub")
    v.set(-2, 14, 1, "FanBlade")
    v.set(0, 14, 1, "FanBlade")
    v.set(-1, 14, 0, "FanBlade")
    v.set(-1, 14, 2, "FanBlade")

    # Maintenance door at the base, left side (+x).
    v.box(5, 1, 0, 5, 2, 1, "Door")
    v.box(5, 3, 0, 5, 3, 1, "DoorLight")

    # Coolant pipe from the base, across the slab to the chilled turret.
    v.box(-6, 1, 1, -6, 1, 3, "Pipe")
    v.box(-6, 1, -2, -6, 1, 0, "Pipe")
    v.box(-6, 1, -3, -5, 1, -3, "Pipe")
    # The turret, front right (-x), frosted, barrel up and forward.
    v.box(-6, 1, -5, -4, 2, -4, "Turret")
    v.set(-5, 3, -4, "Turret")
    v.box(-5, 3, -5, -5, 4, -5, "Barrel")
    v.set(-5, 5, -5, "Muzzle")
    v.box(-6, 3, -4, -6, 3, -4, "Frost")
    v.box(-4, 3, -5, -4, 3, -5, "Frost")
    return v
