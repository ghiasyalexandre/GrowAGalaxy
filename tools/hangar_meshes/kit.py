"""Blender toolkit for the hangar upgrade meshes (run inside Blender).

Each model script in models/ calls `b = Building("<Id>")`, adds shapes with a
look, and `b.finish()`. Shapes are authored in Blender space, standing on
z = 0, centred on x = 0, y = 0, with the building's FRONT towards -Y (the
side its name plate and the deck's centre line face).

finish() joins every shape of the same look into one object, so a building
imports as a handful of MeshParts. Object names carry the look, which
HangarBuilder reads after import (it never trusts the importer's colours):

    <Role>__<RRGGBB>__<Material>     e.g. Hull__E8EAED__SmoothPlastic
    Spin_<Group>_<Part>__<RRGGBB>__<Material>
                                     parts that turn together (about the
                                     group's centre, world up)
    Marker_<Name>                    tiny invisible points: Origin (floor
                                     point), Front (8 studs out of the
                                     front) and Up (8 studs above) on every
                                     building, for placing it; Smoke, Steam, Sparks, Beam and
                                     Light_<RRGGBB>_<range> for effects

Axes: the game's +x is Blender -X (a proper rotation that keeps up as up
and the front as the front), so author anything left/right-specific with
that in mind (e.g. the Showcase Dock's bridge, at game x -21, is Blender
X +21).

Roles starting "Accent" (trims, bands, accent lamps) are repainted in game
in the station's highlight colour (Settings > hangar colour); their colour
here is only a stand-in. Glow uses the Neon material, kept small and dim
(HangarBuilder dims it further), so bloom stays low.
"""

import math

import bpy
import bmesh
from mathutils import Vector


def _material(look):
    role, color, kind = look
    name = f"{color}_{kind}"
    mat = bpy.data.materials.get(name)
    if mat:
        return mat
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    srgb = [int(color[i : i + 2], 16) / 255 for i in (0, 2, 4)]
    lin = [c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in srgb]
    rgba = (*lin, 1.0)
    bsdf.inputs["Base Color"].default_value = rgba
    bsdf.inputs["Roughness"].default_value = 0.4
    if kind in ("Metal", "DiamondPlate"):
        bsdf.inputs["Metallic"].default_value = 0.8
        bsdf.inputs["Roughness"].default_value = 0.3
    if kind == "Neon":
        bsdf.inputs["Emission Color"].default_value = rgba
        bsdf.inputs["Emission Strength"].default_value = 1.5
    if kind == "Glass":
        bsdf.inputs["Alpha"].default_value = 0.35
        try:
            mat.surface_render_method = "BLENDED"
        except AttributeError:
            pass
    mat.diffuse_color = rgba
    return mat


