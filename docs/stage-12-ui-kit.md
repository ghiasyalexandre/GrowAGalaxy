# Stage 12: UI kit, hover animations, vivid sparkles

**Status: code complete, CI-verified (format, lint, strict types, 107 unit tests, build, smoke
test). The art appears in game once the atlas is uploaded (below). Not yet seen in Studio.**

Replaces the single sprite sheet of [stage 11](stage-11-sprite-ui.md) with the full UI kit in
`assets/grow_a_galaxy_ui_assets/` (62 PNGs, two labeled index sheets, `asset_manifest.csv`).

## The atlas

Roblox loads only uploaded images and downscales anything over 1024 x 1024, so
`tools/pack_ui_atlas.py` cleans, scales and packs the 43 pieces the game uses into
**`assets/ui/GaG_UI_Atlas.png`** (1024 x 906) and writes their rects and 9-slice centres to
`src/shared/Config/SpriteAtlas.luau` (generated; formatted with StyLua).

- Cleaning: slivers of neighbouring art along a crop's edges are removed (found on the solid
  shapes, measured from the art rather than the padded crop). `TRIM` handles the one sliver fused
  to its art (the galaxy orb's top).
- Fill bars are drawn partly full in the kit; only their glowing part is kept.
- Icons are packed at 128 px on the long side; buttons and panels at 0.5 to 0.8 scale.

To change the art: edit the PNGs (or the lists in the script), run
`python tools/pack_ui_atlas.py` (needs Pillow), upload the new atlas and update the id.

## Turning it on

1. Studio: **View > Asset Manager > Images > Bulk Import**, pick `assets/ui/GaG_UI_Atlas.png`.
2. Right-click it > **Copy Asset ID**, then in `src/shared/Config/Sprites.luau`:
   `IMAGE = "rbxassetid://123456789" :: string?,`
3. Save; Rojo syncs; Play.

Edit the file in VS Code, not the module in Studio (Rojo ignores Studio-side edits).

## Where each piece is used

| Piece | In game |
|---|---|
| Stardust HUD panel (Stardust art built in) | Wallet; the text keeps clear of the art as it resizes |
| Tall inventory panel | Star Shop, Shipyard and Manage windows |
| Large space panel (planets and stars) | Wide boxes: achievement and celebration banners |
| Small blank panel | Short strips: toasts, Next Goal |
| Cyan / gold / purple / indigo buttons | Normal / Buy / Evolve / unavailable |
| Mining and beam-heat bars | Boost and extraction (cyan), heat, Next Goal, savings bars (orange-red) |
| Close tile | Close button of every window |
| Shop cart | HUD Star Shop button, Buy buttons in the Star Shop |
| Level up, rainbow star, rocket | Manage panel: Level up, Evolve, Move |
| Star creation, planet upgrade | Star Shop title, Next Goal, NEW STAR banner; empty orbits, NEW WORLD banners |
| Rainbow star, level up, medal | STAR EVOLVED, LEVEL UP and achievement banners |
| Space station, gear, info | Return to Station, Effects, the tutorial hint |
| Energy canister, mining asteroid | Boost and extraction gauges |
| Spaceship, mining asteroid, galaxy | Shipyard title and its Ships, Equipment, Galaxy sections |
| Stardust star, coin pile | Reward orbs flying to the wallet; "ready to collect" label |

The other icons (crates, chests, crystals, moon, planets, portal, telescope, gift, shield) are in
the atlas for later features.

## Hover animations

`Theme.hover(button)` gives every Theme button, the HUD buttons, Next Goal and the close tiles
the same feel: it springs up 8% with a slight tilt, a bright band sweeps across, its icon gives a
little twist, pressing squashes it and it pops back. Gamepad selection counts as hover. List rows
(shop, Shipyard, Manage) light up under the pointer.

## Vivid sparkles

The ambient sparkles now come in four saturated colours (cyan, magenta, gold, violet), drawn with
Brightness 4 so they bloom, twinkle twice as they live, with rare big white flares that spin, and
brighter pinpoints in between. Reduced effects still thins them out.

## What CI verifies vs what needs Studio

| Verified by CI | Needs a playtest in Studio (after the upload) |
|---|---|
| Atlas rects inside the atlas, slice centres inside their sprites, id format | Every panel, button, bar and icon at its size; text readable on the art |
| Strict types, lint, build, smoke test (with IMAGE unset) | Hover feel; sparkle brightness and density |

## Known limitations

- Planet tiers keep their drawn icons in the Manage panel (the kit has no full planet ladder).
- The tutorial hint, controls hint, reticle and readout stay plain text.
