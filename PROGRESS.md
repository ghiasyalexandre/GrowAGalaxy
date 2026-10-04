# Progress

Last updated: 2026-10-04 (branch `stage-2-movement-ships`).

## Status by stage

| Stage | Code | CI | Studio playtest |
|---|---|---|---|
| 1. Foundation | Merged | Passing | Loads without errors |
| 2. Movement and ships | Merged | Passing | Loads without errors; feel **not yet** |
| 3. Stardust and asteroid mining | Merged | Passing | Loads without errors; mining **not yet** |
| 4. Star tycoon | Branch `stage-4-star-tycoon` | Passing locally (91 tests) | **Not yet** |
| 5+. Galaxy expansion, ship shop, achievements, tutorial, polish, monetization | Not started | | |

## What works in code (unverified in Studio)

- Star tycoon: buy and place stars with a ghost preview, upgrade them to add orbiting planets,
  move whole systems, collect star income at the station ([stage 4](docs/stage-4-star-tycoon.md)).

- Zero-gravity suit, Starter Shuttle launch/board/fly/exit, assisted docking, Return to Station,
  flight guard, mining laser with heat ([stage 2](docs/stage-2-movement-ships.md)).
- Stardust currency with a schema v1 to v2 migration (Credits balance carried over).
- ~110 asteroids in clusters across the map, respawning; beam mining with weak points, heat,
  reservations, exactly-once Stardust payout, HUD extraction bar, crack, burst and break sound,
  scanner markers for the nearest five, stats for asteroids mined and cool extractions
  ([stage 3](docs/stage-3-stardust-mining.md)).

## Verified in Studio (2026-10-04, through the Studio MCP)

- Rojo sync: every Stage 3 script is present in the open place.
- A playtest starts with `[Grow a Galaxy] server started` and `client started`, no errors and no
  `[Config]` warnings. ProfileStore runs in mock mode (API services off), so nothing saves.

## Needs the user

1. Studio playtest of stages 2 and 3 (test tables in the stage docs): how flying and mining
   feel. Report anything that feels wrong.
2. To test saving: publish the place and turn on Game Settings > Security > Enable Studio Access
   to API Services (the place is `Grow-a-Galaxy-2.rbxl` in `F:\RobloxGames\Grow_A_Galaxy\`).
3. If the Roblox_Studio MCP shows "Connection closed" in a Claude Code session (it doesn't retry
   when Studio wasn't ready at startup), reconnect it with `/mcp`.

## Next up

**Stage 5: progression.** Buy galaxy expansions (Stardust-only costs), the hangar ship shop
(Prospector, earnable; compare, unlock, select) and beam/equipment upgrades, the achievement
system (stats already counted: asteroidsMined, coolExtractions, starsPlaced) with one award
wired up, and a short tutorial. Then drop the deferred material costs from configs.

## Open issues and debts

- Configs for later stages still list material costs next to Stardust (ships, equipment,
  expansions, zones). Make them Stardust-only when those features are built; `Config.Materials`,
  `Config.Recipes`, `Config.Zones` and the profile's `materials`/`cargo` are deferred.
- Only the asteroid break has a sound (a built-in Roblox sound); others need audio assets.
- Achievements are counted (`stats.asteroidsMined`, `stats.coolExtractions`) but not awarded.
- `rokit.toml` has an uncommitted bump of Rojo from 7.4.4 to 7.7.1 (made before this session); the
  CI uses the same file.
