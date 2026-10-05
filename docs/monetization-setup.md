# Optional purchases: Creator Hub setup and review

Everything below is **switched off**. Nothing can be bought until:
1. each product exists on the Creator Hub,
2. its id is filled into `src/shared/Config/Products.luau`, and
3. `PURCHASES_ENABLED = true` is set there (edit in VS Code; Rojo syncs it).

ConfigCheck refuses step 3 while any enabled product still has id 0. To launch with only part
of the catalog, set `enabled = false` on the rest. Nothing here publishes the game, changes
admission or starts sales.

## 0. Connected now (2026-10-05)

`PURCHASES_ENABLED = true`, with these Creator Hub ids:

| Offer | Kind | Id | Grants |
|---|---|---|---|
| Meteor Slicer (ship) | Pass | 2005413560 | The Meteor Slicer, same as the Stardust version |
| 2x Star Production | Pass | 2006121509 | Stars make 2x Stardust |
| Automatic Collection | Pass | 2005767573 | Star income goes straight to the wallet |
| Mining Boost (15 min) | Developer product | 3716697618 | 2x mining Stardust for 15 min of play, stacking time |
| Small Stardust Pack | Developer product | 3716697789 | Exactly 25,000 Stardust, as often as you like |

- **Hidden offers:** every other offer has id 0, so it's disabled: hidden from the Store and never
  fulfilled. To add one, put its id in `Config/Products.luau`; a product is on exactly when it has
  an id.
- **Prices** come from Roblox at runtime. The Store cards and the premium shortcut's gold tag
  show them.
- **Badge** "Black Hole" (748713779889083) is awarded by `BadgeSystem` the first time a star
  evolves into a Black Hole. Players who already did get it on their next join.
- **The listed names** "2× Meteor Slicer Spaceship Unlock" and "2× Stardust Production" are
  mapped to the Meteor Slicer ship unlock and the 2x Star Production pass. A pass grants only
  what `Config/Products` says, whatever its Creator Hub name.

## 1. Create the passes (Creator Hub → your experience → Monetization → Passes)

Create one **Pass** per row. Use the description text as written (it matches the in-game
Store). After creating each, put it **on sale** with a price, then copy its **Pass ID** into
`id = ...` of the matching key.

| Config key | Pass name | Description to paste |
|---|---|---|
| `MiningMultiplier` | 2x Mining Stardust | Doubles the Stardust you get for breaking asteroids. Star income is not affected. Stacks with a Mining Boost (4x while both are active). |
| `StarMultiplier` | 2x Star Production | Doubles the Stardust your stars make from now on. Mining and Stardust already made are not affected. Stacks with a Star Production Boost (4x while both are active). |
| `EnhancedBeam` | Enhanced Mining Beam | 25% more extraction power on every ship, so asteroids break faster. Stardust per asteroid and PvP damage are unchanged. |
| `AutoCollect` | Automatic Stardust Collection | Your stars' income goes straight into your wallet while you play. No offline income and no extra Stardust. |
| `GalactixRacerShip` | Galactix Racer | Unlocks the Galactix Racer at once. Same stats as the version bought with Stardust in the Shipyard. |
| `CamoStellarShip` | Camo Stellar | Unlocks the Camo Stellar at once. Same stats as the Stardust version. |
| `InterstellarRunnerShip` | Interstellar Runner | Unlocks the Interstellar Runner at once. Same stats as the Stardust version. |

Pass icons: 512x512 or smaller (.png/.jpg/.bmp). The UI kit in `assets/ui` has suitable art.

## 2. Create the developer products (Monetization → Developer Products)

| Config key | Product name | Description to paste |
|---|---|---|
| `MiningBoost` | Mining Boost (15 min) | 2x Stardust from asteroids for 15 minutes of play time. Buying again adds 15 more minutes; the boost stays 2x. The timer pauses while you're offline. |
| `StarBoost` | Star Production Boost (15 min) | 2x Stardust from your stars for 15 minutes of play time. Buying again adds 15 more minutes; the boost stays 2x. The timer pauses while you're offline. |
| `StardustSmall` | Stardust Pouch | Adds exactly 2,500 Stardust. |
| `StardustMedium` | Stardust Crate | Adds exactly 12,000 Stardust. |
| `StardustLarge` | Stardust Vault | Adds exactly 50,000 Stardust. |

