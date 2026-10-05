# Progress

Last updated: 2026-10-05 (stage 15 merged into `main`).

## Status by stage

| Stage | Code | CI | Studio playtest |
|---|---|---|---|
| 1. Foundation | Merged | Passing | Loads without errors |
| 2. Movement and ships | Merged | Passing | Loads without errors; feel **not yet** |
| 3. Stardust and asteroid mining | Merged | Passing | Loads without errors; mining **not yet** |
| 4. Star tycoon | Merged | Passing | **Not yet** |
| 5. Progression (click laser, Shipyard, expansions, achievements, tutorial) | Merged | Passing | **Not yet** |
| 6. Atmosphere and polish (sparkles, saved settings, ship paint, Golden Beam) | Merged | Passing | **Not yet** |
| 7. Star and planet tiers | Merged | Passing (101 tests) | **Not yet** |
| 8. UI juice and reward effects | Merged | Passing (101 tests) | **Not yet** |
| 9. Boost, laser feel, Star Shop button, isolated controller start-up | Merged | Passing (104 tests) | **Not yet** |
| 10. Stellar spectacle (star/planet effects, celebrations, shop icons, Next Goal, achievements) | Merged | Passing (105 tests) | **Not yet** |
| 11. Sprite sheet UI (needs the sheet uploaded and its id in Config/Sprites) | Merged | Passing (107 tests) | **Not yet** |
| 12. UI kit atlas (replaces the stage 11 sheet), hover animations, vivid sparkles | Merged | Passing (107 tests) | **Not yet** |
| 13. Evolution ladder (max level per tier, reset on evolve), orbits per tier, lit planets, inspector | Merged | Passing (118 tests) | **Not yet** |
| 14. 11-ship ladder in unlock order, imported ship models, Shipyard Ships tab with previews | Merged | Passing (120 tests) | **Not yet** |
| 15. Opt-in PvP, hull points, ship explosions with debris, over-the-shoulder camera (Alt), slower laser bolts | Merged | Passing (125 tests) | **Not yet** |
| 16+. Save hardening, tuning, monetization | Not started | | |

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

0. Upload `assets/ui/GaG_UI_Atlas.png` to Roblox and put its id in
   `src/shared/Config/Sprites.luau` (`IMAGE`) in VS Code; see [stage 12](docs/stage-12-ui-kit.md).

   Import the ship models (`assets/models/*.obj`, with their `.mtl` and `.png`) with Studio's
   3D Importer and save each as `assets/roblox/Ships/<Name>.rbxm`; see
   [assets/roblox/Ships/README.md](assets/roblox/Ships/README.md). Galactix Racer, Warship and
   Meteor Slicer have no model yet (greybox until then).

1. Studio playtest of stages 2 and 3 (test tables in the stage docs): how flying and mining
   feel. Report anything that feels wrong.
2. To test saving: publish the place and turn on Game Settings > Security > Enable Studio Access
   to API Services (the place is `Grow-a-Galaxy-2.rbxl` in `F:\RobloxGames\Grow_A_Galaxy\`).
3. If the Roblox_Studio MCP shows "Connection closed" in a Claude Code session (it doesn't retry
   when Studio wasn't ready at startup), reconnect it with `/mcp`.

## Next up

**Playtest pass (needs the user).** The user reported (2026-10-04) that the Star Shop console
didn't open; the cause wasn't found by reading the code. Stage 9 adds a button and B key, and
logs any controller failure in Output; check for `failed:` lines. Stages 2-10 are untested in Studio beyond loading without
errors. Priorities: laser feel, mining pace, star/planet prices (Config/Stars, Config/Planets),
placement controls, and whether the reward effects read well. Then save hardening on a published
place, and the next content (more achievements for the new tiers, sounds once audio assets
exist, monetization only after saves are proven).

## Open issues and debts

- `Config.Materials`, `Config.Recipes`, `Config.Zones`, `Config.Celestials`, `Config.SolarSystems`
  and the profile's `materials`/`cargo` are unused leftovers of the original design (still
  config-checked); remove them once the revised design settles.
- Only the asteroid break has a sound (a built-in Roblox sound); others need audio assets.
- `rokit.toml` has an uncommitted bump of Rojo from 7.4.4 to 7.7.1 (made before this session); the
  CI uses the same file.
