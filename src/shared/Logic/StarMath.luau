--!strict
-- Star tycoon numbers derived from Config.Stars and Config.Planets:
-- production, prices, tier rules and income accrual. Pure, so the Lune tests
-- and the client's panels use exactly what the server uses.
--
-- Planets are saved per star as { ["1"] = planetTypeId, ... }, keyed by orbit
-- slot number as a string (plain data for the save).

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

-- Planet orbits of a star of this type (4 at tier 1, one more per tier).
function StarMath.slots(typeId: string): number
	return math.min(S.ORBITS_BASE + tierOf(typeId) - 1, #S.SLOTS)
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

-- The level of the planet in a star's slot ("1".."N").
function StarMath.planetLevel(star: Types.StarRecord, slot: string): number
	local levels = star.planetLevels
	return if levels and levels[slot] then levels[slot] else 1
end

-- Price to raise a planet from `level` to the next, or nil at MAX_LEVEL.
function StarMath.planetLevelCost(planetId: string, level: number): number?
	local def = P.BY_ID[planetId]
	if def == nil or level < 1 or level >= P.MAX_LEVEL then
		return nil
	end
	return math.floor(def.cost * P.LEVEL_COST_SHARE * P.LEVEL_COST_GROWTH ^ (level - 1) + 0.5)
end

-- A planet's radius at a level: a little bigger every level.
function StarMath.planetRadius(planetId: string, level: number): number
	local def = P.BY_ID[planetId]
	local lv = math.clamp(level, 1, P.MAX_LEVEL)
	return (if def then def.radius else 4) * (1 + P.LEVEL_SIZE_STEP * (lv - 1))
end

-- Stardust per second from a star and its planets.
function StarMath.income(star: Types.StarRecord): number
	local total = StarMath.starIncome(star.typeId, star.level)
	for slot, planetId in star.planets do
		total += StarMath.planetIncome(planetId, StarMath.planetLevel(star, slot))
	end
	return total
end

function StarMath.totalIncome(stars: { [string]: Types.StarRecord }): number
	local total = 0
	for _, star in stars do
		total += StarMath.income(star)
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

-- Can a star of this type hold a planet of that type?
function StarMath.planetAllowed(starTypeId: string, planetId: string): boolean
	local star = S.BY_ID[starTypeId]
	local planet = P.BY_ID[planetId]
	return star ~= nil and planet ~= nil and planet.enabled and planet.tier <= star.tier
end

-- The first open, empty slot of a star, as its save key ("1".."4"), or nil.
function StarMath.freeSlot(star: Types.StarRecord): string?
	for slot = 1, StarMath.slots(star.typeId) do
		local key = tostring(slot)
		if star.planets[key] == nil then
			return key
		end
	end
	return nil
end

-- The next planet tier after `planetId`, and the upgrade price (the next
-- tier's price minus UPGRADE_CREDIT of the current one's), or nil at the top.
function StarMath.planetUpgrade(planetId: string): (string?, number?)
	local def = P.BY_ID[planetId]
	if def == nil then
		return nil, nil
	end
	for _, id in P.ORDER do
		local other = P.BY_ID[id]
		if other.tier == def.tier + 1 and other.enabled then
			return id, math.max(1, math.floor(other.cost - def.cost * P.UPGRADE_CREDIT + 0.5))
		end
	end
	return nil, nil
end

-- Uncollected Stardust after `dt` seconds at `rate`, capped at `cap`.
-- Never lowers an amount that is already above the cap.
function StarMath.accrue(uncollected: number, rate: number, dt: number, cap: number): number
	if uncollected >= cap then
		return uncollected
	end
	return math.min(cap, uncollected + math.max(rate, 0) * math.max(dt, 0))
end

-- Planets as an attribute string, slot by slot: "Barren,,Ocean,". Clients
-- read it to draw the planets.
function StarMath.encodePlanets(planets: { [string]: string }): string
	local parts: { string } = {}
	for slot = 1, #S.SLOTS do
		parts[slot] = planets[tostring(slot)] or ""
	end
	return table.concat(parts, ",")
end

-- Planet levels as an attribute string, slot by slot: "2,,1,". Empty
-- slots are blank.
function StarMath.encodePlanetLevels(star: Types.StarRecord): string
	local parts: { string } = {}
	for slot = 1, #S.SLOTS do
		local key = tostring(slot)
		parts[slot] = if star.planets[key] then tostring(StarMath.planetLevel(star, key)) else ""
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
