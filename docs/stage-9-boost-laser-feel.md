# Stage 9: Boost, laser feel and a sturdier Star Shop

**Status: code complete, CI-verified (format, lint, strict types, 104 unit tests, build, smoke
test). Not yet playtested in Studio.**

## Playable result

- **Star Shop opens three ways:** the station console (as before), the new gold **Star Shop [B]**
  button under the wallet, and the **B** key from anywhere. The panel now reports any listing
  error in Output instead of failing silently.
- **Client start-up isolates failures:** each controller is loaded, initialised and started on
  its own; one that errors is reported in Output (`[Grow a Galaxy] Name.phase failed: ...`) and
  skipped, so it can no longer stop later controllers (the suspected cause of the shop not
  opening).
- **Boost:** hold **Shift** (L3 on gamepad, Boost button on touch) while throttling forward. Top
  speed and acceleration jump; the camera pulls back, widens and shakes; speed lines rush past;
  the engines flare white-hot with extra exhaust (other players see it too). The HUD shows a
  BOOST tank under the heat gauge: it drains while boosting, refills over time, and after running
  dry locks ("BOOST RECHARGING") until a quarter full.

| Ship | Boost | Tank | Full refill |
|---|---|---|---|
| Starter Shuttle | x1.6 | 3 s | 6 s |
| Prospector | x1.8 | 4 s | 5 s |
| Crystal Explorer (later) | x2.1 | 5 s | 4 s |
| Heavy Excavator (later) | x1.5 | 3 s | 7 s |
| Nebula Cruiser (later) | x2.5 | 6 s | 4 s |

- **Heavier laser shots:**
  - a white-hot muzzle flash with light at the nose,
  - a thicker three-layer bolt (wide glow, beam, white core) that races out to its target,
  - where it lands: a flash, an expanding shockwave ring, a bright light, a big spark burst and,
    on asteroids, rock chips,
  - on your own ship: each shot kicks the camera up, punches the view in, nudges the ship back and
    shakes the camera; hits shake it harder.

All numbers are in `Config/Beam.luau` (looks and feel), `Config/Movement.luau` (boost camera,
acceleration, restart share) and `Config/Ships.luau` (per-ship boost).

## What CI verifies vs what needs Studio

| Verified by CI | Needs a playtest in Studio |
|---|---|
| Boost tank rules (drain, lock when empty, refill, unlock share) | Boost feel; whether the flight guard ever snaps you back while boosting |
| Config checks: every ship's boost is above 1x; FOV stays under 120 | Laser weight: flash, bolt travel, impact, recoil and shake strength |
| Strict types, lint, build, smoke test | The Star Shop opens from the console, the button and B |

## Studio hierarchy (new and changed)

```
StarterPlayerScripts/Client                                 bootstrap isolates controller errors
StarterPlayerScripts/Client/Controllers/SpeedLinesController NEW speed lines while boosting
StarterPlayerScripts/Client/Controllers/ShipController       boost, recoil, camera shake
StarterPlayerScripts/Client/Controllers/ShipEffectsController bolt travel, flashes, shockwave, chips, boost flare
StarterPlayerScripts/Client/Controllers/HudController        boost gauge, Star Shop button
StarterPlayerScripts/Client/Controllers/StarShopController   opens from button / B, logs errors
PlayerGui/SpeedLines                                         speed line overlay (client only)
Workspace/Camera/GaG_LaserFx                                 muzzle and impact flashes (client only)
```

## Manual test steps

| # | Steps | Expected |
|---|---|---|
| 1 | Play. Check Output. | `client started`, no `failed:` lines. If one appears, send it. |
| 2 | Press B, or click Star Shop under the wallet. | The Star Shop opens; B again or Close shuts it. |
| 3 | At your station, use the Star Shop console. | Same panel. |
| 4 | Fly, hold W and Shift. | Surge of speed, wider view, shake, speed lines, white engine flare; BOOST bar drains. |
| 5 | Hold boost until empty. | "BOOST RECHARGING", greyed; boost returns at a quarter full. |
| 6 | Click at an asteroid. | Muzzle flash, bolt races out, flash + ring + sparks + rock chips at the hit, camera kick and shake. |

## Known limitations

- Boost is client-driven; the server's flight guard allows the boosted top speed at all times
  rather than tracking the tank.
- No sounds yet: Roblox ships no laser or engine sounds with the client, so these need audio
  assets.
