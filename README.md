# Grow a Galaxy

A multiplayer space exploration, asteroid mining and galaxy tycoon for Roblox. Players fly
mining ships out of a stylised ISS hub, mine asteroids for materials, and build their own
three-dimensional galaxy of stars, planets and moons.

The game is built in stages. Each stage has its own report in [`docs/`](docs) with the Studio
hierarchy, setup, manual test steps, acceptance criteria and known limitations.

| Stage | Status |
|---|---|
| 1. Foundation: config, save data, ISS hub, galaxy regions | [Merged](docs/stage-1-foundation.md) |
| 2. Movement and ships: zero-g suit, Starter Shuttle, flight, docking, mining laser | [In review](docs/stage-2-movement-ships.md) |
| 3. Mining | Not started |
| 4. Galaxy construction | Not started |
| 5. Progression | Not started |
| 6. Persistence | Not started |
| 7. Polish | Not started |
| 8. Monetization | Not started |
| 9. Expansion | Not started |

Code is written outside Studio and checked by CI (format, lint, type check, unit tests, build,
and a smoke test that runs the world builders).
**CI cannot run the game**, so every stage report separates what CI verified from what still
needs a playtest in Studio.

## Working on it in Roblox Studio

1. Install [Rokit](https://github.com/rojo-rbx/rokit), then run `rokit install` in this folder.
   It installs the pinned Rojo, StyLua, Selene, Lune and luau-lsp.
2. Install the Rojo plugin in Studio (`rojo plugin install`, or Plugins → Manage Plugins).
3. Run `rojo serve` in this folder.
4. In Studio, open the game's place (or a new Baseplate), open the Rojo plugin and click
   **Connect**. Code changes in `src/` now sync into Studio live.
5. To test saving, publish the place and turn on Game Settings → Security →
   **Enable Studio Access to API Services**. Without it, ProfileStore runs in mock mode and
   prints that data will not be saved.

## Project layout

| Folder | Studio location | What lives there |
|---|---|---|
| `src/shared` | ReplicatedStorage/Shared | Config, save schema types, pure logic, remotes access |
| `src/shared/Config` | ReplicatedStorage/Shared/Config | Every tunable number (prices, stats, recipes, sizes) |
| `src/shared/Logic` | ReplicatedStorage/Shared/Logic | Pure rules shared by client and server, unit-tested |
| `src/server` | ServerScriptService/Server | Server bootstrap, Systems, world builders |
| `src/client` | StarterPlayer/StarterPlayerScripts/Client | Client bootstrap, state, input layer, controllers |
| `vendor` | ServerScriptService/Vendor | ProfileStore (Apache-2.0, by loleris) |
| `tests` | not synced | Lune unit tests for `src/shared/Logic`, and the world smoke test |

Remotes are declared in `default.project.json` under ReplicatedStorage/Remotes and used only
through `src/shared/Net.luau`.

Tuning: edit the modules in `src/shared/Config`. The server checks them for inconsistencies at
startup (`Logic/ConfigCheck`), and so do the unit tests.

## Checks

```sh
stylua --check src tests      # format
selene src                    # lint
lune run tests/run            # unit tests
rojo build -o build.rbxl      # build a place file
lune run tests/WorldSmoke build.rbxl   # run the world builders outside Studio
```

CI also type-checks with luau-lsp (see `.github/workflows/ci.yml`).
