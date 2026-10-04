--!strict
-- Saves the settings a player changes on their client (SettingChanged):
-- the suit stabilizer and reduced effects. DataSystem validates them.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DataSystem = require(script.Parent.DataSystem)
local Net = require(ReplicatedStorage.Shared.Net)
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)

local SettingsSystem = {}

local limit = RateLimiter.new(5, 2)

function SettingsSystem.start()
	Net.SettingChanged.OnServerEvent:Connect(function(player, name, value)
		if limit.allow(player) then
			DataSystem.setSetting(player, name, value)
		end
	end)
end

return SettingsSystem
