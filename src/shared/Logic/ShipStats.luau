--!strict
-- Effective ship stats: the chassis stats from Config.Ships multiplied by the
-- equipment fitted to that ship. Cosmetics never change stats.

local Config = require(script.Parent.Parent.Config)
local Types = require(script.Parent.Parent.Types)

type ShipStats = typeof(Config.Ships.BY_ID.StarterShuttle.stats)

local ShipStats = {}

-- Stats for `shipId` with `loadout` fitted, or nil for an unknown ship.
-- Equipment that is unknown, in the wrong slot, or not owned is ignored.
function ShipStats.effective(
	shipId: string,
	loadout: Types.Loadout?,
	ownedEquipment: { [string]: boolean }?
): ShipStats?
	local def = Config.Ships.BY_ID[shipId]
	if def == nil then
		return nil
	end
	local stats = table.clone(def.stats)
	if loadout == nil then
		return stats
	end
	for slot, itemId in loadout.equipment do
		local item = Config.Equipment.BY_ID[itemId]
		local owned = ownedEquipment == nil or ownedEquipment[itemId] == true
		if item and item.slot == slot and owned then
			for stat, multiplier in item.modifiers do
				local value = (stats :: any)[stat]
				if type(value) == "number" then
					(stats :: any)[stat] = value * multiplier
				end
			end
		end
	end
	return stats
end

-- The player's active ship's stats.
function ShipStats.forProfile(profile: Types.Profile): ShipStats
	local stats = ShipStats.effective(
		profile.activeShip,
		profile.loadouts[profile.activeShip],
		profile.ownedEquipment
	)
	if stats then
		return stats
	end
	return table.clone(Config.Ships.BY_ID[Config.Ships.STARTER_SHIP].stats)
end

-- Total material units in a cargo hold.
function ShipStats.cargoUsed(cargo: { [string]: number }): number
	local total = 0
	for _, amount in cargo do
		total += amount
	end
	return total
end

-- A player may only switch to a ship whose hold fits their current cargo.
function ShipStats.canCarry(stats: ShipStats, cargo: { [string]: number }): boolean
	return ShipStats.cargoUsed(cargo) <= math.floor(stats.cargoCapacity)
end

return ShipStats
