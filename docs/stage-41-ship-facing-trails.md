# Stage 41: Ship facing, thinner trails from the boosters

**Status: CI-verified (format, lint, strict types, 227 unit tests, build, world and orbit
smoke tests). Not yet seen in Studio.**

- **Ship facing:** Red Fighter, Camo Stellar, Infrared Furtive, Interstellar Runner and
  Transtellar no longer get turned 180 degrees (`yaw` removed in `Config/Ships`), so their noses
  point forward like the other ships. If one still looks off (for example sideways), set its
  `yaw` to 90 or -90 in `Config/Ships`.
- **Trails** (the equipped Stardust trails, `TrailSystem`): they start at **half** their old
  width and narrow to the **same** thin end as before (`WidthScale` 1 to 0.2 of half = 0.1 of the
  configured width).
- **Where trails start:** on ships, midway between the two engine nozzles (`Hull.NozzleL` and
  `NozzleR`, where the boost flames come out). On players (the suit has no boosters), at the
  lower back, just behind and below the root, like a jetpack.

## Test in Studio

Equip a trail, float, then fly each of the five ships: noses point the way you fly, and the trail
comes out of the engines, thinner, tapering to a thin tail.
