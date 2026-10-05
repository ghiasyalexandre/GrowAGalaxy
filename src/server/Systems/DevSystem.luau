--!strict
-- Studio-only test hooks. In a live server this module does nothing.
--
-- From the Studio command bar while playtesting (server view):
--   game.ServerStorage.DevCommand:Invoke(game.Players:GetPlayers()[1], "addStardust", 500)
--   game.ServerStorage.DevCommand:Invoke(game.Players:GetPlayers()[1], "printProfile")
--   game.ServerStorage.DevCommand:Invoke(game.Players:GetPlayers()[1], "launch")  -- ship at an ISS berth
--   game.ServerStorage.DevCommand:Invoke(game.Players:GetPlayers()[1], "asteroids")  -- how many exist
--   game.ServerStorage.DevCommand:Invoke(game.Players:GetPlayers()[1], "grantCosmetic", "GoldenBeam")
-- Mock purchases (no Robux; same server code paths, Config.Products keys):
--   ...:Invoke(player, "mockReceipt", "MiningBoost")           -- a developer product receipt
--   ...:Invoke(player, "mockReceipt", "StardustSmall", "R1")  -- twice with the same id grants once
--   ...:Invoke(player, "mockPass", "MiningMultiplier", true)   -- a pass, this session only
--   ...:Invoke(player, "boosts")                               -- boost seconds left
--
-- A BindableFunction is used because modules required from the command bar
-- are separate copies that don't share state with the running game.

local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local AsteroidSystem = require(script.Parent.AsteroidSystem)
local DataSystem = require(script.Parent.DataSystem)
local MonetizationSystem = require(script.Parent.MonetizationSystem)
local RegionSystem = require(script.Parent.RegionSystem)
local ShipSystem = require(script.Parent.ShipSystem)

local DevSystem = {}

local COMMANDS: { [string]: (player: Player, ...any) -> any } = {
	addStardust = function(player, amount)
		return DataSystem.addStardust(player, tonumber(amount) or 0)
	end,
	printProfile = function(player)
		local profile = DataSystem.getProfile(player)
		print(HttpService:JSONEncode(profile))
		return profile ~= nil
	end,
	region = function(player)
		local region = RegionSystem.getRegion(player)
		return if region then region.slot else nil
	end,
	mockReceipt = function(player, key, purchaseId)
		return MonetizationSystem.mockReceipt(
			player,
			tostring(key),
			if purchaseId then tostring(purchaseId) else nil
		)
	end,
	mockPass = function(player, key, on)
		return MonetizationSystem.mockPass(player, tostring(key), on ~= false)
	end,
	boosts = function(player)
		local profile = DataSystem.getProfile(player)
		return if profile
			then `mining {profile.boosts.mining}s, star {profile.boosts.star}s`
			else nil
	end,
	grantCosmetic = function(player, cosmeticId)
		DataSystem.grantCosmetic(player, tostring(cosmeticId))
		return true
	end,
	asteroids = function()
		return AsteroidSystem.count()
	end,
	launch = function(player, hangar)
		ShipSystem.launch(player, if hangar == "Station" then "Station" else "ISS")
		return true
	end,
}

function DevSystem.init()
	if not RunService:IsStudio() then
		return
	end
	local command = Instance.new("BindableFunction")
	command.Name = "DevCommand"
	command.OnInvoke = function(player: Player, name: string, ...: any)
		local handler = COMMANDS[name]
		if handler == nil then
			warn(`[DevSystem] Unknown command "{name}"`)
			return nil
		end
		return handler(player, ...)
	end
	command.Parent = ServerStorage
end

return DevSystem
