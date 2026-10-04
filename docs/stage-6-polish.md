# Stage 6: Atmosphere and polish

**Status: code complete, CI-verified (format, lint, strict types, 96 unit tests, build, smoke
test). Not yet playtested in Studio.**

## Playable result

- **Ambient sparkles.** Everywhere you go, in the suit or a ship, tiny star-shaped glints twinkle
  and fade around you, with faint pinpoints in between, so empty space feels alive. They stay put
  as you move, so they also show your motion. (Built-in Roblox sparkle texture, no asset needed.)
- **Effects setting.** A small "Effects: full / reduced" button under the wallet cuts the sparkles
  and flight dust down for slower devices. It's saved with your profile.
- **Stabilizer saved.** The suit stabilizer (Z) remembers your choice between sessions.
- **Ship paint.** Each ship type has its own hull colour: Starter Shuttle white, Prospector gold
  (Crystal Explorer ice blue, Heavy Excavator rust, Nebula Cruiser violet, for later).
- **Golden Beam.** The Miner 100 achievement's reward now works: your laser bolts and sparks turn
  gold, for everyone watching. Applies from your next launch.

## What CI verifies vs what needs Studio

| Verified by CI | Needs a playtest in Studio |
|---|---|
| Strict type check, lint, unit tests, build, smoke test (ships still build and fit their berths) | Sparkles look good, aren't distracting, and cost little |
| | The Effects button and stabilizer persist across rejoins (published place) |
| | Prospector is gold; a Golden Beam owner's bolts are gold for other players |

## Studio hierarchy (new and changed)

```
ReplicatedStorage/Remotes/SettingChanged          RemoteEvent  NEW stabilization / reducedEffects (booleans)
ReplicatedStorage/Shared/Config/Ships             + paint per ship
ReplicatedStorage/Shared/Config/Cosmetics         + color (BeamColor); Golden Beam enabled
ServerScriptService/Server/Systems/SettingsSystem ModuleScript NEW
ServerScriptService/Server/Systems/DataSystem     + setSetting
ServerScriptService/Server/Systems/ShipSystem     ship attribute BeamColor from an owned cosmetic
ServerScriptService/Server/World/ShipBuilder      hull paint per ship
StarterPlayerScripts/Client/Controllers/SparkleController  NEW ambient sparkles
StarterPlayerScripts/Client/Controllers/SpaceDustController  respects reduced effects
StarterPlayerScripts/Client/Controllers/HudController        + Effects button
Workspace/Camera/GaG_Sparkles                      emitter box (client only)
```

## Manual test steps

| # | Steps | Expected |
|---|---|---|
| 1 | Play and look around in the ISS and outside. | Twinkling glints and pinpoints all around, fading in and out; no popping. |
| 2 | Click "Effects: full". | It reads "reduced"; far fewer sparkles; less flight dust. |
| 3 | Press Z to turn the stabilizer off; rejoin (published place, API access on). | Stabilizer still off; Effects still reduced. |
| 4 | Buy the Prospector at the Shipyard, launch it. | Gold hull. |
| 5 | In the server command bar: `game.ServerStorage.DevCommand:Invoke(game.Players:GetPlayers()[1], "grantCosmetic", "GoldenBeam")`, then launch your ship again. | Gold laser bolts and sparks. |

## Tuning

Sparkle density, size and colours are constants at the top of `SparkleController.luau` (RATE,
REDUCED_RATE, BOX_SIZE, LIFETIME). Ship paints are in `Config/Ships.luau`.
