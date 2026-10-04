# Stage 3: Stardust and asteroid mining

**Status: code complete and CI-verified. In Studio (2026-10-04, via the Studio MCP): every
Stage 3 script synced through Rojo, and a playtest started with no errors (`server started`,
`client started`, no `[Config]` warnings). Mining itself is not yet playtested.**

This stage follows the design revision: **Stardust** is the one currency, asteroids are scattered
across the whole map instead of sitting in mining fields, and mining pays Stardust directly (no
cargo, no materials, no deposits).

## Playable result

When the server starts it fills the space around the ISS with about 110 asteroids in small
clusters: grey, lumpy rocks in three sizes, each with a glowing cyan weak point. They sit
between the ISS and the player regions, in the gaps between regions and beyond them, but never
near the ISS, inside any region (owned or not), on a personal station, or on top of a ship or
player.

While you fly, up to five cyan diamond markers show the nearest asteroids within 2500 studs, with
their distance; a marker turns grey when someone else is mining that asteroid. Asteroids are
replicated to every client however far away, so you can see distant clusters.

Fly up to one and hold the laser on it. An **EXTRACTING** bar fills under the heat gauge. On
plain rock it fills slowly; on the weak point it fills at the ship's full beam power, the bar turns
cyan, and the weak point gets a white outline. As progress rises the rock glows orange and cracks.
When the bar is full the asteroid bursts into debris with an explosion sound and you get Stardust
at once, with a toast
such as `+33 Stardust (Medium asteroid, +3 precision bonus)`. The more of the work you did on the
weak point, the bigger the bonus (up to +25%).

Heat still matters: a Medium asteroid takes about as long as the beam can fire before it
overheats, and a Large one needs a cooling pause. While you mine an asteroid it is reserved for
you; anyone else who tries gets a toast. If you stop hitting it for 6 seconds, it is released and
its progress resets. New asteroids appear every few seconds to replace mined ones.

Credits are now **Stardust** everywhere: HUD, configs, save data. Existing saves keep their
balance through a schema migration (version 1 to 2).

## What CI verifies vs what needs Studio

| Verified by CI on every push | Needs a playtest in Studio |
|---|---|
| Format, lint, strict type check, Rojo build | How mining feels: extraction speed, rewards, heat pressure |
| Unit tests: extraction rate on rock vs weak point, rewards and the precision bonus (rounded, never below base), reservations (owner, busy, lapsed) | The server's ray agrees with what the pilot sees (it uses the server's copy of the ship's position) |
| Unit tests: spawn rules reject spots near the ISS, outside the height/distance band, inside every region slot at full expansion, on every station, too close to other asteroids, ships or players; the volume fits MAX_COUNT asteroids | Asteroids are easy enough to find, and the field looks good |
| Unit tests: Credits migrate to Stardust without losing the balance, even if a template default was filled in first | The extraction bar, weak-point outline, cracking glow and debris burst |
| Config checks: asteroid sizes, population caps, spawn volume inside the flight area, stations covered by REGION_CLEARANCE, every ship's beam reaches past the largest asteroid | Reservations with two players; respawning keeps the population up |
| Smoke test: every asteroid size builds with its rock, lumps and a non-colliding neon weak point that pokes out of the rock, stays inside its placement extent and streams persistently | Performance with ~110 asteroids (about 440 anchored parts) |
| Config checks: scanner values positive, break sound is an rbxasset URI | Scanner markers point at the right asteroids; the break sound plays |
| **Studio (done):** all Stage 3 scripts present after Rojo sync; playtest starts without errors | |

## Studio hierarchy

New and changed items only.

```
ReplicatedStorage/Shared
├── Config
│   ├── Asteroids        ModuleScript  NEW sizes, population, spawn rules, mining, looks
│   ├── Economy          ModuleScript  Stardust (was Credits)
│   └── (Ships, Equipment, Galaxy, Celestials, SolarSystems, Zones, Achievements)
│                                      cost fields renamed credits -> stardust
├── Logic
│   ├── AsteroidField    ModuleScript  NEW where asteroids may spawn (pure, unit-tested)
│   ├── MiningMath       ModuleScript  NEW extraction rate, reward, reservations
│   ├── ProfileSchema    ModuleScript  schema v2: credits -> stardust migration
│   ├── RegionMath       ModuleScript  + toLocal
│   └── ConfigCheck      ModuleScript  + asteroid checks
└── Types                ModuleScript  Profile.stardust, ShipInfo.beamPower

ServerScriptService/Server
├── Systems
│   ├── AsteroidSystem   ModuleScript  NEW spawning, registry, reservations, breaking
│   ├── MiningSystem     ModuleScript  NEW server raycast, extraction, payout
│   ├── BeamSystem       ModuleScript  calls MiningSystem each tick
│   ├── DataSystem       ModuleScript  addStardust, spendStardust, addStat
│   └── DevSystem        ModuleScript  addStardust (was addCredits), asteroids
└── World
    └── AsteroidBuilder  ModuleScript  NEW greybox asteroid

StarterPlayer/StarterPlayerScripts/Client/Controllers
├── AsteroidController   ModuleScript  NEW cracking glow, weak-point outline, debris burst
└── HudController        ModuleScript  Stardust wallet, extraction bar
```

Created by code when the game runs:

