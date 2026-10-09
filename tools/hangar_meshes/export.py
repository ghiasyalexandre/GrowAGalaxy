"""Builds every hangar model and exports them as one FBX (run in Blender).

    import sys; sys.path.insert(0, r"<repo>/tools/hangar_meshes")
    import export; export.run()

Writes assets/models/hangar/HangarMeshes.fbx: one root per building, named
by its Config.Hangar id, holding its merged meshes and markers. Import it
once with Studio's 3D Importer, put the building models in a folder
named Hangar, and save that folder as assets/roblox/Hangar.rbxm (mapped to
ServerStorage/Assets/Hangar). HangarBuilder and DeviceBuilder place and
dress them.
"""

import importlib
import pathlib

import bpy

import kit

ROOT = pathlib.Path(__file__).resolve().parent.parent.parent
OUT = ROOT / "assets" / "models" / "hangar" / "HangarMeshes.fbx"
IDS = [
    "StardustSilo",
    "FuelDepot",
    "Refinery",
    "CoolingTower",
    "MiningLab",
    "ArmorWorkshop",
    "HoloGalaxy",
    "ShowcaseDock",
    "VictorySpire",
    # Station deck machines (DeviceBuilder), shipped in the same file.
    "StardustCollector",
    "GalaxyControl",
    "EggLab",
    "IncubatorChamber",
]


def run():
    importlib.reload(kit)
    for col in bpy.data.collections:
        col.hide_viewport = False
        col.hide_render = False
    for model_id in IDS:
        importlib.reload(importlib.import_module(f"models.{model_id}")).build()
    for o in bpy.context.selected_objects:
        o.select_set(False)
    count = 0
    for o in bpy.data.objects:
        if o.get("hangar_id"):
            o.hide_set(False)
            o.select_set(True)
            count += 1
    OUT.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.fbx(
        filepath=str(OUT),
        use_selection=True,
        object_types={"EMPTY", "MESH"},
        apply_scale_options="FBX_SCALE_UNITS",
        axis_forward="-Z",
        axis_up="Y",
        use_mesh_modifiers=True,
        mesh_smooth_type="FACE",
        add_leaf_bones=False,
        bake_anim=False,
    )
    tris = {mid: kit.tris(mid) for mid in IDS}
    return {"objects": count, "file": str(OUT), "tris": tris, "total": sum(tris.values())}