Copy each **Product ID** into `id = ...`. If you change a pack's amount, change both the
config (`grants.stardust`, `benefit`) and the Creator Hub description.

## 3. Turn it on (only after review)

In `Config/Products.luau`: fill every `id`, set `PURCHASES_ENABLED = true`, run the checks
(CLAUDE.md), playtest with the mocks (section 5), publish when ready. Prices are never stored in
code: the Store reads each player's current price from Roblox.

## 4. Suggested prices (for review; not set anywhere)

The baseline: asteroids pay 12 / 30 / 70 Stardust (+25% precision bonus); early stars make
1 to 12 Stardust/s; ships cost 2,500 to 1,000,000; stars 100 to 600,000.

| Offer | Suggested | Reasoning |
|---|---|---|
| 2x Mining Stardust | 199 R$ | The core early-game loop; a common price for a 2x pass. Mining stays rewarding at 1x. |
| 2x Star Production | 249 R$ | Grows in value as the galaxy grows; slightly above mining. |
| Enhanced Mining Beam | 99 R$ | Speed only (25%), no extra payout; a small convenience. |
| Automatic Collection | 149 R$ | Pure convenience, no extra Stardust. |
| Galactix Racer | 49 R$ | Ship 3 costs 8,000 Stardust: reachable in the first session or two. |
| Camo Stellar | 149 R$ | Ship 5, 45,000 Stardust: a few hours of play. |
| Interstellar Runner | 299 R$ | Ship 7, 160,000 Stardust: mid-game. |
| Mining Boost (15 min) | 25 R$ | Cheap, short, time-limited; adds time, never strength. |
| Star Production Boost (15 min) | 35 R$ | Worth more to players with many stars. |
| Stardust Pouch (2,500) | 25 R$ | About an early Red Fighter; roughly 100 Stardust per Robux. |
| Stardust Crate (12,000) | 99 R$ | About 120 per Robux. |
| Stardust Vault (50,000) | 349 R$ | About 145 per Robux. The Store shows only exact amounts, no "% off" or "best value" claims. |

Review against playtest pacing: if a pack covers more than a few hours of play at that stage,
reduce it.

## 5. Testing without Robux (Studio only)

The mocks run the same server code paths, only in Studio, and only from the server-side command
bar (a BindableFunction in ServerStorage; clients can't reach it). Mocked passes aren't saved.

```lua
local dev = game.ServerStorage.DevCommand
local p = game.Players:GetPlayers()[1]
dev:Invoke(p, "mockReceipt", "MiningBoost")           -- "granted"; HUD shows 2x MINING 15:00
dev:Invoke(p, "mockReceipt", "MiningBoost")           -- 30:00, still 2x
dev:Invoke(p, "mockReceipt", "StardustSmall", "R1")   -- +2,500
dev:Invoke(p, "mockReceipt", "StardustSmall", "R1")   -- same PurchaseId: nothing added
dev:Invoke(p, "mockPass", "MiningMultiplier", true)   -- asteroid rewards x2 (x4 with the boost)
dev:Invoke(p, "mockPass", "AutoCollect", true)        -- income goes straight to the wallet
dev:Invoke(p, "boosts")                               -- seconds left
```

In Studio without API access ProfileStore runs in mock mode, so "saved" means saved to the mock
store; the acknowledge-after-save logic still runs. **A real purchase test spends real Robux**
(unless done by a group/owner test account flow Roblox offers); don't run one without deciding to.

## 6. Policy notes

**Roblox requirements** (Paid access in local currency page, developer products and passes
pages, reviewed Oct 2026):
- Paid-access experiences must stay public, give buyers the entire game, and must not require
  Robux to access parts of it. Passes and developer products are explicitly allowed.
- No private servers, no benefits in other games, no place copying (this task changes none of
  these; admission settings were not touched).
- Developer products must be fulfilled in a single server-side `ProcessReceipt`, returning
  `NotProcessedYet` when they can't be granted, and never from `PromptProductPurchaseFinished`.
- The Community Standards and Terms of Use pages could not be fetched from here (HTTP 403);
  review them directly before launch, especially on paid random items and misleading practices.

**Our own design rules** (not Roblox policy): no paid random rewards; no fake discounts,
countdowns or scarcity; prompts only after a button press, never automatically or after a
failed mine; no region or mode locked behind a Robux ship; every Robux ship also earnable with
Stardust; no overlapping bundles in the first release.
