# Stage 32 (overhaul stage 3): ISS Planet Egg Lab

**Status: code complete, CI-verified (format, lint, strict types, 205 unit tests, build, world
and orbit smoke tests). Not yet playtested in Studio. No Robux purchase is involved: eggs cost
Stardust only.**

## The Egg Lab

A new ISS module, the **Planet Egg Lab**, sits between the Star Lounge and Navigation: a giant
egg turning on a pedestal inside six rarity-coloured rings, shelves of small eggs, a sign, and a
console (**Open Planet Egg Lab**) that anyone can use.

The panel (`EggShopController`) has three tabs:

- **Mystery egg**: the price, your balance, Buy, how many eggs you hold (max 50), the note that
  hatching starts when you put the egg in your hangar's incubator (5 chambers), and the exact
  chance of all 28 planet types grouped by rarity, with each rarity's total and hatch time.
  If random eggs are off for you, the reason is shown and Buy says Unavailable.
- **Choose a planet**: a non-random egg of any type, at its listed price.
- **Details**: how the roll works, the full odds, the price formulas, hatch times, the egg limit
  and the restrictions.

## Rules (server: `EggSystem`, `DataSystem.buyEgg`, `Logic/EggMath`)

- **Mystery egg price:** `500 × 1.15^(eggs bought)`, rounded (500, 575, 661, …).
- **Chosen planet price:** the current mystery egg price × Common 3, Uncommon 6, Rare 16, Epic 50,
  Legendary 150, Interstellar 400. Buying one also counts as an egg bought.
- **Roll:** a whole number from 1 to 1,200,000 drawn with the server's `Random`; each planet type
  owns a run of rolls as long as its weight, so its chance is exactly its weight ÷ 1,200,000
  (12.5% / 7% / 2.333% / 0.833% / 0.5% / 0.25% per type by rarity). The outcome is saved with
  the egg at purchase and never rerolled; the client isn't told a mystery egg's planet before it
  hatches (`ProfileSchema.eggsView`). Duplicates are allowed.
- **Atomic purchase:** `DataSystem.buyEgg` checks room (50 eggs held, waiting plus incubating) and
  balance, takes the Stardust, counts the purchase and saves the egg, without yielding. If the
  price the client showed differs from the server's (another purchase raised it), nothing is
  bought and the player is told the new price.
- **Paid random items policy:** Stardust can be bought with Robux, so mystery eggs are only sold
  when `PolicyService:GetPolicyInfoForPlayerAsync(player).ArePaidRandomItemsRestricted` is
  `false`. The check runs when the player joins; while it hasn't answered or after it fails the
  policy is **unknown** and mystery eggs are off with a message ("We couldn't check…"), retried
  every 30 s. Restricted players see "Mystery eggs aren't available in your region". Chosen
  planets are always available to everyone.
- No paid luck, rerolls, hatch speed-ups or trading exist.
- Remote: `EggRequest` (`"status"`, `"buyMystery", price?`, `"buyChosen", typeId, price?`),
  rate-limited. `HatchRequest` and `WheelRequest` are declared for stages 4 and 5.
- Tuning: `Config/Eggs` (with a price review comment); validated by ConfigCheck.

## Test in Studio

1. Walk from Arrival towards Navigation: the Egg Lab module with the turning egg.
2. Open the console. Check the balance, price, odds list (28 rows, percentages as above) and
   the Details tab.
3. **Policy:** in a Studio playtest PolicyService normally answers "allowed". Buy a mystery egg:
   Stardust drops by the price, "eggs waiting" goes up, the next price is 15% higher. In the
   Output there should be no `[EggSystem] Policy check failed` warning; if there is, Buy should
   show Unavailable with the "couldn't check" message.
4. **Chosen:** buy a Common chosen egg; the price is 3× the mystery price.
5. **Price race:** not testable by hand easily; covered by the expected-price check in code.
6. Eggs can't be hatched until stage 4.

## Limitations

- Restricted-policy behaviour can't be simulated in Studio without a test account in a
  restricted region; the code path is the same as "unknown" (Buy disabled, message shown).
