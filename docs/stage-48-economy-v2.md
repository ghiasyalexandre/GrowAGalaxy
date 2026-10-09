# Stage 48: economy v2

This stage applies the economy proposal in `REBALANCE.md` (economy designer, Oct 2026). The formulas live in
`src/shared/Logic/EconomyMath.luau`. The numbers live in `Config/*`.

## Terms

- **B (production)**: every star's own rate, plus each equipped planet's share of its host star's rate, times the trail and the Refinery. B leaves out passes, boosts and mining. `ProfileSchema.incomeRate` returns B.
- **H (high-water mark)**: `economy.high`, the best B so far. It never falls. Egg prices, and through them planet-level prices, come from H.
- **R (reward rate)**: the average B over the last 10 online minutes. It's snapshotted once per UTC day and is never below 1. These rewards are minutes of R:

  | Reward | Minutes of R |
  |---|---|
  | Daily calendar | 2 to 15 (loops; a missed day doesn't reset progress) |
  | Wheel | 1, 2, 3, 5, 8 or 12 (free spin every 24 h) |
  | Raids | 2, 4 or 6 (first win per day only) |
  | Achievements | 1, 3 or 10 |
  | Codes | 2 |
  | Vanity hangar items | priced at 2, 5 or 10 |

## What changed

### Stars

- Each star has a BuildIndex k (`build`), which never changes.
- Star price is `cost × 1.1^k` (changed from REBALANCE.md's 1.12).
- Level-up price is `cost × 0.18 × 1.2^(L−1) × 1.1^k` (changed from 1.22 and 1.12).
- Evolving costs `next cost × 1.1^k`.
- Max level is `4 + floor((t−1)/4)`.
- The level multiplier is `1 + 0.2n + 0.01n²`.
- Each star type makes 3× the type before it.

### Planets

- A planet earns `host × b × tier × (1 + 0.25(L−1))`, where `host` is its star's own rate.
- Tier multipliers go from 1 to 2.2.
- Level-up prices are a share of the egg price.
- Sale value is `paid × fraction + 0.25 × spent`. Tier adds nothing.
- Equip Best puts the planets with the best multipliers on the strongest stars.
- Storage is now reserved: eggs count toward the 200-planet limit. Rolls pause when storage is full. A hatched planet is never sold because storage is full.

### Eggs

- Price is `max(250, 60H)`: keeping eggs never raises it (REBALANCE.md's ×1.003 per kept egg was dropped).
- Each lab level needs a minimum star tier.
- Every player gets one free tutorial egg 2 minutes into their first session.

### Galaxy and offline income

- Expansions cost 2M, 300M and 40B.
- Offline income pays 25% of B, for up to 8 hours.
- The collector tank holds 2 hours of income.
- The Silo raises both limits by 50%.

### Mining

- Payout is `B (at first hit) × a × W × precision × pass × boost`.
- `a = 0.65 + 0.015 × ship step + 0.003125 × equipment levels`.
- W is 10, 20 or 40 by asteroid size.
- Swarm asteroids pay 1.5×, for up to 5 minutes of work in any 30 minutes.

### Ships, equipment, trails and hangar

- **Ships:** new prices from 5K to 400B, and each ship needs a minimum star tier. The Quasar Hoverboard is 1.6T and needs tier 17.
- **Equipment:** four item groups (Optics Mk II is new). There are 4 levels, each costing 2× the last, giving +15% per level up to +60%.
- **Trails:** ×1.1 to ×1.5. A trail is part of B, so it also raises mining.
- **Hangar:** new prices and effects (Refinery +10%, Silo for both caps).

### Store

- The 2× Mining and 2× Star passes are still sold.
- The Stardust Pack (`StardustSmall`) now grants 12 hours of the buyer's production B at the moment of purchase (`productionHours = 12`). B includes trail and Refinery; passes and boosts don't apply. Each receipt grants once.
- The fixed 120K and 500K packs and the 2× boosts are no longer sold (`onSale = false`), but receipts already paid for are still fulfilled at their promised values.

### Endgame

- Constellation Projects become available with 20 maxed Cosmic Phoenixes and lab level 8.
- They cost 6 hours of reference production and get 20% pricier each rank, up to a 2-quadrillion cap.
- Each project only raises `constellationRank`.

### Analytics

- `Util/EconomyAnalytics` logs each source and sink on wallet changes, plus progression events.
- It works on a wallet basis: star income is logged when it's collected or paid offline.

## Save v21

- **Stars:** each gets a BuildIndex. Stars are ordered by numeric id, and `nextBuild` is set to the next index.
- **Star levels:** each star keeps the same share of the way to max.
- **Old planets:** they keep their old fixed sale value (`legacy`). Eggs that haven't hatched get it when they hatch.
- **Existing players:** they don't get the tutorial egg.
- **H and R:** H is set from the new B. R starts at 1 until the first snapshot.
- **Wallets and uncollected Stardust:** kept as they are.

## Not done

- Restricted-policy players don't have a guaranteed planet purchase path. Rolls stay off for them, as before.
- The offline time before the migration is paid under the new rules, not settled once under the old ones.
- `LogFunnelStepEvent` onboarding steps aren't wired. Only economy and progression events are logged.
- Fixed `TUTORIAL.FINISH_REWARD` is unchanged.

## Needs a Studio playtest

1. Join with an old save. Check that star levels are remapped, the wallet is kept, and planets show their legacy sale values.
2. Start a new account:
   - the first star costs 100;
   - the tutorial egg arrives at about 2 minutes;
   - the first daily prize is 120.
3. Buy stars and level them up. Check that prices match the panel, including after you buy more stars.
4. Equip a planet. Check that its income follows its star, and that Equip Best moves planets to the strongest star.
5. Roll eggs. The price should be about a minute of production, and rolling should be blocked when storage is full.
6. Mine asteroids and compare the payout per minute with idle income (target 1.65–1.85×).
7. Spin the free wheel, claim the daily prize and win a raid twice in one day. The second win pays nothing.
8. Check that the hangar vanity pads show prices in minutes.
