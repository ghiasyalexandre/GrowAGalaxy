# Stage 22: Hangar and Station travel buttons, Zero G Dodgeball

**Status: code complete, CI-verified (format, lint, strict types, 173 unit tests, build, world
and orbit smoke tests). Not yet playtested in Studio.**

## Travel buttons

The bottom-left **Return to Station** button is now two buttons:

| Button | Takes you to |
|---|---|
| **Hangar** | Your own station, your tycoon (the ISS if you have none yet) |
| **Station** | The ISS arrival module, where everyone spawns |

- Any ship you're flying is stowed first.
- Both buttons share an 8 s cooldown (was 15 s).
- The Launch Ship button moved right to make room.

## Zero G Dodgeball

The ISS **Zero-G Playground** module is now the **Zero G Dodgeball** portal room:
- A big glowing ring with a shimmering sun-coloured field.
- Its prompt, **Play Zero G Dodgeball**, warps you to the arena.
- The bouncy balls are gone; two small hoops stay for show.

**The arena** is 1,000 studs below the ISS, clear of the asteroid field:
- **Walls:** a 260 × 160 × 260 glass box with a glowing gold frame along its edges. The walls are
  solid, so players and balls stay in.
- **Cover:** 34 floating, glowing neon blocks (cubes, slabs and pillars), laid out the same on
  every server and always at least 8 studs apart, so you can float between them.
- **Spawns:** 8 points around the walls.
- **Exit:** a portal by the first spawn goes **Back to the ISS**.
- **No queue:** anyone inside the box is playing; leaving it (the portal or the travel buttons)
  ends it.
- **No ships:** a piloted ship that comes within 40 studs of the box is stowed.

**Moving:**
- Your suit floats **2× faster** in the arena.
- **Launch** (Shift / gamepad B / touch button) next to any block face, or a wall, throws you
  off it at 95 studs per second. You fly away from the face and towards where you're looking,
  never back into it. A ring of light flashes where you pushed off. The cooldown is 0.5 s.

**The sun-ball:**
- Everyone holds an endless dodgeball shaped like a little sun: a white-hot core in a blazing
  orange shell with flames, a glow and a fiery trail. A small one glows in your hand while it's
  ready.
- **Throw** (click / R2 / touch button): it flies straight (zero-g) at 150 studs per second where
  you aim: the mouse, or straight ahead on a gamepad or touch screen.
- The next ball is ready **1.6 s** later.
- **On a block or wall:** the ball bursts.
- **On another player:**
  - They're **out**: flung back, with a red flash and "OUT! Hit by <name>".
  - After 2 s they reappear at a random spawn.
  - You score a hit.
- **The server decides every hit:** it sweeps a sphere along the ball's path each frame. Players
  who are already out can't be hit again.
- **HUD:** a banner shows **Hits** and **Outs** this session and whether your sun is ready.
  Hits also count towards the saved stat `dodgeballHits`.
- **Anti-cheat:** the server's speed check allows the faster suit, launches and knockbacks only
  inside the arena.

Tuning: `src/shared/Config/Dodgeball.luau`. Rules and tests: `Logic/DodgeballMath`.

## Code

| File | Job |
|---|---|
| `Config/Dodgeball`, `Logic/DodgeballMath` (+ spec) | Arena geometry, block layout, spawns, launch direction, ball path |
| `World/DodgeballBuilder` | Glass box, frame, cover blocks (tag `DodgeBlock`), spawns, exit portal, sign |
| `Systems/DodgeballSystem` | Membership, no-ships rule, throws, hits, respawns, held sun |
| `DodgeballController` (client) | Throw / Launch bindings, sun visuals, knockback, banner |
| `SuitController` | Arena speed, `launch()` |
| `NavigationSystem.addTarget` | Lets DodgeballSystem own the "Dodgeball" warp target |
| `SuitSystem`, `HudController` | Hangar / Station travel |
| Remotes | `DodgeballThrow`, `DodgeballEvent` |

## Test in Studio (2 players for hits)

1. **Travel:** press Hangar, then Station. You should land at your station, then at the ISS.
2. **Portal:** at the ISS, go to the Zero G Dodgeball module and use the portal.
3. **Moving:** float around; you should be faster. Press Shift next to a block to launch.
4. **Throwing:** click to throw. The sun should fly and burst on blocks, and the hand sun should
   dim until it's ready again.
5. **Hits:** with a second player, a hit should fling them, flash red and respawn them.
6. **No ships:** fly a ship towards the arena; it should be stowed.
7. **Leaving:** use the exit portal; the banner should go away.

## Known limitations

- Hits use the server's view of where players are, so at high ping a ball that looked like a
  near miss can count, and the other way round.
- There's no round structure or leaderboard: just session hits and outs.
