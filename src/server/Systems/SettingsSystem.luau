--!strict
-- Saves the settings a player changes on their client (SettingChanged):
-- the suit stabilizer, reduced effects, floating and the planet settings
-- (DataSystem validates them; "autoSell" carries a rarity and on/off), the
-- hangar highlight colour ("hangarColor", an id or "": StationSystem repaints), and
-- PvP, which CombatSystem decides.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatSystem = require(script.Parent.CombatSystem)
local CloakSystem = require(script.Parent.CloakSystem)
local DataSystem = require(script.Parent.DataSystem)
local HangarSystem = require(script.Parent.HangarSystem)
local StationSystem = require(script.Parent.StationSystem)
local Net = require(ReplicatedStorage.Shared.Net)
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)

local SettingsSystem = {}

local limit = RateLimiter.new(5, 2)

function SettingsSystem.start()
	Net.SettingChanged.OnServerEvent:Connect(function(player, name, value, extra)
		if not limit.allow(player) then
			return
		end
		if name == "pvp" then
			CombatSystem.requestPvp(player, value)
		elseif name == "autoSell" then
			DataSystem.setAutoSell(player, value, extra)
		elseif name == "cloak" then
			CloakSystem.request(player, value)
		elseif name == "hangarToggle" then
			-- (id, on): a built `toggle` hangar upgrade shown or hidden.
			if type(extra) == "boolean" and DataSystem.setHangarOff(player, value, not extra) then
				HangarSystem.refresh(player)
			end
		elseif name == "hangarColor" then
			if DataSystem.setHangarColor(player, value) then
				StationSystem.recolor(player)
			end
		else
			DataSystem.setSetting(player, name, value)
		end
	end)
end

return SettingsSystem
