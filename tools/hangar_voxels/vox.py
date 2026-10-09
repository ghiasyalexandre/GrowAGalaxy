"""Voxel toolkit for the hangar upgrade models (Config.Hangar).

Each model is a `Vox`: a grid of 1-stud voxels in station space (x right,
y up, z towards the back; the front faces -z, towards the berth), standing on
y = 0 and centred on x = 0, z = 0. Every voxel holds a palette key.

The models are designed in Blender (run `models/<Id>.py` there through
`preview.py`) and exported by `export.py` to
`src/server/World/HangarVoxels.luau`, which HangarBuilder turns into Parts:
`greedy()` merges same-key voxels into as few boxes as it can.

Palette entries (a dict per key):
    color         hex, required
    material      Roblox Enum.Material name (default "SmoothPlastic")
    name          part name (default the key); HangarBuilder finds lights,
                  smoke and sparks by it
    transparency  0..1
    collide       False for decoration you can float through
    group         child Model the parts go into (spinning pieces)
    pulse         (from, to) transparency the client breathes between
"""

import itertools
import math

GLOW = "Neon"


class Vox:
    def __init__(self, model_id, palette):
        self.id = model_id
        self.palette = palette
        self.cells = {}

    # -- placing ---------------------------------------------------------

    def set(self, x, y, z, key):
        if key is None:
            self.cells.pop((x, y, z), None)
        else:
            assert key in self.palette, key
            self.cells[(x, y, z)] = key

    def box(self, x0, y0, z0, x1, y1, z1, key):
        """Fills the inclusive range."""
        for x in range(min(x0, x1), max(x0, x1) + 1):
            for y in range(min(y0, y1), max(y0, y1) + 1):
                for z in range(min(z0, z1), max(z0, z1) + 1):
                    self.set(x, y, z, key)

    def cyl(self, cx, cz, r, y0, y1, key, hollow=0.0):
        """Upright cylinder around the voxel-corner point (cx, cz)."""
        for x in range(math.floor(cx - r) - 1, math.ceil(cx + r) + 1):
            for z in range(math.floor(cz - r) - 1, math.ceil(cz + r) + 1):
                d = math.hypot(x + 0.5 - cx, z + 0.5 - cz)
                if d <= r and d >= hollow:
                    for y in range(y0, y1 + 1):
                        self.set(x, y, z, key)

    def octagon(self, x0, z0, x1, z1, y0, y1, key, cut=1):
        """A box with its four vertical edges chamfered by `cut` voxels
        (two or three crossed boxes, so it stays cheap in parts)."""
        self.box(x0 + cut, y0, z0, x1 - cut, y1, z1, key)
        self.box(x0, y0, z0 + cut, x1, y1, z1 - cut, key)

    def ring(self, cx, cz, r, y, key, width=1.0):
        self.cyl(cx, cz, r, y, y, key, hollow=r - width)

    def dome(self, cx, cy, cz, r, key):
        """Upper half-sphere on the plane y = cy (voxel-corner centre)."""
        for x in range(math.floor(cx - r) - 1, math.ceil(cx + r) + 1):
            for y in range(cy, cy + math.ceil(r) + 1):
                for z in range(math.floor(cz - r) - 1, math.ceil(cz + r) + 1):
                    if math.dist((x + 0.5, y + 0.5 - 0.5, z + 0.5), (cx, cy, cz)) <= r:
                        self.set(x, y, z, key)

    def ball(self, cx, cy, cz, r, key):
        for x in range(math.floor(cx - r) - 1, math.ceil(cx + r) + 1):
            for y in range(math.floor(cy - r) - 1, math.ceil(cy + r) + 1):
                for z in range(math.floor(cz - r) - 1, math.ceil(cz + r) + 1):
                    if math.dist((x + 0.5, y + 0.5, z + 0.5), (cx, cy, cz)) <= r:
                        self.set(x, y, z, key)

    def text(self, glyphs, x0, y0, z, key, dx=1):
        """Pixel letters on the plane z, top row first; '#' is a voxel."""
        for row, line in enumerate(glyphs):
            for col, ch in enumerate(line):
                if ch == "#":
                    self.set(x0 + col * dx, y0 + len(glyphs) - 1 - row, z, key)

    def pattern(self, rows, x0, y0, z, keys, dx=1):
        """Like text(), but each character maps to a key (`keys`); '.' and
        unmapped characters are left empty."""
        for row, line in enumerate(rows):
            for col, ch in enumerate(line):
                if ch in keys:
                    self.set(x0 + col * dx, y0 + len(rows) - 1 - row, z, keys[ch])

    # -- merging ---------------------------------------------------------

    def greedy(self):
        """Merges voxels of one key into boxes: (x, y, z, sx, sy, sz, key).

        Per key, tries growing boxes along each order of the three axes and
        keeps the order that needs the fewest boxes.
        """
        by_key = {}
        for cell, key in self.cells.items():
            by_key.setdefault(key, set()).add(cell)
        boxes = []
        for key in sorted(by_key):
            best = None
            for order in itertools.permutations(range(3)):
                found = _merge(by_key[key], order)
                if best is None or len(found) < len(best):
                    best = found
            boxes += [(*b, key) for b in best]
        return boxes

    def bounds(self):
        xs = [c[0] for c in self.cells]
        ys = [c[1] for c in self.cells]
        zs = [c[2] for c in self.cells]
        return (min(xs), min(ys), min(zs)), (max(xs) + 1, max(ys) + 1, max(zs) + 1)


def _merge(cells, order):
    """Greedy boxes over a set of cells, growing along axes in `order`."""
    left = set(cells)
    out = []
    # Visit cells so the first axis grown varies fastest.
    for cell in sorted(cells, key=lambda c: tuple(c[a] for a in reversed(order))):
        if cell not in left:
            continue
        size = [1, 1, 1]
        for axis in order:
            while True:
                size[axis] += 1
                ranges = [range(cell[a], cell[a] + size[a]) for a in range(3)]
                ranges[axis] = [cell[axis] + size[axis] - 1]
                if all((x, y, z) in left for x in ranges[0] for y in ranges[1] for z in ranges[2]):
                    continue
                size[axis] -= 1
                break
        for x in range(cell[0], cell[0] + size[0]):
            for y in range(cell[1], cell[1] + size[1]):
                for z in range(cell[2], cell[2] + size[2]):
                    left.discard((x, y, z))
        out.append((cell[0], cell[1], cell[2], size[0], size[1], size[2]))
    return out
