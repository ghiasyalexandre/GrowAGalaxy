# Stage 11: Sprite sheet UI

> Superseded by [stage 12](stage-12-ui-kit.md): the UI now uses the packed UI kit atlas. The
> skinning code below still applies; the sprite names and the image to upload changed.

**Status: code complete, CI-verified (format, lint, strict types, 107 unit tests, build, smoke
test). The art only appears in game once the sheet is uploaded to Roblox (below). Not yet seen
in Studio.**

## The sheet

`assets/ui/GaG_SpriteSheet.png` is the original (1448 x 1086). `assets/ui/GaG_SpriteSheet_1024.png`
is the same art at 1024 x 768, the copy to upload: Roblox downscales anything over 1024, and the
sprite rects in `src/shared/Config/Sprites.luau` are measured on this copy.

| Sprites | Used for |
|---|---|
| Stardust | Wallet icon, Next Goal icon, reward orbs (tumbling into the wallet), Collect label |
| StarPlus | Star Shop button and title, star celebration banners (NEW STAR, LEVEL UP, STAR EVOLVED) |
| PlanetUp | Empty orbits in the Manage panel, NEW WORLD / WORLD UPGRADED banners |
| Ship | Shipyard title and Ships section, Return to Station button, boost gauge |
| Laser | Shipyard Equipment section, extraction gauge |
| Galaxy | Shipyard Galaxy (expansion) section |
| Medal | Achievement banners |
| Gear | Effects (settings) button |
| ButtonBlue / Gold / Purple / Dark | Buttons: primary / buy / special (Evolve) / disabled |
| PanelLarge / PanelWide | Every panel; wide ones (banners, toasts, wallet, Next Goal) pick the wide frame by shape |
| TrackOrange + FillOrange | Heat gauge, Next Goal, shop saving-up bars |
| TrackGrey + FillCyan | Boost and extraction gauges |

Buttons and bars are 9-slice: their corners keep their shape at any size (the slice scale follows
the element's height), and only plain middle sections stretch.

## Turning it on

1. In Studio: **View > Asset Manager > Images > Bulk Import**, pick
   `assets/ui/GaG_SpriteSheet_1024.png`. (Or Creator Hub > Creations > Development Items >
   Images > Upload.) The place must be published to the account or group that owns it.
2. Right-click the image > **Copy Asset ID** and set it in `src/shared/Config/Sprites.luau`:
   `IMAGE = "rbxassetid://123456789" :: string?,`
3. Rojo syncs it; press Play.

While `IMAGE` is nil, the UI keeps its plain gradient look, so nothing breaks before the upload.
`ConfigCheck` rejects an `IMAGE` that isn't `rbxassetid://<number>` and any rect outside the sheet.

To change art later: edit the PNG keeping each sprite in place, re-export at 1024 x 768, and
re-upload (a new upload gets a new id). If sprites move, update their rects in `Config/Sprites`.

## What CI verifies vs what needs Studio

| Verified by CI | Needs a playtest in Studio (after the upload) |
|---|---|
| Rects inside the sheet, slice centres inside their sprites, id format (unit tests) | Every panel, button, bar and icon looks right at its size |
| Strict types, lint, build, smoke test (with IMAGE unset) | Text stays readable on the art; nothing overlaps the frame borders |

## Studio hierarchy (new and changed)

```
ReplicatedStorage/Shared/Config/Sprites               NEW sheet id, sprite rects, slice centres
StarterPlayerScripts/Client/UI/Sprites                NEW icons, 9-slice skins, panel frames
StarterPlayerScripts/Client/UI/Theme                  panels, buttons, bars use the skins; Theme.icon; "special" buttons
StarterPlayerScripts/Client/Controllers/HudController wallet, buttons, gauges, Next Goal dressed
StarterPlayerScripts/Client/Controllers/NotifyController toasts are frames with a label (skinnable)
StarterPlayerScripts/Client/Controllers/RewardController sprite orbs, banner icons, Collect icon
StarterPlayerScripts/Client/Controllers/StarShopController / ShopController / StarController  header and row icons
```

A skinned element gets an `ImageLabel` named `Skin` (ZIndex 0) behind its children; buttons move
their text to a child `TextLabel` named `Label`.

## Manual test steps (after setting IMAGE)

| # | Steps | Expected |
|---|---|---|
| 1 | Play. | Wallet in the wide frame with the Stardust icon; Effects (gear), Star Shop (gold, star icon) and Return to Station (blue, ship) buttons. |
| 2 | Open the Star Shop (B). | Large frame, star icon by the title, gold Buy / dark disabled buttons, orange saving-up bars. |
| 3 | Manage a star. | Purple Evolve button; empty orbits show the planet icon. |
| 4 | Break an asteroid. | Stardust icons tumble into the wallet. |
| 5 | Earn an achievement. | Banner in the wide frame with the medal icon. |
| 6 | Fly. | Heat (orange), boost (cyan, ship icon) and extraction (cyan, laser icon) bars. |

## Known limitations

- The tutorial hint, controls hint, reticle and readout stay plain text.
- The sheet's art includes glow margins, so a skinned element's visible body is a little smaller
  than its box.
