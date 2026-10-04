# Stage 1: Foundation

**Status: code complete, CI-verified, not yet playtested in Studio.**

## Playable result

You join and appear in a greybox ISS above Earth. You can walk through its modules, see your own
empty galaxy region (and other players' regions) as glowing boxes in the distance, warp to your
personal station and back with the navigation consoles, and step outside to the docking area
through the airlock. Your Credits (0 to start) load from and save to a DataStore.

Stage 1 deliberately keeps normal gravity and uses warps for travel. Zero gravity, spacesuit
movement and ships arrive in Stage 2.

## What CI verifies vs what needs Studio

| Verified by CI on every push | Needs a playtest in Studio |
|---|---|
| Formatting (StyLua) and lint (Selene) | The ISS, Earth and regions look right |
| Strict type check (luau-lsp) | Spawning, walking, warps and airlocks work |
| Unit tests (Lune) for config consistency, region layout, star placement rules and save-data cleanup | Regions are assigned and freed as players join and leave |
| The place builds (Rojo) | Credits save and load; session locking |
| Smoke test: the ISS, Earth, all 8 regions and stations build without errors, within part budgets, with every marker present | Lighting, signs and prompts behave in the real engine |

## Studio hierarchy

Synced by Rojo from the repo:

```
ReplicatedStorage
├── Shared                      Folder         src/shared
│   ├── Config                  ModuleScript   src/shared/Config/init.luau
│   │   ├── World               ModuleScript   layout of a server: ring of regions, Earth, fields
│   │   ├── Materials           ModuleScript   Iron, Silicate, Ice, Crystal, Stellar Gas
│   │   ├── Zones               ModuleScript   Outer, Frozen, Crystal and Nebula belts
│   │   ├── Ships               ModuleScript   five ships with stats and earn costs
│   │   ├── Equipment           ModuleScript   beam, thruster, cooling and cargo upgrades
│   │   ├── Recipes             ModuleScript   Stellar Core, star, planets, moon
│   │   ├── Celestials          ModuleScript   star, planet and moon types with levels
│   │   ├── SolarSystems        ModuleScript   system tiers and their requirements
│   │   ├── Galaxy              ModuleScript   orbits, spacing, region expansions
│   │   ├── Economy             ModuleScript   Credits and the income formula constants
│   │   ├── Cosmetics           ModuleScript
│   │   ├── Achievements        ModuleScript
│   │   └── Products            ModuleScript   Robux products (all disabled)
│   ├── Logic                   Folder
│   │   ├── ConfigCheck         ModuleScript   finds inconsistent config values
│   │   ├── PlacementRules      ModuleScript   where a star may be placed
│   │   ├── ProfileSchema       ModuleScript   default save data and load-time cleanup
│   │   └── RegionMath          ModuleScript   region slots and region coordinates
│   ├── Util                    Folder
│   │   ├── Format              ModuleScript
│   │   └── Signal              ModuleScript
│   ├── Net                     ModuleScript   typed access to the remotes
│   └── Types                   ModuleScript   save schema and remote payload types
└── Remotes                     Folder         default.project.json
    ├── GetInitialState         RemoteFunction client asks for its starting state
    ├── ProfileChanged          RemoteEvent    server tells a client a profile field changed
    └── RegionsChanged          RemoteEvent    server tells everyone who owns which region

ServerScriptService
├── Server                      Script         src/server/init.server.luau
│   ├── Systems                 Folder
│   │   ├── ClientSyncSystem    ModuleScript   answers GetInitialState, broadcasts regions
│   │   ├── DataSystem          ModuleScript   ProfileStore sessions, all profile changes
│   │   ├── DevSystem           ModuleScript   Studio-only test hooks
│   │   ├── NavigationSystem    ModuleScript   warp and airlock prompts
│   │   ├── RegionSystem        ModuleScript   region slots and ownership
│   │   ├── StationSystem       ModuleScript   personal stations
│   │   └── WorldSystem         ModuleScript   lighting, ISS, Earth
│   ├── World                   Folder
│   │   ├── Build               ModuleScript   part, sign, console and prompt helpers
│   │   ├── EarthBuilder        ModuleScript
│   │   ├── IssBuilder          ModuleScript
│   │   ├── RegionBuilder       ModuleScript
│   │   └── StationBuilder      ModuleScript
│   └── Util                    Folder
│       └── RateLimiter         ModuleScript
└── Vendor                      Folder
    └── ProfileStore            ModuleScript   vendor/ProfileStore.luau

StarterPlayer
└── StarterPlayerScripts
    └── Client                  LocalScript    src/client/init.client.luau
        ├── ClientState         ModuleScript   the client's copy of its profile and regions
        └── Controllers         Folder
            ├── HudController   ModuleScript   Credits, sector and hint
            └── WaypointController ModuleScript "Your station" marker
```

Created by code when the game runs (you won't see these in Edit mode):

```
Workspace/World/ISS                 the hub (greybox, or a copy of ServerStorage/Assets/ISS)
Workspace/World/Earth               backdrop
Workspace/Regions/Region_<slot>     one per player: Bounds (12 glowing edges) and Station
Lighting/SpaceSky, SpaceBloom       space lighting (the template's Atmosphere, Sky and effects are removed)
ServerStorage/DevCommand            BindableFunction, Studio only
PlayerGui/Hud, PlayerGui/StationWaypoint
```

### Replacing the greybox ISS

Build your own ISS model in Studio and put it at `ServerStorage/Assets/ISS` (a Model). It must
contain parts named `ArrivalSpawn` (a SpawnLocation), `AirlockInside`, `DockingSpawn`, `Berth1`,
`Berth2` and `Berth3`. For the consoles, add ProximityPrompts with the CollectionService tag
`WarpPrompt` and a string attribute `WarpTarget` set to `OwnStation`, `DockingArea` or
`Interior`. If any marker is missing, the game warns and falls back to the greybox.

## Setup

1. Check out the `stage-1-foundation` branch and run `rokit install`.
2. Open the place in Studio. If it came from the Baseplate template, delete `Baseplate` and
   `SpawnLocation` from Workspace. The game also removes them at runtime and warns.
3. Run `rojo serve` and click **Connect** in the Rojo plugin.
4. For the saving tests, publish the place and enable
   Game Settings → Security → **Enable Studio Access to API Services**.
5. Before going live, set the place's maximum players to 8 (one region per player;
   `Config.World.MAX_PLAYERS`).

## Manual test steps

| # | Steps | Expected |
|---|---|---|
| 1 | Press **Play**. | You spawn on the orange pad in the Arrival module, facing along the station. The output shows `[Grow a Galaxy] server started` and no `[Config]` warnings. |
| 2 | Walk the full length of the station. | Hanging signs read Observation Cupola, Arrival, Mission Terminal, Navigation, Ship Showroom, Upgrade Workshop, Docking Airlock. The cupola has a glass floor with Earth visible below. |
| 3 | Use the Docking Airlock console ("Go outside"). | You appear on the docking platform with three glowing berth outlines. "Go inside" brings you back. |
| 4 | From outside (or with the free camera), look at the station. | Cylindrical modules, a long truss above them, four solar-array assemblies, two radiators, the docking platform, and Earth below with land masses. |
| 5 | Look out at the horizon. | Your region's glowing box edges and your station's beacon with "<your name>'s Galaxy" are visible, plus a "Your station" marker with the distance. HUD shows `Your galaxy: Sector 1`. |
| 6 | Use the Navigation console ("Warp to my station"). | You land on your station's deck facing into your region. The consoles read Navigation, Hangar, Cargo deposit, Collect Credits. |
| 7 | Use the station's Navigation console ("Warp to the ISS"). | You return to the Arrival pad. Using a console again within 2 seconds does nothing. |
| 8 | Test → Clients and Servers → **Local Server** with 3 players. | Each player gets a different sector and region colour, and sees everyone's regions and name tags. Close one client: their region disappears. Start a new client: it takes the free slot. |
| 9 | With API access on, in the server's command bar run `game.ServerStorage.DevCommand:Invoke(game.Players:GetPlayers()[1], "addCredits", 500)`. | The HUD shows 500. Stop, play again: still 500. |
| 10 | With API access on, publish, then open the place in a second Studio window and press Play in both, one after the other. | The first session is kicked with "Your save was opened on another server" (this can take a little while). The second loads the same Credits. Nothing is overwritten. |
| 11 | Turn API access off and press Play. | Output shows ProfileStore's "Roblox API services unavailable - data will not be saved". The game still runs. |
| 12 | During play, open the MicroProfiler (Ctrl+F6) or Script Performance. | No game script shows steady per-frame server work. |

## Acceptance criteria

Verified by CI:

1. Format, lint, strict type check, Lune unit tests, Rojo build and the world-builder smoke
   test all pass.
2. The dropper prototype is gone.
3. Every config table from the spec exists and is typed: materials, zones, five ships with
   trade-offs, equipment, the starting recipes, celestial types with levels, system tiers,
   galaxy expansions, achievements, cosmetics and disabled products.
4. Config tests prove: no system tier needs a level that only it unlocks; every zone's unlock
   uses materials from earlier zones; enabled recipes only need materials from enabled zones;
   orbit radii keep planets and moons apart and inside the system radius; each expansion
   physically fits its system count; every ship is earnable; enabled products have ids.
5. Placement tests prove: a star inside the bounds with enough spacing passes; one too close to
   a wall, too close to another star, malformed, or over the system cap fails.
6. Region tests prove: every region faces the ISS, fully expanded neighbours never overlap, and
   regions stay clear of the Outer Belt and Earth.
7. Save tests prove: a missing or damaged profile is repaired; data from a newer game version is
   refused untouched; unknown ids are kept; ids are never reused.

Needs a Studio playtest (steps above):

8. Spawning, ISS layout and readability (tests 1 to 4).
9. Region assignment, visibility, freeing and ownership-safe warps (tests 5 to 8).
10. Credits persist; a second session cannot overwrite the first (tests 9 and 10).
11. Mock mode works without API access (test 11).
12. No per-frame server work (test 12). The greybox ISS is 176 parts (counted by the smoke test).

## Known limitations

- Normal gravity and warps stand in for zero-g movement and ships until Stage 2.
- The ISS, Earth and stations are greybox geometry built from parts.
- Mission terminal, showroom, workshop, hangar, deposit and collect consoles are placeholders.
- Region slots aren't saved; a returning player may get a different sector (their galaxy will
  load there unchanged once Stage 4 adds building).
- Players beyond `MAX_PLAYERS` are kicked with a "server full" message; set the place's max
  players to match.
- The HUD is basic and has not been checked on phone or console screen sizes.
