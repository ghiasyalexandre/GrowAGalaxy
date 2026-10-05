# Stage 21: Vanity hangar, ship paint, settings and music, solar flares, golden swarms, steeper progression

**Status: code complete, CI-verified (format, lint, strict types, 168 unit tests, build, world
smoke test, new orbit smoke test). Not yet playtested in Studio.**

## Hangar: vanity upgrades and the Showcase Dock

Four new red pads, each with its building away from the pad:

| Upgrade | Pad | Cost | What you get |
|---|---|---|---|
| Neon Runway | front, right of the entrance | 5,000 | Pulsing cyan chevrons and gold edge lights leading in to your berth |
| Galaxy Hologram | front, left of the entrance | 12,000 | A turning spiral-galaxy hologram over the deck, beamed up from a projector |
| Showcase Dock | back right | 15,000 | A platform off the right wall with three lit cradles showing your three favourite ships, turning, in their paint jobs, with name tags |
| Victory Spire | back left (after the Hologram) | 30,000 | A tall spire off the left wall with turning rings, a pulsing beacon and a light beam into the sky |

- These upgrades are vanity only: they have no gameplay effect.
- Two crates moved to make room for the back pads.

## Ship paint and finish (Shipyard, new Paint tab)

- **Ship:** pick one of your owned ships. A big turning preview shows it in its current paint
  job.
- **Colour:** one of 16 swatches, or **F** for the factory colours.
- **Finish:** Factory, Standard (smooth plastic), Metallic (metal, slight shine) or Glossy
  (high shine).
- **Showcase:** put the ship on show, or take it off. Up to 3 ships.
- **How the paint works:**
  - The imported ships are single textured meshes, and Roblox doesn't tint mesh textures.
  - So each client loads the texture into an EditableImage, turns it greyscale (the brightest
    pixel becomes white) and multiplies it by your colour. A 12% floor keeps panel lines
    visible on dark coats.
  - Plain (untextured) parts are painted by the server; the finish (material and shine) is set
    by the server too.
- **Fallback:** if EditableImage isn't allowed for the experience, the ship gets a solid coat of
  the colour instead. If you see solid ships, check **Game Settings > Security** for the
  EditableImage / mesh and image APIs option.
- Changes show at once on your flying ship and on the dock, for everyone.
- Save data version 10 adds per-ship paint and finish, the showcase list, and equipment levels
  (below). Older saves keep factory paint, an empty showcase and level 1 equipment.

## Ship upgrades: 5 levels each

Each equipment item in the Shipyard's Upgrades tab now has **5 levels**:
- **Bonus:** buying an item gives its listed bonus. Each level multiplies that bonus: ×1, ×1.6,
  ×2.2, ×2.8, ×3.4. A +25% beam reaches +85%.
- **Price:** each level costs **3.5×** the one before. The Focused Beam goes 600 → 2.1k →
  7.4k → 26k → 90k.
- **Display:** rows show `Lv 2/5`, the bonus now → the next level's bonus, and an Upgrade button.

## Settings panel (replaces "Effects: full")

The HUD button under the wallet now says **Settings** and opens a panel:
- **Effects:** Full or Reduced (as before).
- **Sound effects volume:** 0 to 100% (a slider; it previews live and saves on release).
- **Music volume:** 0 to 100%.
- **Galaxy boundary:** shown or hidden. This hides your own region's glowing box, on your
  screen only.

**Volume groups:** every sound joins an SFX or a Music group, so the sliders control
everything.

## Music

`assets/roblox/Music` is now mapped to `ReplicatedStorage/Assets/Music`.
- **SpaceMusic** loops as the game music.
- **SpaceDisco** crossfades in (over 2 s) while you're in a Death Star raid, and back out
  afterwards.
- Each track keeps the volume saved in its file.

Any other copy of either track, such as the ones you placed in Studio, is silenced so the music
never plays twice. You can delete those copies.

## HUD

- The Star Shop, Shipyard and Store buttons are stacked **vertically** under Settings and PvP.
- The Next Goal panel and the boost chips moved down to make room.

