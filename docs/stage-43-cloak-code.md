# Stage 43: Planet names in rarity colours, the cloak code

**Status: CI-verified (format, lint, strict types, 227 unit tests, build, world and orbit
smoke tests). Not yet seen in Studio.**

## Planet names in rarity colours

Planet names now use their rarity's colour (grey, green, blue, purple, orange, pink) in the
Inspect labels, the star panel's orbit rows and planet picker, the Egg Lab odds list (dimmer for
types not found yet) and the incubator's egg list. The Planets panel and ISS gallery already did.

## Code SneakySpace: the cloak

Redeeming **SneakySpace** (Settings, code box) unlocks a **Cloak** switch in Settings
(Hidden / Visible). While hidden:

- your character and your ship are fully invisible to everyone, your name tag is hidden and
  your trail is removed;
- you see yourself faintly (75% see-through), only on your own screen;
- laser shots and engine flames still show, so you're not completely untraceable;
- switching it off (or leaving) puts everything back, including a ship you left behind.

The unlock is simply having redeemed the code (no save change). `CloakSystem` does the hiding
twice a second, so new characters, launched ships and respawns stay hidden.
`Config.Codes`: any code with `cloak = true` unlocks it.

## Test in Studio (two clients)

1. Redeem SneakySpace; Settings shows Cloak. Turn it on: the other client can't see you or your
   ship, you see yourself faintly.
2. Fly and shoot: the other client sees the laser and engine glow only.
3. Turn it off: fully visible again on both.
