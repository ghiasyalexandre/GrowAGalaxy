"""The Quasar Hoverboard ship model (run inside Blender).

    import sys; sys.path.insert(0, r"<repo>/tools/ship_meshes")
    import importlib, QuasarBoard; importlib.reload(QuasarBoard); QuasarBoard.run()

Builds the board and writes assets/models/QuasarBoard.obj with its .mtl and
a palette .png, the same format as the other ship sources: every part is
UV-mapped onto one flat colour cell of the palette. Import it in Studio as
described in assets/roblox/Ships/README.md and save it as QuasarBoard.rbxm.

Blender space: the board lies along Y with its nose towards -Y, the deck
top at about z = 0.6, one unit = one stud (the game rescales it anyway).
"""

import math
import pathlib

import bpy
import bmesh

ROOT = pathlib.Path(__file__).resolve().parent.parent.parent
OUT = ROOT / "assets" / "models"
NAME = "QuasarBoard"

# Palette: name -> colour. Each gets an 8x8 cell in a 64x64 image.
PALETTE = {
    "pearl": "EEF1F8",  # deck shell
    "grip": "161A24",  # grip top
    "carbon": "2A2F3C",  # pods, engines
    "steel": "8C96A8",  # trims, struts
    "cyan": "3FE8FF",  # edge rails, pod cores
    "violet": "B06BFF",  # engine nozzles, under-strip
    "gold": "FFC04A",  # foot plates, fins
    "glass": "9FD8FF",  # nose visor
}
CELL = 8
SIZE = 64

parts = []  # (object, palette key)


