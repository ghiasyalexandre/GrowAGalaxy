--!strict
-- Ship paint jobs and the Showcase Dock (Config.Paint), from the Shipyard's
-- Paint tab through CustomizeRequest:
--
--   ("paint", shipId, colour | nil)     a swatch colour, or nil for factory
--   ("finish", shipId, finishId | nil)  a finish, or nil for factory
--   ("showcase", shipId, on: boolean)   put an owned ship on show, or not
--
-- Returns (ok, message). DataSystem validates ownership and values; a spawned
-- ship and the dock's displays are repainted at once.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local DataSystem = require(script.Parent.DataSystem)
local HangarSystem = require(script.Parent.HangarSystem)
local Net = require(ReplicatedStorage.Shared.Net)
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)
local ShipSystem = require(script.Parent.ShipSystem)

local CustomizeSystem = {}

local limit = RateLimiter.new(6, 1)

local function handle(
	player: Player,
	action: unknown,
	shipId: unknown,
	value: unknown
): (boolean, string)
	local profile = DataSystem.getProfile(player)
	if profile == nil or type(shipId) ~= "string" or Config.Ships.BY_ID[shipId] == nil then
		return false, "Unknown ship."
	end
	local loadout = profile.loadouts[shipId]
	if not profile.ownedShips[shipId] or loadout == nil then
		return false, "You don't own that ship."
	end
	local name = Config.Ships.BY_ID[shipId].displayName
	if action == "paint" and (value == nil or type(value) == "string") then
		if not DataSystem.setShipLook(player, shipId, value :: string?, loadout.finish) then
			return false, "That colour isn't on offer."
		end
	elseif action == "finish" and (value == nil or type(value) == "string") then
		if not DataSystem.setShipLook(player, shipId, loadout.paint, value :: string?) then
			return false, "That finish isn't on offer."
		end
	elseif action == "showcase" and type(value) == "boolean" then
		if not DataSystem.setShowcase(player, shipId, value) then
			return false,
				`The Showcase Dock holds {Config.Paint.SHOWCASE_SLOTS} ships: take one off first.`
		end
		HangarSystem.refreshShowcase(player)
		local built = profile.hangar.ShowcaseDock == true
		return true,
			if value
				then `{name} is in your showcase.{if built
					then ""
					else " Build the Showcase Dock in your hangar to see it."}`
				else `{name} left your showcase.`
	else
		return false, "Unknown request."
	end
	ShipSystem.refreshLook(player)
	if table.find(profile.showcase, shipId) then
		HangarSystem.refreshShowcase(player)
	end
	return true, `{name} repainted.`
end

function CustomizeSystem.start()
	Net.CustomizeRequest.OnServerInvoke = function(player, action, shipId, value)
		if not limit.allow(player) then
			return false, "Slow down a little."
		end
		return handle(player, action, shipId, value)
	end
end

return CustomizeSystem
