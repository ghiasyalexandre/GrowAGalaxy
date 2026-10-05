# Stage 20: Floating posture, showroom fix, Death Star overhaul, wilder asteroids, curved progression

**Status: code complete, CI-verified (format, lint, strict types, 166 unit tests, build, smoke
test). Not yet playtested in Studio.**

## Floating posture

- A floating player now rests **leaning 30° forward**, like a swimmer, and leans up to **70°**
  at full speed ahead (was 0° at rest, 50° at full speed). Going backwards straightens them
  up.
- **Feet stay out of floors.** Legs don't collide, so they used to sink through the deck. Now a
  short downward check from the body finds the floor. If it's closer than the legs reach, plus a
  0.6-stud gap, the suit pushes the player up. The reach shortens as they lean.
- Tuning (`Config/Movement`): `SUIT_IDLE_LEAN_DEGREES`, `SUIT_LEAN_DEGREES`, `SUIT_FLOOR_GAP`,
  `SUIT_FLOOR_PUSH`.

## Showroom ships turn in place

Spinning decorations (`SpinController`) now turn about their model's **bounding-box centre**,
not its pivot. Imported ship models can have their pivot far to one side, which made the
showroom ships circle around their pads. The hologram and the raid beacon's rings turn as before.

## The Death Star, overhauled

**Weak point:**
- It jumps to a new spot on the hull **every time the boss loses 5% of its health** (20 moves
  per fight). Each new spot is at least 50° round from the last, anywhere on the sphere, so
  raiders have to fly around the boss.
- A green streak shows where it went, with a **WEAK POINT MOVED!** banner.
- An always-on-top green target marker shows it through the hull.

**Moves:**

| Move | Easy | Medium | Hard | How to survive |
|---|---|---|---|---|
| Turbolaser volley (existing) | ✓ | ✓ | ✓ | Keep moving: bolts fly to where you were |
| **Homing drones** (new) | 2 every 18 s | 3 every 15 s | 4 every 12 s | Outrun them (75 studs/s) or shoot them: one hit pops one |
| **Shockwave ring** (new) | every 22 s | every 18 s | every 14 s | Its plane glows red for 1.5 s, then a ring races out along it: fly above or below the plane |
| Superlaser (existing) | | every 30 s | every 20 s | Get off the red aiming line |
| **Orbital bombardment** (new, Hard only) | | | 6 blasts every 16 s | Red zones swell on and around raiders for 2.6 s, then explode: move away |

- The shockwave, superlaser and bombardment never come at the same time: after one of them, the
  others wait 5 s.
- **Enrage:** below 25% health the boss is **ENRAGED**. Every move comes 1.35× as often, with a
  banner and a shake; the boss bar says ENRAGED.

**Balance:** ships got stronger beams in this stage (see below), so the boss changed with them:
- Shots now do **half** the shooter's beam power to the boss, the same share a shot puts into an
  asteroid.
- Boss health is **4,000 / 12,000 / 35,000** for one raider (was 1,500 / 4,000 / 10,000). That
  aims at a 1.5 to 3 minute fight with a ship suited to the difficulty.
- Rewards are **4,000 / 14,000 / 45,000 Stardust** (was 3,000 / 9,000 / 25,000), plus the same
  boosts as before on Medium and Hard.

Tuning: `Config/Raids` (`moves` per difficulty, and the `WEAK_POINT_*`, `ENRAGE_*`, `DRONE_*`,
`SHOCKWAVE_*` and `BOMBARD_*` settings). Rules and tests: `Logic/RaidMath`.

## Asteroids, scattered more randomly

**Groups:** each group now picks its own size and shape:
- Its size runs from **1 to 7** rocks, weighted towards small groups, so **lone rocks are
  common**. It was always a clump of 2 to 5.
- Its own spread is between **35 and 190 studs**. It was always 80.
- Three in ten groups of 3 or more are **streams**: rocks strung out along a line, like a little
  belt.

**Rocks:** each one is **up to 25% bigger or smaller** than its size's average. Its durability and
reward scale with its area, so a big Large rock takes longer and pays more.

Tuning: `Config/Asteroids` (`CLUSTER_*`, `STREAM_CHANCE`, `SIZE_JITTER`).

## Curved progression

Rewards now grow faster the further you get, instead of in a straight line.

| What | Before | Now |
|---|---|---|
| Star level production | ×(1 + 0.75 per level): ×3.25 at L4, ×7.75 at L10, ×13.75 at L18 | ×(1 + 0.6n + 0.05n²): ×3.25 at L4 (unchanged), **×10.45 at L10, ×25.65 at L18** |
| Ship beam power, ladder order | 10, 14, 15, 24, 22, 25, 26, 30, 36, 38, 42 | 10, 14, 15, 24, **23, 28, 32, 44, 54, 57, 70** |
| Ship hull | 100 + 30 per ship (100 … 400) | 100 + 20n + 4n² (**100, 124, 156 … 604, 700**) |
| Daily Stardust, days 7 / 8 / 9 / 11 / 12 / 14 | 2,500 / 1,500 / 2,000 / 3,000 / 4,000 / 10,000 | **3,500 / 1,900 / 2,500 / 3,600 / 4,500 / 15,000** |
| Daily boosts, days 6 / 13 | 10 / 20 min | **15 / 30 min** |
| Raid rewards | 3k / 9k / 25k | **4k / 14k / 45k** |

- Nothing early got cheaper or weaker. Each ship's role is kept: the Warship and Transtellar
  still hit hard, and the speed ships a little less.
- Higher beam power also means faster mining, so late-game mining income now curves upward
  too.
- PvP time to kill is unchanged: hull and beam power rose together, so every ship still takes
  about 10 shots from an equal ship.
- The star level-up banner shows the multiplier rounded to two decimals.
- Tests check that each star level and each ship's hull adds more than the step before.
- Tuning: `Config/Stars` (`LEVEL_INCOME_LINEAR`, `LEVEL_INCOME_CURVE`), `Config/Ships` (stats,
  hull formula), `Config/Daily`, `Config/Raids`.

## Test in Studio

1. Float around the ISS. You should lean forward at rest, more when moving, and your feet should
   stay above the floor.
2. In the Ship Showroom, the two ships should turn in place over their pads.
3. Run an Easy raid:
   - The green weak point should jump about every 5% of health, with a marker you can see
     through the boss.
   - Red drones should chase you; shoot one to pop it.
   - The red plane should flash before each shockwave ring.
4. Run a Hard raid to see the bombardment zones and the enrage banner below 25%.
5. Fly around the asteroid field: lone rocks, loose clumps and stretched lines of rocks of mixed
   sizes.
6. Level a star past level 4 and check the multiplier in the banner.

## Known limitations

- Drones are moved by the server, so they may look a little steppy at high ping.
- The floor push uses a straight-down check: angled or vertical walls still let legs clip.
- Balance is estimated from fire rate, heat and beam power, not playtested. Tune boss health and
  move intervals after a few raids.
