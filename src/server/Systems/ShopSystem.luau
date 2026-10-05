--!strict
-- The station Shipyard: ships, equipment and galaxy expansions, all bought
-- with Stardust. Ship and equipment changes apply the next time the player
-- launches their ship.
--
-- ShopRequest (RemoteFunction, client -> server), returns (ok, message):
--   "buyShip", shipId          buy an earnable ship (fitted with your equipment)
--   "selectShip", shipId       make an owned ship the one your hangars launch
--   "buyTrail", trailId        buy a trail (Config.Trails) and equip it
--   "equipTrail", trailId|""   equip an owned trail, or none
--   "buyEquipment", itemId     buy an item (fitted to every ship you own), or
--                              raise one you own a level, up to MAX_LEVEL
--   "expand"                   buy the next galaxy expansion

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local DataSystem = require(script.Parent.DataSystem)
local Net = require(ReplicatedStorage.Shared.Net)
local Progression = require(ReplicatedStorage.Shared.Logic.Progression)
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)
local RegionSystem = require(script.Parent.RegionSystem)

local CURRENCY = Config.Economy.CURRENCY_NAME
local APPLY_NOTE = "Launch your ship from a hangar to use it."

local ShopSystem = {}

local limit = RateLimiter.new(5, 2)

local function buyShip(player: Player, profile: any, shipId: string): (boolean, string)
	local cost = Progression.shipCost(shipId)
	if cost == nil then
		return false, "That ship isn't for sale."
	end
	if profile.ownedShips[shipId] then
		return false, "You already own that ship."
	end
	if not Progression.shipUnlocked(shipId, profile.ownedShips) then
		local previous = Progression.previousShip(shipId)
		local name = if previous
			then Config.Ships.BY_ID[previous].displayName
			else "the ship before it"
		return false, `Own the {name} first.`
	end
	if not DataSystem.spendStardust(player, cost) then
		return false, `You need {cost} {CURRENCY} for that ship.`
	end
	DataSystem.grantShip(player, shipId)
	DataSystem.setActiveShip(player, shipId)
	return true, `{Config.Ships.BY_ID[shipId].displayName} bought and selected. {APPLY_NOTE}`
end

local function selectShip(player: Player, shipId: string): (boolean, string)
	if not DataSystem.setActiveShip(player, shipId) then
		return false, "You don't own that ship."
	end
	return true, `{Config.Ships.BY_ID[shipId].displayName} selected. {APPLY_NOTE}`
end

local function buyEquipment(player: Player, profile: any, itemId: string): (boolean, string)
	local owned = profile.ownedEquipment[itemId] == true
	local nextLevel = if owned then (profile.equipmentLevels[itemId] or 1) + 1 else 1
	if Progression.equipmentCost(itemId) == nil then
		return false, "That item isn't for sale."
	end
	local cost = Progression.equipmentCost(itemId, nextLevel)
	if cost == nil then
		return false, "That item is already at its top level."
	end
	if not DataSystem.spendStardust(player, cost) then
		return false, `You need {cost} {CURRENCY} for that.`
	end
	local def = Config.Equipment.BY_ID[itemId]
	if owned then
		DataSystem.levelEquipment(player, itemId)
		return true,
			`{def.displayName} upgraded to level {nextLevel}/{Config.Equipment.MAX_LEVEL}. {APPLY_NOTE}`
	end
	DataSystem.grantEquipment(player, itemId, def.slot)
	return true, `{def.displayName} fitted to your ships. {APPLY_NOTE}`
end

local function expand(player: Player, profile: any): (boolean, string)
	local level = profile.galaxy.expansion
	local cost = Progression.expansionCost(level)
	if cost == nil then
		return false, "Your galaxy is already as big as it gets."
	end
	if not DataSystem.spendStardust(player, cost) then
		return false, `You need {cost} {CURRENCY} to expand your galaxy.`
	end
	DataSystem.setExpansion(player, level + 1)
	RegionSystem.resize(player, level + 1)
	local nextDef = Config.Galaxy.EXPANSIONS[level + 1]
	return true, `Galaxy expanded! It now holds {nextDef.maxSystems} stars.`
end

local function onRequest(player: Player, action: unknown, id: unknown): (boolean, string)
	if not limit.allow(player) then
		return false, "Slow down a little."
	end
	local profile = DataSystem.getProfile(player)
	if profile == nil then
		return false, "Your save isn't loaded yet."
	end
	if action == "expand" then
		return expand(player, profile)
	end
	if type(id) ~= "string" then
		return false, "Invalid request."
	end
	if action == "buyShip" then
		return buyShip(player, profile, id)
	elseif action == "selectShip" then
		return selectShip(player, id)
	elseif action == "buyEquipment" then
		return buyEquipment(player, profile, id)
	elseif action == "buyTrail" then
		local def = Config.Trails.BY_ID[id]
		if def == nil then
			return false, "That trail isn't for sale."
		elseif profile.ownedTrails[id] then
			return false, "You already own that trail."
		elseif not DataSystem.spendStardust(player, def.cost) then
			return false, `You need {def.cost} {CURRENCY} for that.`
		end
		DataSystem.grantTrail(player, id)
		DataSystem.equipTrail(player, id)
		return true,
			`{def.displayName} equipped: x{def.multiplier} Stardust from everything you earn.`
	elseif action == "equipTrail" then
		local wanted = if id == "" then nil else id
		if not DataSystem.equipTrail(player, wanted) then
			return false, "You don't own that trail."
		end
		local def = if wanted then Config.Trails.BY_ID[wanted] else nil
		return true, if def then `{def.displayName} equipped.` else "Trail removed."
	end
	return false, "Invalid request."
end

function ShopSystem.start()
	Net.ShopRequest.OnServerInvoke = onRequest
end

return ShopSystem
