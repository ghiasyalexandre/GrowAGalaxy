# Stage 15: Opt-in PvP, ship explosions, over-the-shoulder camera

**Status: code complete, CI-verified (format, lint, strict types, 125 unit tests, build, smoke
test). Not yet playtested in Studio. PvP needs two players (Studio: Test → Clients and Servers,
2 players).**

## Playable result

**PvP switch.** A **PvP: off / ON** button next to the effects button. It's saved with your
settings and is off by default. A laser shot damages another ship only if:
- both pilots have PvP on,
- the target is being piloted (parked ships can't be shot),
- neither ship is inside a docking area (ISS or any station: safe zones).

You can't switch PvP off within 15 s of dealing or taking damage ("You're in combat ..."), or
toggle it more than once every 3 s. Ships of PvP players carry a red **PvP** tag, with a hull bar
once damaged.

**Hull.** Every ship has hull points, from 100 (Micro Recon) up by 30 per ship to 400 (Meteor
Slicer); equipment can modify `hull` like any stat. A hit does the shooter's laser power x 0.6
(a Micro Recon needs 17 shots to destroy another, so heat matters). The hull repairs itself
6 s after the last hit at 8% per second. A **HULL** gauge shows while flying.

**Destruction (option 1).** At 0 hull every client sees:
- a white flash inside a swelling fireball, a shockwave ring in the wing plane, smoke, fire and
  sparks, and a low boom (the built-in `impact_explosion_03` sound, played at 0.7 speed);
- 28 chunks of hull (14 with reduced effects) in the ship's paint and darker shades, about 30%
  of them glowing embers trailing fire, flung out, tumbling, slowing and fading over 2.8 s.

Cameras within 300 studs shake. The pilot floats free at the wreck; both players get a message;
the owner can launch again after 5 s. Nothing is lost.

**Feedback.** A hit marker flashes at the reticle when your shot damages a ship. When your own
ship is hit, the screen's edges flash red and the camera shakes.

**Over-the-shoulder camera.** **Tap Alt** (D-pad right on a gamepad) to toggle it. Flying, the
chase camera slides 8 studs right, so the ship sits left of the reticle; in the suit the camera
moves 2.5 studs right. **Holding Alt** still frees the mouse cursor while flying (a press longer
than 0.3 s counts as a hold).

**Slower laser bolts.** Bolts take 0.0625 s to reach their target instead of 0.05 s (20% slower;
`Config.Beam.BOLT_TRAVEL_TIME`). Hits are still decided by the server at once.

**Hit box.** A ship wearing an imported model now has an invisible hull sized to the model (60%
of its width, 80% of its height, 85% of its length) instead of the fixed 6x4x12 box, so shots
and collisions match what you see.

## Tuning

All in `Config/Combat` (damage, repair, combat lock, relaunch delay, explosion size and timing,
debris count/speed/lifetime/embers, shake, tag distance, sound) and `Config/Movement` (shoulder
offsets, smoothing, Alt tap time). Hull points are in `Config/Ships`.

## Save data

`settings.pvp` (boolean, default off) is filled in on load like the other settings; no schema
bump was needed.

## What CI verifies vs what needs Studio

| Verified by CI | Needs a playtest in Studio (2 players) |
|---|---|
| Only two opted-in pilots, outside docking areas, damage each other; parked ships immune | Shots damage, tags and hull bars show, safe zones hold |
| Damage scales with laser power; repair after the delay; switch-off refused mid-fight | Explosion and debris look and sound right; relaunch waits 5 s |
| Hull rises along the ladder; combat config checked | Alt tap vs hold feels right; shoulder view in ship and suit |

## Studio hierarchy (new and changed)

```
ReplicatedStorage/Remotes/ShipDestroyed                   NEW server -> all: draw an explosion
ReplicatedStorage/Shared/Config/Combat                    NEW PvP and explosion tuning
ReplicatedStorage/Shared/Logic/CombatMath                 NEW damage, repair, toggle rules
ServerScriptService/Server/Systems/CombatSystem           NEW hits, hull, PvP switch, PvP attribute
ServerScriptService/Server/Systems/ShipSystem             destroy(), shipOf(), relaunch delay
StarterPlayerScripts/Client/Controllers/CombatController  NEW explosions, tags, hit marker, damage flash
StarterPlayerScripts/Client/Controllers/ShoulderController NEW Alt shoulder view (suit)
StarterPlayerScripts/Client/Controllers/HudController     PvP button, HULL gauge
PlayerGui/Combat                                          hit marker and damage flash
Workspace/Camera/GaG_Explosions                           explosion parts (client only)
Player attribute PvP, ship attributes Health and Paint
```

## Manual test steps

| # | Steps | Expected |
|---|---|---|
| 1 | Tap Alt in the suit, then flying. | Camera shifts right; tap again to return. Holding Alt frees the cursor. |
| 2 | Two players: both press PvP, launch, fly out of the docking areas. | Red PvP tags over each other's ships. |
| 3 | Shoot the other ship. | Hit markers; their hull bar drops; their screen edges flash red. |
| 4 | Keep firing until it breaks. | Fireball, ring, smoke, tumbling chunks with fiery embers, boom; pilot floats free. |
| 5 | Victim launches straight away. | "Being rebuilt" until 5 s have passed. |
| 6 | Turn PvP off right after a hit. | Refused with the seconds left. |
| 7 | One player without PvP. | Their ship takes no damage and shows no tag. |
