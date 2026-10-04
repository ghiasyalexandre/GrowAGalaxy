# Progress

Last updated: 2026-10-04 (branch `stage-2-movement-ships`).

## Status by stage

| Stage | Code | CI | Studio playtest |
|---|---|---|---|
| 1. Foundation | Merged | Passing | Loads without errors |
| 2. Movement and ships | Merged | Passing | Loads without errors; feel **not yet** |
| 3. Stardust and asteroid mining | Merged | Passing | Loads without errors; mining **not yet** |
| 4. Star tycoon | Merged | Passing | **Not yet** |
| 5. Progression (click laser, Shipyard, expansions, achievements, tutorial) | Branch `stage-5-progression` | Passing locally (96 tests) | **Not yet** |
| 6+. Persistence hardening, polish, monetization | Not started | | |

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

**Stage 6: persistence and polish.** Playtest-driven tuning of stages 2-5; a save-safety pass
(publish with API access, rejoin tests, session-lock behaviour); settings (stabilizer, look
sensitivity) saved; per-ship visual differences for the Prospector; showing cosmetic rewards.

## Open issues and debts

- `Config.Materials`, `Config.Recipes`, `Config.Zones`, `Config.Celestials`, `Config.SolarSystems`
  and the profile's `materials`/`cargo` are unused leftovers of the original design (still
  config-checked); remove them once the revised design settles.
- Only the asteroid break has a sound (a built-in Roblox sound); others need audio assets.
- `rokit.toml` has an uncommitted bump of Rojo from 7.4.4 to 7.7.1 (made before this session); the
  CI uses the same file.
