# Stage 35: ISS upgrades, gacha and inventory tools, walking

**Status: code complete, CI-verified (format, lint, strict types, 225 unit tests, build, world
and orbit smoke tests). Not yet playtested in Studio. No Robux involved.**

## Floating off (Settings)

Settings has a new **Floating** switch: **Float** (as before) or **Walk**. With Walk, wherever
there's a floor within 24 studs below your feet you walk and jump on it (Space / A / R1 jumps),
pulled down by a force on your own character only. The world stays zero-g, so ships, asteroids
and everyone else are unaffected. Off a floor's edge, in open space and in Zero G Dodgeball you
float as usual. Falls are capped at 40 studs/s so the flight guard never trips
(`Config.Movement` `WALK_*`). The controls hint still describes floating.

## Planet inventory tools (Planets panel, P)

- **Filters:** rarity chips (All, Common … Interstellar), a place switch (All places / In orbit /
  Inventory) and a sort switch (rarity / income / level).
- **Per planet:** **Lock / Unlock** (a locked planet can never be sold, by hand, in bulk or
  automatically), **Lv up**, **Equip / Unequip**, and **Sell** (inventory and unlocked only;
  Rare and rarer ask "Sure?" first). The header shows owned/500, planets in orbit with their
  production, and your **Planet Index** (types found, out of 28).
- **Equip best:** fills every orbit of every star with your best-earning planets. Planets
  already in orbit that make the cut don't move; income is settled first.
- **Sell…** (bulk), per rarity: **Duplicates** (every unlocked inventory copy except the best
  of each type, which is kept whether it's in orbit or not) or **All** (every unlocked
  inventory planet). Both show the total and ask "Sure?" first.
- **Auto-sell…:** per rarity (Common, Uncommon, Rare, Epic; never Legendary or Interstellar),
  sell newly hatched planets on the spot. **Keep new types** (on by default) never auto-sells a
  type you've never had.

**Sale values** (`Config.Planets.SELL_VALUE`): Common 40, Uncommon 100, Rare 300, Epic 1,000,
Legendary 3,000, Interstellar 10,000, plus half of the Stardust spent levelling the planet.
A mystery egg's expected sale value (~300) stays below the cheapest egg (500), which
ConfigCheck enforces, so buying eggs to sell them never pays.

**Storage:** at most 500 planets. A planet that hatches when you're full is sold
automatically, so nothing is lost.

## Gacha

- **Buy ×1 / ×5 / ×10** mystery eggs at once, each egg at its own rising price, all bought
  together or not at all (the shown total must match the server's).
- **Planet Index:** every type you've owned. The Egg Lab's odds list marks found types with ✓
  and shows your count; the hatch message says when a type is new.
- **Auto-incubate** (on by default; Settings and the Incubator panel): a chamber that frees up
  takes your oldest waiting egg from the moment it freed, so incubation chains through time
  away too. **Fill all chambers** starts the oldest waiting eggs in every free chamber.
- **Rare hatch announcements:** Epic or rarer hatches are announced to everyone in the server
  and listed on the Egg Lab's board.

## ISS

- **Arrival:** an ISS Directory board (what each module is for, where to hatch eggs).
- **Star Lounge:** a **Top Stardust** board (the global leaderboard's top 10, read every
  2 minutes; where that store can't be read, as in Studio without API access, the richest
  players in this server), and a **Daily Wheel kiosk** that opens the wheel.
- **Planet Egg Lab:** a **Rare hatches** board (the last 6 Epic+ hatches in this server) and a
  gallery: one planet of each rarity circles the giant egg, each changing to the next type of its
  rarity every 20 s, so the whole catalog passes by. The gallery is drawn on each client, only
  nearby, and holds still with Reduced effects.
- The ISS is 329 parts (budget 400).

## Save data: version 16

New fields with safe defaults, nothing converted: settings `floating` (true), `autoIncubate`
(true), `keepNewTypes` (true), `autoSell` (none); planets may be `locked`; `discovered` (the
Planet Index) starts as every type you own. Remotes: `StarRequest` gains `sellPlanets`,
`lockPlanet`, `equipBest`; `EggRequest "buyMystery"` takes a count; `HatchRequest` gains
`fill`; `SettingChanged` takes the new settings and `("autoSell", rarity, on)`.

## Test in Studio

1. **Walk:** Settings → Floating: Walk. On the ISS and your station deck you walk, jump with
   Space and fall back down; step off the deck edge and you float. Dodgeball still floats.
   Watch Output for flight-guard rubber-banding.
2. **Multi-buy:** buy ×5; five eggs appear, and the price matches the shown total.
3. **Auto-incubate:** fill the chambers with Fill all; with more eggs waiting, each chamber
   restarts by itself when it hatches. Leave, rejoin later: several eggs have hatched in turn.
4. **Auto-sell:** turn on Common auto-sell, hatch a Common you already own: it's sold and the
   message says so. With Keep new types on, a never-seen Common is kept.
5. **Inventory:** filter, sort, lock a planet (its Sell button says Locked), sell one, bulk-sell
   duplicates, Equip best (income should rise or stay).
6. **ISS:** read the Directory, the Top Stardust board (in-server list in Studio), use the wheel
   kiosk, watch the gallery change types; hatch an Epic+ with a second client in the server to
   see the announcement and the Rare hatches board.

## Limitations

- Walking relies on the Humanoid landing under a custom force with world gravity at 0; it's
  built to Roblox's documented behaviour but needs a playtest for feel (jump height, slopes).
- The global Top Stardust board only fills on a published place with API access.
