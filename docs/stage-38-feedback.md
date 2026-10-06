# Stage 38: Feedback round (bloom, cursor, codes, visits, eggs, tutorial)

**Status: code complete, CI-verified (format, lint, strict types, 226 unit tests, build, world
and orbit smoke tests). Not yet playtested in Studio. No Robux involved.**

| Change | Where |
|---|---|
| **Softer bloom indoors:** while the camera is inside any player's station (hangar and Incubator Bay) or the Zero G arena, the bloom eases from 0.6 down to 0.2, and back outside. | `BloomController`, `Config.World.BLOOM_INTENSITY / BLOOM_INDOOR` |
| **Mouse cursor while flying:** press **M** to free the cursor (click PvP, Planets or any HUD button without leaving the ship), M again to steer. Holding Alt still works. The controls hint says so. | `Input` (CursorToggle), `ShipController` |
| **Inspecting hides the prompts:** while a solar system is inspected, every star's Manage and Inspect prompts are hidden; they come back on leaving. | `StarController.setPromptsShown`, `InspectController` |
| **Manage/Inspect prompt distance +50%:** 90 to 135 studs. | `Config.Stars.MANAGE_DISTANCE` |
| **Code PlanetzPlz:** one level 1 planet of each of the 28 types into the inventory (and the Planet Index). Needs 28 free planet spaces, or it says how many to free first and isn't used up. | `Config.Codes`, `DataSystem.redeemCode` |
| **Code StarzShipz:** every spaceship. | same |
| **Visit other players' hangars:** a **Visit** button in the bottom row (beside Launch Ship, on foot) lists everyone in the server; Visit takes you to their hangar, and they're told. Shares the travel cooldown. | `VisitController`, `SuitSystem` (`"visit", userId`) |
| **Mystery eggs cost a flat 1,000 Stardust** (no rise per egg). ×5 and ×10 cost 5,000 and 10,000. | `Config.Eggs` (`PRICE_BASE 1000`, `PRICE_GROWTH 1`) |
| **Planets only from eggs:** the "Choose a planet" egg is gone (server action removed). Eggs already bought that way still hatch. | `EggSystem`, `EggShopController` |
| **Chat announcements:** Legendary and Interstellar hatches are posted in this server's chat ("[Planet Egg] Name hatched a Legendary Phoenix Core!", in the rarity's colour). Epic+ still pop up as messages and on the ISS board. | `ChatController`, `ChatAnnounce` remote, `Config.Eggs.CHAT_RARITY` |
| **Hatch times rounded up to 30 s:** Common 30 s, Uncommon 30 s, Rare 90 s, Epic 4 min, Legendary 11 min, Interstellar 30 min. Hatches already running keep their end time. | `Config.Planets` |
| **"Berth" is now "Dock":** the pad (`DockPad`), outline (`DockOutline`), marker (`StationDock`) and every message. | `StationBuilder`, `Build`, `ShipSystem` |
| **Easier tutorial:** every step is one short line (at most 80 letters, checked by ConfigCheck) with a big font. Visual cues: a row of dots (done = green tick, current = gold with its number, coming = dim), "Next: …" under it, and a big green **✓ Great job!** flash when a step is done. | `Config.Tutorial`, `TutorialController` |

## Notes

- Without a "choose a planet" option, players where Roblox restricts paid random items (and
  anyone while that check hasn't answered) can't get planets at all. That's allowed, but those
  players can only grow with stars.
- The visit button is hidden while flying because travelling stows the ship.

## Test in Studio

1. Bloom: walk around your station and the arena, then fly out: the glow softens indoors.
2. Fly, press M: the cursor appears; click PvP; press M: steering again.
3. Inspect a system: no Manage/Inspect prompts on screen; leave: they're back. They appear from
   about 135 studs.
4. Settings → code box: `PlanetzPlz` (28 planets in Planets), `StarzShipz` (all ships in the
   Shipyard).
5. With two clients: Visit the other player; they get a message.
6. Egg Lab: every egg 1,000; no "Choose a planet" tab.
7. Hatch a Legendary (e.g. from `PlanetzPlz`... codes don't hatch, so use eggs) and watch the
   chat in both clients.
8. Hatch times: a Common takes 30 s.
9. Fresh profile: the tutorial card shows one line per step, the dots and the green flash.
