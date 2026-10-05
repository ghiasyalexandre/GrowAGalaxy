# Stage 16: Hangar station, upgrade pads, HUD buttons

**Status: code complete, CI-verified (format, lint, strict types, 129 unit tests, build, smoke
test). Not yet playtested in Studio.**

## Playable result

**HUD buttons.**
- **Shipyard** (purple, next to Star Shop) opens the Shipyard from anywhere; press it again to
  close.
- **Launch Ship** (blue, bottom left beside Return to Station) spawns your active ship at your
  station's berth, moves you beside it and seats you, wherever you were. Hidden while flying.
  The ISS hangar console still works as before.

**The hangar station.** Your station is now a hangar deck (64 x 72 studs, was 44 x 44):
- three lit truss arches overhead, half walls with window bands and glowing trim;
- lane stripes and lane lights from the spawn to the gangway, red landing lights on the gangway;
- crates and barrels in the back corners, the hub tower and beacon at the back with a glowing
  ring, and a "<name>'s Hangar" sign;
- **one console: Collect**, with a glowing Stardust orb above it. The Navigation, Hangar
  (launch), Star Shop and Shipyard consoles are gone; the HUD buttons replace them.

**Upgrade pads.** Red glowing ground circles on the deck, pulsing, each with a sign showing the
upgrade's name, what it does and its cost. **Step on a circle** (or use its Build prompt) to buy
it. The building rises out of the deck with a bounce, a golden burst and a ring, and you get a
HANGAR UPGRADE banner. Only the owner can build; a pad you can't afford says how much you need
(at most every few seconds while you stand on it).

| Upgrade | Cost | Effect | Needs | Building |
|---|---|---|---|---|
| Stardust Silo | 1,500 | Stars hold 50% more uncollected Stardust | | twin silos with gold bands |
| Fuel Depot | 3,000 | +25% boost time on every ship | | three fuel tanks on cradles |
| Stardust Refinery | 6,000 | +15% Stardust from your stars | Silo | refinery with chimney smoke |
| Cooling Tower | 10,000 | +25% laser cooling on every ship | Fuel Depot | tower with cyan vents and steam |
| Mining Lab | 25,000 | +15% laser power on every ship | Refinery | glass dome, crystal, laser mast |
| Armor Workshop | 20,000 | +30% hull on every ship | Cooling Tower | workshop with a sparking welder |

A pad only appears once its requirements are built, so the deck fills up as you progress. Ship
effects apply from your next launch; income and storage at once (the HUD's income rate includes
the Refinery). All values are in `Config/Hangar`.

## Save data

Schema v7 adds `hangar` (the upgrades built). Older profiles start with none.

## What CI verifies vs what needs Studio

| Verified by CI | Needs a playtest in Studio |
|---|---|
| Requirements, prices, stacking effects; v7 save field; hangar config checked (pads on the deck and apart) | Walking onto a pad buys it; signs readable; rise animation and banner |
| Station builds with only the Collect console; every pad and building builds within budget | Launch Ship moves you to the berth and seats you |
| | The new deck layout and lighting look good; nothing blocks the spawn or lane |

## Studio hierarchy (new and changed)

```
ReplicatedStorage/Shared/Config/Hangar                     NEW upgrades, pads, costs, effects
ReplicatedStorage/Shared/Logic/HangarMath                  NEW availability, prices, multipliers
ServerScriptService/Server/Systems/HangarSystem            NEW pads, purchases, buildings
ServerScriptService/Server/World/HangarBuilder             NEW pad and building geometry
ServerScriptService/Server/World/StationBuilder            the hangar deck; only the Collect console
ServerScriptService/Server/Systems/ShipSystem              ShipRequest "launch" (launch and board)
StarterPlayerScripts/Client/Controllers/HangarController   NEW pad pulse, rise animation, banner
StarterPlayerScripts/Client/Controllers/HudController      Shipyard and Launch Ship buttons
<region>/Station/Hangar/<UpgradeId>                        a pad (State "pad") or building ("built")
```

## Manual test steps

| # | Steps | Expected |
|---|---|---|
| 1 | Join. | Hangar deck with arches and lights; only the Collect console; two red pads (Silo, Fuel Depot). |
| 2 | Press Launch Ship from the deck. | Ship at the berth, you seated in it. |
| 3 | Press Shipyard. | Shipyard opens; press again to close. |
| 4 | Earn 1,500 and step on the Silo pad. | Silo rises with a burst; banner; Refinery pad appears. |
| 5 | Step on a pad without enough Stardust. | One message saying how much is needed. |
| 6 | Buy the Fuel Depot, relaunch. | Boost gauge lasts 25% longer. |
