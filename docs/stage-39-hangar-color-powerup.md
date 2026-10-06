# Stage 39: Hangar highlight colour, giant ball powerup

**Status: code complete, CI-verified (format, lint, strict types, 227 unit tests, build, world
and orbit smoke tests). Not yet playtested in Studio.**

## Hangar highlight colour

**Settings → Hangar color**: a row of round swatches, **Auto** (the region's own colour, as
before) and 10 colours: Cyan, Blue, Purple, Pink, Red, Orange, Gold, Green, Mint, White
(`Config.Hangar.HIGHLIGHT_COLORS`). The pick is outlined; choosing one repaints your station at
once for everyone: the glowing floor and wall strips, lane lights, arch light panels, back rail,
the beacon above the hub and the "<name>'s Hangar" / "<name>'s Galaxy" signs. Glowing pieces
keep the stage 37 dimming. The galaxy boundary box keeps the region colour.

- Saved in the profile (`hangarColor`, schema **version 17**; nothing else changes, unknown
  values fall back to Auto) and applied whenever your station is built.
- Pieces in the highlight colour carry the attribute `GaG_Accent`
  (`StationBuilder.recolor`); `SettingChanged("hangarColor", id | "")` →
  `DataSystem.setHangarColor` → `StationSystem.recolor`.

## Zero G Dodgeball: giant ball powerup

Every **12 seconds**, if none is out, a glowing green orb labelled **GIANT BALL!** appears near
a random spawn point in the arena. The first player (not out) to float into it takes it: their
next throw is **3× bigger**, and so is its hit area, so it's much easier to hit with. The sun in
their hand grows to show the charge (player attribute `DodgeBig`), and it's used up on that one
throw. The next orb appears 12 seconds after the last one is taken. Leaving the arena loses the
charge. Balls fly through the orb.

Tuning: `Config.Dodgeball` `POWERUP_INTERVAL` (12), `POWERUP_SCALE` (3), `POWERUP_REACH`
(7 studs), `POWERUP_COLOR`.

## Test in Studio

1. Settings → Hangar color: pick Pink; your station's strips, beacon and signs turn pink. Pick
   Auto: back to the region colour. Rejoin: the pick is kept.
2. With a second client, check they see your colour.
3. Dodgeball: wait for the GIANT BALL orb, float into it, see your sun grow, throw: a huge ball
   that hits easily; the next throw is normal size. A new orb appears 12 s later.
