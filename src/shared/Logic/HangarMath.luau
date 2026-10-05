--!strict
-- Hangar upgrade rules shared by server, client and tests: which upgrades are
-- on offer, whether one can be bought, and the combined effect of the ones
-- built (Config.Hangar). Pure module: no Roblox services.

local Config = require(script.Parent.Parent.Config)

type Owned = { [string]: boolean }

local HangarMath = {}

-- True when every upgrade this one requires is built.
function HangarMath.available(id: string, owned: Owned): boolean
	local def = Config.Hangar.BY_ID[id]
	if def == nil or owned[id] then
		return false
	end
	for _, need in def.requires do
		if not owned[need] then
			return false
		end
	end
	return true
end

-- The price of an upgrade the player can buy now, or nil and why not.
function HangarMath.canBuy(id: string, owned: Owned, stardust: number): (number?, string?)
	local def = Config.Hangar.BY_ID[id]
	if def == nil then
		return nil, "That upgrade doesn't exist."
	elseif owned[id] then
		return nil, `{def.displayName} is already built.`
	elseif not HangarMath.available(id, owned) then
		local names: { string } = {}
		for _, need in def.requires do
			local other = Config.Hangar.BY_ID[need]
			table.insert(names, if other then other.displayName else need)
		end
		return nil, `Build the {table.concat(names, " and ")} first.`
	elseif stardust < def.cost then
		return nil, `You need {def.cost} {Config.Economy.CURRENCY_NAME} for the {def.displayName}.`
	end
	return def.cost, nil
end

-- Combined multiplier for a ship stat from the upgrades built.
function HangarMath.statMultiplier(owned: Owned, stat: string): number
	local multiplier = 1
	for id in owned do
		local def = Config.Hangar.BY_ID[id]
		local stats = def and def.stats
		if stats and stats[stat] then
			multiplier *= stats[stat]
		end
	end
	return multiplier
end

local function product(owned: Owned, field: "income" | "storage"): number
	local multiplier = 1
	for id in owned do
		local def = Config.Hangar.BY_ID[id]
		local value = def and def[field]
		if value then
			multiplier *= value
		end
	end
	return multiplier
end

-- Multiplier on star income.
function HangarMath.incomeMultiplier(owned: Owned): number
	return product(owned, "income")
end

-- Multiplier on the uncollected Stardust cap.
function HangarMath.storageMultiplier(owned: Owned): number
	return product(owned, "storage")
end

return HangarMath
