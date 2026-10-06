# Stage 33 (overhaul stage 4): Hangar incubator, five hatch chambers

**Status: code complete, CI-verified (format, lint, strict types, 211 unit tests, build, world
and orbit smoke tests). Not yet playtested in Studio.**

## Incubator Bay

Every station has a new **Incubator Bay**: an annex off the left side of the hangar deck,
through a doorway in the left wall (between the hangar pads, so walking through never steps on a
pad). It holds **5 incubator chambers** in a row (`Config.Eggs.HATCH_SLOTS`): a dark base with
a glass dome. The bay adds 17 parts (station total 102 of the 110 budget); everything that moves
is drawn on each client.

Above each chamber a label shows **Chamber N**, its status (`Empty`, or `Rare egg · 42% · 1:12`)
and a progress bar. Inside the dome a planet forms in the rarity's colour, growing and
brightening with progress, with swirling sparks (not with Reduced effects; the bobbing also
stops). When it hatches the new planet pops out above the chamber for 5 seconds with a burst, and
its owner gets a **PLANET HATCHED** banner (with a flash for Epic and rarer) and a message.

Visitors see the same labels, progress and reveals, but the chambers' **Incubate** prompts are
only enabled for the owner, and requests only ever change the requester's own profile.

## Incubating

Press **Incubate an egg** at a chamber to open the **Incubator** panel: the 5 chambers with live
timers, then your waiting eggs. Mystery eggs say "hatches in 10 s to 30 min, by its rarity"
(the planet stays hidden); chosen eggs show their planet and exact time. **Incubate** puts the
egg in the chamber you opened (or the first free one).

## Rules (server: `HatchSystem`, `DataSystem.startHatch` / `completeHatch`, `Logic/HatchMath`)

- **Atomic start:** the egg leaves the inventory and the hatch record (`eggId`, the planet chosen
  at purchase, `startedAt`, `endsAt`) is created in one step. A busy chamber, an egg that isn't
  yours or a bad chamber number changes nothing.
- **Hatch time** = the planet's rarity time: 10 s, 28 s, 80 s, 226 s, 637 s, 1,800 s.
- **Timestamps are unix seconds** saved in the profile, so eggs keep hatching while you're offline.
- **Exactly once:** every second (and when your profile loads) each finished hatch is completed
  in one step that removes the hatch and adds the planet (level 1) to your inventory, so the same
  egg can't be granted twice and the chamber frees itself.
- **Offline summary:** eggs that finished while you were away are granted on join, followed by
  one message ("While you were away, 3 eggs hatched: Aurora World (Rare), 2x Basalt World
  (Common). Equip them from Planets (P).").
- A planet type unknown to this server (saved by a newer version) is left in its chamber.
- Remote: `HatchRequest` `"start", eggId, chamber?` (rate-limited).
- Stat: `planetsHatched` (Worldbuilder achievement: hatch 10).

## Test in Studio

1. Fly or walk to your station: the doorway in the left wall leads to the bay with 5 domes.
2. Buy a Common chosen egg at the ISS (cheapest), go to a chamber, Incubate it: the label counts
   down from 0:10, the forming planet grows, then it pops out, the banner plays, and the planet is
   in Planets (P).
3. Incubate a longer egg (e.g. Rare 80 s), leave the game, rejoin after it should be done: the
   "While you were away" message lists it and it's in the Planets panel. The chamber is empty.
4. With a second player (Studio multi-client test): they see your chambers' progress but can't
   press the prompts.
5. Reduced effects on: no sparks or bobbing; progress and reveals still show.

## Limitations

- Exactly-once and offline completion are proven by unit tests on `HatchMath` and by the
  single-step design; a forced server crash between two saves can't be simulated in Studio.
