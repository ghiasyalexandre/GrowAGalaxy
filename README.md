# Grow a Galaxy 2

A space tycoon for Roblox. Claim a galaxy, buy droppers that mine stardust ore,
and send it down the conveyor into your Star Furnace to grow your fortune.

Built with [Rojo](https://rojo.space), so all game code lives in `src/` and syncs into Studio.

## Open it in Roblox Studio

**Quick look (no tools):** open `Grow-a-Galaxy-2.rbxl` (or build one with
`rojo build -o Grow-a-Galaxy-2.rbxl`) in Studio and press Play.

**Day-to-day development:**

1. Install [Rokit](https://github.com/rojo-rbx/rokit), then in this folder run `rokit install`
   (installs the pinned Rojo, Wally, Selene and StyLua).
2. In Studio, install the Rojo plugin: Plugins tab → Manage Plugins, or run `rojo plugin install`.
3. Run `rojo serve` in this folder.
4. Open a new Baseplate place in Studio, delete the `Baseplate` part, open the Rojo plugin and
   click **Connect**. Code changes in `src/` now appear in Studio live.
5. To save progress in playtests, publish the place and enable
   Game Settings → Security → **Enable Studio Access to API Services**.

## How the game works

- Each player is assigned one of 6 plots around the central hub (set the server's max players to 6).
- Green pads buy droppers in order: Asteroid Miner → Comet Harvester → Nebula Siphon →
  Star Forge → Black Hole Reactor.
- Droppers spawn ore on a conveyor; the Star Furnace turns it into Stardust.
- Stardust and owned droppers save to a DataStore.

Prices, income and layout are tuned in `src/shared/Config.luau`.

## Structure

- `src/shared` → ReplicatedStorage/Shared: types, config, formatting
- `src/server` → ServerScriptService/Server: `WorldSystem` (space lighting, hub),
  `DataSystem` (profiles, saving), `TycoonSystem` (plots, droppers, buying)
- `src/client` → StarterPlayerScripts/Client: `HudController` (Stardust counter)

## Checks

- Format: `stylua src`
- Lint: `selene src`

CI runs both on every push and pull request.

## Next steps

- Swap the starter DataStore code for session-locked saving (e.g. ProfileStore) before launch.
- Add rebirths, more tiers and a shop UI.
