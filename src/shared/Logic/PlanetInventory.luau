--!strict
-- Owned planets (profile.planets: id -> PlanetRecord) and where they sit.
-- Pure rules shared by the server (DataSystem, StarSystem), the client's
-- panels and the tests.
--
-- A planet is in inventory (no star) or in exactly one orbital slot of one
-- of its owner's stars. A slot holds at most one planet, and only slots
-- 1..the star type's orbits (Config.Stars) are open. Equipping a planet
-- that's already in orbit moves it in one step: there's never a moment it
-- sits in two slots or none. Moving keeps its level.

local Config = require(script.Parent.Parent.Config)
local StarMath = require(script.Parent.StarMath)
local Types = require(script.Parent.Parent.Types)

type PlanetRecord = Types.PlanetRecord
type StarRecord = Types.StarRecord

export type Problem = "UnknownPlanet" | "UnknownStar" | "SlotLocked" | "SlotTaken"
export type SellProblem = "UnknownPlanet" | "InOrbit" | "Locked"

local PlanetInventory = {}

PlanetInventory.MESSAGES = {
	UnknownPlanet = "You don't own that planet.",
	UnknownStar = "That isn't one of your stars.",
	SlotLocked = "That orbit isn't open yet: evolve the star to open more.",
	SlotTaken = "Another planet already orbits there.",
} :: { [Problem]: string }

-- The planets on a star: orbit slot -> record.
function PlanetInventory.equippedOn(
	planets: { [string]: PlanetRecord },
	starId: string
): { [number]: PlanetRecord }
	local result: { [number]: PlanetRecord } = {}
	for _, planet in planets do
		if planet.star == starId and planet.slot then
			result[planet.slot] = planet
		end
	end
	return result
end

-- The ids of the planets on a star: orbit slot -> planet id.
function PlanetInventory.idsOn(
	planets: { [string]: PlanetRecord },
	starId: string
): { [number]: string }
	local result: { [number]: string } = {}
	for id, planet in planets do
		if planet.star == starId and planet.slot then
			result[planet.slot] = id
		end
	end
	return result
end

-- The id of the planet in a star's slot, if any.
function PlanetInventory.occupant(
	planets: { [string]: PlanetRecord },
	starId: string,
	slot: number
): string?
	for id, planet in planets do
		if planet.star == starId and planet.slot == slot then
			return id
		end
	end
	return nil
end

-- The first open, empty slot of a star, or nil.
function PlanetInventory.freeSlot(
	planets: { [string]: PlanetRecord },
	starId: string,
	star: StarRecord
): number?
	local taken = PlanetInventory.equippedOn(planets, starId)
	for slot = 1, StarMath.slots(star.typeId) do
		if taken[slot] == nil then
			return slot
		end
	end
	return nil
end

-- Whether `planetId` may go into `starId`'s `slot` (moving it there if it
-- orbits somewhere else).
function PlanetInventory.check(
	planets: { [string]: PlanetRecord },
	stars: { [string]: StarRecord },
	planetId: string,
	starId: string,
	slot: number
): (boolean, Problem?)
	local planet = planets[planetId]
	if planet == nil or Config.Planets.BY_ID[planet.typeId] == nil then
		return false, "UnknownPlanet"
	end
	local star = stars[starId]
	if star == nil then
		return false, "UnknownStar"
	end
	if slot ~= math.floor(slot) or slot < 1 or slot > StarMath.slots(star.typeId) then
		return false, "SlotLocked"
	end
	local occupant = PlanetInventory.occupant(planets, starId, slot)
	if occupant and occupant ~= planetId then
		return false, "SlotTaken"
	end
	return true, nil
end

-- Puts the planet in that slot (validated as by check). Returns the same.
function PlanetInventory.equip(
	planets: { [string]: PlanetRecord },
	stars: { [string]: StarRecord },
	planetId: string,
	starId: string,
	slot: number
): (boolean, Problem?)
	local ok, problem = PlanetInventory.check(planets, stars, planetId, starId, slot)
	if not ok then
		return false, problem :: Problem?
	end
	local planet = planets[planetId]
	planet.star = starId
	planet.slot = slot
	return true, nil
end

-- Takes a planet out of orbit into inventory. False if it isn't owned.
function PlanetInventory.unequip(planets: { [string]: PlanetRecord }, planetId: string): boolean
	local planet = planets[planetId]
	if planet == nil then
		return false
	end
	planet.star = nil
	planet.slot = nil
	return true
end

-- Sends every planet on a star back to inventory (the star is going away).
function PlanetInventory.releaseStar(planets: { [string]: PlanetRecord }, starId: string): number
	local moved = 0
	for _, planet in planets do
		if planet.star == starId then
			planet.star = nil
			planet.slot = nil
			moved += 1
		end
	end
	return moved
