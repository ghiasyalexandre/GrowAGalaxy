"""Neon Runway (vanity): "chevron lights guide you in to your dock".

Built at its site off the deck's front, floating in space: eight rows of
stepped cyan voxel chevrons, 12 studs apart, pointing in towards the berth
(+z). Each row is fainter the further out it is and breathes (pulse). Two
dark guide rails run alongside with a gold landing lamp at every row.
Budget: 120 parts (tests/WorldSmoke).
"""

from vox import Vox

ROWS = 8
SPACING = 12

PALETTE = {
    "Rail": {"color": "#2A2E38", "material": "Metal", "collide": False},
    "Lamp": {"color": "#FFD36B", "material": "Neon", "collide": False, "name": "EdgeLight"},
    "Gate": {"color": "#8D9099", "material": "Metal", "collide": False},
    "GateLight": {"color": "#FF6EC8", "material": "Neon", "collide": False, "name": "GateLight"},
}
for i in range(ROWS):
    fade = i / ROWS
    PALETTE[f"Chevron{i}"] = {
        "color": "#5FE3FF",
        "material": "Neon",
        "collide": False,
        "name": "Chevron",
        "transparency": round(0.1 + fade * 0.5, 3),
        "pulse": (round(0.05 + fade * 0.4, 3), round(0.6 + fade * 0.3, 3)),
    }


def build():
    v = Vox("NeonRunway", PALETTE)
    for i in range(ROWS):
        z0 = -i * SPACING
        key = f"Chevron{i}"
        # The tip, then three 2-wide steps back on each side.
        v.box(-1, 0, z0 + 3, 0, 0, z0 + 4, key)
        for step in range(1, 4):
            z = z0 + 3 - step
            v.box(-1 - 2 * step, 0, z, -2 * step, 0, z, key)
            v.box(2 * step - 1, 0, z, 2 * step, 0, z, key)
        # Landing lamps on the rails.
        for x in (-14, 13):
            v.set(x, 0, z0, "Lamp")
    for x in (-14, 13):
        v.box(x, -1, -(ROWS - 1) * SPACING - 3, x, -1, 4, "Rail")
    # A gate framing the start of the approach, at the far end.
    far = -(ROWS - 1) * SPACING - 4
    for x in (-12, 11):
        v.box(x, -1, far, x, 9, far, "Gate")
    v.box(-12, 10, far, 11, 10, far, "Gate")
    v.box(-11, 9, far, 10, 9, far, "GateLight")
    return v
