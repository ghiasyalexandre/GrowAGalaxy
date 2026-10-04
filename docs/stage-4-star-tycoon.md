# Stage 4: Star tycoon

**Status: code complete, CI-verified (format, lint, strict types, 91 unit tests, build, smoke
test). Not yet playtested in Studio.**

## Playable result

At your station's **Star Shop** console, "Buy a star" starts placement if you can afford it (the
first star costs 100 Stardust; each star you own multiplies the next price by 2.5). A glowing ghost
star floats ahead of your camera inside a faint sphere showing the room its planets will need. It
turns green on a valid spot and red with the reason otherwise (outside your galaxy or too near its
edge, too close to another star, galaxy full). Press Enter to buy it there.

Stars produce Stardust every second (shown over each star, and as `+X/s` in the wallet). Production
piles up as "to collect" (capped at 2 hours' worth) until you use your station's **Collect** console.

Fly or float near one of your stars and choose **Manage star** (reach 400 studs). The panel shows
its level, production, and the next upgrade: cost, production before and after, and the planet it
adds. **Upgrade** (U) adds that planet: Ember, Verdant, Azure, then a Gas Giant, each on its own
tilted orbit drawn as a faint ring. **Move** (M) reuses the ghost to move the whole system.

| Placement control | Keyboard and mouse | Gamepad | Touch |
|---|---|---|---|
| Confirm / cancel | Enter / Backspace | A / B | Confirm / Cancel buttons |
| Higher / lower | E / Q | D-pad up / down | Higher / Lower buttons |
| Nearer / farther | Mouse wheel | D-pad left / right | Nearer / Farther buttons |
| Snap to a 40-stud grid | T | Y | |

Your galaxy holds 3 stars at first (6 and 10 with later expansions, which aren't buyable yet).

## What CI verifies vs what needs Studio

| Verified by CI | Needs a playtest in Studio |
|---|---|
| Unit tests: star prices grow with stars owned, upgrade costs stop at the top level, planets appear with upgrades, total income, income accrual and its cap | Ghost placement feel: distance, height, snapping, colours, info label |
| Unit tests: save schema v3 keeps valid stars and drops corrupt ones; v2 systems become stars | Buying, moving and upgrading stars; Stardust deducted once |
| Config checks: planet orbits stay inside SYSTEM_RADIUS and clear of the star and each other, costs positive, production never drops | Planets orbit smoothly on tilted rings; labels and the Manage panel |
| Strict type check of the server, client and shared code | Collect console pays out; other players can't manage your stars or use your shop |

## Studio hierarchy (new and changed)

```
ReplicatedStorage/Remotes/StarRequest           RemoteFunction NEW place / move / upgrade
ReplicatedStorage/Shared/Config/Stars           ModuleScript   NEW star types, levels, planets, prices
ReplicatedStorage/Shared/Config/Galaxy          maxSystems 3 / 6 / 10
ReplicatedStorage/Shared/Logic/StarMath         ModuleScript   NEW prices, production, planets, accrual
ReplicatedStorage/Shared/Logic/ProfileSchema    schema v3: galaxy.stars
ServerScriptService/Server/Systems/StarSystem   ModuleScript   NEW requests, income tick, Collect
ServerScriptService/Server/Systems/DataSystem   + addStar, updateStar, accrueIncome, collectIncome
ServerScriptService/Server/World/StarBuilder    ModuleScript   NEW star model
ServerScriptService/Server/World/StationBuilder Star Shop and Collect consoles with prompts
StarterPlayerScripts/Client/Controllers/StarController       NEW planets, rings, labels, Manage panel
StarterPlayerScripts/Client/Controllers/PlacementController  NEW ghost placement
StarterPlayerScripts/Client/Controllers/HudController        + production and "to collect"

Workspace/Regions/Region_<slot>/Stars/Star_<id>   Model (persistent), Core (neon ball, PointLight,
                                                   Manage prompt); attributes StarId, OwnerUserId,
                                                   TypeId, Level, Income. Planets and orbit rings
                                                   are added locally by each client.
```

Save data: `galaxy = { expansion, nextId, stars = { [id] = { typeId, level, pos, appearance? } } }`.
`stats.starsPlaced` counts stars bought.

## Manual test steps

| # | Steps | Expected |
|---|---|---|
| 1 | Play; run `game.ServerStorage.DevCommand:Invoke(game.Players:GetPlayers()[1], "addStardust", 10000)` in the server command bar. | Wallet shows 10K. |
| 2 | At your station, use **Star Shop**. Look around, E/Q, wheel, T. | Ghost star with sphere, green inside your region, red with a reason outside it or near its edge. |
| 3 | Press Enter on a green spot. | Star appears, toast `Yellow Star placed!`, wallet down 100, `+1/s` over the star and in the wallet line. |
| 4 | Try a second star right next to the first. | Red "Too close to another star"; the server refuses too. |
| 5 | Wait 20 s, use **Collect**. | Toast `Collected ~20 Stardust`; "to collect" resets. |
| 6 | Manage the star, Upgrade 4 times. | Each adds a planet on a tilted ring (Ember, Verdant, Azure, Gas Giant); production 2.5, 5, 9, 15/s; the button disappears at the top. |
| 7 | Manage, Move, confirm elsewhere. | Star and planets move together. |
| 8 | Local Server with 2 players. | Player 2 sees player 1's stars and planets but gets no Manage prompt, and their Star Shop/Collect at player 1's station refuse. |
| 9 | Rejoin (published place with API access on). | Stars come back where they were, at their levels. |

## Known limitations

- Galaxy expansion can't be bought yet (Stage 5), so the cap is 3 stars.
- One star type (Yellow Star); more types and appearances are config entries away.
- Ghost placement aims along the camera; there's no top-down placement view.
- Touch and gamepad bindings are untested on devices. The Manage panel needs Alt for the mouse
  while flying (or U / M / Backspace).
- Moons and per-planet development are deferred.
