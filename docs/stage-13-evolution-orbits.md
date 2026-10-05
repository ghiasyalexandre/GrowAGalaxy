# Stage 13: Evolution ladder, visible orbits, system inspector

**Status: code complete, CI-verified (format, lint, strict types, 118 unit tests, build, smoke
test). Not yet playtested in Studio.**

## Playable result

**Levels and evolution.** A star levels up from 1 to its type's max level, then evolves:

| Tier | Star | Max level | Orbits |
|---|---|---|---|
| 1 | Brown Dwarf | 4 | 4 |
| 2 | Red Dwarf | 6 | 5 |
| 3 | Yellow Dwarf | 8 | 6 |
| 4 | White Dwarf | 10 | 7 |
| 5 | Red Giant | 12 | 8 |
| 6 | Blue Giant | 14 | 9 |
| 7 | Red Supergiant | 16 | 10 |
| 8 | Black Hole | 18 | 11 |

- **Evolve** is only possible at max level (the button reads "Evolve at level N" until then).
  Evolving costs the next type's price, keeps every planet, adds one orbit, and starts the star
  again at **level 1**. Reaching max level shows a MAX LEVEL banner ("Ready to evolve into ...").
- Max level grows by 2 per evolution, so it's always even (`MAX_LEVEL_BASE` 4, `MAX_LEVEL_STEP`
  2 in `Config/Stars`; ConfigCheck keeps both even).
- Each level adds 75% of the type's base production (x1, x1.75, x2.5 ...). Level-ups cost
  40% of the type's price, growing 25% per level. The star grows up to 20% bigger by max level.
- Orbits depend on the type, not the level, so they never close again when a star evolves.

**Visible orbits.** All of a star's orbits show as rings. Planets used to sit far outside their
star's light (a PointLight reaches 60 studs at most) and looked dark; now each planet carries a
light on its sunward side in the star's colour, so its day side glows and its night side stays
dark. Each also leaves a glowing trail along its orbit, and they're a little bigger. Orbits are
evenly spaced (44 studs out, 17 apart) and follow Kepler's law: the innermost has an 88-day year,
the 11th about 2.6 years. A system now reaches 222 studs (was 210); star spacing and wall margin
grew to match.

**Inspect a system.** Any star, yours or another player's, has an **Inspect system** prompt (R,
or R3 on a gamepad); your own stars also have **Inspect** in the Manage panel.

- The camera circles the star (drag to orbit, mouse wheel to zoom; right stick and D-pad on a
  gamepad). Each planet is labelled with its name, orbit and the length of its year.
- **System time** slider: from 1 hour per second up to 3 decades per second, on a log scale
  (marks at 1 hour, 1 day, 1 year and 3 decades per second). D-pad left/right moves it.
- **Pause / Play**, **Normal** (back to the everyday speed, 5.5 days per second), and "Time
  passed" since you opened the view.
- Backspace, B or the close tile leaves. While inspecting from a ship, the ship coasts to a stop
  and its controls stand by.
- The time slider is local: other players keep seeing the shared speed.

## Save data

Schema v5: a saved level above its type's new max is lowered to the max on load (e.g. a level 5
Brown Dwarf becomes level 4, ready to evolve). Planets are kept.

## What CI verifies vs what needs Studio

| Verified by CI | Needs a playtest in Studio |
|---|---|
| Max levels even and +2 per tier; evolve only at max; level-up stops at max; 4 + tier - 1 orbits; free slots up to the type's orbits; star size at max level | Planets clearly visible and lit; trails look good, not noisy |
| Kepler periods rise outward; slider maps 1 hour..3 decades per second both ways; time labels | Inspect camera, slider dragging, labels; leaving restores the suit or ship camera |
| v5 clamps old levels; orbit config fits SYSTEM_RADIUS | Prices feel right across the longer ladder |

## Studio hierarchy (new and changed)

```
ReplicatedStorage/Shared/Logic/OrbitTime                    NEW orbit angles, slider scale, time labels
ReplicatedStorage/Shared/Config/Stars                       per-tier max level, generated orbits, clock rates
StarterPlayerScripts/Client/Controllers/InspectController   NEW inspect camera, labels, time panel
StarterPlayerScripts/Client/Controllers/StarController      orbit clock, lit planets with trails, Inspect prompt/button
StarterPlayerScripts/Client/Controllers/ShipController      stands by while inspecting
PlayerGui/Inspect                                           the time panel
Workspace/Camera/GaG_InspectLabels                          planet labels (client only)
<star>/Core/GaG_Inspect                                     local Inspect prompt (client only)
```

## Manual test steps

| # | Steps | Expected |
|---|---|---|
| 1 | Place a Brown Dwarf, look at it. | 4 faint orbit rings. |
| 2 | Buy a planet. | It orbits with a lit day side and a trail. |
| 3 | Manage: level up to 4. | Evolve reads "Evolve at level 4" until then; MAX LEVEL banner at 4. |
| 4 | Evolve. | Red Dwarf at level 1/6, 5 orbits, planets kept. |
| 5 | Press R near any star. | Inspect view; planets labelled with their years. |
| 6 | Drag the slider fully left, then right. | 1 hour/s (nearly still) to 3 decades/s (inner planets blur round). |
| 7 | Pause, Normal, Backspace. | Time stops; returns to 5.5 days/s; camera back to normal. |
