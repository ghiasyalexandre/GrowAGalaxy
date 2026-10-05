# Ship models

Rojo syncs this folder to `ReplicatedStorage/Assets/Ships`. Each `.rbxm` here becomes a model
named after its file, and `ShipBuilder` dresses that ship with it (the greybox shuttle stands in
for a missing one). The Shipyard shows the same model as a spinning preview.

| File | Ship | Source in `assets/models` |
|---|---|---|
| `MicroRecon.rbxm` | Micro Recon | MicroRecon.obj |
| `RedFighter.rbxm` | Red Fighter | RedFighter.obj |
| `GalactixRacer.rbxm` | Galactix Racer | (none yet) |
| `Warship.rbxm` | Warship | (none yet) |
| `CamoStellarJet.rbxm` | Camo Stellar | CamoStellarJet.obj |
| `InfraredFurtive.rbxm` | Infrared Furtive | InfraredFurtive.obj |
| `InterstellarRunner.rbxm` | Interstellar Runner | InterstellarRunner.obj |
| `Transtellar.rbxm` | Transtellar | Transtellar.obj |
| `DualStriker.rbxm` | Dual Striker | DualStriker.obj |
| `UltravioletIntruder.rbxm` | Ultraviolet Intruder | UltravioletIntruder.obj |
| `MeteorSlicer.rbxm` | Meteor Slicer | (none yet) |

The file name must match the ship's `model` in `src/shared/Config/Ships.luau`.

## Importing one (Studio)

1. **Home → Import 3D**, pick e.g. `assets/models/MicroRecon.obj`. Keep its `.mtl` and `.png`
   next to it, so the importer finds the palette. The preview should be coloured.
2. Import. Studio uploads the mesh and texture to your account and inserts a Model.
3. Rename the Model to the file name above (e.g. `MicroRecon`).
4. Right-click it → **Save to File…** → this folder, as `MicroRecon.rbxm`. Then delete the
   inserted copy. Rojo syncs the file in.

Size and position don't matter: the game scales each model so its longest horizontal side is the
ship's `modelSize` and centres it on the ship. If a ship flies backwards, change its `modelYaw` in
`Config/Ships` (0 or 180; 90 or -90 for a sideways export).
