--!strict
-- Star tycoon numbers derived from Config.Stars and Config.Planets:
-- production, prices, tier rules and income accrual. Pure, so the Lune tests
-- and the client's panels use exactly what the server uses.
--
-- Planets are individually owned (profile.planets, Logic/PlanetInventory);
-- the ones equipped on a star are passed in as `equipped`: orbit slot number
-- -> planet record. Only equipped planets produce.

local Config = require(script.Parent.Parent.Config)
local Types = require(script.Parent.Parent.Types)

local S = Config.Stars
local P = Config.Planets

local StarMath = {}

local function tierOf(typeId: string): number
	local def = S.BY_ID[typeId]
	return if def then def.tier else 1
end

-- The highest level a star of this type reaches (4, 6, 8 ... by tier).
function StarMath.maxLevel(typeId: string): number
	return S.MAX_LEVEL_BASE + S.MAX_LEVEL_STEP * (tierOf(typeId) - 1)
end

-- Planet slots of a star of this type (Config.Stars `orbits`, at most 9).
function StarMath.slots(typeId: string): number
	local def = S.BY_ID[typeId]
	return math.min(if def then def.orbits else 1, #S.SLOTS)
end

-- Production multiplier at a level: grows a little faster every level.
function StarMath.levelMultiplier(level: number): number
	local n = math.max(level, 1) - 1
	return 1 + S.LEVEL_INCOME_LINEAR * n + S.LEVEL_INCOME_CURVE * n * n
end

-- Visual radius of a star: grows to MAX_RADIUS_SCALE at max level.
function StarMath.radius(typeId: string, level: number): number
	local def = S.BY_ID[typeId]
	local top = StarMath.maxLevel(typeId)
	local progress = if top > 1 then (math.clamp(level, 1, top) - 1) / (top - 1) else 0
	return (if def then def.radius else 12) * (1 + (S.MAX_RADIUS_SCALE - 1) * progress)
end

-- Stardust per second from the star itself (planets not included), rounded
-- to a whole number.
function StarMath.starIncome(typeId: string, level: number): number
	local def = S.BY_ID[typeId]
	if def == nil then
		return 0
	end
	return math.floor(def.income * StarMath.levelMultiplier(level) + 0.5)
end

-- A planet's Stardust per second at a level (1 when omitted), whole.
function StarMath.planetIncome(planetId: string, level: number?): number
	local def = P.BY_ID[planetId]
	if def == nil then
		return 0
	end
	local lv = math.clamp(level or 1, 1, P.MAX_LEVEL)
	return math.floor(def.income * (1 + P.LEVEL_INCOME_STEP * (lv - 1)) + 0.5)
end

-- Price to raise a planet from `level` to the next, or nil at MAX_LEVEL.
function StarMath.planetLevelCost(planetId: string, level: number): number?
	local def = P.BY_ID[planetId]
	if def == nil or level < 1 or level >= P.MAX_LEVEL then
		return nil
	end
	local base = P.UPGRADE_COST[def.rarity] or 0
	return math.floor(base * P.UPGRADE_GROWTH ^ (level - 1) + 0.5)
end

-- A planet's radius at a level: a little bigger every level.
function StarMath.planetRadius(planetId: string, level: number): number
	local def = P.BY_ID[planetId]
	local lv = math.clamp(level, 1, P.MAX_LEVEL)
	return (if def then def.radius else 4) * (1 + P.LEVEL_SIZE_STEP * (lv - 1))
end

-- Stardust per second from a star and the planets equipped on it
-- (slot -> planet record; nil = none).
function StarMath.income(
	star: Types.StarRecord,
	equipped: { [number]: Types.PlanetRecord }?
): number
	local total = StarMath.starIncome(star.typeId, star.level)
	if equipped then
		for _, planet in equipped do
			total += StarMath.planetIncome(planet.typeId, planet.level)
		end
	end
	return total
end

-- Stardust per second from every star and every planet equipped on one.
function StarMath.totalIncome(
	stars: { [string]: Types.StarRecord },
	planets: { [string]: Types.PlanetRecord }?
): number
	local total = 0
	for _, star in stars do
		total += StarMath.starIncome(star.typeId, star.level)
	end
	if planets then
		for _, planet in planets do
			local starId = planet.star
			if starId and stars[starId] then
				total += StarMath.planetIncome(planet.typeId, planet.level)
			end
		end
	end
	return total
end

-- Highest star tier in a galaxy (0 when empty).
function StarMath.highestTier(stars: { [string]: Types.StarRecord }): number
	local highest = 0
	for _, star in stars do
		local def = S.BY_ID[star.typeId]
		if def then
			highest = math.max(highest, def.tier)
		end
	end
	return highest
end

-- May a new star of this type be bought? Needs a star of the previous tier
-- (the first tier needs nothing).
function StarMath.typeUnlocked(typeId: string, stars: { [string]: Types.StarRecord }): boolean
	local def = S.BY_ID[typeId]
	return def ~= nil and def.enabled and StarMath.highestTier(stars) >= def.tier - 1
end

-- The next star type to aim for: the tier above the best star owned (the
-- first tier for an empty galaxy), or nil once the top tier is owned.
function StarMath.nextTier(stars: { [string]: Types.StarRecord }): string?
	local wanted = StarMath.highestTier(stars) + 1
	for _, id in S.ORDER do
		local def = S.BY_ID[id]
		if def.tier == wanted and def.enabled then
			return id
		end
	end
	return nil
end

-- Price of a new star when the player already owns `owned` stars.
function StarMath.placeCost(typeId: string, owned: number): number?
	local def = S.BY_ID[typeId]
	if def == nil then
		return nil
	end
	return math.floor(def.cost * S.PRICE_GROWTH ^ math.max(owned, 0) + 0.5)
end

-- Cost to level a star up from `level`, or nil at its max level.
function StarMath.upgradeCost(typeId: string, level: number): number?
	local def = S.BY_ID[typeId]
	if def == nil or level < 1 or level >= StarMath.maxLevel(typeId) then
		return nil
	end
	return math.floor(def.cost * S.UPGRADE_SHARE * S.UPGRADE_GROWTH ^ (level - 1) + 0.5)
end

-- May this star evolve now? Only at its max level, and not past the top.
function StarMath.canEvolve(star: Types.StarRecord): boolean
	return StarMath.evolveTarget(star.typeId) ~= nil
		and star.level >= StarMath.maxLevel(star.typeId)
end

-- The type a star evolves into, or nil for the last tier.
function StarMath.evolveTarget(typeId: string): string?
	local def = S.BY_ID[typeId]
	if def == nil then
		return nil
	end
	for _, id in S.ORDER do
		local other = S.BY_ID[id]
		if other.tier == def.tier + 1 and other.enabled then
			return id
		end
	end
	return nil
end

-- Uncollected Stardust after `dt` seconds at `rate`, capped at `cap`.
-- Never lowers an amount that is already above the cap.
function StarMath.accrue(uncollected: number, rate: number, dt: number, cap: number): number
	if uncollected >= cap then
		return uncollected
	end
	return math.min(cap, uncollected + math.max(rate, 0) * math.max(dt, 0))
end

-- The planets equipped on a star as attribute strings, slot by slot: types
-- ("Basalt,,Aurora,...") and levels ("3,,1,..."); empty slots are blank.
-- Clients read them to draw the planets.
function StarMath.encodePlanets(equipped: { [number]: Types.PlanetRecord }): string
	local parts: { string } = {}
	for slot = 1, #S.SLOTS do
		local planet = equipped[slot]
		parts[slot] = if planet then planet.typeId else ""
	end
	return table.concat(parts, ",")
end

function StarMath.encodePlanetLevels(equipped: { [number]: Types.PlanetRecord }): string
	local parts: { string } = {}
	for slot = 1, #S.SLOTS do
		local planet = equipped[slot]
		parts[slot] = if planet then tostring(planet.level) else ""
	end
	return table.concat(parts, ",")
end

function StarMath.decodePlanetLevels(text: string): { [number]: number }
	local levels: { [number]: number } = {}
	local slot = 0
	for part in string.gmatch(text .. ",", "([^,]*),") do
		slot += 1
		local n = tonumber(part)
		if n then
			levels[slot] = n
		end
	end
	return levels
end

function StarMath.decodePlanets(text: string): { [number]: string }
	local planets: { [number]: string } = {}
	local slot = 0
	for part in string.gmatch(text .. ",", "([^,]*),") do
		slot += 1
		if part ~= "" then
			planets[slot] = part
		end
	end
	return planets
end

return StarMath
