"""Armor Workshop: "+30% hull on every ship".

An open garage under a roof crowned by a big silver-and-cyan shield sign.
Inside, a chunky blue ship hull sits on a striped lift, half covered in
silver armour plates, while a yellow robot arm welds on the next one
(sparks fly from its torch). A rack of spare plates stands at the back and
a red toolbox at the front. Everything stays within 4 studs of the pad's
back line: a truss arch passes just behind it. Budget: 120 parts.
"""

from vox import Vox

PALETTE = {
    "Slab": {"color": "#4A505E", "material": "DiamondPlate"},
    "Hazard": {"color": "#F2C230"},
    "Post": {"color": "#8D9099", "material": "Metal"},
    "Roof": {"color": "#3A4050", "material": "Metal"},
    "RoofTrim": {"color": "#FFB347", "material": "Neon", "collide": False, "name": "RoofStrip"},
    "BackWall": {"color": "#C7CCD4"},
    "ShieldRim": {"color": "#D9DEE6", "material": "Metal", "collide": False},
    "ShieldFace": {"color": "#3FB6FF", "material": "Neon", "collide": False, "name": "Shield"},
    "Lift": {"color": "#2A2E38", "material": "Metal"},
    "LiftStripe": {"color": "#F2C230"},
    "ShipHull": {"color": "#3F7BFF"},
    "Cockpit": {"color": "#A9DCFF", "material": "Glass", "transparency": 0.3},
    "Armor": {"color": "#C9CED6", "material": "Metal"},
    "Rivet": {"color": "#FFD36B", "material": "Neon", "collide": False},
    "Robot": {"color": "#F2C230"},
    "RobotJoint": {"color": "#2A2E38", "material": "Metal"},
    "Torch": {"color": "#FFF4D6", "material": "Neon", "collide": False},
    "Toolbox": {"color": "#E8413C"},
    "Handle": {"color": "#2A2E38", "material": "Metal"},
}


def build():
    v = Vox("ArmorWorkshop", PALETTE)

    # Floor with a hazard stripe across the open front.
    v.box(-6, 0, -5, 5, 0, 4, "Slab")
    v.box(-6, 0, -5, 5, 0, -5, "Hazard")

    # Four posts, a back wall and a roof with a glowing front strip.
    for x in (-6, 5):
        for z in (-4, 4):
            v.box(x, 1, z, x, 8, z, "Post")
    v.box(-5, 1, 4, 4, 5, 4, "BackWall")
    v.box(-6, 9, -4, 5, 9, 4, "Roof")
    v.box(-5, 8, -4, 4, 8, -4, "RoofTrim")

    # The shield sign standing on the roof's front edge.
    shield = [
        "#######",
        "#ccccc#",
        "#cc#cc#",
        "#c###c#",
        ".#c#c#.",
        "..#c#..",
        "...#...",
    ]
    v.pattern(shield, -4, 10, -4, {"#": "ShieldRim", "c": "ShieldFace"})

    # The lift, striped, with the ship hull on it (nose to the front).
    v.box(-4, 1, -3, 1, 1, 3, "Lift")
    v.box(-4, 1, -3, 1, 1, -3, "LiftStripe")
    v.box(-3, 2, -1, 0, 4, 3, "ShipHull")
    v.box(-2, 2, -3, -1, 3, -2, "ShipHull")  # the nose
    v.box(-2, 5, 0, -1, 5, 1, "Cockpit")
    # Armour already on: the right side and the nose tip.
    v.box(-4, 2, -1, -4, 4, 3, "Armor")
    v.box(-2, 2, -4, -1, 3, -4, "Armor")
    for z in (0, 2):
        v.set(-5, 3, z, "Rivet")
    # A plate being fitted on the left side.
    v.box(1, 2, 0, 1, 3, 2, "Armor")

    # Robot arm on the left: base, upright, elbow, forearm, torch.
    v.box(3, 1, 0, 4, 2, 1, "Robot")
    v.box(3, 3, 0, 3, 6, 0, "Robot")
    v.set(3, 7, 0, "RobotJoint")
    v.box(2, 7, 0, 2, 7, 0, "Robot")
    v.box(1, 6, 0, 1, 6, 0, "RobotJoint")
    v.set(1, 5, 1, "Torch")

    # Spare plates on a rack against the back wall.
    v.box(-5, 1, 3, -5, 4, 3, "Post")
    for x in (-4, -3):
        v.box(x, 1, 3, x, 4, 3, "Armor")

    # Red toolbox at the front right.
    v.box(-5, 1, -4, -4, 1, -3, "Toolbox")
    v.set(-5, 2, -4, "Handle")
    v.set(-4, 2, -4, "Handle")
    return v
