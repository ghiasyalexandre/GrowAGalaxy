# Stage 37: Full new-player tutorial, closer star prompts, dimmer glow

**Status: code complete, CI-verified (format, lint, strict types, 227 unit tests, build, world
and orbit smoke tests). Not yet playtested in Studio.**

## The tutorial (Config/Tutorial, TutorialController, TutorialSystem)

Made so young players can follow it: one big card at the top of the screen with a picture, a
short title, two or three simple sentences, "Step N of 13" and a progress bar. The words match
the device: keyboard and mouse, controller, or touch (keys, sticks and on-screen buttons named
for each).

| # | Step | Done when |
|---|---|---|
| 1 | Welcome, Space Explorer! | Next |
| 2 | Float around | you move a little in the suit (or Next) |
| 3 | Get in your spaceship (arrow at Launch Ship) | you launch |
| 4 | Fly your ship | you fly a little (or Next) |
| 5 | Catch some Stardust | you mine a space rock |
| 6 | Buy your first star (arrow at Star Shop) | you place a star |
| 7 | Collect your Stardust (arrow at Hangar, marker on your Collect console) | you collect |
| 8 | Get a planet egg (arrow at Station, marker on the Egg Lab console) | you buy an egg |
| 9 | Hatch your egg (arrow at Hangar, marker on your first incubator dome) | you incubate an egg |
| 10 | Wait for it... (marker on the dome) | the egg hatches |
| 11 | Give your star a planet (arrow at Planets) | you equip a planet |
| 12 | Make your star stronger (marker on your star) | you level up a star |
| 13 | You're a Galaxy Builder! | Finish: **+1,000 Stardust**, once |

Raids aren't part of it.

- **Pointers:** a gold arrow bounces beside the HUD button a step needs, and the button's
  border glows. Places in the world get a "Here!" marker (name, distance, bouncing arrow) and a
  gold outline, both visible through walls.
- **Buttons:** Next / Finish on the steps you confirm (the float and fly steps also finish by
  themselves), **How to play** (the guide), **Hide** (shrinks the card to a small tab at the top;
  tap to bring it back), **Skip** (press twice; no reward).
- **Order:** the card always shows the first step not done, so anything a player already did
  (mined a rock before buying a star, say) is skipped automatically.
- **How to play guide:** every step's instructions for your device, ticked when done, plus
  tips (Daily prizes, the Daily Wheel, the Shipyard, evolving stars, the travel buttons). Open
  it from the card or **Settings → How to play**, also after the tutorial.
- The card sits under every panel (an open shop covers it), moves below the flight gauges while
  flying, and shrinks a little on small screens. The old one-line hint on the HUD is gone.
- **Server:** gameplay steps complete from stats (as before, plus the new `eggsIncubated`).
  Confirm-steps go through `TutorialRequest "ack"`, accepted only for the player's current step;
  the final step pays the reward once. `"skip"` ends the tutorial. Players who had already
  finished the old tutorial don't see it again.

## Star prompts

The star's **Manage star** and **Inspect system** prompts now show from 90 studs (was 400), so
they appear once you're inside the solar system instead of covering it from far away
(`Config.Stars.MANAGE_DISTANCE`).

## Dimmer glow

Everything that glows on player stations (including the Incubator Bay), hangar upgrades (pads
and buildings) and the Zero G Dodgeball arena is 20% dimmer: Neon colours darker, lights and
beams less bright (`Config.World.EMISSIVE_DIM`, `Build.dimEmissive`). The sun-balls' lights are
dimmed by the same share; their colours stay bright so they're easy to see.

## Test in Studio

1. Use a fresh profile (or a test account): the Welcome card shows. Follow every step on
   keyboard, then try a controller and the touch emulator to check the wording and the arrows.
2. Check that the arrow sits beside Launch Ship, Star Shop, Hangar, Station and Planets, and
   that the world markers appear on your Collect console, the Egg Lab, the incubator and your star.
3. Hide and show the card; open How to play from the card and from Settings; Skip (twice).
4. Finish gives 1,000 Stardust once.
5. Star prompts: they appear only close to a star.
6. Look at your station, hangar upgrades and the Dodgeball arena: glow should be noticeably softer.

## Limitations

- World markers need the target streamed in; far away they appear once it loads.
- A tutorial step after a missing target (e.g. a player with no star) still shows its text.
