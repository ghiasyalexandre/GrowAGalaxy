--!strict
-- Star tycoon numbers derived from Config.Stars and Config.Planets:
-- production, prices, tier rules and income accrual. Pure, so the Lune tests
-- and the client's panels use exactly what the server uses.
--
-- Planets are saved per star as { ["1"] = planetTypeId, ... }, keyed by orbit
-- slot number as a string (plain data for the save).

local Config = require(script.Parent.Parent.Config)
local StarsConfig = require(script.Parent.Parent.Config.Stars)
local Types = require(script.Parent.Parent.Types)

local S = Config.Stars
local P = Config.Planets

local StarMath = {}

function StarMath.levelDef(level: number): StarsConfig.LevelDef
	return S.LEVELS[math.clamp(level, 1, #S.LEVELS)]
end

function StarMath.maxLevel(): number
	return #S.LEVELS
end

-- Open orbit slots at a level.
function StarMath.slots(level: number): number
	return math.min(StarMath.levelDef(level).slots, #S.SLOTS)
end

-- Visual radius of a star.
function StarMath.radius(typeId: string, level: number): number
	local def = S.BY_ID[typeId]
	return (if def then def.radius else 12) * StarMath.levelDef(level).radiusScale
end

-- Stardust per second from the star itself (planets not included).
function StarMath.starIncome(typeId: string, level: number): number
	local def = S.BY_ID[typeId]
	if def == nil then
		return 0
	end
	return def.income * StarMath.levelDef(level).incomeMultiplier
end

function StarMath.planetIncome(planetId: string): number
	local def = P.BY_ID[planetId]
	return if def then def.income else 0
end

-- Stardust per second from a star and its planets.
function StarMath.income(star: Types.StarRecord): number
	local total = StarMath.starIncome(star.typeId, star.level)
	for _, planetId in star.planets do
		total += StarMath.planetIncome(planetId)
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

-- Price of a new star when the player already owns `owned` stars.
function StarMath.placeCost(typeId: string, owned: number): number?
	local def = S.BY_ID[typeId]
	if def == nil then
		return nil
	end
	return math.floor(def.cost * S.PRICE_GROWTH ^ math.max(owned, 0) + 0.5)
end

-- Cost to level a star up from `level`, or nil at the top.
function StarMath.upgradeCost(typeId: string, level: number): number?
	local def = S.BY_ID[typeId]
	if def == nil or level < 1 or level >= #S.LEVELS then
		return nil
	end
	local share = S.LEVELS[level + 1].upgradeShare
	return if share then math.floor(def.cost * share + 0.5) else nil
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
	for slot = 1, StarMath.slots(star.level) do
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
