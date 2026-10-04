--!strict
-- Tells a player's client to celebrate Stardust they just earned (Reward
-- remote): orbs fly from `position` (a world position, or nil for the screen
-- centre) to the wallet, with a pop-up. `kind` picks the style. The Stardust
-- itself is already in the profile; this is presentation only.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)

export type Kind = "collect" | "mine" | "achievement"

local Reward = {}

function Reward.send(player: Player, kind: Kind, amount: number, position: Vector3?, label: string?)
	Net.Reward:FireClient(player, kind, amount, position, label)
end

return Reward
