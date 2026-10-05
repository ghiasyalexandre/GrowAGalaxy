# Stage 19: A roomier ISS, the Saturn V raid beacon, Death Star raids

**Status: code complete, CI-verified (format, lint, strict types, 157 unit tests, build, smoke
test). Not yet playtested in Studio.**

> Boss moves, health and rewards changed in [stage 20](stage-20-polish.md); the tables below
> are as of stage 19.

## The ISS, rebuilt

The station's tube is wider (radius 16, a 28-stud floor) with window bands along both sides.
From one end to the other:

| Module | What's there |
|---|---|
| Observation Cupola | Big windows onto Earth |
| Arrival | Where players spawn |
| Star Lounge | A turning galaxy hologram, couches along the walls |
| Navigation | The route console to your station |
| Zero-G Playground | 10 bouncy glowing balls to push around, floating neon hoops |
| Ship Showroom | Red Fighter and Ultraviolet Intruder models turning on pads (with imported models) |
| Raid Airlock | Warps out to the raid platform |

The whole ISS is a PvP **safe zone** (a part tagged `SafeZone`). The old docking berths, ISS
launch console and ISS docking zone are gone: ships launch and dock only at your own station.

## The raid platform and the Saturn V beacon

Outside the Raid Airlock is a 260 × 260 platform. In the middle stands the **Saturn V**
(`assets/roblox/Stuff/SaturnV.rbxm`, mapped to `ServerStorage/Assets/Stuff`), scaled to 170
studs tall. Every script, sound, click detector, prompt and humanoid inside the model is removed
before it is placed, and every part is anchored. Without the asset, a greybox rocket stands in.

Glow around it: three neon rings on the floor turning in alternate directions (cyan, violet,
pink), a glowing base, a light beam into the sky, sparkles rising and coloured lights.

Around the rocket are three **difficulty pads**: a glowing circle under a pulsing light column,
with a sign showing the difficulty, its reward, the queue (`2 / 6 in queue`) and its status
(`Launching in 14s`, `Raid in progress`).

## Queues

- **Join:** step on a pad or use its **Join** prompt. You can be in only one queue; joining
  another moves you.
- **Leave:** use the prompt again, or the **Leave** button on the queue chip.
- A queue holds up to **6** players. It launches 20 s after the first player joins, or 5 s after
  it fills, once no raid of that difficulty is running. Queued players show a chip at the top
  of the screen with the count and the countdown.

## Raids

Everyone in the queue is put in their active ship 520 studs in front of the **Death Star**
(`assets/roblox/Bosses/DeathStar`, mapped to `ServerStorage/Assets/Bosses`, 260 studs across;
a grey sphere without the asset). Each difficulty has its own arena, so all three can run at
once.

- **Shoot it** with the ship's laser. The glowing green **superlaser dish** (the weak point)
  takes **3×** damage.
- **Turbolaser volleys:** green bolts fly to where a raider *was* when they were fired. Keep
  moving and they miss.
- **Superlaser** (Medium and Hard): the dish charges for 3 s, with a red aiming line and a
  **SUPERLASER CHARGING: MOVE!** warning, then fires a huge beam down that line.
- **Damage** uses ship hull from stage 15. A raider whose ship is destroyed, who leaves their
  ship or who leaves the game is out, and is sent back to the platform.
- **The HUD** shows a boss bar with health, time left (5 min) and raiders still flying.
- **The win:** a chain of explosions and a blinding flash. Then, after 6 s, everyone returns to
  the raid platform (without their ship).
- **Rewards** go to raiders who are still flying, or who dealt at least 3% of the boss's health.
  They show in a **RAID VICTORY** banner.

| Difficulty | Boss health (1 raider) | Extra per raider | Volleys | Superlaser | Reward |
|---|---|---|---|---|---|
| Easy | 1,500 | +60% | 2 bolts every 4 s, 12 dmg | No | 3,000 Stardust |
| Medium | 4,000 | +70% | 3 bolts every 3 s, 18 dmg | Every 30 s, 70 dmg | 9,000 Stardust + 10 min 2x Mining |
| Hard | 10,000 | +80% | 4 bolts every 2.2 s, 26 dmg | Every 20 s, 120 dmg | 25,000 Stardust + 20 min 2x Stars |

- Rewards are fixed; no multiplier applies. Boost time adds to the same boosts sold in the Store
  and given by daily prizes.
- Stats `raidsWon` and `raidsWon<Difficulty>` are recorded, for future achievements.
- Tuning: `src/shared/Config/Raids.luau`. Rules: `Logic/RaidMath` (tested).

## Code

| File | Job |
|---|---|
| `Config/Raids`, `Logic/RaidMath` (+ spec) | Tuning; boss health, damage, queue timing, reward eligibility, hit tests |
| `World/IssBuilder` | The rebuilt ISS and the raid platform (markers `RaidBeacon`, `DockingSpawn`) |
| `World/RaidBuilder` | Saturn V beacon and glow, difficulty pads, the Death Star |
| `Systems/RaidSystem` | Queues, raids, boss attacks, rewards, sending players home |
| `Systems/ShipSystem` | ISS berths removed; `spawnAndBoard` for raids |
| `Systems/CombatSystem` | `damageShip` for boss attacks; `SafeZone` tag |
| `Systems/BeamSystem` | Hands each shot to `RaidSystem.shot` |
| `DataSystem.grantRaidReward` | Stardust plus boost time |
| `RaidController` (client) | Queue chip, boss bar, bolts, superlaser, finale, victory banner |
| `SpinController` (client) | Turns `GaG_Spin` decorations, pulses `GaG_Pulse` parts |
| Remotes | `RaidRequest` (join/leave), `RaidEvent` (effects and results) |

## Test in Studio

1. In Studio, check that `ServerStorage/Assets/Stuff/SaturnV` and
   `ServerStorage/Assets/Bosses/DeathStar` are there after Rojo syncs.
2. Play. Walk through the ISS: the modules, the hologram turning, the playground balls.
3. Take the Raid Airlock. The Saturn V should stand **upright** on the platform with turning
   rings. If it lies on its side, report it: the model's up axis then needs a fixed rotation.
4. Step on the Easy pad. The chip should show the countdown; after 20 s you should be in your
   ship facing the Death Star.
5. Dodge bolts and shoot the green dish; check the boss bar drops faster on the dish.
6. Win (or let the timer run out) and check the banner, the reward and the return to the
   platform.
7. Repeat on Medium to see the superlaser warning and beam.

## Known limitations

- **Saturn V orientation:** the rocket is assumed to be modelled standing along its Y axis.
- **Death Star dish position:** the weak point is placed at the upper front of the sphere
  (facing raiders), not matched to the mesh's own dish.
- **Lune smoke test:** the smoke test can't scale models, so it checks the greybox rocket. The
  real asset needs a playtest.
- **Shared arenas:** players watching from nearby see every raid's effects; only raiders see
  the HUD.
- **Damage scaling:** boss health assumes the beam powers of the current ship ladder; tune
  `bossHealth` after playtesting.
