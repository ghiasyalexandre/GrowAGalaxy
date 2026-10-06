# Stage 34 (overhaul stage 5): Daily Wheel

**Status: code complete, CI-verified (format, lint, strict types, 215 unit tests, build, world
and orbit smoke tests). Not yet playtested in Studio. No Robux involved.**

**Stage 36 change:** a spin now costs **1,000 Stardust** (`Config.Wheel.SPIN_COST`), still once
per 24 hours. Because Stardust can be bought with Robux, a paid spin counts as a paid random
item: like mystery eggs it's only offered where PolicyService allows those, and stays off while
that's unknown. The Spin button shows the price, "Need 1,000 Stardust" or "Unavailable". The
cost is taken and the prize added in the same step; the smallest prize equals the cost.

## The wheel

- **HUD button** on the right edge, beside the Daily button: a little six-colour wheel with the
  countdown to the next free spin under it (`23:59:12`), or **SPIN!** and a pulsing red badge
  when a spin is ready.
- **Panel:** the wheel (six equal segments with their prizes, gold spokes, a red pointer at the
  top, rim bulbs that chase while it's open), the full prize and odds list beside it, the status
  line (ready, or time left) and the **SPIN** button ("Come back tomorrow" while waiting).

| Prize | Chance |
|---|---|
| 1,000 Stardust | 40% |
| 2,500 Stardust | 25% |
| 5,000 Stardust | 15% |
| 10,000 Stardust | 12% |
| 15,000 Stardust | 6% |
| 25,000 Stardust | 2% |

## Rules (server: `WheelSystem`, `DataSystem.spinWheel`, `Logic/WheelMath`)

- **One free spin every 24 hours**, counted from the last spin (`profile.wheel.nextSpin`, unix
  seconds, saved). No paid spins, nothing shortens the wait.
- **The server picks and grants first:** a whole roll from 1 to 100 with the server's `Random`
  picks the prize (each prize owns exactly its weight in rolls); `DataSystem.spinWheel` checks
  the cooldown, sets the next spin time, records the prize and adds the Stardust in one step, and
  only then answers. The client animation just shows the result, so closing the game mid-spin
  loses nothing.
- **Fixed prizes:** no pass, boost or trail multiplier applies.
- **Animation:** 4 s with five extra turns, easing out to land the prize under the pointer
  (`WheelMath.landing`), then the winning chip is outlined, a DAILY WHEEL banner plays (with a
  flash for the 15,000 and 25,000 prizes) and a message confirms the amount.
- **Reduced effects** (Settings) also reduces motion: the wheel turns less than one turn in 1 s,
  the bulbs and the badge stay still.
- Remote: `WheelRequest` `"spin"` → `(ok, message, prizeIndex)`, rate-limited.
- Stat: `wheelSpins`. Tuning: `Config/Wheel` (ConfigCheck requires whole prizes and weights
  adding up to 100, since they're shown as percentages).

## Test in Studio

1. The wheel button shows SPIN! and a badge on a fresh profile. Open it, check the odds list.
2. Spin: the Stardust counter rises at once (granted before the animation), the wheel lands on
   the same prize the message names, the badge goes and the countdown starts at ~24:00:00.
3. Spin again: the button says "Come back tomorrow"; a forced request returns "Your next free
   spin is in …".
4. Rejoin: the countdown continues (saved).
5. Reduced effects on: a short, single-turn spin; still bulbs and badge.
6. Phone and console: the button sits beside Daily on the right; gamepad selection lands on the
   Spin button; Backspace or B closes the panel (not mid-spin).
