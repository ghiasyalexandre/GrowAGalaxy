# Stage 17: Optional Robux purchases (switched off)

**Status: code complete, CI-verified (format, lint, strict types, 145 unit tests, build, smoke
test). Not playtested in Studio. Purchases are disabled: no ids are configured and
`PURCHASES_ENABLED = false`.** Setup and review: [monetization-setup.md](monetization-setup.md).

## What exists

**Catalog** (`Config/Products`): 4 permanent passes (2x Mining Stardust, 2x Star Production,
Enhanced Mining Beam, Automatic Stardust Collection), 3 ship passes (Galactix Racer, Camo
Stellar, Interstellar Runner), 2 boosts (Mining, Star Production; 15 minutes each) and 3
Stardust packs (2,500 / 12,000 / 50,000). Every id is 0 (not configured).

**Galaxy Store** (HUD **Store** button, cyan/violet): tabs Passes, Boosts, Stardust, Ships.
Each card shows the exact benefit, PERMANENT / TEMPORARY 15 MIN / ONE-TIME, how it stacks, the
time left on an active boost, the price Roblox reports for this player, Owned, and how to earn
it by playing (ships, packs). Unconfigured offers say "Not available yet" and can't be pressed;
a price that can't be loaded disables the offer. A prompt opens only when the player presses
Buy; cancelling says nothing was charged. Ships already owned (earned or bought) show Owned.
Gamepad: the first Buy button is selected; Backspace or the close tile closes.

**HUD**: active boosts as chips under the goal panel ("2x MINING 14:32", "2x STARS 3:05"),
counting down locally and resynced by the server every 10 s.

## How rewards are calculated (server only)

`Logic/RewardMath`: effective multiplier = permanent (pass) x temporary (boost, 2x while time
is left). Mining and star production are separate sources.

| Source | Where it's applied, once | Not multiplied |
|---|---|---|
| Mining | `MiningSystem.payOut`, when an asteroid breaks | packs, balances |
| Stars | `DataSystem.accrueIncome`, as income accrues each second | income already accrued, collecting it |
| Extraction speed | `MiningSystem.shot` (Enhanced Beam) | payout per asteroid, PvP damage, ship stats |

A boost that runs out inside an income interval only boosts the part it covered. Boost time
counts down only while the player is in a server (persisted; paused offline). Buying a boost
again adds 15 minutes; it never gets stronger. The uncollected cap scales with the permanent
star pass (not with boosts). Automatic Collection moves whole Stardust from "uncollected" to the
wallet each second (a transfer, never multiplied); it also completes the tutorial's collect
step.

## Purchase handling

- `MonetizationSystem` is the only `ProcessReceipt` assignment in the code base (there was none
  before). Receipts run `Logic/ReceiptFlow`: allowlisted product (enabled, configured, developer
  product) → player in this server → profile loaded → reward + PurchaseId written together
  (`DataSystem.applyPurchase`) → wait until ProfileStore's saved copy contains the PurchaseId
  (`DataSystem.waitForSave`) → `PurchaseGranted`. Any other outcome returns `NotProcessedYet`.
  The same PurchaseId is never processed twice at once, and is never granted twice.
- Unknown product ids are logged and left for retry, never discarded.
- Passes: `UserOwnsGamePassAsync` on profile load (3 tries with backoff). On failure the passes
  Roblox last confirmed (saved in the profile) stay active, the player is told, and it rechecks
  every 60 s. `PromptGamePassPurchaseFinished` (server) grants a new pass at once and rechecks.
  Client claims are never used. A ship pass adds the ship to owned ships if it isn't already
  (earned copies are left alone).

## Save data (schema v8)

Adds `boosts = { mining, star }` (seconds left), `verifiedPasses`, and keeps up to 100
`receipts` (was 50). Older profiles start with no boosts. Existing data is untouched.

## Verified by CI

- Multipliers: 1x / pass 2x / boost 2x / both 4x; each pass only affects its own source; beam
  pass changes no reward.
- Boost split across an interval; extending adds time, not strength.
- Packs add exact amounts; repeated receipts grant once; failed saves are not acknowledged;
  unknown products, absent players, missing profiles and errors retry; concurrent processing of
  one PurchaseId grants once; receipt list trimming.
- Catalog: one grant per product, packs/boosts are developer products, Robux ships are also
  earnable, purchases off and all ids 0.
- Save v8 fields, world build and smoke test.

## Needs Studio / a live test

Store layout on desktop, phone and gamepad; price loading; HUD chips; the mocks (setup guide
section 5); a real purchase (spends Robux; not done).

## Known limitations

- Boost time counts while the player is in a server, including when idle.
- A refunded ship pass leaves the ship owned (it was granted into the save); a refunded
  multiplier pass stops on the next successful ownership check.
- Automatic Collection also moves income accrued before the pass was bought (a transfer, no
  extra Stardust).
- Prices show as "R$ N" text (no Robux glyph font).
- Lune can't fit imported ship models (`GetBoundingBox`), so the smoke test now tolerates that
  one ShipBuilder warning; model fitting needs Studio.
