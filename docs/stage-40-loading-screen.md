# Stage 40: Loading screen

**Status: code complete, CI-verified (format, lint, strict types, 227 unit tests, build, world
and orbit smoke tests). Not yet seen in Studio. Needs the key art uploaded (below).**

A custom loading screen replaces Roblox's default one (`src/first/LoadingScreen.client.luau`,
synced to ReplicatedFirst so it runs before anything else):

- The **Grow a Galaxy 2 key art** fills the screen (cropped to fit any screen shape, never
  stretched) and drifts slowly closer.
- At the bottom: a status line ("Loading the galaxy...", "Building your galaxy...", "Let's go!"),
  a gold progress bar and kid-friendly tips that change every few seconds.
- It closes once the place has loaded **and** our client has finished starting (it sets the
  local player attribute `GaG_ClientReady`), after at least 2.5 s, then fades out.
- **Play now** appears after 10 s if loading is slow; after 45 s it closes by itself.
- Until the art is uploaded, a title card in the same colours shows instead ("GROW A /
  GALAXY 2" in white and gold on a purple space gradient).

## Studio action needed: upload the art

1. The image is saved as `assets/ui/GaG_LoadingScreen.png` (1672 x 941).
2. Upload it to Roblox (Studio: View > Asset Manager > Bulk Import, or Creator Hub > Creations
   > Development Items > Images). Roblox scales it to 1024 wide, fine for a background.
3. Copy its image id and set `IMAGE = "rbxassetid://<id>"` at the top of
   `src/first/LoadingScreen.client.luau` in VS Code.

The id lives in the script (not Config) because ReplicatedFirst runs before ReplicatedStorage
has loaded.

## Test in Studio

Studio loads fast, so to see it properly use **Test > Clients and Servers** or a published test
server. Check the art fills the screen on PC, phone and tablet emulators, the bar fills, the tips
change, and it fades away to the game.
