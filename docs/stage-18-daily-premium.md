# Stage 18: Daily prizes, flashy Galaxy Store, premium shortcut

**Status: code complete, CI-verified (format, lint, strict types, 151 unit tests, build, smoke
test). Not yet playtested in Studio. Robux purchases are still switched off (stage 17).**

## Daily prizes

A **DAILY** button on the right edge (a round gift tile with a pulsing red **!** while a prize
is waiting) opens a 14-day calendar. The calendar also opens by itself once per session, 3
seconds after joining, when a prize is waiting.

| Day | Prize | Day | Prize |
|---|---|---|---|
| 1 | 250 Stardust | 8 | 1,500 Stardust |
| 2 | 400 Stardust | 9 | 2,000 Stardust |
| 3 | 2x Mining 10 min | 10 | 2x Mining 20 min |
| 4 | 700 Stardust | 11 | 3,000 Stardust |
| 5 | 1,000 Stardust | 12 | 4,000 Stardust |
| 6 | 2x Stars 10 min | 13 | 2x Stars 20 min |
| 7 | **2,500 Stardust** (big) | 14 | **10,000 Stardust** (big) |

- One claim per **UTC** day (the server's clock, never the client's). After day 14 the calendar
  starts again at day 1.
- Missing a day doesn't lose your place: the next claim is the next day on the calendar (no
  streak pressure).
- Prizes are fixed: multipliers never apply. Boost prizes add time to the same 2x boosts sold in
  the Store (they stack by adding time) and show in the HUD's boost chips.
- Tiles: claimed (dimmed, CLAIMED), TODAY (gold edge, pulsing, shining), still to come; days 7
  and 14 are violet with a bigger chest. The Claim button names the prize, or counts down to the
  next UTC midnight. Claiming shows a DAILY PRIZE banner.
- Tuning: `Config/Daily` (prizes, open on join).

## Galaxy Store, flashier

- A rainbow (cyan, violet, magenta, gold) border that rotates around the panel.
- A twinkling star field behind everything.
- A gradient header banner with a shine sweep; the title "PREMIUM GALAXY STORE" in gold with a
  bright band sliding across it; the gift icon rocks.
- Cards: navy fading into violet, edged in their category's colour (violet passes, cyan boosts
  and ships, gold packs), the edges breathing; every Buy button has a shine sweep.

## Premium shortcut (right edge)

A round window under the Daily button with a spinning rainbow ring, a breathing violet glow and
a gentle pulse, labelled PREMIUM. Every **15 seconds** it crossfades between:
- the **Interstellar Runner** (the latest ship with a Robux pass), its imported model turning
  and banking (its ship icon until the model is imported); click opens the Store's **Ships** tab;
- a **black hole**: a dark core in a violet halo with two tilted, counter-spinning accretion
  disks; click opens the **Passes** tab (2x Star Production).

It never opens anything by itself.

## Save data

Schema v9 adds `daily = { day, lastClaim }`. Older profiles start at day 1, never claimed.

## Studio hierarchy (new)

```
ReplicatedStorage/Remotes/DailyRequest                     RemoteFunction ("claim")
ReplicatedStorage/Shared/Config/Daily, Logic/DailyMath     prizes and claim rules
ServerScriptService/Server/Systems/DailySystem             claims
StarterPlayerScripts/Client/Controllers/DailyController    Daily button and calendar
StarterPlayerScripts/Client/Controllers/PremiumController  the premium shortcut
PlayerGui/DailyButton, Daily, Premium
```

## Manual test steps

| # | Steps | Expected |
|---|---|---|
| 1 | Join. | After 3 s the calendar opens; Day 1 TODAY, red ! on the Daily button. |
| 2 | Claim. | +250 Stardust, banner; button shows the countdown; ! gone. |
| 3 | Claim again (rejoin). | Refused: already claimed today. |
| 4 | Watch the right edge for 30 s. | Ship, then black hole, then ship; pulsing, ring spinning. |
| 5 | Click it on each. | Store opens on Ships / Passes; rainbow border, stars, shine. |
