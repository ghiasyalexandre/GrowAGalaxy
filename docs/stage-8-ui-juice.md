# Stage 8: UI juice and reward effects

**Status: code complete, CI-verified (format, lint, strict types, 101 unit tests, build, smoke
test). Not yet playtested in Studio.**

## Playable result

- **Stardust rewards feel good.** Collecting at your station, breaking an asteroid or earning an
  achievement now:
  - bursts sparkles in the world where the Stardust came from,
  - sprays glowing gold orbs on screen that stream into your wallet, which bounces and flashes
    gold as each one lands,
  - pops a big bouncing `+1.2K Stardust` with what it was for ("Collected from your stars",
    "Medium asteroid · +3 precision"), which floats up and fades.
- **Wallet.** A gradient panel with a gold edge; the number counts up smoothly to the new balance
  and a bright shimmer sweeps across it every few seconds.
- **Achievements** slide in as a gold "ACHIEVEMENT UNLOCKED" banner with the name and rewards.
- **Collect console** shows a pulsing gold "1.2K ready to collect" above it when your stars have
  produced at least 1 Stardust.
- **Toasts** match the theme (gradient, glowing edge, pop-in) and sit below the tutorial hint.
- **Shipyard** uses the shared theme like the Star Shop and Manage panels.
- Reduced effects (HUD toggle) caps the orbs at 5.

## What CI verifies vs what needs Studio

| Verified by CI | Needs a playtest in Studio |
|---|---|
| Strict type check, lint, unit tests, build, smoke test | Orbs fly to the right place on different screen sizes and with the top bar |
| | Pop-ups, banner and ready label are readable and not in the way |
| | The effects stay smooth when mining quickly |

## Studio hierarchy (new and changed)

```
ReplicatedStorage/Remotes/Reward                       RemoteEvent NEW kind, amount, position?, label?
ServerScriptService/Server/Util/Reward                 ModuleScript NEW
ServerScriptService/Server/Systems/MiningSystem        Reward instead of a toast on breaking
ServerScriptService/Server/Systems/StarSystem          Reward from the Collect console
ServerScriptService/Server/Systems/ProgressionSystem   Reward (banner) for achievements
StarterPlayerScripts/Client/Controllers/RewardController  NEW orbs, pop-ups, bursts, banner, ready label
StarterPlayerScripts/Client/Controllers/HudController     wallet count-up, shimmer, bump; walletTarget()
StarterPlayerScripts/Client/Controllers/NotifyController  themed toasts, moved below the hint
StarterPlayerScripts/Client/Controllers/ShopController    themed
PlayerGui/Rewards                                       effects layer (ignores the top bar inset)
Workspace/Camera/GaG_CollectReady                       ready-to-collect billboard (client only)
```

## Manual test steps

| # | Steps | Expected |
|---|---|---|
| 1 | Break an asteroid. | Sparkle burst at the asteroid; orbs spray out and stream into the wallet; wallet bounces and counts up; "+12 Stardust / Small asteroid" pops and fades. |
| 2 | Own a star, wait, look at the Collect console. | Pulsing "N ready to collect" above it. |
| 3 | Collect. | Burst at the console, more orbs (scales with the amount), big pop-up; the ready label disappears. |
| 4 | Buy your first star. | Gold achievement banner slides in (First Light), plus orbs for its Stardust reward. |
| 5 | Toggle Effects to reduced and collect again. | At most 5 orbs. |
