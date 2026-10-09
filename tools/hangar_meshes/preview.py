"""Builds one hangar model in Blender and renders it (run inside Blender).

    import sys; sys.path.insert(0, r"<repo>/tools/hangar_meshes")
    import preview; preview.show("StardustSilo", r"<out>.png")

Other buildings stay in the scene (each in its own collection); only the
shown one is visible while rendering.
"""

import importlib
import math

import bpy
import mathutils

import kit


def show(model_id, png=None, distance=None):
    importlib.reload(kit)
    module = importlib.reload(importlib.import_module(f"models.{model_id}"))
    root = module.build()
    for col in bpy.data.collections:
        col.hide_render = col.name != model_id
        col.hide_viewport = col.name not in (model_id, "Preview")
    objs = [o for o in bpy.data.objects if o.get("hangar_id") == model_id and o.type == "MESH" and not o.name.startswith("Marker_")]
    lo = mathutils.Vector((1e9, 1e9, 1e9))
    hi = -lo
    for o in objs:
        for corner in o.bound_box:
            w = o.matrix_world @ mathutils.Vector(corner)
            lo = mathutils.Vector(map(min, lo, w))
            hi = mathutils.Vector(map(max, hi, w))
    centre = (lo + hi) / 2
    size = max(hi - lo)

    prev = bpy.data.collections.get("Preview")
    if prev is None:
        prev = bpy.data.collections.new("Preview")
        bpy.context.scene.collection.children.link(prev)
    for o in list(prev.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    prev.hide_render = False
    cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
    cam.data.lens = 50
    direction = mathutils.Vector((-0.55, -1.0, 0.5)).normalized()
    cam.location = centre + direction * (distance or size * 2.2 + 4)
    cam.rotation_euler = (centre - cam.location).to_track_quat("-Z", "Y").to_euler()
    prev.objects.link(cam)
    bpy.context.scene.camera = cam
    sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
    sun.data.energy = 3.0
    sun.rotation_euler = mathutils.Vector((-0.5, -0.8, 1.0)).to_track_quat("Z", "Y").to_euler()
    prev.objects.link(sun)
    fill = bpy.data.objects.new("Fill", bpy.data.lights.new("Fill", "SUN"))
    fill.data.energy = 0.8
    fill.rotation_euler = mathutils.Vector((0.8, 0.6, 0.3)).to_track_quat("Z", "Y").to_euler()
    prev.objects.link(fill)
    deck = bpy.data.objects.get("PreviewDeck")
    if deck is None:
        bpy.ops.mesh.primitive_plane_add(size=40, location=(0, 0, 0))
        deck = bpy.context.active_object
        deck.name = "PreviewDeck"
        mat = bpy.data.materials.new("PreviewDeck")
        mat.use_nodes = True
        mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.07, 0.08, 0.1, 1)
        deck.data.materials.append(mat)
    for c in list(deck.users_collection):
        c.objects.unlink(deck)
    prev.objects.link(deck)

    scene = bpy.context.scene
    world = scene.world or bpy.data.worlds.new("World")
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    if bg:
        bg.inputs["Color"].default_value = (0.02, 0.025, 0.05, 1)
        bg.inputs["Strength"].default_value = 1.2
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 900
    scene.render.resolution_y = 900
    for area in bpy.context.screen.areas if bpy.context.screen else []:
        if area.type == "VIEW_3D":
            for space in area.spaces:
                if space.type == "VIEW_3D":
                    space.shading.type = "MATERIAL"
                    space.region_3d.view_location = centre
                    space.region_3d.view_distance = (cam.location - centre).length
                    space.region_3d.view_rotation = cam.rotation_euler.to_quaternion()
    if png:
        if hasattr(scene.render.image_settings, "media_type"):
            scene.render.image_settings.media_type = "IMAGE"
        scene.render.image_settings.file_format = "PNG"
        scene.render.filepath = png
        bpy.ops.render.render(write_still=True)
    return {
        "tris": kit.tris(model_id),
        "objects": len([o for o in root.children]),
        "size": [round(v, 2) for v in (hi - lo)],
    }


def lineup(ids, png, gap=4.0, distance=None, height=0.45):
    """Builds `ids` and renders them side by side (roots shifted along X for
    the picture only; they're put back afterwards)."""
    roots = []
    for model_id in ids:
        importlib.reload(kit)
        module = importlib.reload(importlib.import_module(f"models.{model_id}"))
        roots.append(module.build())
    for col in bpy.data.collections:
        col.hide_render = col.name not in ids and col.name != "Preview"
        col.hide_viewport = col.hide_render
    widths = []
    for root in roots:
        xs = []
        for o in root.children:
            if o.type == "MESH" and not o.name.startswith("Marker_"):
                for c in o.bound_box:
                    xs.append((o.matrix_world @ mathutils.Vector(c)).x)
        widths.append((min(xs), max(xs)))
    x = 0.0
    for root, (lo, hi) in zip(roots, widths):
        root.location.x = x - lo
        x += (hi - lo) + gap
    total = x - gap
    show_ids = set(ids)
    centre = mathutils.Vector((total / 2, 0, 6))
    prev = bpy.data.collections.get("Preview")
    cam = next((o for o in prev.objects if o.type == "CAMERA"), None) if prev else None
    if cam is None:
        show(ids[0])
        prev = bpy.data.collections.get("Preview")
        cam = next(o for o in prev.objects if o.type == "CAMERA")
        for col in bpy.data.collections:
            col.hide_render = col.name not in show_ids and col.name != "Preview"
    cam.location = centre + mathutils.Vector((-0.15, -1.0, height)).normalized() * (distance or total * 1.0)
    cam.rotation_euler = (centre - cam.location).to_track_quat("-Z", "Y").to_euler()
    deck = bpy.data.objects.get("PreviewDeck")
    if deck:
        deck.scale = (max(total, 40) / 40 * 1.5, 2, 1)
        deck.location = (total / 2, 0, 0)
    scene = bpy.context.scene
    scene.render.resolution_x = 1600
    scene.render.resolution_y = 700
    scene.render.filepath = png
    bpy.ops.render.render(write_still=True)
    for root in roots:
        root.location.x = 0
    scene.render.resolution_x = 900
    scene.render.resolution_y = 900
    return {mid: kit.tris(mid) for mid in ids}
