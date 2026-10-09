# Progress

Last updated: 2026-10-05 (stage 46 merged into `main`).

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
| 16. Hangar station rebuild, hangar upgrade pads, HUD Shipyard and Launch Ship buttons | Merged | Passing (129 tests) | **Not yet** |
| 17. Optional Robux purchases: passes, boosts, packs, ship passes, Galaxy Store, boost HUD (all switched off, no ids) | Merged | Passing (145 tests) | **Not yet** |
| 18. Daily prizes (14-day calendar), flashier Galaxy Store, premium shortcut (ship / black hole) | Merged | Passing (151 tests) | **Not yet** |
| 19. Roomier ISS (lounge, playground, showroom), Saturn V raid beacon, Death Star raids (Easy / Medium / Hard queues) | Merged | Passing (157 tests) | **Not yet** |
| 20. Floating lean, floor clearance and suit thruster sound (default walking sounds muted), showroom spin fix, Death Star overhaul (moving weak point, drones, shockwaves, Hard bombardment, enrage), random asteroid groups, curved progression | Merged | Passing (166 tests) | **Not yet** |
| 21. Vanity hangar + Showcase Dock, ship paint and finish, 5-level equipment, Settings panel and music, vertical shop buttons, solar flares, golden swarms, steeper whole-number progression, closer stars, star panel and orbit hardening | Merged | Passing (168 tests + orbit smoke) | **Not yet** |
| 22. Hangar / Station travel buttons, Zero G Dodgeball arena (portal, cover blocks, block launches, sun-balls) | Merged | Passing (173 tests) | **Not yet** |
| 23. Hidden pilot, laser/boost colours (paint removed), ship rockets, top flight HUD, controls-hint setting, Stardust trails, tougher richer golden asteroids | Merged | Passing (175 tests) | **Not yet** |
| 24. Planet levels 1-5 (x3 income, slightly bigger, moons), planet atmospheres and effects, pricier expansions | Merged | Passing (177 tests) | **Not yet** |
| 25. Live Roblox products connected (3 passes, 2 developer products), Black Hole badge, premium price tag | Merged | Passing (178 tests) | **Not yet** (no live purchase tested) |
| 26. Stardust leaderboard store (OrderedDataStore `StardustLeaderboard`, scope `global`, units Stardust; current balance) | Merged | Passing (178 tests) | **Not yet** |
| 27. Store: repeat purchases never stick on Waiting, Small Stardust Pack = 25,000, compact phone layout, gamepad tabs/close | Merged | Passing (179 tests) | **Not yet** |
| 28. Premium icon under panels, list scroll kept on refresh, orbit rings only for bought planets, Showcase Dock spin fix + white pads, redeemable codes (ILUVGHIASY = 5,000,000 Stardust) | Merged | Passing (180 tests) | **Not yet** |
| 29. Offline star income (up to 3 days, into the wallet on return), Stardust in the player list (leaderstats) | Merged | Passing (183 tests) | **Not yet** |
| 30. Overhaul stage 1: star placement fixed (footprint discs, separate height margin, ghost on an aim plane clamped into a drawn build box, starts at the nearest valid spot, on-screen controls, specific reasons) | Merged | Passing (185 tests) | **Not yet** |
| 31. Overhaul stage 2: owned planets (28 types, 6 rarities, levels 1-5, distinct looks), planet inventory and Planets panel, equip/move/unequip with income settled first, 3-9 orbits per star, save v15 migration ([doc](docs/stage-31-planet-inventory.md)) | Merged | Passing (197 tests + orbit smoke) | **Not yet** |
| 32. Overhaul stage 3: ISS Planet Egg Lab (mystery eggs with exact odds rolled and saved on the server at purchase, chosen-planet eggs, PolicyService paid-random-item check with a safe "unknown" default, odds and details disclosure) ([doc](docs/stage-32-planet-eggs.md)) | Merged | Passing (205 tests) | **Not yet** |
| 33. Overhaul stage 4: hangar Incubator Bay with 5 chambers (atomic start, unix timestamps so eggs hatch offline, exactly-once grant that frees the chamber, offline summary, forming and reveal visuals, visitors view only) ([doc](docs/stage-33-hangar-incubator.md)) | Merged | Passing (211 tests) | **Not yet** |
| 34. Overhaul stage 5: Daily Wheel (free spin every 24 h, server picks and grants before the animation, fixed prizes and shown odds, reduced-motion spin) ([doc](docs/stage-34-daily-wheel.md)) | Merged | Passing (215 tests) | **Not yet** |
| 35. ISS directory, Top Stardust board, Daily Wheel kiosk, rare-hatch board and planet gallery; planet selling, locking, bulk and auto-sell, filters, Equip best, Planet Index; multi-buy eggs, auto-incubate with offline chaining, Fill all; Floating off (walk on floors); save v16 ([doc](docs/stage-35-iss-gacha-inventory.md)) | Merged | Passing (225 tests) | **Not yet** |
| 36. Daily Wheel spins cost 1,000 Stardust (still once a day, paid-random-item policy applies); planet storage 200 | Merged | Passing | **Not yet** |
| 37. Full kid-friendly tutorial (13 steps, device-specific words, HUD arrows, world markers, How to play guide, finish reward), star prompts from 90 studs, station/hangar/arena glow dimmed 20% ([doc](docs/stage-37-tutorial.md)) | Merged | Passing (227 tests) | **Not yet** |
| 38. Softer indoor bloom, M frees the cursor in ships, inspect hides star prompts, prompt distance 135, codes PlanetzPlz and StarzShipz, Visit other hangars, flat 1,000 eggs, no direct planet purchases, chat announcements for Legendary+, hatch times rounded to 30 s, Berth renamed Dock, shorter tutorial with progress dots ([doc](docs/stage-38-feedback.md)) | Merged | Passing (226 tests) | **Not yet** |
| 39. Hangar highlight colour (10 colours in Settings, saved, v17), Dodgeball giant ball powerup every 12 s (next throw 3x bigger) ([doc](docs/stage-39-hangar-color-powerup.md)) | Merged | Passing (227 tests) | **Not yet** |
| 40. Loading screen with the key art, progress bar and tips (art needs uploading; title card until then) ([doc](docs/stage-40-loading-screen.md)) | Merged | Passing (227 tests) | **Not yet** |
| 41. Five imported ships face forward, trails half as wide at the start and coming out of the engine nozzles ([doc](docs/stage-41-ship-facing-trails.md)) | Merged | Passing (227 tests) | **Not yet** |
| 42-43. Planet names in rarity colours; code SneakySpace unlocks a Cloak (invisibility) switch in Settings ([doc](docs/stage-43-cloak-code.md)) | Merged | Passing (227 tests) | **Not yet** |
| 44. Code ResetMyGalaxy erases your own progress and code history (typed twice to confirm; purchase receipts kept) ([doc](docs/stage-44-reset-code.md)) | Merged | Passing (227 tests) | **Not yet** |
| 45. Galaxy Control console on the hangar deck: every solar system (level up, evolve, manage, inspect) and galaxy expansion in one panel ([doc](docs/stage-45-galaxy-control.md)) | Merged | Passing (227 tests) | **Not yet** |
| 46. Stardust Collector, Galaxy Control and Planet Egg dispenser are real machines; Neon Runway on/off switch in Settings (save v18) ([doc](docs/stage-46-devices-runway.md)) | Merged | Passing (228 tests) | **Not yet** |
| 47. Unified HUD layout (phone/tablet/desktop); ISS rebuild with gravity wheel; personal Egg Lab with rolls, rerolls, lab upgrades and 7 planet tiers (save v19) ([doc](docs/stage-47-egg-lab-tiers.md)) | Branch `stage-47-hud-layout`, uncommitted | Passing (235 tests) | **Not yet** |
| 48. Economy v2 from REBALANCE.md: BuildIndex star pricing, host-scaled planets, H-priced eggs, R-scaled rewards, B-based mining, 8 h offline at 25%, 2 h tank, ship tier gates, Constellation Projects (save v21) ([doc](docs/stage-48-economy-v2.md)) | Branch `stage-47-hud-layout`, uncommitted | Passing (253 tests) | **Not yet** |

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

