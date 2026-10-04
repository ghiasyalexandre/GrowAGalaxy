# Stage 2: Movement and ships

**Status: code complete, CI-verified, not yet playtested in Studio.**

## Playable result

Gravity is off everywhere. You float through the ISS in a spacesuit with gentle thrusters, a
strong brake and an optional stabilizer. Outside the airlock, the hangar console launches your
free Starter Shuttle onto a berth. You board it, fly it with arcade controls and a chase camera,
and dock it at the ISS or at your own station by flying slowly into the marked docking area.
You can leave your ship anywhere and float back to it. "Return to Station" brings you home if
you get lost.

The Stage 1 warps between the ISS and your station are gone: you fly there now. The navigation
consoles set a route marker instead. The airlocks still move you between the interior and the
docking platform.

## What CI verifies vs what needs Studio

| Verified by CI on every push | Needs a playtest in Studio |
|---|---|
| Format, lint, strict type check, Rojo build | How the suit and the ship feel (speeds, turning, camera) |
| Unit tests for the flight maths: acceleration and braking limits, input normalisation, camera-relative suit thrust, ship reverse and strafe caps, aim angles, turn-rate limiting, the flight-area edge, the server's travel check, docking-zone tests | Floating with PlatformStand plus constraints behaves as described |
| Unit tests for ship stats with equipment, and that you can't switch to a ship whose hold is too small | Boarding, exiting and docking (seat, network ownership, camera hand-over) |
| Config checks: the suit is slower than every ship, docking is possible below every ship's top speed, the flight area holds every region and stays above the Earth | Touch buttons and gamepad bindings on real devices |
| Smoke test: the place has zero gravity; every ISS and station berth fits a ship, sits inside its docking zone, has a clear 150-stud launch path and at least two clear exit points; ISS berths face outwards; prompts and zones are tagged; the ship is fully welded to an anchored hull with its seat, constraints and prompt | FlightGuard doesn't flag normal play, and does move back a player who teleports |

## Controls

| Action | Keyboard and mouse | Gamepad | Touch |
|---|---|---|---|
| Float or thrust | WASD | Left stick | Thumbstick |
| Up / down | Space / Ctrl or C | RB / LB (A also goes up) | Up / Down buttons |
| Brake (hold) | X | LT | Brake button |
| Stabilizer on/off (suit) | Z | D-pad up | Stabilizer button |
| Steer (ship) | Mouse (cursor locked) | Right stick | Drag on the screen |
| Free the cursor (ship) | Hold Alt | | |
| Exit ship | F | Y | Exit button |
| Dock | G | X | Dock button |
| Interact (board, launch, airlock, route) | E | X | Tap the prompt |
| Return to Station | HUD button | HUD button | HUD button |

In the suit, the camera is Roblox's normal camera and "forward" is wherever it looks. In a ship,
the ship turns towards where you aim, no faster than its turn rate. Letting go of the throttle
glides to a stop, and Brake stops quickly.

## Studio hierarchy

New and changed items only; everything else is as in [Stage 1](stage-1-foundation.md).

```
Workspace                       $properties in default.project.json:
                                Gravity = 0, FallenPartsDestroyHeight = -10000

ReplicatedStorage
├── Shared
│   ├── Config
│   │   └── Movement            ModuleScript   NEW suit, ship handling, camera, docking, flight area, guard
│   ├── Logic
│   │   ├── ConfigCheck         ModuleScript   + movement and flight-area checks
│   │   ├── FlightMath          ModuleScript   NEW pure flight maths shared by client and server
│   │   └── ShipStats           ModuleScript   NEW effective ship stats with equipment, cargo fit
│   ├── Net                     ModuleScript   + four remotes
│   └── Types                   ModuleScript   + ShipInfo
└── Remotes
    ├── ShipRequest             RemoteEvent    NEW client asks to "exit" or "dock"
    ├── ShipState               RemoteEvent    NEW server tells a player their ship model and stats
    ├── SuitRecover             RemoteEvent    NEW client asks for Return to Station
    └── Notify                  RemoteEvent    NEW server sends a short on-screen message

ServerScriptService/Server
├── Systems
│   ├── FlightGuard             ModuleScript   NEW twice-a-second movement check
│   ├── NavigationSystem        ModuleScript   now airlocks only
│   ├── ShipSystem              ModuleScript   NEW launch, board, exit, dock, stow, berths
│   ├── StationSystem           ModuleScript   + getStation (berth, docking zone)
│   ├── SuitSystem              ModuleScript   NEW Return to Station
│   ├── WorldSystem             ModuleScript   + zero gravity, DockZone marker
│   └── DevSystem               ModuleScript   + "launch" command
├── World
│   ├── Build                   ModuleScript   + launch and route prompts, dockZone, berthOutline
│   ├── IssBuilder              ModuleScript   + outward berths, docking zone, hangar console
│   ├── ShipBuilder             ModuleScript   NEW Starter Shuttle greybox
│   └── StationBuilder          ModuleScript   + berth pad, docking zone, hangar and route consoles
└── Util
    ├── Notify                  ModuleScript   NEW
    └── Teleport                ModuleScript   NEW shared "move this character" helper

StarterPlayer/StarterPlayerScripts/Client
├── ClientState                 ModuleScript   + ship, mode, stabilizer, flight readout, route
├── Input                       ModuleScript   NEW one input layer for all devices
└── Controllers
    ├── HudController           ModuleScript   + controls hint, readout, Return to Station, reticle
    ├── NotifyController        ModuleScript   NEW toasts
    ├── ShipController          ModuleScript   NEW flight, chase camera, docking hint
    ├── SuitController          ModuleScript   NEW zero-g spacesuit
    └── WaypointController      ModuleScript   now follows the route (your station or the ISS)
```