end

-- What selling a planet pays (Config.Planets): SELL_FRACTION[rarity] of
-- what its egg roll actually cost plus SELL_LEVEL_REFUND of the Stardust
-- actually spent levelling it, whole; a planet from before economy v2 pays
-- its fixed legacy value instead. Tier never adds anything.
function PlanetInventory.sellValue(planet: PlanetRecord): number
	local def = Config.Planets.BY_ID[planet.typeId]
	if def == nil then
		return 0
	end
	if planet.legacy then
		return math.floor(planet.legacy)
	end
	local fraction = Config.Planets.SELL_FRACTION[def.rarity] or 0
	return math.floor(
		(planet.paid or 0) * fraction + (planet.spent or 0) * Config.Planets.SELL_LEVEL_REFUND
	)
end

-- Whether a planet may be sold: owned, a known type, in the inventory (not
-- in orbit) and not locked.
function PlanetInventory.canSell(
	planets: { [string]: PlanetRecord },
	planetId: string
): (boolean, SellProblem?)
	local planet = planets[planetId]
	if planet == nil or Config.Planets.BY_ID[planet.typeId] == nil then
		return false, "UnknownPlanet"
	end
	if planet.star then
		return false, "InOrbit"
	end
	if planet.locked then
		return false, "Locked"
	end
	return true, nil
end

-- How many planets the player owns.
function PlanetInventory.count(planets: { [string]: PlanetRecord }): number
	local n = 0
	for _ in planets do
		n += 1
	end
	return n
end

local function idNumber(id: string): number
	return tonumber(string.match(id, "%d+")) or 0
end

-- The most productive arrangement. A planet earns a share (its factor,
-- StarMath.planetFactor) of its host star's own rate, so the best layout
-- puts the highest factors on the strongest stars: stars are taken
-- strongest first and each gets the next best planets for its orbits.
-- Planets already on the star they're chosen for keep their slots; the
-- rest fill its free slots in order. Returns planet id -> { star, slot } for
-- every planet that should be in orbit; any planet missing from it should
-- be in the inventory.
function PlanetInventory.best(
	planets: { [string]: PlanetRecord },
	stars: { [string]: StarRecord }
): { [string]: { star: string, slot: number } }
	local starIds: { string } = {}
	for id in stars do
		table.insert(starIds, id)
	end
	table.sort(starIds, function(a, b)
		local sa, sb = stars[a], stars[b]
		local ra = StarMath.starIncome(sa.typeId, sa.level)
		local rb = StarMath.starIncome(sb.typeId, sb.level)
		if ra ~= rb then
			return ra > rb
		end
		return idNumber(a) < idNumber(b)
	end)
	local candidates: { string } = {}
	for id, planet in planets do
		if Config.Planets.BY_ID[planet.typeId] then
			table.insert(candidates, id)
		end
	end
	table.sort(candidates, function(a, b)
		local pa, pb = planets[a], planets[b]
		local fa = StarMath.planetFactor(pa.typeId, pa.level, pa.tier)
		local fb = StarMath.planetFactor(pb.typeId, pb.level, pb.tier)
		if fa ~= fb then
			return fa > fb
		end
		-- Equal earners: keep the ones already in orbit, so nothing moves.
		local ea, eb =
			pa.star ~= nil and stars[pa.star] ~= nil, pb.star ~= nil and stars[pb.star] ~= nil
		if ea ~= eb then
			return ea
		end
		return idNumber(a) < idNumber(b)
	end)
	local result: { [string]: { star: string, slot: number } } = {}
	local next = 1
	for _, starId in starIds do
		local open = StarMath.slots(stars[starId].typeId)
		local group: { string } = {}
		while #group < open and next <= #candidates do
			table.insert(group, candidates[next])
			next += 1
		end
		local taken: { [number]: boolean } = {}
		local moving: { string } = {}
		for _, id in group do
			local planet = planets[id]
			if
				planet.star == starId
				and planet.slot
				and planet.slot <= open
				and not taken[planet.slot]
			then
				result[id] = { star = starId, slot = planet.slot }
				taken[planet.slot] = true
			else
				table.insert(moving, id)
			end
		end
		local slot = 1
		for _, id in moving do
			while taken[slot] do
				slot += 1
			end
			result[id] = { star = starId, slot = slot }
			taken[slot] = true
		end
		if next > #candidates then
			break
		end
	end
	return result
end

-- A new planet id ("p<n>") and the next counter.
function PlanetInventory.newId(counter: number): (string, number)
	return `p{counter}`, counter + 1
end

return PlanetInventory