## Solar systems

- **Solar flares:** every star near the camera now and then throws up a glowing loop of plasma
  off its surface, with a flash at its foot and a burst of sparks. Hotter stars flare more often.
- **Black holes:** they fire twin jets from their poles instead.
- **Reduced effects:** flares come a third as often and without sparks.
- Stars can be placed **33% closer**: the minimum spacing is now 296 studs, down from 444.
  Neighbours' outer orbit rings may cross, but no planet ever reaches another star.

## Planets orbiting

**Tested headlessly: the orbit code works.** A new smoke test (`tests/OrbitSmoke`) runs the real
client StarController in Lune and checks that planets move along their orbits; they move about
30 studs in 2 s. It runs in CI now.

**Hardening:**
- One failing system can no longer stop the others from turning. The first error is reported
  once in Output as `[StarController] orbit update failed: ...`.
- A star whose core part replicates late is picked up when it arrives.

If planets still don't move in Studio:
1. Look for that warning in Output.
2. Check that Studio is running the current scripts. The Rojo plugin's two-way sync once pushed
   stale copies back.

## Star panel refresh fix

**The bug:** at max level the panel still showed `3/4`. The panel only redrew after the
level-up effects and banner ran, so one failure left it stale.

**The fix:**
- The panel and label now redraw first.
- The effects run protected; a failure is logged and the panel redraws again.
- The panel also redraws whenever a level up, evolve or purchase request returns.

## ISS

The main hull's white and light-grey panels are **20% darker**, so they glare less.

## Golden asteroid swarm (every 7 minutes)

- **The swarm:** 14 golden asteroids (gold foil with sparkles) appear in a clump somewhere in
  the field, worth **3×** the usual Stardust.
- **Announcement:** every player gets a GOLDEN SWARM banner and a gold marker showing the
  distance and time left; the marker can be seen through anything.
- **Late joiners:** players who join mid-swarm get the marker too.
- **The end:** after 2.5 minutes whatever nobody is mining crumbles.
- **Tuning:** `Config/Asteroids` `SWARM_*`.

## Progression: steeper, whole numbers

| What | Before | Now |
|---|---|---|
| Each extra star's price | ×1.25 per star owned | **×1.35** |
| Star level-up price growth | ×1.25 per level | **×1.35** |
| Star types (Red Dwarf … Black Hole) | 600 … 600k | **700, 3.5k, 14k, 50k, 170k, 550k, 1.8M** |
| Planets (Molten … Crystal) | 800 … 650k | **900, 4k, 14k, 45k, 140k, 420k, 1.3M** |
| Ships (Red Fighter … Meteor Slicer) | 2.5k … 1M | **2.5k, 9k, 25k, 60k, 130k, 260k, 500k, 900k, 1.6M, 2.8M** |
| Galaxy expansions | 6k, 40k | **8k, 60k** |
| Hangar upgrades (Refinery … Armor) | 6k, 10k, 25k, 20k | **7k, 14k, 40k, 30k** |

**Whole numbers:**
- Star income per second (level included) is rounded to a whole number.
- The total income rate is a whole number.
- Barren Rock gives 2/s instead of 1.5/s.
- The level-up banner shows the multiplier rounded, e.g. ×10.

## Test in Studio

1. **Music:** SpaceMusic plays; join a raid and SpaceDisco fades in.
2. **Settings:** the sliders change volume, the boundary toggle hides your region's box, and
   all three survive a rejoin.
3. **Paint:** open Shipyard > Paint, paint your ship a colour and Glossy, launch, and look at it.
4. **Showcase:** put 3 ships on show, build the Showcase Dock and check the cradles.
5. **Vanity:** build the Runway, the Hologram and the Spire.
6. **Equipment:** buy a level of a piece of equipment; the price for the next level jumps.
7. **Stars:** watch a star for flares, and place a star close to another.
8. **Swarm:** wait 7 minutes on a server for the golden swarm, or set `SWARM_INTERVAL` low.
9. **Star panel:** level a star to max with its panel open; it should say 4/4 straight away.
