--!strict
-- Saves the settings a player changes on their client (SettingChanged):
-- the suit stabilizer and reduced effects (DataSystem validates them), and
-- PvP, which CombatSystem decides.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatSystem = require(script.Parent.CombatSystem)
local DataSystem = require(script.Parent.DataSystem)
local Net = require(ReplicatedStorage.Shared.Net)
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)

local SettingsSystem = {}

local limit = RateLimiter.new(5, 2)

function SettingsSystem.start()
	Net.SettingChanged.OnServerEvent:Connect(function(player, name, value)
		if not limit.allow(player) then
			return
		end
		if name == "pvp" then
			CombatSystem.requestPvp(player, value)
		else
			DataSystem.setSetting(player, name, value)
		end
	end)
end

return SettingsSystem
