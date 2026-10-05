--!strict
-- The passes each player in this server owns, as verified by
-- MonetizationSystem through Roblox (never from a client). Reward code reads
-- them here, so it doesn't depend on MonetizationSystem itself.

local Players = game:GetService("Players")

local Entitlements = {}

local EMPTY: { [string]: boolean } = table.freeze({})
local passes: { [Player]: { [string]: boolean } } = {}

-- Pass key -> true for every pass the player owns (read-only).
function Entitlements.passes(player: Player): { [string]: boolean }
	return passes[player] or EMPTY
end

function Entitlements.set(player: Player, owned: { [string]: boolean })
	if player.Parent == Players then
		passes[player] = table.freeze(table.clone(owned))
	end
end

Players.PlayerRemoving:Connect(function(player)
	passes[player] = nil
end)

return Entitlements
