# Stage 5: Progression

**Status: code complete, CI-verified (format, lint, strict types, 96 unit tests, build, smoke
test). Not yet playtested in Studio.**

## Playable result

- **Click-to-shoot laser.** Each click (RT, or the Laser button) fires one bolt, at most one every
  0.22 s. A shot adds 9 heat (Starter Shuttle: 12 rapid shots to overheat) and, on an asteroid,
  half a second's worth of beam power (5 progress on a weak point with the Starter Shuttle: a
  Small asteroid takes 5 well-aimed shots). Lasers cool between shots. Everyone sees the bolts.
- **Starting Stardust.** New players start with 100 Stardust, exactly the first star's price.
- **Shipyard** (new console on your station): buy the **Prospector** (2,500) and switch between
  owned ships; buy equipment (Focused Beam Mk II 600, Thrusters Mk II 500, Cooling Mk II 500),
  fitted to every ship you own; buy **galaxy expansions** (6,000 and 40,000), which grow your
  region and raise the star limit from 3 to 6 to 10. Ship and equipment changes apply the next
  time you launch your ship. All prices are Stardust only now.
- **Achievements** pay out automatically with a toast: First Light (first star, +100 and a title),
  Miner 100 (100 asteroids), Star Cluster (3 stars), Cool Head (break an asteroid without
  overheating).
- **Tutorial**: a hint at the top of the screen walks new players through launch, mine, buy a
  star, collect, upgrade. Steps count in any order, from saved stats.

## What CI verifies vs what needs Studio

| Verified by CI | Needs a playtest in Studio |
|---|---|
| Unit tests: per-shot heat and overheat; config checks (at least 4 shots before overheating, starting Stardust covers the first star) | How clicking feels: fire rate, heat per shot, shots per asteroid |
| Unit tests: tutorial step in any order and done at the end; achievements earned once; every enabled achievement and step uses a stat the game counts; shop prices | Shipyard panel: buying, selecting, Stardust deducted once, toasts |
| Strict type check, Rojo build, smoke test | Expansion redraws the region edges larger; a 4th star can then be placed |
| | Achievement toasts and rewards; tutorial hint advances and disappears |

## Studio hierarchy (new and changed)

```
ReplicatedStorage/Remotes/ShopRequest            RemoteFunction NEW buyShip / selectShip / buyEquipment / expand
ReplicatedStorage/Shared/Config/Beam             shots: FIRE_INTERVAL, HEAT_PER_SHOT, SHOT_POWER, BOLT_TIME
ReplicatedStorage/Shared/Config/Tutorial         ModuleScript   NEW steps (stat + hint)
ReplicatedStorage/Shared/Logic/Progression       ModuleScript   NEW tutorial step, achievements, prices
ServerScriptService/Server/Systems/BeamSystem    shots instead of a held beam
ServerScriptService/Server/Systems/MiningSystem  shot() and refresh() instead of step()
ServerScriptService/Server/Systems/ShopSystem    ModuleScript   NEW
ServerScriptService/Server/Systems/ProgressionSystem ModuleScript NEW achievements and tutorial
ServerScriptService/Server/Systems/DataSystem    + statChanged, grantShip, setActiveShip, grantEquipment,
                                                   setExpansion, claimAchievement, grantCosmetic, setTutorialStep
ServerScriptService/Server/Systems/RegionSystem  + resize
StarterPlayerScripts/Client/Controllers/ShopController  NEW Shipyard panel
StarterPlayerScripts/Client/Controllers/HudController   + tutorial hint
Workspace/Ships/Ship_<UserId>                    attributes Shot (counter) and BeamAim replace BeamOn
Workspace/Regions/Region_<slot>/Station/ShipyardConsole  NEW console with "Open Shipyard" prompt
```

New stats: `shipsLaunched`, `collections`, `starUpgrades`.

## Manual test steps

| # | Steps | Expected |
|---|---|---|
| 1 | Play as a new player (or after clearing your save). | Wallet 100. Hint: "Next: Use the Hangar console...". |
| 2 | Launch, board, click at an asteroid's weak point. | One bolt per click; heat bar jumps per shot and cools between; 5 weak-point shots break a Small asteroid. Hint moves on. Holding the button fires only once. |
| 3 | Click as fast as you can for a while. | Overheats after about 12 quick shots; fires again after cooling to 30%. |
| 4 | Buy a star at the Star Shop. | Toast "Achievement: First Light! +100 Stardust, ...". Hint moves to Collect. |
| 5 | Dev command `addStardust 50000`, open the **Shipyard**. | Ships, Equipment and Galaxy rows with prices. |
| 6 | Buy Prospector, Beam Mk II; relaunch at a hangar. | Ship readout shows top speed 140; shots extract faster. |
| 7 | Buy an expansion. | Region edges redraw bigger; the Star Shop allows a 4th star. |
| 8 | Finish the tutorial steps. | "Tutorial complete" toast; the hint disappears and stays gone after rejoining. |

## Known limitations

- Equipment is fitted automatically to every ship; there's no per-ship loadout UI.
- Ship model looks are the same for every ship (Starter Shuttle greybox).
- Cosmetic rewards (titles, beam colours) are owned but not shown anywhere yet.
- The Shipyard panel needs Alt for the mouse while flying; it's meant to be used at the station.
