# Stage 44: The reset code

**Status: CI-verified (format, lint, strict types, 227 unit tests, build, world and orbit
smoke tests). Not yet tried in Studio.**

**ResetMyGalaxy** (Settings, code box) erases the player's own progress:

1. Typing it once only warns: "this erases ALL your progress... Type the code again within 30
   seconds to confirm." Nothing changes.
2. Typing it again within 30 seconds resets the save to a brand-new profile: Stardust, stars,
   planets, eggs, ships, upgrades, stats, achievements, tutorial, settings, and the list of
   redeemed codes (so every code, including this one, can be used again).
3. The player is kicked with "Your galaxy has been reset. Rejoin to start fresh!", which saves
   the fresh profile and rebuilds their world when they come back.

Kept on purpose: the Robux purchase receipts (so a purchase can never be granted twice; game
passes are re-checked with Roblox on join anyway). Developer-product Stardust already spent or
held is gone like everything else.

Code: `Config.Codes` (`reset = true`, `RESET_CONFIRM_SECONDS`), `CodeSystem`,
`DataSystem.resetProfile`.

## Test in Studio

Use a test account with API access on (saving): note your Stardust, type the code once
(warning only), again (kicked), rejoin: a fresh start with the tutorial; codes work again.