Created by code when the game runs:

```
Workspace/Ships/Ship_<UserId>          a player's ship (streams persistently for its owner)
  Hull                                 PrimaryPart, anchored while parked
    Thrust, ExitLeft, ExitRight, ExitTop   Attachments
    Engine                             LinearVelocity (the pilot's client sets it)
    Steer                              AlignOrientation (the pilot's client sets it)
    BoardPrompt                        ProximityPrompt, tag "BoardPrompt"
  PilotSeat                            Seat (CanTouch off)
  Nose, Windscreen, Wing x2, WingLight x2, EnginePod x2, EngineGlow x2, TailFin
Workspace/World/ISS/DockingArea/DockZone, HangarConsole, Berth1-3
Workspace/Regions/Region_<slot>/Station/DockZone, BerthPad, Gangway, StationBerth
Character/HumanoidRootPart/SuitAttachment, SuitThrust, SuitStabilizer   (client only)
PlayerGui/Hud, PlayerGui/Notifications, PlayerGui/RouteWaypoint
```

### Replacing the greybox ISS

The Stage 1 contract still applies, with these changes. Berths `Berth1` to `Berth3` should face
the direction ships leave in (their LookVector), with room for a ship around them. Add a part
named `DockZone` (non-colliding) that covers the berths and their approach, tagged `DockZone`
with a number attribute `OwnerUserId = 0`. Add a hangar ProximityPrompt tagged `LaunchPrompt`
with a string attribute `Hangar = "ISS"`, and a navigation prompt tagged `RoutePrompt` with
`RouteTarget = "Station"`. The airlock prompts keep the `WarpPrompt` tag; `WarpTarget =
"OwnStation"` is no longer used.

## Setup

1. Check out the `stage-2-movement-ships` branch. If `rojo serve` is already running, it picks
   up the new files; reconnect the Rojo plugin if Studio doesn't show `Workspace.Gravity = 0`.
2. Nothing else changes from Stage 1. No new assets or settings are needed.

## Manual test steps

