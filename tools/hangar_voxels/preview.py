"""Shows one hangar model in Blender (run inside Blender).

    import sys; sys.path.insert(0, r"<repo>/tools/hangar_voxels")
    import preview; preview.show("StardustSilo", r"<out>.png")

Clears the scene, builds the model's merged boxes (one mesh per palette key,
so the box seams match what Roblox will get), adds a reference deck and the
pad circle, frames a camera from the front-left and renders to `png`.
Roblox (x, y, z) maps to Blender (x, -z, y): the model's front (-z) looks
towards Blender +y.
"""

import importlib
import math

import bpy
import mathutils

import vox

DECK = "#4E5463"


def _rgb(hex_color):
    h = hex_color.lstrip("#")
    srgb = [int(h[i : i + 2], 16) / 255 for i in (0, 2, 4)]
    lin = [c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in srgb]
    return (*lin, 1.0)


def _material(key, entry):
    mat = bpy.data.materials.new(f"{key}")
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    color = _rgb(entry["color"])
    kind = entry.get("material", "SmoothPlastic")
    bsdf.inputs["Base Color"].default_value = color
    bsdf.inputs["Roughness"].default_value = 0.45
    if kind == "Metal" or kind == "DiamondPlate":
        bsdf.inputs["Metallic"].default_value = 0.7
        bsdf.inputs["Roughness"].default_value = 0.35
    if kind == "Neon":
        bsdf.inputs["Emission Color"].default_value = color
        bsdf.inputs["Emission Strength"].default_value = 2.0
    alpha = 1 - entry.get("transparency", 0)
    if kind in ("Glass", "ForceField"):
        alpha = min(alpha, 0.45)
    if alpha < 1:
        bsdf.inputs["Alpha"].default_value = alpha
        try:
            mat.surface_render_method = "BLENDED"
        except AttributeError:
            pass
    mat.diffuse_color = color
    return mat


def _mesh(name, boxes, mat, collection):
    verts, faces = [], []
    for (x, y, z, sx, sy, sz, _key) in boxes:
        x0, x1 = x, x + sx
        y0, y1 = y, y + sy
        z0, z1 = z, z + sz
        base = len(verts)
        for (rx, ry, rz) in [
            (x0, y0, z0), (x1, y0, z0), (x1, y0, z1), (x0, y0, z1),
            (x0, y1, z0), (x1, y1, z0), (x1, y1, z1), (x0, y1, z1),
        ]:
            verts.append((rx, -rz, ry))
        for f in [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]:
            faces.append(tuple(base + i for i in f))
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    obj.data.materials.append(mat)
    collection.objects.link(obj)
    return obj


def _clear():
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    for block in (bpy.data.meshes, bpy.data.materials, bpy.data.cameras, bpy.data.lights):
        for item in list(block):
            if item.users == 0:
                block.remove(item)
    for col in list(bpy.data.collections):
        bpy.data.collections.remove(col)


def show(model_id, png=None, deck=True, distance=None):
    import models  # noqa: F401  (package of the model scripts)

    module = importlib.reload(importlib.import_module(f"models.{model_id}"))
    importlib.reload(vox)
    model = module.build()
    _clear()
    col = bpy.data.collections.new(model_id)
    bpy.context.scene.collection.children.link(col)

    boxes = model.greedy()
    by_key = {}
    for b in boxes:
        by_key.setdefault(b[6], []).append(b)
    for key, items in by_key.items():
        _mesh(key, items, _material(key, model.palette[key]), col)

    (x0, y0, z0), (x1, y1, z1) = model.bounds()
    if deck:
        pad = max(x1 - x0, z1 - z0) + 8
        floor = vox.Vox("Deck", {"Deck": {"color": DECK}})
        _mesh(
            "Deck",
            [(-pad // 2, -1, -pad // 2, pad, 1, pad, "Deck")],
            _material("Deck", {"color": DECK, "material": "DiamondPlate"}),
            col,
        )
        del floor

    # Camera from the front-left, above, looking at the model's middle.
    centre = mathutils.Vector(((x0 + x1) / 2, -(z0 + z1) / 2, (y0 + y1) / 2))
    size = max(x1 - x0, y1 - y0, z1 - z0)
    dist = distance or size * 2.1 + 6
    direction = mathutils.Vector((-0.45, 1.0, 0.55)).normalized()
    cam_data = bpy.data.cameras.new("Cam")
    cam_data.lens = 50
    cam = bpy.data.objects.new("Cam", cam_data)
    cam.location = centre + direction * dist
    cam.rotation_euler = (centre - cam.location).to_track_quat("-Z", "Y").to_euler()
    col.objects.link(cam)
    bpy.context.scene.camera = cam

    sun_data = bpy.data.lights.new("Sun", "SUN")
    sun_data.energy = 3.5
    sun = bpy.data.objects.new("Sun", sun_data)
    sun.rotation_euler = (
        mathutils.Vector((-0.6, 0.9, 1.0)).to_track_quat("Z", "Y").to_euler()
    )
    col.objects.link(sun)

    scene = bpy.context.scene
    world = scene.world or bpy.data.worlds.new("World")
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    if bg:
        bg.inputs["Color"].default_value = (0.02, 0.025, 0.06, 1)
        bg.inputs["Strength"].default_value = 1.6
    scene.render.engine = "BLENDER_EEVEE"
    try:
        scene.eevee.use_bloom = True
    except AttributeError:
        pass
    scene.view_settings.view_transform = "AgX" if "AgX" in [
        i.identifier for i in scene.view_settings.bl_rna.properties["view_transform"].enum_items
    ] else "Filmic"
    scene.render.resolution_x = 900
    scene.render.resolution_y = 900
    scene.render.film_transparent = False

    # Frame the viewport on it too, for looking around by hand.
    for area in bpy.context.screen.areas if bpy.context.screen else []:
        if area.type == "VIEW_3D":
            for space in area.spaces:
                if space.type == "VIEW_3D":
                    space.shading.type = "MATERIAL"
                    r3d = space.region_3d
                    r3d.view_location = centre
                    r3d.view_distance = dist
                    r3d.view_rotation = cam.rotation_euler.to_quaternion()

    if png:
        if hasattr(scene.render.image_settings, "media_type"):
            scene.render.image_settings.media_type = "IMAGE"
        scene.render.image_settings.file_format = "PNG"
        scene.render.filepath = png
        bpy.ops.render.render(write_still=True)
    return {
        "voxels": len(model.cells),
        "parts": len(boxes),
        "size": [x1 - x0, y1 - y0, z1 - z0],
        "min": [x0, y0, z0],
    }
