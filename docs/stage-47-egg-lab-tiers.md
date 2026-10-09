# Stage 47: personal Egg Lab, rerolls, planet tiers

**Status: code complete, CI-verified (format, lint, strict types, 235 unit tests, build, world
and orbit smoke tests). Not yet playtested in Studio.**

The same branch also carries the unified HUD layout and the ISS rebuild (bigger modules, the
gravity wheel).

## What changed

- **The ISS Planet Egg Lab is gone.** Each player's station has its own **Egg Lab** at the far end
  of the Incubator Bay, next to the incubator chambers (`DeviceBuilder.eggLab`, model `EggLab`
  tagged `GaG_EggLab`). Only the owner's prompt is enabled. The rare-hatch board moved to the
  ISS Star Lounge.
- **Roll, then keep or roll again.** Each roll pays the egg price and puts a mystery egg on the
  lab's pedestal. Its **rarity and tier** show, but its planet stays hidden until it hatches.
  **Roll again** pays again and replaces it (the old egg is lost). **Keep** moves it into your
  eggs for free and starts it in a free chamber when auto-incubate is on.
- **7 planet tiers** (`Config.Planets.TIERS`): Plain x1, Glowing x1.5, Sparkling x2.2, Ringed x3.2,
  Radiant x4.6, Cosmic x6.8, Celestial x10. The tier multiplies only income. The rarity still sets
  the base income range (every rarity earns more than the one below, `ConfigCheck`). Selling
  ignores the tier, so rolling to sell never profits.
- **Tier looks** (`PlanetLook.tierFx`, cooler each tier): glow, then sparkles, halo ring, aura
  shell, star motes, and finally a rainbow ring with rainbow sparks. They show on planets in
  orbit, on the hatch reveal and on the pedestal egg. Reduced effects drops the particles.
- **Roll visuals** (`EggLabController`): the pedestal egg shakes and flickers through the rarity
  colours for `ROLL_SECONDS`, then pops into the new egg with a burst (bigger for Epic+ or
  tier 5+). It bobs and turns while it waits. Visitors see it too.
- **Lab upgrades** (`Config.Eggs.LAB_LEVELS`, 8 levels, 10k to 150M Stardust) raise
  `rarityLuck` and `tierLuck`. A type's weight is `weight × rarityLuck^rarityIndex`, and a tier's is
  `TIER_WEIGHTS[t] × tierLuck^(t-1)`, all whole numbers shown exactly in the panel. At level 8,
  Interstellar goes from 1% to about 4.8% and Celestial from 0.1% to about 1.5%.
- **Price scales with your galaxy:** `PRICE_BASE 1000 × PRICE_GROWTH 1.02^(eggs kept)`. Rerolls
  don't raise the price, but chasing a top tier always costs real time.
- **Announcements:** Epic+ or tier 5+ hatches go to the server and the hatch feed. Legendary+ or
  tier 7 hatches also go to the chat.

## Rules (server: `EggSystem`, `DataSystem.rollEgg` / `keepEgg` / `upgradeEggLab`, `Logic/EggMath`)

- `EggRequest`: `"status"`, `"roll", expectedPrice`, `"keep"`, `"upgrade", expectedCost`. A
  stale price changes nothing. Rate limited. Rolls only when PolicyService allows paid random
  items.
- Roll and pay happen in one step, and so do keeping (with the unhatched-egg cap) and upgrading.
- The lab model's attributes `Rarity`, `Tier`, `RolledAt` and `LabLevel` show the pedestal egg,
  never its planet.

## Save (version 19)

Planets, eggs and hatches gain `tier` (older ones: 1, so incomes are unchanged). New `eggLab =
{ level, current?, rolls }`. A pedestal egg of an unknown type is dropped. `eggsBought` now counts
kept eggs.

## Needs a Studio playtest

1. Hangar → Incubator Bay → Egg Lab: Roll, Roll again, Keep. Check the egg animation and colours,
   and that the price rises after Keep but not after a reroll.
2. Upgrade the lab: the odds in the panel shift, and the Upgrade tab compares levels.
3. Hatch a high-tier egg (use a test profile): the reveal, banner and tier effects in orbit.
4. A visitor sees your egg but can't open your lab.
5. The tutorial's egg step points at your own lab.

## Later on this branch: hangar redesign, Neon Runway removed (save version 20)

- The station is an enclosed sci-fi hangar: five truss arches under a glass roof, glass curtain
  walls above the half walls, a hazard-striped front portal with the owner's name facing the
  berth and a faint force field, chevrons down the lane, lockers, fuel lines, a gantry crane,
  and a slim control tower (ops windows, spinning radar dish, beacon) instead of the hub and
  crates. The Planet Egg Lab stands left of the Stardust Collector.
- The Neon Runway upgrade is gone. Save v20 refunds its 5,000 Stardust to anyone who built it
  (once) and drops it from `hangar` / `hangarOff`. The `toggle` mechanism stays (no upgrade uses
  it now).
- Playtest: walk the hangar; check that hangar upgrade buildings and the Galaxy Hologram fit under
  the roof (18 studs), the bay doorway is clear, and ships launch and dock through the portal.
