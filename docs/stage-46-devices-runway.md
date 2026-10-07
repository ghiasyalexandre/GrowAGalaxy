# Stage 46: Real machines for Collect, Galaxy Control and the Egg Lab; runway switch

**Status: CI-verified (format, lint, strict types, 228 unit tests, build, world and orbit
smoke tests). Not yet seen in Studio.**

## The machines (World/DeviceBuilder)

The three plain console boxes are now machines that look like what they do. Same places, same
prompts, same panels.

- **Stardust Collector** (your hangar deck, centre): a round base, a stem, a glass collector
  sphere with the glowing gold Stardust core inside (and a gold orbit ring), three glowing intake
  arms rising from the base to the sphere, a cap, and a slanted control panel at the front
  ("Collect"). The prompt is on the panel.
- **Galaxy Control** (left of the Collector): a holo-table. A projector glows on the table top
  and above it a purple galaxy disc with a golden core, two orbit rings and three stars slowly
  turns. Slanted front panel "Galaxy Control".
- **Planet Egg dispenser** (ISS Planet Egg Lab, where the console was): a white machine on a
  plinth with "Planet Eggs" on the front, a chute, a glowing coin slot, six rarity lights
  (Common to Interstellar) along the top and a glass dome with a pink egg turning inside.

The part names the tutorial markers and reward effects look for are kept
(`CollectConsole`, `StardustOrb`, `GalaxyConsole`, `EggConsole`). The station is now 120 parts
(its budget in the world smoke test went from 110 to 130); the ISS is 339 of 400.

## Neon Runway switch

Once you've built the **Neon Runway**, Settings shows a **Neon Runway: On / Off** switch. Off
removes it from your hangar; On builds it back. Nothing is refunded or lost, it's still yours.

- Saved in the profile (`hangarOff`, schema **version 18**; empty for everyone, so nothing
  changes until you switch). Only built upgrades marked `toggle = true` in `Config/Hangar` can
  be switched (the runway for now: add `toggle = true` to another vanity upgrade to make it
  switchable too).
- `SettingChanged("hangarToggle", id, on)` → `DataSystem.setHangarOff` → `HangarSystem.refresh`.

## Test in Studio

1. Your deck: the Collector and Galaxy Control look right, face the spawn, and their prompts and
   panels work; the hologram turns (not with Reduced effects).
2. ISS Egg Lab: the dispenser opens the Egg Lab; the egg turns.
3. Build the Neon Runway, then Settings → Neon Runway Off: it disappears; On: it's back; rejoin:
   the choice is kept.