class Building:
    def __init__(self, model_id):
        self.id = model_id
        self.parts = []  # (object, look)
        self.markers = []
        for obj in list(bpy.data.objects):
            if obj.get("hangar_id") == model_id:
                bpy.data.objects.remove(obj, do_unlink=True)
        self.col = bpy.data.collections.get(model_id) or bpy.data.collections.new(model_id)
        if self.col.name not in bpy.context.scene.collection.children:
            bpy.context.scene.collection.children.link(self.col)
        self.col.hide_viewport = False
        self.col.hide_render = False

    # -- shapes ------------------------------------------------------------

    def _take(self, look, bevel=0.0, smooth=True, segments=2):
        obj = bpy.context.active_object
        for c in list(obj.users_collection):
            c.objects.unlink(obj)
        self.col.objects.link(obj)
        if bevel > 0:
            mod = obj.modifiers.new("Bevel", "BEVEL")
            mod.width = bevel
            mod.segments = segments
            mod.harden_normals = True
            mod.limit_method = "ANGLE"
        if smooth:
            for poly in obj.data.polygons:
                poly.use_smooth = True
            mod = obj.modifiers.new("Normals", "WEIGHTED_NORMAL")
            mod.keep_sharp = True
        self.parts.append((obj, look))
        return obj

    def box(self, look, size, at, rot=(0, 0, 0), bevel=0.15):
        bpy.ops.mesh.primitive_cube_add(size=1, location=at, rotation=_rad(rot))
        bpy.context.active_object.scale = size
        bpy.ops.object.transform_apply(scale=True)
        return self._take(look, bevel)

    def cyl(self, look, radius, depth, at, rot=(0, 0, 0), sides=24, bevel=0.1, top=None):
        """A cylinder (or a cone/frustum if `top` radius is given)."""
        if top is None:
            bpy.ops.mesh.primitive_cylinder_add(
                vertices=sides, radius=radius, depth=depth, location=at, rotation=_rad(rot)
            )
        else:
            bpy.ops.mesh.primitive_cone_add(
                vertices=sides,
                radius1=radius,
                radius2=top,
                depth=depth,
                location=at,
                rotation=_rad(rot),
            )
        return self._take(look, bevel)

    def ball(self, look, radius, at, scale=(1, 1, 1), segments=20):
        bpy.ops.mesh.primitive_uv_sphere_add(
            segments=segments, ring_count=segments // 2, radius=radius, location=at
        )
        obj = bpy.context.active_object
        obj.scale = scale
        bpy.ops.object.transform_apply(scale=True)
        return self._take(look, 0)

    def torus(self, look, major, minor, at, rot=(0, 0, 0), sides=32):
        bpy.ops.mesh.primitive_torus_add(
            major_radius=major,
            minor_radius=minor,
            major_segments=sides,
            minor_segments=6,
            location=at,
            rotation=_rad(rot),
        )
        return self._take(look, 0)

    def tube(self, look, points, radius, sides=8):
        """A pipe along a polyline of points, with rounded bends."""
        curve = bpy.data.curves.new("Pipe", "CURVE")
        curve.dimensions = "3D"
        curve.bevel_depth = radius
        curve.bevel_resolution = 1
        curve.use_fill_caps = True
        spline = curve.splines.new("POLY")
        spline.points.add(len(points) - 1)
        for p, (x, y, z) in zip(spline.points, points):
            p.co = (x, y, z, 1)
        obj = bpy.data.objects.new("Pipe", curve)
        bpy.context.scene.collection.objects.link(obj)
        bpy.context.view_layer.objects.active = obj
        for o in bpy.context.selected_objects:
            o.select_set(False)
        obj.select_set(True)
        bpy.ops.object.convert(target="MESH")
        return self._take(look, 0)

    def lathe(self, look, profile, at=(0, 0, 0), sides=24):
        """A solid of revolution round the z axis from a list of
        (radius, height) points, bottom to top (capped at both ends)."""
        bm = bmesh.new()
        rings = []
        for r, z in profile:
            ring = []
            for i in range(sides):
                a = 2 * math.pi * i / sides
                ring.append(bm.verts.new((at[0] + r * math.cos(a), at[1] + r * math.sin(a), at[2] + z)))
            rings.append(ring)
        for lower, upper in zip(rings, rings[1:]):
            for i in range(sides):
                j = (i + 1) % sides
                bm.faces.new((lower[i], lower[j], upper[j], upper[i]))
        bm.faces.new(list(reversed(rings[0])))
        bm.faces.new(rings[-1])
        mesh = bpy.data.meshes.new("Lathe")
        bm.to_mesh(mesh)
        bm.free()
        obj = bpy.data.objects.new("Lathe", mesh)
        bpy.context.scene.collection.objects.link(obj)
        bpy.context.view_layer.objects.active = obj
        return self._take(look, 0)

    def text(self, look, body, at, size=4.0, depth=0.3, rot=(90, 0, 0)):
        """Solid letters (Blender's default font), standing up, facing -Y."""
        bpy.ops.object.text_add(location=at, rotation=_rad(rot))
        obj = bpy.context.active_object
        obj.data.body = body
        obj.data.size = size
        obj.data.extrude = depth
        obj.data.align_x = "CENTER"
        obj.data.align_y = "CENTER"
        bpy.ops.object.convert(target="MESH")
        return self._take(look, 0, smooth=False)

    def marker(self, name, at):
        self.markers.append((name, at))

    # -- finishing -----------------------------------------------------------

    def finish(self):
        """Applies modifiers, joins shapes by look, names them, parents them
        to an empty named after the building."""
        # Every building carries these three, so the game can scale and turn
        # it however the importer brought it in: Origin is the floor point,
        # Front is 8 studs straight out of the front (-Y), Up 8 studs above.
        self.markers.append(("Origin", (0, 0, 0)))
        self.markers.append(("Front", (0, -8, 0)))
        self.markers.append(("Up", (0, 0, 8)))
        root = bpy.data.objects.new(self.id, None)
        root["hangar_id"] = self.id
        self.col.objects.link(root)
        groups = {}
        for obj, look in self.parts:
            groups.setdefault(look, []).append(obj)
        # Merged with the data API (evaluated meshes, modifiers applied), so
        # it works whatever is selected, active or hidden.
        depsgraph = bpy.context.evaluated_depsgraph_get()
        for look, objs in groups.items():
            bm = bmesh.new()
            for o in objs:
                evaluated = o.evaluated_get(depsgraph)
                mesh = evaluated.to_mesh()
                mesh.transform(o.matrix_world)
                bm.from_mesh(mesh)
                evaluated.to_mesh_clear()
            role, color, kind = look
            name = f"{role}__{color}__{kind}"
            # Origin at the shape's own centre (spinning groups turn about it).
            lo = Vector((min(v.co.x for v in bm.verts), min(v.co.y for v in bm.verts), min(v.co.z for v in bm.verts)))
            hi = Vector((max(v.co.x for v in bm.verts), max(v.co.y for v in bm.verts), max(v.co.z for v in bm.verts)))
            centre = (lo + hi) / 2
            for v in bm.verts:
                v.co -= centre
            data = bpy.data.meshes.new(name)
            bm.to_mesh(data)
            bm.free()
            data.materials.append(_material(look))
            obj = bpy.data.objects.new(name, data)
            obj.location = centre
            obj["hangar_id"] = self.id
            self.col.objects.link(obj)
            obj.parent = root
            for o in objs:
                bpy.data.objects.remove(o, do_unlink=True)
        for name, at in self.markers:
            bm = bmesh.new()
            bmesh.ops.create_cube(bm, size=0.2)
            data = bpy.data.meshes.new(f"Marker_{name}")
            bm.to_mesh(data)
            bm.free()
            m = bpy.data.objects.new(f"Marker_{name}", data)
            m.location = at
            m["hangar_id"] = self.id
            self.col.objects.link(m)
            m.parent = root
        return root


def _rad(rot):
    return tuple(math.radians(a) for a in rot)


def tris(model_id):
    total = 0
    for obj in bpy.data.objects:
        if obj.get("hangar_id") == model_id and obj.type == "MESH":
            total += sum(len(p.vertices) - 2 for p in obj.data.polygons)
    return total


def look(role, color, kind="SmoothPlastic"):
    return (role, color.lstrip("#").upper(), kind)


def lerp(a, b, t):
    return a + (b - a) * t


V = Vector
