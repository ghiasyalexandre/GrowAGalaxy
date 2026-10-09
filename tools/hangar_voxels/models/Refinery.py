"""Stardust Refinery: "+15% Stardust from your stars".

Raw purple star-rock rides a conveyor into a factory hall; a molten gold
furnace window glows on its front; a striped chimney smokes; a fan turns on
the roof; gold pipes carry the melt round to an output chute that piles up
glowing Stardust cubes. A gold star emblem sits over the window.
Kept under 16 studs tall: the deck's middle truss arch passes overhead.
Budget: 120 parts (tests/WorldSmoke).
"""

from vox import Vox

PALETTE = {
    "Slab": {"color": "#4A505E", "material": "Metal"},
    "Hazard": {"color": "#F2C230"},
    "Wall": {"color": "#D9DEE6"},
    "Trim": {"color": "#5B6CFF"},
    "Roof": {"color": "#3A4050", "material": "Metal"},
    "RoofTrim": {"color": "#FFD36B"},
    "Melt": {"color": "#FF9A2E", "material": "Neon", "name": "Furnace"},
    "Frame": {"color": "#2A2E38", "material": "Metal"},
    "Chimney": {"color": "#E8EAED"},
    "ChimneyBand": {"color": "#E8413C"},
    "ChimneyGlow": {"color": "#FFB347", "material": "Neon", "collide": False},
    "Belt": {"color": "#22252E", "material": "Metal"},
    "Roller": {"color": "#8D9099", "material": "Metal"},
    "Rock": {"color": "#8A5CFF", "collide": False},
    "RockGlint": {"color": "#C49BFF", "material": "Neon", "collide": False},
    "Pipe": {"color": "#FFD36B", "material": "Neon", "collide": False},
    "Chute": {"color": "#8D9099", "material": "Metal"},
    "Stardust": {"color": "#FFC94A", "material": "Neon", "name": "Output"},
    "Emblem": {"color": "#FFD36B", "material": "Neon", "collide": False},
    "Door": {"color": "#3A4050", "material": "Metal"},
    "Window": {"color": "#7FD4FF", "material": "Neon", "collide": False},
    "Crate": {"color": "#9C6B3F", "material": "Wood"},
    "CrateBand": {"color": "#FFD36B"},
    "DoorLight": {"color": "#5FE3FF", "material": "Neon", "collide": False},
    "FanHub": {"color": "#8D9099", "material": "Metal", "group": "Fan"},
    "FanBlade": {"color": "#E8EAED", "collide": False, "group": "Fan"},
    "Vent": {"color": "#8D9099", "material": "Metal"},
}


def build():
    v = Vox("Refinery", PALETTE)

    # Foundation with a hazard stripe along the front.
    v.box(-7, 0, -5, 6, 0, 5, "Slab")
    v.box(-7, 0, -5, 6, 0, -5, "Hazard")

    # The hall: walls with a blue base trim, a dark roof with gold edging.
    v.box(-3, 1, -2, 4, 7, 4, "Wall")
    v.box(-3, 1, -2, 4, 1, 4, "Trim")
    v.box(-4, 8, -3, 5, 8, 5, "Roof")
    v.box(-4, 8, -3, 5, 8, -3, "RoofTrim")
    v.box(-3, 9, -2, 4, 9, 4, "Roof")

    # Furnace window on the front, framed, with the melt glowing behind it.
    v.box(-1, 2, -2, 3, 5, -2, "Frame")
    v.box(0, 3, -2, 2, 4, -2, "Melt")
    v.box(-1, 2, -3, 3, 2, -3, "Frame")  # sill
    # A gold star emblem standing on the roof's front edge.
    v.text([".#.", "###", ".#."], 0, 9, -3, "Emblem")
    # Glowing windows down the hall's right side (-x).
    for z in (0, 3):
        v.box(-3, 4, z, -3, 5, z, "Window")

    # Door on the hall's left side (+x).
    v.box(4, 1, -1, 4, 3, 0, "Door")
    v.set(4, 4, -1, "DoorLight")
    v.set(4, 4, 0, "DoorLight")

    # Conveyor in from the right (-x), with rocks riding it into the hall.
    v.box(-7, 2, -1, -4, 2, 0, "Belt")
    for x in (-7, -5):
        v.box(x, 1, -1, x, 1, 0, "Roller")
    v.set(-7, 3, 0, "Rock")
    v.set(-6, 3, -1, "Rock")
    v.set(-6, 4, -1, "RockGlint")
    v.set(-4, 3, 0, "Rock")
    v.box(-3, 2, -1, -3, 3, 0, "Frame")  # the intake hatch
    # A stack of raw-rock crates waiting at the front.
    v.box(-7, 1, -4, -5, 2, -3, "Crate")
    v.box(-7, 2, -4, -5, 2, -4, "CrateBand")
    v.box(-6, 3, -4, -6, 3, -3, "Crate")
    v.set(-6, 4, -3, "RockGlint")

    # Chimney with red bands and a glowing top (smoke comes from it).
    v.octagon(1, 2, 3, 4, 10, 14, "Chimney")
    v.box(1, 11, 3, 3, 11, 3, "ChimneyBand")
    v.box(2, 11, 2, 2, 11, 4, "ChimneyBand")
    v.box(1, 13, 3, 3, 13, 3, "ChimneyBand")
    v.box(2, 13, 2, 2, 13, 4, "ChimneyBand")
    v.box(2, 15, 3, 2, 15, 3, "ChimneyGlow")
    v.box(1, 15, 3, 1, 15, 3, "Chimney")
    v.box(3, 15, 3, 3, 15, 3, "Chimney")

    # Roof fan that turns, beside a vent.
    v.box(-2, 10, 0, -2, 10, 0, "FanHub")
    v.box(-4, 10, 0, -3, 10, 0, "FanBlade")
    v.box(-1, 10, 0, 0, 10, 0, "FanBlade")
    v.box(-2, 10, -2, -2, 10, -1, "FanBlade")
    v.box(-2, 10, 1, -2, 10, 2, "FanBlade")
    v.box(-2, 10, 3, -1, 11, 4, "Vent")

    # Gold pipes from the roof down the left side to the output chute.
    v.box(5, 7, 2, 5, 7, 4, "Pipe")
    v.box(6, 3, 2, 6, 7, 2, "Pipe")
    v.box(5, 3, -2, 6, 3, 1, "Chute")
    v.set(6, 2, -2, "Chute")

    # The output: a pile of glowing Stardust cubes.
    v.box(5, 1, -4, 6, 1, -3, "Stardust")
    v.set(5, 2, -4, "Stardust")
    v.set(6, 2, -3, "Stardust")
    v.set(5, 1, -2, "Stardust")
    return v
