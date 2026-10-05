# Stage 7: Star and planet tiers

> Levels, evolution and orbits changed in [stage 13](stage-13-evolution-orbits.md): a star
> evolves only at its type's max level and restarts at level 1; orbits come with the type.

**Status: code complete, CI-verified (format, lint, strict types, 101 unit tests, build, smoke
test). Not yet playtested in Studio.**

## Playable result

**Eight star tiers.** The Star Shop console now opens a panel listing every star:

| Tier | Star | Price | Base Stardust/s | Holds planets up to |
|---|---|---|---|---|
| 1 | Brown Dwarf | 100 | 1 | Barren Rock |
| 2 | Red Dwarf | 600 | 4 | Molten World |
| 3 | Yellow Dwarf | 2,500 | 12 | Desert World |
| 4 | White Dwarf | 8,000 | 30 | Ocean World |
| 5 | Red Giant | 25,000 | 75 | Terran World |
| 6 | Blue Giant | 75,000 | 180 | Ice Giant |
| 7 | Red Supergiant | 200,000 | 420 | Gas Giant |
| 8 | Black Hole | 600,000 | 1,000 | Crystal World |

A tier can be bought once you have a star of the tier below. Prices rise 25% for each star you
already own. Giants and supergiants glow with a corona; the black hole is a dark core inside a
tilted, glowing accretion disk.

**Managing a star** (Manage star prompt): the panel shows its tier, level and production, with:

- **Level up** (5 levels): multiplies the star's own production (x1, x2, x3.5, x5.5, x8) and opens
  orbit slots (1, 2, 3, 4, 4).
- **Evolve** into the next tier in place, for that tier's price, keeping level and planets. A star
  evolves all the way from Brown Dwarf to Black Hole.
- **Move**, as before.
- **Orbits**: each of the 4 orbit slots shows its planet, "empty" with **Buy a planet**, or the
  star level that opens it. Open but empty orbits show as faint rings.

**Eight planet tiers**, bought into a star's free orbit:

| Tier | Planet | Price | Stardust/s |
|---|---|---|---|
| 1 | Barren Rock | 150 | 1.5 |
| 2 | Molten World | 800 | 5 |
| 3 | Desert World | 3,000 | 14 |
| 4 | Ocean World | 9,000 | 35 |
| 5 | Terran World | 28,000 | 85 |
| 6 | Ice Giant | 80,000 | 200 |
| 7 | Gas Giant (ringed) | 220,000 | 480 |
| 8 | Crystal World (ringed) | 650,000 | 1,100 |

A planet can be upgraded in its orbit to the next tier, for that tier's price minus half the
current one's, as far as its star's tier allows.

New panels use a shared theme (`src/client/UI/Theme.luau`): gradient panels with a glowing edge,
gold buy buttons that grow on hover and squash on click, and a springy pop-in.

## Save data

Schema v4: each star saves `planets = { ["1"] = planetId, ... }` by orbit slot. Existing stars
keep type and level and start with no planets. New stats: `planetsBought`, `planetUpgrades`,
`starEvolutions`. The last tutorial step is now "buy a planet".

## What CI verifies vs what needs Studio

| Verified by CI | Needs a playtest in Studio |
|---|---|
| Unit tests: tier unlocks, evolution chain, slots per level, planet tier caps, free slots, planet upgrade prices, income with planets, planet attribute encoding, accrual | Shop and Manage panels: layout, buttons, prices updating as Stardust changes |
| Config checks: both ladders rise in price and income, levels only improve, the biggest star and planet fit every orbit inside SYSTEM_RADIUS | Star tier looks (corona, black hole disk), planet looks and rings |
| Unit tests: schema v4 keeps valid planet slots and drops bad ones | Evolve keeps planets; upgrading a planet swaps it in place |

## Manual test steps

| # | Steps | Expected |
|---|---|---|
| 1 | Dev command `addStardust 2000000`. Open the **Star Shop**. | 8 rows; only Brown Dwarf buyable, others "Needs a ...". |
| 2 | Buy and place a Brown Dwarf. Reopen the shop. | Red Dwarf now buyable; prices up 25%. |
| 3 | Manage it: Buy a planet. | Picker: Barren Rock buyable, others need bigger stars. Buying adds it on orbit 1. |
| 4 | Level up twice. | Orbits 2 and 3 open (faint rings). |
| 5 | Evolve repeatedly to Black Hole. | Colour, size and glow change each tier; the black hole gets its disk; planets stay. |
| 6 | Upgrade the planet to Crystal World. | It changes tier by tier; Gas Giant and Crystal World have rings. |

## Known limitations

- No selling or removing stars and planets.
- Star tiers share one set of levels and orbit slots.
- Prices and incomes are first guesses; tune them in `Config/Stars.luau` and `Config/Planets.luau`.