- Upload `assets/ui/GaG_LoadingScreen.png` and put its id in `IMAGE` at the top of
  `src/first/LoadingScreen.client.luau` ([stage 40](docs/stage-40-loading-screen.md)).

- **Overhaul (stages 30-34) Studio playtest**, in this order, following each doc's test table:
  star placement (row 30: place, stack and move stars, check the build box and messages), then
  [planet inventory and migration](docs/stage-31-planet-inventory.md) (join with an existing
  save first, to see the v15 migration), [Planet Egg Lab](docs/stage-32-planet-eggs.md),
  [incubator](docs/stage-33-hangar-incubator.md) (including leaving and rejoining while an egg
  hatches), [Daily Wheel](docs/stage-34-daily-wheel.md), then
  [stage 35](docs/stage-35-iss-gacha-inventory.md) (walking, selling, auto-sell, multi-buy, ISS boards). Report Output errors. Nothing in these
  stages spends Robux or needs new product ids.

- Optional purchases (stage 17) are built but off. To launch them: create the passes and
  developer products, fill in the ids and review prices, following
  [docs/monetization-setup.md](docs/monetization-setup.md). Test first with the Studio mocks
  there. A real purchase test spends Robux.

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

- During stages 17 and 18 files on disk were repeatedly reverted to older versions while a
  Rojo server (with Studio connected) and other tools were running. Commits were verified
  before they were made; if Studio shows stale scripts, check the Rojo plugin's two-way sync.

- `Config.Materials`, `Config.Recipes`, `Config.Zones`, `Config.Celestials`, `Config.SolarSystems`
  and the profile's `materials`/`cargo` are unused leftovers of the original design (still
  config-checked); remove them once the revised design settles.
- Only the asteroid break has a sound (a built-in Roblox sound); others need audio assets.
- `rokit.toml` has an uncommitted bump of Rojo from 7.4.4 to 7.7.1 (made before this session); the
  CI uses the same file.
