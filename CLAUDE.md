# Grow a Galaxy: working notes

Stable instructions for working on this repo. Implementation status lives in
[PROGRESS.md](PROGRESS.md); per-stage details (hierarchy, test steps, limitations) live in
[docs/](docs). Don't duplicate either here.

## Source of truth

- Code lives in `src/` and syncs into Studio through Rojo (`default.project.json`, the only
  project file). Never edit Rojo-managed scripts in Studio; edit the files.
- The world (ISS, Earth, regions, stations, ships, asteroids) is **built by code at runtime**
  (`src/server/World/*Builder.luau`). The place file holds almost nothing. To replace a greybox
  with a hand-built model, follow the contract in the stage docs (e.g. `ServerStorage/Assets/ISS`
  with the named markers); keep such assets in a Rojo-mapped `.rbxm` so syncing can't lose them.
- Rojo syncing does not save or publish the place.

## Mapping

| Folder | Studio |
|---|---|
| `src/shared` | ReplicatedStorage/Shared (Config, Logic, Types, Net, Util) |
| `src/server` | ServerScriptService/Server (Systems, World builders, Util) |
| `src/client` | StarterPlayer/StarterPlayerScripts/Client (Controllers, Input, ClientState) |
| `src/first` | ReplicatedFirst (the loading screen; runs before Shared exists, so its settings live in the script) |
| `vendor` | ServerScriptService/Vendor (ProfileStore) |
| `tests` | not synced; Lune unit tests and the world smoke test |
| `assets/roblox/Ships` | ReplicatedStorage/Assets/Ships (imported ship models as `.rbxm`, saved from Studio) |
| `assets/roblox/Music` | ReplicatedStorage/Assets/Music (SpaceMusic, SpaceDisco Sounds) |
| `assets/roblox/Stuff`, `assets/roblox/Bosses` | ServerStorage/Assets (Saturn V beacon, Death Star) |
| `assets` (the rest) | not synced; source art (`assets/models`: ship OBJs with palettes). The UI kit is packed into `assets/ui/GaG_UI_Atlas.png` by `tools/pack_ui_atlas.py` (writes `Config/SpriteAtlas.luau`); the atlas is uploaded to Roblox by hand |

Remotes are declared in `default.project.json` (ReplicatedStorage/Remotes) and accessed only via
`src/shared/Net.luau`. Add new remotes in both places.

## Tools (Windows)

Rokit installs the pinned tools into `%USERPROFILE%\.rokit\bin`, which is **not on PATH** on this
machine. Prefix commands or fix PATH for the session:

```powershell
$env:Path = "$env:USERPROFILE\.rokit\bin;$env:Path"   # PowerShell
```
```sh
export PATH="$HOME/.rokit/bin:$PATH"                  # Git Bash
```

Serve with `rojo serve default.project.json` (port 34872). Check first whether one is already
running (`http://localhost:34872/api/rojo`).

## Checks (same as CI; run all before reporting work done)

```sh
stylua --check src tests
selene src
lune run tests/run
rojo sourcemap default.project.json -o sourcemap.json
luau-lsp analyze --sourcemap=sourcemap.json --definitions=globalTypes.d.luau --ignore="**/ProfileStore.luau" src
rojo build -o build.rbxl && lune run tests/WorldSmoke build.rbxl && lune run tests/OrbitSmoke build.rbxl
```

`globalTypes.d.luau` comes from the URL in `.github/workflows/ci.yml`. Files must stay LF
(`.gitattributes`); StyLua rejects CRLF.

CI cannot run the game. Always separate "verified by CI" from "needs a Studio playtest", and
never claim sync, play, save or publish worked without evidence.

## Code conventions

- `--!strict` everywhere. Tunable numbers go in `src/shared/Config/*`, never in logic.
  `Logic/ConfigCheck` validates config at server start and in tests; extend it with new config.
- Pure rules go in `src/shared/Logic/*` (no Roblox services) with a spec in `tests/specs/` and
  an entry in `tests/run.luau`.
- Server systems are ModuleScripts in `src/server/Systems` with optional `init()` (create
  instances) and `start()` (connect events); neither may yield. Client controllers are the same.
- Server-authoritative: validate every remote (type, rate limit via `Util/RateLimiter`,
  ownership). Clients only do input, camera, previews, UI and cosmetic effects.
- Profiles: change them only through `DataSystem` functions. Schema changes bump
  `ProfileSchema.VERSION` with an explicit migration and a test; never reset data on failure.
- Match the existing comment style: a header comment per module explaining its job and contract.

## Design (current)

The design revision of Oct 2026 overrides the original spec where they conflict:

- **Stardust** is the only currency. Earned from mining (paid at once) and from stars (accrues
  as uncollected, collected at the station). No materials, crafting, cargo or deposits in the MVP.
- Asteroids spawn randomly across the map (not in fields), with weak points and beam heat.
- The tycoon: buy stars with Stardust and place them in 3D in your region; upgrade a star to add
  orbiting planets and raise its production. Moons and planet development come later.
- Save stars as id, position relative to the region, type, appearance, level. Derive planets and
  orbits from level plus config.
- PvP is opt-in only (a saved setting, off by default; both pilots must have it on; docking
  areas are safe). Ships explode at 0 hull; nothing is lost but a short relaunch wait.
- Offline income: stars pay for time away (current rate, passes and trail, no boosts), capped
  at 1 day, into the wallet on return (Config.Economy, Logic/OfflineMath).
- Excluded from the MVP: trading, stealing, gravitational simulation.
- Monetization only after core gameplay and saving are reliable. Never invent product ids or
  enable purchases without configured products.

## Studio / MCP

A Roblox Studio MCP server is configured for Claude Desktop (`%LOCALAPPDATA%\Roblox\mcp.bat`),
not for Claude Code. Without it, Studio state can't be inspected from here; ask the user to
playtest and report Output errors.
