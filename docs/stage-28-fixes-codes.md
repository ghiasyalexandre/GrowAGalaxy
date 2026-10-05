# Stage 28: UI fixes, redeemable codes, Showcase Dock fix

**Status: code complete, CI-verified (format, lint, strict types, 180 unit tests, build, world
and orbit smoke tests). Not yet playtested in Studio.**

## Fixes

- **Premium icon over panels:** the pulsing premium shortcut now draws below every panel
  (its ScreenGui has DisplayOrder -1), so it no longer covers the star / planet panel or others.
- **Shipyard jumping to the top:**
  - **Cause:** lists rebuild whenever Stardust changes. Emptying a list shrank its automatic
    canvas and snapped the scroll to the top.
  - **Fix:** `Theme.clear` now puts the scroll position back once the new rows are laid out.
    This fixes the Shipyard, the Galaxy Store, the star panel and every other list built this
    way.
  - **Unchanged:** switching tabs still starts at the top.
- **Orbit rings:** a star only draws an orbit's ring once a planet has been bought for it
  (before, every open orbit showed one).
- **Showcase Dock ships not showing:**
  - **Cause:** spinning decorations (`SpinController`) remembered a model's position when the
    client first saw it. If its parts hadn't streamed in yet, that position was wrong, and every
    frame the model was put back there, far from the dock.
  - **Fix:** spinners now turn a little each frame from wherever they are, about their centre.
    The centre is measured again whenever a model's parts change.
  - **Display ships:** these are sent whole (Atomic streaming), shrunk so their widest turning
    circle fits the 12-stud pad, and set 1 stud above it.
  - **Pads:** the cradle glow pads are white.

## Codes (Settings panel)

- **Redeeming:** Settings has a **Codes** row. Type a code and press **Redeem** (or Enter).
  Letter case and spaces around the code don't matter.
- **The code:** `ILUVGHIASY` gives **500,000 Stardust**, once per player. A second try says it's
  already been redeemed.
- **Server side:** codes are checked on the server (`CodeSystem`), with a rate limit (5 tries,
  then one every 5 s) so they can't be guessed by brute force. The reward is a fixed amount;
  multipliers don't apply.
- **Adding codes:** add more in `src/shared/Config/Codes.luau`, written in upper case.
- **Save data version 13:** adds `redeemedCodes`.

## Test in Studio

1. Open a star's panel with the premium icon on screen: the panel should cover the icon.
2. Scroll down in the Shipyard while mining or collecting Stardust: the list should stay put.
3. A new star should show no orbit rings until its first planet is bought.
4. Put ships on show, build the Showcase Dock, and look for the ships turning over the white
   pads.
5. Settings > Codes: redeem ILUVGHIASY (+500,000 Stardust), then try again; it should be
   refused.
