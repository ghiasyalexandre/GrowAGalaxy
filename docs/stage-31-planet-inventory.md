# Stage 31 (overhaul stage 2): Owned planets, nine orbits, planet inventory

**Status: code complete, CI-verified (format, lint, strict types, 197 unit tests, build, world
and orbit smoke tests). Not yet playtested in Studio.**

Planets are now individually owned. Each one has its own id, type, rarity and level, and sits
either in your **inventory** (not producing) or in one orbit of one of your stars. Only planets in
orbit produce Stardust. Planets are no longer bought from a star: from overhaul stage 3 on they
come from planet eggs (ISS) hatched in your hangar (stage 4).

## Stars: orbits

Each star type has a whole number of orbits that never goes down as you evolve, and the top
(Black Hole) has 9:

| Star tier | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 |
|---|---|---|---|---|---|---|---|---|
| Orbits | 3 | 4 | 5 | 6 | 7 | 7 | 8 | 9 |

- Evolving keeps every planet in its slot and only opens slots. It never grants planets.
- The Manage panel shows `orbits used/open · next evolution: N` (or `max orbits`), lists every
  open orbit and previews the ones the next evolution opens.
- The system footprint shrank to fit nine orbits (radius 165, was 222), so stars can sit closer.

## The planet catalog (Config/Planets)

28 types in six rarities. Every type has an exact integer weight out of 1,200,000 (used by the
egg roll in stage 3):

| Rarity | Types | Chance each | Hatch time | Base income (Stardust/s) |
|---|---|---|---|---|
| Common | Basalt, Dune, Moss, Rust | 12.5% | 10 s | 2–6 |
| Uncommon | Storm, Coral Reef, Copper Canyons, Fungal Glow | 7% | 28 s | 12–18 |
| Rare | Obsidian Lava, Aurora, Giant Geode, Magnetic Ring, Bioluminescent Ocean, Fractured Quartz | 2.33% | 80 s | 35–60 |
| Epic | Floating Islands, Mechanical, Plasma Storm, Prismatic Ocean, Shattered, Eclipse | 0.83% | 226 s | 120–220 |
| Legendary | Phoenix Core, Celestial Garden, Cosmic Clockwork, Nebula Shell | 0.5% | 637 s | 480–600 |
| Interstellar | Jagged Diamond, Contained Singularity, Pulsar Lattice, Dimensional Rift | 0.25% | 1,800 s | 1,100–1,600 |

- Levels 1–5: each level adds 50% of the base income (×3 at level 5) and 3.5% size, plus a
  small moon. Level L → L+1 costs `UPGRADE_COST[rarity] × 1.8^(L−1)` (Common 300 … Interstellar
  250,000 for the first level).
- Looks (`client/Fx/PlanetLook`): each type combines shapes named by its `features`: surface
  patches, bands, clouds, cracks, glowing cracks and fungi, embers, aurora rings, crystal
  spikes, planetary rings, floating shards and islands, gears, a glowing core seen through the
  crust, an eclipse halo, a caged singularity, pulsar beams or a rift. Epic and rarer planets
  glow; Legendary planets shed golden sparks and Interstellar ones star sparks. Particles are
  left out with Reduced effects; the shapes always stay.

## Equipping, moving, levelling

- **Star panel** (Manage star): each open orbit is either a planet (Level, Unequip) or empty
  (**Equip a planet** → a list of your planets, inventory first, with the star's production
  before and after). Picking a planet that orbits another star moves it in one step.
- **Planets panel** (new HUD button under Store, or **P**): every planet you own, rarest first,
  with where it is, Level, and Equip (choose a star; it takes the first free orbit) or Unequip.
- Server (`StarSystem`): `equipPlanet planetId starId slot?`, `unequipPlanet planetId`,
  `levelPlanet planetId`. Every request checks ownership, that the slot is open
  (1..the star's orbits, whole) and free, and the price (`Logic/PlanetInventory`).
- **Income is settled first.** `DataSystem.settleIncome` adds up the player's income since the
  last settlement at the current rate before any change that alters the rate (equip, unequip,
  move, planet level, star level or evolution) and every second; the change applies from that
  moment. Passes, the star boost and trails multiply the total once, as before.
- If a star ever disappears, its planets fall back to the inventory (on load, and
  `PlanetInventory.releaseStar`).

## Save data: version 15

New profile fields: `planets` (id → `{typeId, level, star?, slot?, custom?}`), `nextPlanetId`,
and, empty until later stages, `eggs`, `nextEggId`, `eggsBought`, `hatches`, `wheel`.

Migration from version 14 and older (`ProfileSchema.migratePlanetsV14`):

1. Every planet in a star's orbit becomes an owned planet with the same level, mapped to a new
   type that earns at least as much:

   | Old | New |
   |---|---|
   | Barren (2/s) | Basalt (2/s) |
   | Molten (5/s) | Rust (6/s) |
   | Desert (14/s) | Copper Canyons (16/s) |
   | Ocean (35/s) | Bioluminescent Ocean (55/s) |
   | Terran (85/s) | Floating Islands (120/s) |
   | Ice Giant (200/s) | Shattered World (200/s) |
   | Gas Giant (480/s) | Nebula Shell (600/s) |
   | Crystal (1,100/s) | Jagged Diamond (1,100/s) |

   An unknown old id becomes a Basalt planet rather than being dropped.
2. It stays in the same slot if the star's new orbit count still has it; otherwise it goes to
   the inventory. Before, stars had 4–11 orbits; now 3–9, so a tier 1 star's 4th planet, a
   tier 8 star's 10th and 11th, and so on, move to the inventory (still owned, just not in orbit).
3. Stars stop saving `planets` and `planetLevels`.
4. Stats carry over once: `planetsEquipped` and `planetsHatched` start at the old
   `planetsBought`; `planetLevels` adds the old `planetUpgrades`.

The conversion only touches stars that still have the old fields, so running it twice changes
nothing. Every load also normalizes planets: an equipped planet whose star is gone, whose slot is
past the star's orbits, or whose slot is already taken goes to the inventory; levels are clamped
to 1–5; planet types this server doesn't know are kept untouched. A failed load still kicks the
player before anything is saved (unchanged).

Achievements now count: Planetfall (`planetsEquipped` 1), Terraformer (level up planets 5
times, `planetLevels`), Worldbuilder (hatch 10 planets, `planetsHatched`). The tutorial's last
step is now "buy an egg, hatch it, equip it".

## Test in Studio

1. **Migration:** join with a save that has planets. Every old planet should appear in the
   Planets panel (P) with its level; those past the star's new orbit count say "In inventory".
   Your income should be at least what it was minus the planets moved to inventory.
2. **Equip:** in the Planets panel press Equip on an inventory planet, choose a star: the planet
   appears in orbit with its look, the NEW WORLD banner plays, income rises.
3. **Move:** from a star's panel, Equip a planet that orbits another star: it leaves that star and
   appears here in the chosen orbit, with no gap in income.
4. **Unequip and level:** both from either panel; income and the moon count update.
5. **Full star:** a star with every orbit taken shows "No free orbit" in the star chooser.
6. **Looks:** inspect planets of different types (needs eggs in stages 3–4 for new players, or
   the migration for old saves); check Reduced effects removes particles only.
7. **Evolve:** evolve a star; its planets stay in their slots and the new orbits show empty.

## Limitations

- New players can't get planets until overhaul stages 3–4 (eggs and hatching).
- Planet customisation (`custom`) is saved and kept but nothing sets it yet.
