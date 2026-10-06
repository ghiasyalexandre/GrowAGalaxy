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

-- A new planet id ("p<n>") and the next counter.
function PlanetInventory.newId(counter: number): (string, number)
	return `p{counter}`, counter + 1
end

return PlanetInventory
