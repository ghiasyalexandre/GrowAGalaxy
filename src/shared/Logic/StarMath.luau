--!strict
-- Star tycoon numbers derived from Config.Stars: production, prices, which
-- planets a level shows, and income accrual. Pure, so the Lune tests and the
-- client's previews use exactly what the server uses.

local Config = require(script.Parent.Parent.Config)
local StarsConfig = require(script.Parent.Parent.Config.Stars)
local Types = require(script.Parent.Parent.Types)

local S = Config.Stars

local StarMath = {}

-- The level definition for a star, clamped to the levels that exist. Nil for
-- an unknown type.
function StarMath.levelDef(typeId: string, level: number): StarsConfig.LevelDef?
	local def = S.BY_ID[typeId]
	if def == nil then
		return nil
	end
	return def.levels[math.clamp(level, 1, #def.levels)]
end

function StarMath.maxLevel(typeId: string): number
	local def = S.BY_ID[typeId]
	return if def then #def.levels else 0
end

-- Stardust per second from one star.
function StarMath.income(typeId: string, level: number): number
	local levelDef = StarMath.levelDef(typeId, level)
	return if levelDef then levelDef.income else 0
end

-- Stardust per second from every star in a galaxy.
function StarMath.totalIncome(stars: { [string]: Types.StarRecord }): number
	local total = 0
	for _, star in stars do
		total += StarMath.income(star.typeId, star.level)
	end
	return total
end

-- Price of a new star of this type when the player already owns `owned` stars.
function StarMath.placeCost(typeId: string, owned: number): number?
	local def = S.BY_ID[typeId]
	if def == nil then
		return nil
	end
	return math.floor(def.cost * S.PRICE_GROWTH ^ math.max(owned, 0) + 0.5)
end

-- Cost to upgrade from `level` to the next level, or nil at the top.
function StarMath.upgradeCost(typeId: string, level: number): number?
	local def = S.BY_ID[typeId]
	if def == nil or level < 1 or level >= #def.levels then
		return nil
	end
	return def.levels[level + 1].upgradeCost
end

-- Indexes into Config.Stars.PLANETS for every planet a star shows at `level`.
function StarMath.planetsAt(typeId: string, level: number): { number }
	local def = S.BY_ID[typeId]
	local planets: { number } = {}
	if def then
		for index = 1, math.min(level, #def.levels) do
			local planet = def.levels[index].planet
			if planet then
				table.insert(planets, planet)
			end
		end
	end
	return planets
end

-- Uncollected Stardust after `dt` seconds at `rate`, capped at `cap`.
-- Never lowers an amount that is already above the cap.
function StarMath.accrue(uncollected: number, rate: number, dt: number, cap: number): number
	if uncollected >= cap then
		return uncollected
	end
	return math.min(cap, uncollected + math.max(rate, 0) * math.max(dt, 0))
end

return StarMath