```
Workspace/Asteroids/Asteroid_<id>    Model (Persistent streaming), PrimaryPart = Rock
                                     attributes: AsteroidId, Size, Progress, ReservedBy, Broken
  Rock, Lump1, Lump2                 anchored balls
  WeakPoint                          neon ball, CanCollide off
Workspace/Ships/Ship_<UserId>        + attributes MiningTarget, MiningProgress, MiningWeak
Workspace/Camera/GaG_WeakPointHighlight   Highlight (client only)
Workspace/Camera/GaG_AsteroidScanner      5 BillboardGui markers (client only)
Workspace/Terrain/GaG_AsteroidBurst       debris burst and break Sound (client only, removed after 3 s)
```

Save data: `stardust` replaces `credits`; `stats.asteroidsMined` counts broken asteroids and
`stats.coolExtractions` those broken without the beam overheating (for the "Mine 100 asteroids"
and "Cool Head" achievements later). `materials` and `cargo` stay in the schema but nothing
uses them.

## Setup

None beyond Stage 2. With `rojo serve` running and the plugin connected, the new files sync on
their own.

## Manual test steps

| # | Steps | Expected |
|---|---|---|
| 1 | Press **Play**. | The wallet reads **STARDUST**. No `[Config]` warnings. In the server command bar, `game.ServerStorage.DevCommand:Invoke(game.Players:GetPlayers()[1], "asteroids")` returns about 110. |
| 2 | Launch your ship at the ISS and fly out about 800 studs in any direction. | Scanner diamonds with distances point at the nearest asteroids, visible from far away. Clusters of 2 to 5 grey asteroids with glowing cyan weak points. None within ~700 studs of the ISS, none inside region boundaries, none at your station. |
| 3 | Hold the laser on the rock of a Small asteroid, away from the weak point. | The EXTRACTING bar appears and fills slowly (about 8 s of beam time for a Small rock with the Starter Shuttle). The hint says to aim at the weak point. |
| 4 | Move the reticle onto the weak point. | The bar turns cyan and fills about three times faster; the weak point gets a white outline; the rock glows orange, then cracks past halfway. |
| 5 | Keep going until it breaks. | Debris burst and an explosion sound, the asteroid disappears, toast `+N Stardust (...)`, and the wallet goes up by N. Mostly weak-point work gives a bonus (Small: 12 base, up to 15). |
| 6 | Mine a Large asteroid on its weak point. | The laser overheats before it breaks. Wait for the cooldown, resume: progress is kept (under 6 s). |
| 7 | Start on an asteroid, fly away for 10 s, come back. | Its glow is gone and progress starts from zero. |
| 8 | Local Server, 2 players. Player 1 mines an asteroid; player 2 fires at the same one. | Player 2's scanner marker for it is grey. Player 2's bar doesn't appear and they get "Someone else is mining that asteroid". 6 s after player 1 stops, player 2 can take it over (from zero). |
| 9 | Mine several asteroids, then wait 10 to 20 s and rerun the `asteroids` dev command. | The count climbs back towards 110 and never goes above 140. |
| 10 | Stop the game and play again (published place with API access on). | Stardust balance is kept. A save from before this stage shows its old Credits balance as Stardust. |
| 11 | Watch the Server stats (Shift+F2) and the client FPS while flying through the field. | No noticeable cost from the asteroids. |

## Acceptance criteria

Verified by CI:

1. Format, lint, strict type check, Lune unit tests (85), Rojo build and the smoke test pass.
2. Spawn rules keep asteroids out of the ISS clearance, every region slot at full size, every
   station, and away from each other, ships and players; the volume holds MAX_COUNT (unit tests).
3. Extraction rate, reward with precision bonus and reservations behave as configured (unit tests).
4. Credits migrate to Stardust without loss (unit tests).

Needs a Studio playtest (steps above):

5. Asteroids fill the map in clusters and respawn up to the target, never past the maximum (1, 2, 9).
6. Beam mining with weak points, heat and visual feedback; Stardust paid exactly once (3 to 6).
7. Reservations release after inactivity and block competing miners (7, 8).
8. Stardust persists, including migrated Credits (10).

## Tuning

`src/shared/Config/Asteroids.luau`: sizes (radius, weak-point size, durability, reward, spawn
weight), population (target, maximum, cluster size and spread, spawn interval), spawn area
(ISS clearance, distance, height, region clearance, gaps), mining (rock efficiency, precision
bonus, reservation timeout), scanner (range, marker count, interval), break sound and colours. Ship beam power and range are in `Config/Ships.luau`.

## Known limitations

- Untested in Studio (right-hand column above).
- Only the break has a sound (Roblox's built-in `impact_explosion_03`). Beam hum and impact sounds
  need audio assets; none were invented.
- Scanner markers only show asteroids that are on screen; there is no off-screen arrow.
- Weak points are static; moving or multi-stage weak points are for later asteroid types.
- The server traces the beam from its own copy of the ship's position, which trails the pilot's
  screen slightly. At beam ranges of 120+ studs this should be invisible, but very fast sweeps
  across a small weak point may count as rock for a tick.
- If asteroids turn out to be hard to find, raise `TARGET_COUNT` or `SCAN_RANGE`, or lower
  `HEIGHT` and `MAX_DISTANCE`.
- Achievements (including "Mine 100 asteroids") aren't awarded yet; the stat is counted.
- Configs for later stages still list material costs next to Stardust costs (ships, equipment,
  celestials, expansions). Stage 4 replaces the celestial and tier configs with the star-upgrade
  model; ship and equipment costs become Stardust-only when the shop arrives.
