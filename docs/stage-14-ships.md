# Stage 14: Ship ladder, imported models, Shipyard Ships tab

**Status: code complete, CI-verified (format, lint, strict types, 120 unit tests, build, smoke
test). Not yet playtested in Studio. Models need importing in Studio (below).**

## Playable result

**The ladder.** Eleven ships, bought in order: each needs the one before it.

| # | Ship | Price | Speed | Laser | Boost | Model |
|---|---|---|---|---|---|---|
| 1 | Micro Recon | starter | 120 | 10 | x1.6 / 3 s | MicroRecon.obj |
| 2 | Red Fighter | 2,500 | 135 | 14 | x1.7 / 3.5 s | RedFighter.obj |
| 3 | Galactix Racer | 8,000 | 165 | 15 | x2.0 / 4 s | none yet |
| 4 | Warship | 20,000 | 125 | 24 | x1.5 / 3 s | none yet |
| 5 | Camo Stellar | 45,000 | 150 | 22 | x1.8 / 4 s | CamoStellarJet.obj |
| 6 | Infrared Furtive | 90,000 | 170 | 25 | x2.0 / 4.5 s | InfraredFurtive.obj |
| 7 | Interstellar Runner | 160,000 | 195 | 26 | x2.2 / 5 s | InterstellarRunner.obj |
| 8 | Transtellar | 280,000 | 185 | 30 | x2.0 / 5 s | Transtellar.obj |
| 9 | Dual Striker | 450,000 | 180 | 36 | x1.9 / 5 s | DualStriker.obj |
| 10 | Ultraviolet Intruder | 700,000 | 210 | 38 | x2.3 / 5.5 s | UltravioletIntruder.obj |
| 11 | Meteor Slicer | 1,000,000 | 240 | 42 | x2.5 / 6 s | none yet |

The server refuses a purchase out of order ("Own the Red Fighter first."). Full stats are in
`Config/Ships`; the Galactix Racer keeps the old Crystal Explorer's (disabled) Robux unlock slot.

**Shipyard.** Two tabs: **Ships** and **Upgrades** (equipment and galaxy expansion, as before).
Each ship card has a turning preview of its model (or the ship icon on its paint colour while the
model isn't imported), its ladder number, role, boost, bars for speed, laser, boost and heat, and
Buy / Select / Active. Locked ships are dimmed with "LOCKED" and "Own the ... first"; the next
ship to buy is tagged NEXT SHIP with a shining button, and an unaffordable one says how much more
Stardust it needs. Previews are kept between refreshes, so Stardust ticking doesn't rebuild them.

**Models in the world.** A ship whose model is imported wears it: scaled so its longest
horizontal side is `modelSize` studs (14 for the Micro Recon up to 22 for the Dual Striker, and
never larger than the berth), turned by `modelYaw`, centred on the ship. Untextured parts get the
ship's paint; textured parts (the MagicaVoxel palette) keep their colours. The model is cosmetic:
massless, non-colliding, welded to the invisible Hull, which does the physics as before. Engine
glows, exhaust nozzles, the laser muzzle and the wing trails move to the model's measured
extents. Without a model the old greybox shuttle stands in.

## Importing the models (Studio, once per ship)

See [assets/roblox/Ships/README.md](../assets/roblox/Ships/README.md): 3D Importer on the
`.obj` (with its `.mtl` and `.png` beside it), rename the Model to the ship's file name, Save to
File into `assets/roblox/Ships/`. Rojo maps that folder to `ReplicatedStorage/Assets/Ships`.

Nose directions were read off the OBJ silhouettes: Red Fighter, Camo Stellar, Infrared Furtive,
Interstellar Runner and Transtellar point at +Z in the export (`modelYaw = 180`); Micro Recon,
Dual Striker and Ultraviolet Intruder at -Z (0). If one flies backwards, flip its `modelYaw`.
Star Marine Trooper isn't on the ladder and stays unused.

## Save data

Schema v6 renames the old ship ids: Starter Shuttle → Micro Recon, Prospector → Red Fighter,
Crystal Explorer → Galactix Racer, Heavy Excavator → Warship, Nebula Cruiser → Camo Stellar
(owned ships, active ship, loadouts).

## What CI verifies vs what needs Studio

| Verified by CI | Needs a playtest in Studio |
|---|---|
| Ladder order, starter first, rising prices; unlock rule; ConfigCheck on model fields | Models import with colours; sizes and noses look right; effects sit on the models |
| v6 renames old ids and keeps loadouts | Shipyard cards, previews turning, tabs, gamepad selection |
| World builds with no models (greybox fallback) | Pilot seat height on small ships; berth spacing with the wider models |

## Studio hierarchy (new and changed)

```
ReplicatedStorage/Assets/Ships                         NEW imported ship models (assets/roblox/Ships)
ReplicatedStorage/Shared/Util/ShipModel                NEW find and fit a ship's model
ReplicatedStorage/Shared/Config/Ships                  the 11-ship ladder, model fields, RENAMED
ServerScriptService/Server/World/ShipBuilder           model skin + measured effect layout
StarterPlayerScripts/Client/Controllers/ShopController Ships | Upgrades tabs, ship cards
<ship>/Skin                                            the fitted model (cosmetic)
```

## Manual test steps

| # | Steps | Expected |
|---|---|---|
| 1 | Import MicroRecon as in the README; play. | Your hangar ship is the coloured Micro Recon, nose forward, glows at its tail. |
| 2 | Open the Shipyard. | Ships tab: 11 cards, previews turning; #2 NEXT SHIP, #3+ LOCKED. |
| 3 | Buy the Red Fighter (2,500). | Selected; #3 unlocks; relaunch shows the Red Fighter. |
| 4 | Upgrades tab. | Equipment and expansion as before. |
| 5 | Old save with the Prospector. | Loads owning the Red Fighter. |
