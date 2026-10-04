--!strict
-- Short on-screen messages for one player (shown as toasts by the client).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)

local Notify = {}

function Notify.send(player: Player, text: string)
	Net.Notify:FireClient(player, text)
end

return Notify