def _cell_uv(key):
    index = list(PALETTE).index(key)
    cx = (index % (SIZE // CELL)) * CELL + CELL / 2
    cy = (index // (SIZE // CELL)) * CELL + CELL / 2
    return cx / SIZE, 1 - cy / SIZE


def _add(obj, key):
    parts.append((obj, key))
    return obj


def _mesh_object(name, bm):
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def _prim(op, key, at, rot=(0, 0, 0), scale=(1, 1, 1), bevel=0.0, **kw):
    op(location=at, rotation=tuple(math.radians(r) for r in rot), **kw)
    obj = bpy.context.active_object
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel > 0:
        mod = obj.modifiers.new("Bevel", "BEVEL")
        mod.width = bevel
        mod.segments = 1
        mod.limit_method = "ANGLE"
    for poly in obj.data.polygons:
        poly.use_smooth = True
    return _add(obj, key)


def box(key, size, at, rot=(0, 0, 0), bevel=0.05):
    return _prim(bpy.ops.mesh.primitive_cube_add, key, at, rot, tuple(s / 2 for s in size), bevel, size=1 * 2)


def cyl(key, radius, depth, at, rot=(0, 0, 0), sides=20, bevel=0.03):
    return _prim(
        bpy.ops.mesh.primitive_cylinder_add, key, at, rot, (1, 1, 1), bevel, radius=radius, depth=depth, vertices=sides
    )


def cone(key, r1, r2, depth, at, rot=(0, 0, 0), sides=20):
    return _prim(
        bpy.ops.mesh.primitive_cone_add, key, at, rot, (1, 1, 1), 0.0, radius1=r1, radius2=r2, depth=depth, vertices=sides
    )


def torus(key, major, minor, at, rot=(0, 0, 0)):
    return _prim(
        bpy.ops.mesh.primitive_torus_add,
        key,
        at,
        rot,
        (1, 1, 1),
        0.0,
        major_radius=major,
        minor_radius=minor,
        major_segments=24,
        minor_segments=6,
    )


def ball(key, radius, at, scale=(1, 1, 1)):
    return _prim(bpy.ops.mesh.primitive_uv_sphere_add, key, at, (0, 0, 0), scale, 0.0, radius=radius, segments=16, ring_count=8)


# --- The deck: a lofted, tapered surfboard shape with kicked-up ends -------

LENGTH = 12.0
WIDTH = 3.4


def half_width(t):
    # t in [-1, 1] along the board: a pointed nose (-1) and a squared swallow tail (+1).
    if t < 0:
        return WIDTH / 2 * (1 - abs(t) ** 2.6) ** 0.5 + 0.05
    return WIDTH / 2 * (1 - t**6) ** 0.5 * 0.92 + 0.25


def lift(t):
    nose = max(0.0, -t - 0.62) / 0.38
    tail = max(0.0, t - 0.75) / 0.25
    return 1.3 * nose**2 + 0.45 * tail**2


def loft(key, name, z0, thickness, inset=0.0, stations=48, ring=20, top_only=False):
    bm = bmesh.new()
    rings = []
    for i in range(stations + 1):
        t = -1 + 2 * i / stations
        y = t * LENGTH / 2
        hw = max(half_width(t) - inset, 0.04)
        z = z0 + lift(t)
        pts = []
        for j in range(ring):
            a = 2 * math.pi * j / ring
            # A flattened superellipse: a thin rounded slab.
            ca, sa = math.cos(a), math.sin(a)
            x = hw * math.copysign(abs(ca) ** 0.35, ca)
            h = thickness / 2 * math.copysign(abs(sa) ** 0.7, sa)
            pts.append(bm.verts.new((x, y, z + h)))
        rings.append(pts)
    for i in range(stations):
        for j in range(ring):
            a, b = rings[i][j], rings[i][(j + 1) % ring]
            c, d = rings[i + 1][(j + 1) % ring], rings[i + 1][j]
            bm.faces.new((a, b, c, d))
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    obj = _mesh_object(name, bm)
    for poly in obj.data.polygons:
        poly.use_smooth = True
    return _add(obj, key)


def rail(key, name, side, z, radius=0.07, from_t=-0.93, to_t=0.95, out=0.0):
    pts = []
    for i in range(41):
        t = from_t + (to_t - from_t) * i / 40
        pts.append((side * (half_width(t) + out), t * LENGTH / 2, z + lift(t)))
    curve = bpy.data.curves.new(name, "CURVE")
    curve.dimensions = "3D"
    curve.bevel_depth = radius
    curve.bevel_resolution = 1
    spline = curve.splines.new("POLY")
    spline.points.add(len(pts) - 1)
    for p, co in zip(spline.points, pts):
        p.co = (*co, 1)
    obj = bpy.data.objects.new(name, curve)
    bpy.context.scene.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    for o in bpy.context.selected_objects:
        o.select_set(False)
    obj.select_set(True)
    bpy.ops.object.convert(target="MESH")
    return _add(bpy.context.active_object, key)


def build():
    for obj in list(bpy.data.objects):
        if obj.get("ship_id") == NAME:
            bpy.data.objects.remove(obj, do_unlink=True)
    parts.clear()

    # Shell, grip top and a steel keel line under it.
    loft("pearl", "Deck", 0.35, 0.42)
    loft("grip", "Grip", 0.58, 0.06, inset=0.38, stations=40, ring=16)
    loft("steel", "Keel", 0.12, 0.12, inset=1.2, stations=40, ring=12)
    # Glowing edge rails both sides, a thinner upper trim line.
    for side in (-1, 1):
        rail("cyan", f"Rail{side}", side, 0.36, radius=0.07, out=0.02)
        rail("steel", f"Trim{side}", side, 0.52, radius=0.035, from_t=-0.85, to_t=0.9, out=-0.12)

    # Two gold foot plates with steel bolts and cyan grip lights.
    for y in (-1.9, 2.0):
        box("gold", (2.0, 1.4, 0.06), (0, y, 0.64), bevel=0.15)
        box("grip", (1.7, 1.1, 0.05), (0, y, 0.68), bevel=0.12)
        for bx in (-0.8, 0.8):
            for by in (-0.55, 0.55):
                cyl("steel", 0.07, 0.06, (bx, y + by, 0.69), sides=10, bevel=0)
        for k in range(3):
            box("cyan", (1.3, 0.06, 0.03), (0, y - 0.35 + k * 0.35, 0.71), bevel=0)

    # Nose: a glass visor wedge and a gold sensor chevron.
    ball("glass", 0.55, (0, -4.35, 0.62 + lift(-0.72)), scale=(1.0, 1.8, 0.35))
    for side in (-1, 1):
        box("gold", (0.12, 1.0, 0.05), (side * 0.45, -3.4, 0.64), rot=(0, 0, side * 28), bevel=0)

    # Four grav pods underneath: carbon housings, steel collars, glowing cores.
    for x in (-0.95, 0.95):
        for y in (-3.0, 2.6):
            cyl("carbon", 0.62, 0.32, (x, y, 0.0), sides=20)
            torus("steel", 0.62, 0.07, (x, y, 0.05))
            torus("cyan", 0.42, 0.06, (x, y, -0.16))
            cyl("cyan", 0.25, 0.06, (x, y, -0.17), sides=24, bevel=0)
            for k in range(6):
                a = k * math.pi / 3
                box("steel", (0.06, 0.32, 0.05), (x + 0.42 * math.cos(a), y + 0.42 * math.sin(a), -0.15), rot=(0, 0, math.degrees(a) + 90), bevel=0)
    # A violet glow strip down the belly.
    box("violet", (0.22, 7.6, 0.05), (0, 0, 0.07), bevel=0)

    # Tail: twin engines with violet nozzles, flanked by gold fins.
    tail_z = 0.42 + lift(0.9)
    for x in (-0.75, 0.75):
        cyl("carbon", 0.36, 1.5, (x, 5.1, tail_z), rot=(90, 0, 0))
        torus("steel", 0.36, 0.06, (x, 4.45, tail_z), rot=(90, 0, 0))
        torus("steel", 0.36, 0.06, (x, 5.55, tail_z), rot=(90, 0, 0))
        cone("carbon", 0.36, 0.28, 0.4, (x, 6.0, tail_z), rot=(90, 0, 0))
        cyl("violet", 0.24, 0.05, (x, 6.2, tail_z), rot=(90, 0, 0), bevel=0)
        torus("violet", 0.27, 0.035, (x, 6.2, tail_z), rot=(90, 0, 0))
    for side in (-1, 1):
        fin = box("gold", (0.08, 1.3, 0.75), (side * 1.55, 5.15, 0.95), rot=(-25, side * 12, 0), bevel=0.03)
        box("cyan", (0.1, 0.9, 0.05), (side * 1.57, 5.25, 1.25), rot=(-25, side * 12, 0), bevel=0)
        # Stabiliser wings sweeping out under the tail.
        box("pearl", (1.1, 0.9, 0.08), (side * 2.0, 4.3, 0.3), rot=(0, side * -8, side * -25), bevel=0.04)
        box("cyan", (0.7, 0.06, 0.05), (side * 2.15, 3.9, 0.36), rot=(0, side * -8, side * -25), bevel=0)
    # A pearl cowl over the engines with a cyan stripe and a vent grille.
    box("pearl", (2.3, 1.3, 0.35), (0, 4.75, tail_z + 0.3), rot=(-6, 0, 0), bevel=0.15)
    box("cyan", (0.18, 1.2, 0.04), (0, 4.75, tail_z + 0.49), rot=(-6, 0, 0), bevel=0)
    for k in range(4):
        box("carbon", (1.6, 0.06, 0.04), (0, 4.35 + k * 0.22, tail_z + 0.46), rot=(-6, 0, 0), bevel=0)
    # Centre spoiler bar between the fins.
    box("steel", (2.6, 0.18, 0.08), (0, 5.4, 1.12), rot=(-15, 0, 0), bevel=0.03)

    for obj, _ in parts:
        obj["ship_id"] = NAME


def palette_image():
    img = bpy.data.images.get(NAME) or bpy.data.images.new(NAME, SIZE, SIZE)
    px = [0.0] * (SIZE * SIZE * 4)
    for index, color in enumerate(PALETTE.values()):
        rgb = [int(color[i : i + 2], 16) / 255 for i in (0, 2, 4)]
        x0 = (index % (SIZE // CELL)) * CELL
        y0 = SIZE - CELL - (index // (SIZE // CELL)) * CELL
        for y in range(y0, y0 + CELL):
            for x in range(x0, x0 + CELL):
                o = (y * SIZE + x) * 4
                px[o : o + 4] = [*rgb, 1.0]
    img.pixels = px
    img.filepath_raw = str(OUT / f"{NAME}.png")
    img.file_format = "PNG"
    img.save()
    return img


def join_and_export(img):
    mat = bpy.data.materials.get(NAME) or bpy.data.materials.new(NAME)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    tex = nodes.get("Palette") or nodes.new("ShaderNodeTexImage")
    tex.name = "Palette"
    tex.image = img
    tex.interpolation = "Closest"
    mat.node_tree.links.new(tex.outputs["Color"], nodes["Principled BSDF"].inputs["Base Color"])

    for o in bpy.context.selected_objects:
        o.select_set(False)
    for obj, key in parts:
        bpy.context.view_layer.objects.active = obj
        obj.select_set(True)
        bpy.ops.object.convert(target="MESH")  # applies bevels
        obj.select_set(False)
        mesh = obj.data
        mesh.materials.clear()
        mesh.materials.append(mat)
        uv = mesh.uv_layers.get("UVMap") or mesh.uv_layers.new(name="UVMap")
        u, v = _cell_uv(key)
        for loop in uv.data:
            loop.uv = (u, v)
    for obj, _ in parts:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = parts[0][0]
    bpy.ops.object.join()
    board = bpy.context.active_object
    board.name = NAME
    board["ship_id"] = NAME
    bpy.ops.wm.obj_export(
        filepath=str(OUT / f"{NAME}.obj"),
        export_selected_objects=True,
        export_materials=True,
        path_mode="STRIP",
        forward_axis="NEGATIVE_Z",
        up_axis="Y",
    )
    return board


def run(export=True):
    OUT.mkdir(parents=True, exist_ok=True)
    build()
    if export:
        img = palette_image()
        board = join_and_export(img)
        return {"tris": sum(len(p.vertices) - 2 for p in board.data.polygons)}
    return {"parts": len(parts)}
