# Grow a Galaxy 2

A Roblox space game. You float around a space station, fly a little ship out to mine asteroids
for Stardust, and spend it building your own galaxy: stars you place in 3D, with planets
orbiting them that you hatch from eggs. Stars and planets earn more Stardust, which you spend on
bigger stars, better ships and more eggs.

There's also opt-in PvP, Death Star raids, a zero-g dodgeball arena, a daily wheel and a bunch
of hangar upgrades to show off.

## What's in there

Roughly, by area:

- **Flying and mining**: spacesuit movement (or walking, if you turn floating off), 11 ships,
  click-to-shoot mining laser, asteroids with weak points, golden asteroid swarms.
- **The tycoon**: 8 star types up to a black hole, levelling and evolving, up to 9 orbits per
  star, 28 planet types in 6 rarities with their own looks.
- **Eggs**: buy planet eggs at the ISS, hatch them in your hangar's incubator (keeps going
  while you're offline), then equip, level, lock or sell planets.
- **Your station**: the hangar deck, upgrade pads, a showcase dock for ships, a highlight
  colour you can pick.
- **Social and extras**: visiting other players' hangars, raids, dodgeball, daily prizes and
  wheel, codes, achievements, a kid-friendly tutorial.
- **Monetization**: a few game passes and dev products, wired up but only active with real ids
  configured.

[`PROGRESS.md`](PROGRESS.md) has the stage-by-stage history and what still needs testing in
Studio. Each stage has its own notes in [`docs/`](docs) (what changed, how to test it, known
gaps). [`CLAUDE.md`](CLAUDE.md) has the conventions and the full list of checks.

## How it's built

Everything is written in VS Code and synced into Studio with Rojo. The place file is close to
empty: the ISS, Earth, player regions, stations, ships and asteroids are all built by code when
the server starts (`src/server/World`). The only things made in Studio are the imported ship
models, music and a couple of boss assets, saved as `.rbxm` files under `assets/roblox`.

- `src/shared` is synced to ReplicatedStorage. It holds `Config` (every number you'd want to
  tweak), `Logic` (pure game rules with unit tests), the save types and the remote access
  (`Net.luau`).
- `src/server` holds the server systems and world builders.
- `src/client` holds the client controllers and UI.
- `src/first` is the loading screen (ReplicatedFirst).
- `vendor` is ProfileStore (by loleris) for saving.
- `tests` holds Lune tests, which aren't synced.

The server is authoritative for anything that matters (Stardust, saves, purchases, egg rolls);
the client does input, camera, UI and effects. Config is sanity-checked at server start and in
the tests, so a bad tuning edit shows up straight away.

## Getting set up

1. Install [Rokit](https://github.com/rojo-rbx/rokit) and run `rokit install` here. That gets
   the pinned Rojo, StyLua, Selene, Lune and luau-lsp. (On Windows the tools end up in
   `%USERPROFILE%\.rokit\bin`, which you may need to add to PATH.)
2. Install the Rojo plugin in Studio (`rojo plugin install`).
3. Run `rojo serve default.project.json`, open the place in Studio and hit Connect in the Rojo
   plugin.
4. Saving only works on a published place with **Enable Studio Access to API Services** turned
   on. Otherwise ProfileStore runs in mock mode and nothing is kept.

## Checks

CI runs the same thing:

```sh
stylua --check src tests
selene src
lune run tests/run
rojo sourcemap default.project.json -o sourcemap.json
luau-lsp analyze --sourcemap=sourcemap.json --definitions=globalTypes.d.luau --ignore="**/ProfileStore.luau" src
rojo build -o build.rbxl && lune run tests/WorldSmoke build.rbxl && lune run tests/OrbitSmoke build.rbxl
```

The smoke tests build the world and spin up the orbit code outside Studio, which catches a lot,
but nothing here can actually play the game. Anything about feel, UI layout or saving still
needs a playtest.
