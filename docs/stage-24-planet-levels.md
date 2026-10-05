# Stage 24: Planet levels, livelier planets, pricier expansions

**Status: code complete, CI-verified (format, lint, strict types, 177 unit tests, build, world
and orbit smoke tests). Not yet playtested in Studio.**

## Planet levels (1 to 5, per planet)

Each planet in a star's orbit now levels up on its own, from the star's Manage panel. The
**Level** button sits next to the tier upgrade, and the row shows `Lv 2/5` and the planet's
current income.

| Level | Income (× base) | Size | Price to reach it |
|---|---|---|---|
| 1 | ×1 | 100% | (buying the planet) |
| 2 | ×1.5 | 103.5% | 50% of its price |
| 3 | ×2 | 107% | 90% |
| 4 | ×2.5 | 110.5% | 162% |
| 5 | **×3** | 114% | 292% |

- Incomes are rounded to whole numbers; the star's total includes every planet's level.
- Upgrading a planet to the next tier starts it again at level 1.
- Each level past the first adds a **little moon** circling the planet, so you can see its level
  from afar.
- Levelling up plays the materialize effect and a PLANET LEVEL UP banner.
- The size gain is capped so a top-level Gas Giant on the outermost orbit still fits inside its
  system (ConfigCheck).
- Tuning: `Config/Planets` (`MAX_LEVEL`, `LEVEL_INCOME_STEP`, `LEVEL_SIZE_STEP`,
  `LEVEL_COST_SHARE`, `LEVEL_COST_GROWTH`).

## Cooler planets

- **All planets:** a shimmering atmosphere in a lighter shade of the planet's colour.
- **Molten Worlds:** throw off glowing embers.
- **Crystal Worlds:** glint with sparkles.
- **Gas and Ice Giants:** swirl with slow storm clouds.

The embers, sparkles and storms are left out with reduced effects.

## Galaxy expansions

They cost **12,000** and **90,000** Stardust, up from 8,000 and 60,000.

## Save data

Version 12: stars save `planetLevels` (slot → level 2–5). Existing planets are level 1.

## Test in Studio

1. **Levels:** open a star with a planet, press Level, and check that the income, size and
   moon count change.
2. **Tier upgrade:** upgrade that planet's tier; it should go back to level 1.
3. **Visuals:** look at a Molten, Crystal or Gas Giant planet for the effects.
