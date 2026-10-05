# Scenery models

Rojo syncs this folder to `ServerStorage/Assets/Stuff` (server only). `RaidBuilder` uses
`SaturnV.rbxm` as the raid beacon on the ISS raid platform: it removes every script, sound,
click detector, prompt and humanoid, anchors the parts and scales it to
`Config.Raids.BEACON_HEIGHT`. Without the file a greybox rocket stands in. See
[stage 19](../../../docs/stage-19-iss-raids.md).