| # | Steps | Expected |
|---|---|---|
| 1 | Press **Play**. | You spawn in the Arrival module and start floating. The bottom-left reads "Stabilizer on" and the hint shows the suit controls. The output has no `[Config]` warnings. |
| 2 | Float through the station with WASD, Space and Ctrl. | Movement follows the camera, speeds up gently, and tops out at a slow drift. Letting go stops you within about a second. X stops you quickly. |
| 3 | Press Z, float, then let go. | "Stabilizer off" toast. You keep drifting until you press X or Z. |
| 4 | Use the Docking Airlock, then the **Hangar** console ("Launch ship"). | Toast: "Your Starter Shuttle is ready at the berth". A white shuttle with wing lights in your region colour sits over a berth, nose pointing away from the station. |
| 5 | Float to it and press E on **Board**. | You sit in the cockpit. The camera moves behind the ship, the cursor locks, the hint shows flight controls and the readout shows `Speed 0 / 120`. |
| 6 | Fly: mouse to steer, W/S, A/D, Space/Ctrl, X. | The nose follows the aim smoothly. Full throttle reaches about 120. Releasing W glides to a stop; X stops in a second or two. You can't climb more than 80 degrees. |
| 7 | Hold Alt. | The cursor appears and steering pauses. Release to steer again. |
| 8 | Press F away from any station. | You float out beside the ship, which stays parked in place. Its Board prompt works again. |
| 9 | Fly towards your station (follow the "Your station" marker). Enter the translucent box around its berth pad at full speed, then slow down. | The hint first says to slow below 25, then "press G to dock". |
| 10 | Press G. | The ship snaps onto the berth over the pad and you float out beside it. Toast: "Docked." |
| 11 | Use the station's **Navigation** console. | Toast "Route set: ISS docking area"; the marker now points at the ISS. Launch from the station **Hangar**, fly back and dock at the ISS. |
| 12 | Press **Return to Station** in the HUD, both while floating and while flying. | You appear on your station deck; if you were flying, your ship is gone (launch it again from a hangar). Pressing again within 15 s shows a recharge message. |
| 13 | Local Server with 2 players. Player 2 floats to player 1's ship. | No Board prompt for player 2. Player 2 can't launch from player 1's station hangar (toast explains). Both can share the ISS berths. |
| 14 | Local Server with 4 players: three launch at the ISS, wait 30 s, then the fourth launches. | The fourth gets a berth; the longest-parked ship is stowed and its owner gets a toast. |
| 15 | While floating, switch the command bar to the **Client** view and run `game.Players.LocalPlayer.Character:PivotTo(CFrame.new(0, 0, 4000))` (a teleport the server didn't make). | Within a second the server moves you back and the server output shows a `[FlightGuard]` warning. Normal floating and flying never trigger it. |
| 16 | Fly straight out past your region and keep going. | Around 6000 studs from the ISS you stop moving outwards; you can still turn and fly back. |
| 17 | On a phone (Device emulator) and with a gamepad. | Touch: Up, Down, Brake (suit) and Up, Down, Brake, Exit, Dock (ship) buttons appear; dragging on the open screen steers. Gamepad: bindings as in the table. |

## Acceptance criteria

Verified by CI:

1. Format, lint, strict type check, Lune unit tests (55), Rojo build and the smoke test pass.
2. The suit is slower than every ship; acceleration and braking are rate-limited; diagonal input
   isn't faster; reverse and strafe are capped; turning respects the turn rate (unit tests).
3. The server's travel check accepts top speed with tolerance and rejects teleports (unit test).
4. Every berth (3 at the ISS, 1 per station) fits a ship, lies inside a docking zone that extends
   in front of it, has a clear launch path and clear exit points; ISS berths face outwards
   (smoke test).
5. The place runs with zero gravity and won't destroy parts below the ISS (smoke test).

Needs a Studio playtest (steps above):

6. Zero-g suit movement with braking, stabilization and Return to Station (tests 1 to 3, 12).
7. Launch, board, fly, exit and assisted docking at the ISS and at your own station (4 to 11).
8. Ownership: nobody else can board your ship or use your hangar; idle ships free up ISS berths
   (13, 14).
9. FlightGuard catches impossible travel without flagging normal play; the flight area holds
   (15, 16).
10. Touch and gamepad controls work (17).

## Tuning

Everything that affects feel is in `src/shared/Config/Movement.luau` (suit speeds, reverse and
strafe shares, idle glide, camera distance and smoothing, look sensitivity, docking speed) and
in each ship's stats in `Config/Ships.luau` (top speed, acceleration, braking, turn rate). After
playtesting, tell me what felt wrong ("turns too slowly", "camera too close") and I'll adjust.

## Known limitations

- Untested in Studio: everything in the right-hand column above. The riskiest parts are the
  seat and PlatformStand hand-over when boarding and leaving, and the camera hand-over.
- Every ship uses the Starter Shuttle greybox. The hangar only launches your active ship; ship
  selection, comparison, equipment and cosmetics come with the Prospector in Stage 5.
- The suit has no floating animation: with PlatformStand the character holds a still pose.
- The chase camera can clip through the ISS when you fly very close to it.
- Return to Station is instant, with a 15 s cooldown. Once mining exists it could be used to
  skip the flight home; Stage 3 may add a short channel time.
- Ships parked away from a berth stay until you launch again or leave the game, and can block a
  path. Only ISS berths reclaim idle ships.
- A fast ship that rams a floating player can push them hard enough for FlightGuard to move
  them back.
- The stabilizer choice and look sensitivity aren't saved yet (settings arrive in Stage 7).
- Touch button positions use Roblox's default layout and haven't been checked on real phones.
