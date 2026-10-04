# Stage 10: Stellar spectacle

**Status: code complete, CI-verified (format, lint, strict types, 105 unit tests, build, smoke
test). Not yet playtested in Studio.**

## Playable result

**Big moments in the world**, seen by every player near the star (`src/client/Fx/StarFx.luau`):

| Moment | Effect |
|---|---|
| A star is placed | It ignites: a white flash, a coloured fireball, two glowing shockwave rings, a burst of sparkles and light |
| A star levels up | Three rings rise past it, a sparkle fountain shoots up, a pulse of light |
| A star evolves | A supernova: a huge white blast, a second shockwave tilted through the orbits, 140 sparkles, a long glow in the new colour |
| A planet is bought or upgraded | Sparkles rush inwards and condense into the planet, then a flash and a ring |

**Your own milestones** get a banner in the star's colour, with confetti: NEW STAR, LEVEL UP,
STAR EVOLVED (which also flashes the screen), NEW WORLD and WORLD UPGRADED. Achievement banners
get confetti too. Banners queue, so several at once play one after another.

**Star Shop:**
- living star icons: a pulsing halo around a slowly turning gradient core. The black hole is a dark
  core in a swirling accretion ring; locked tiers are "?" silhouettes,
- **NEXT GOAL** tag on the tier you're working towards,
- a saving-up bar and percentage on tiers you can't afford yet,
- affordable rows get a pulsing gold border and a shine sweeping across the Buy button,
- header shows your production.

**Manage panel:** planets drawn as lit spheres, ringed for Gas Giant and Crystal World.

**HUD Next Goal** (under the Star Shop button): the next star tier with a progress bar and
"340 / 600 Stardust". When it's affordable it bounces, glows gold, shines and says "READY: press
B". Clicking it opens the Star Shop.

**New achievements:**

| Achievement | Goal | Reward |
|---|---|---|
| Planetfall | Buy a planet | 300 |
| Stellar Evolution | Evolve a star | 1,500 |
| Terraformer | Upgrade planets 5 times | 8,000 |
| Worldbuilder | Buy 10 planets | 20,000 |
| Event Horizon | Own a black hole (placed or evolved) | 250,000 |

## What CI verifies vs what needs Studio

| Verified by CI | Needs a playtest in Studio |
|---|---|
| Next goal = tier above your best star (unit test) | How every effect reads at different star sizes and distances |
| Every enabled achievement uses a counted stat | Banners, confetti and the screen flash aren't too much |
| Strict types, lint, build, smoke test | Shop icons and bars look right and stay smooth as Stardust changes |

## Studio hierarchy (new and changed)

```
StarterPlayerScripts/Client/Fx/StarFx                     NEW world effects (plain module)
StarterPlayerScripts/Client/UI/Theme                      animate/spin/pulse/shine, star and planet icons, progress bars
StarterPlayerScripts/Client/Controllers/StarController     effects on attribute changes, celebrations, myRecords()
StarterPlayerScripts/Client/Controllers/StarShopController icons, goal tag, saving-up bars, shine
StarterPlayerScripts/Client/Controllers/RewardController   banner queue, confetti, screen flash
StarterPlayerScripts/Client/Controllers/HudController      Next Goal panel
ServerScriptService/Server/Systems/StarSystem              BornAt attribute; blackHoles stat
Workspace/Regions/Region_N/Stars/<star>                    attribute BornAt (server time of placement)
Workspace/Camera/GaG_StarFx                                effect parts (client only)
```

## Manual test steps

| # | Steps | Expected |
|---|---|---|
| 1 | `addStardust 2000000`, open the Star Shop (B). | Animated icons; NEXT GOAL on Brown Dwarf; gold pulsing border and shining Buy on affordable rows; "?" on locked ones. |
| 2 | Place a star. | Ignition effect at the star; NEW STAR banner with confetti; First Light banner after it. |
| 3 | Level it up. | Rising rings and fountain; LEVEL UP banner. |
| 4 | Evolve it. | Supernova and screen flash; STAR EVOLVED banner; Stellar Evolution achievement. |
| 5 | Buy and upgrade a planet. | Sparkles condense into the planet; NEW WORLD / WORLD UPGRADED banners. |
| 6 | Spend down to below the next tier's price. | HUD Next Goal shows progress; earn back up and it bounces to READY. |

## Known limitations

- A star that streams in or loads after joining never replays its birth (only within 4 seconds
  of placement).
- Players who owned a black hole before this stage get Event Horizon only on their next one.
