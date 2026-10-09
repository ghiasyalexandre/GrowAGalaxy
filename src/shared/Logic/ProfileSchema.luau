--!strict
-- Default save data and load-time cleanup for player profiles.
--
-- normalize() repairs types and fills in missing fields, but keeps unknown ids
-- (a ship or material removed from config by mistake must not wipe someone's
-- save). Gameplay code always checks config before using a saved id.
-- Pure module: no Roblox services, so the Lune unit tests run it directly.

local Config = require(script.Parent.Parent.Config)
local EconomyMath = require(script.Parent.EconomyMath)
local PlacementRules = require(script.Parent.PlacementRules)
local Progression = require(script.Parent.Progression)
local StarMath = require(script.Parent.StarMath)
local Types = require(script.Parent.Parent.Types)

type Profile = Types.Profile
type Vec3 = Types.Vec3

local MAX_RECEIPTS = Config.Products.MAX_RECEIPTS

local ProfileSchema = {}

-- 1: first release. 2: "credits" renamed to "stardust" (the one currency).
-- 3: galaxy saves stars (level-based upgrades) instead of systems and bodies.
-- 4: stars save the planets bought for them (planets became purchases).
-- 5: each star type has its own max level (4, 6, 8 ...): levels above it are
--    lowered to it (normalize does this for every load).
-- 6: the 11-ship ladder replaced the first five ships: their ids are renamed
--    (Config.Ships.RENAMED) in owned ships, the active ship and loadouts.
-- 7: hangar upgrades (Config.Hangar), saved as built ids; older profiles start
--    with none (normalize fills it in).
-- 8: optional purchases: boost time left per source and the passes Roblox
--    last confirmed; receipts keep up to Config.Products.MAX_RECEIPTS ids.
--    Older profiles start with no boosts (normalize fills them in).
-- 9: daily prizes: the next calendar day (1..14) and the day last claimed.
--    Older profiles start at day 1, never claimed.
-- 10: ship paint jobs (loadout paint and finish), the hangar's showcase list
--    and the region boundary setting; equipment levels (owned items start at
--    level 1). Older profiles keep factory paint, an
--    empty showcase and the boundary shown (normalize fills them in).
-- 11: ship colours replaced paint jobs: loadouts save laserColor and
--    boostColor (paint and finish are dropped); trails bought and the one
--    equipped; the controls hint setting. Older profiles start with none.
-- 12: planets level up in their slots: stars save planetLevels (slot ->
--    2..MAX_LEVEL). Older planets are level 1.
-- 13: redeemed codes (Config.Codes), so each works once per player.
--    Older profiles have redeemed none.
-- 14: offline earnings: the last time the player was online (unix
--    seconds). Older profiles start at 0, so the first visit after this
--    update pays nothing extra.
-- 15: planets became individually owned: every planet that sat in a star's
--    orbit became a PlanetRecord (type mapped by Config.Planets.LEGACY,
--    same level) in the same slot, or in inventory when that slot is past
--    its star's new capacity (at most 9). Stars no longer save planets.
--    Also new: eggs, hangar hatches and the daily wheel (start empty).
-- 16: settings gain floating, autoIncubate, keepNewTypes and autoSell
--    (defaults: float, auto-incubate on, keep new types, auto-sell off);
--    planets may be locked; `discovered` (the Planet Index) starts as every
--    type the player owns. No existing data changes.
-- 17: hangarColor (the hangar highlight colour pick), nil = the region's
--    colour as before. No existing data changes.
-- 18: hangarOff (built hangar upgrades the owner switched off, e.g. the
--    Neon Runway), empty: everything shows as before.
-- 19: planet tiers and each player's own Egg Lab: planets, eggs and
--    hatches save a tier (1..7); older ones are tier 1 (x1, as before).
--    eggLab starts at level 1 with no egg on the pedestal. eggsBought now
--    counts eggs kept (the same thing for older saves). No income changes.
-- 20: the Neon Runway hangar upgrade was removed: anyone who built it gets
--    its price back (RUNWAY_REFUND Stardust) and it leaves hangar and
--    hangarOff.
-- 21: economy v2. Stars get a BuildIndex (`build`, 0..N-1 in id order) and
--    galaxy.nextBuild; star levels keep their share of the way to max on
--    the new max levels (EconomyMath.remapLevel). Planets save what they
--    cost (`paid`, `spent`); older planets and eggs keep their old fixed
--    sale value instead (Config.Planets.LEGACY_SELL_VALUE, once). New:
--    `economy` (H from the new production, R, raid day), constellationRank
--    0, and tutorialEgg (true for existing players: no tutorial egg).
--    Balances and uncollected Stardust are kept as they are.
-- 22: equipment is per ship: each loadout saves `levels` (item -> level).
--    Older saves give every owned ship the items the player owned, at their
--    levels, so nothing gets weaker. ownedEquipment and equipmentLevels are
--    kept but no longer used.
ProfileSchema.VERSION = 22

-- Auto-sell choices: only rarities players may auto-sell, set to true.
local function autoSellSettings(raw: any): { [string]: boolean }
	local result: { [string]: boolean } = {}
	if type(raw) == "table" then
		for _, rarity in Config.Planets.AUTO_SELL_RARITIES do
			if raw[rarity] == true then
				result[rarity] = true
			end
		end
	end
	return result
end

local function defaultSettings(): Types.Settings
	return {
		musicVolume = 0.5,
		sfxVolume = 0.8,
		cameraSensitivity = 1,
		stabilization = true,
		reducedEffects = false,
		pvp = Config.Combat.PVP_DEFAULT,
		showBounds = true,
		showControls = true,
		floating = true,
		autoIncubate = true,
		keepNewTypes = true,
		autoSell = {},
	}
end

function ProfileSchema.default(): Profile
	local starter = Config.Ships.STARTER_SHIP
	return {
		schemaVersion = ProfileSchema.VERSION,
		stardust = Config.Economy.STARTING_STARDUST,
		uncollected = 0,
		materials = {},
		cargo = {},
		ownedShips = { [starter] = true },
		activeShip = starter,
		loadouts = { [starter] = { equipment = {}, levels = {} } },
		ownedEquipment = {},
		equipmentLevels = {},
		ownedCosmetics = {},
		inventory = {},
		galaxy = { expansion = 1, nextId = 1, nextBuild = 0, stars = {} },
		unlockedZones = { [Config.Zones.STARTER_ZONE] = true },
		research = {},
		achievements = {},
		tutorial = { step = 1, done = false },
		stats = {},
		settings = defaultSettings(),
		hangar = {},
		hangarOff = {},
		showcase = {},
		ownedTrails = {},
		redeemedCodes = {},
		lastOnline = 0,
		planets = {},
		nextPlanetId = 1,
		eggs = {},
		nextEggId = 1,
		eggsBought = 0,
		eggLab = { level = 1, current = nil, rolls = 0 },
		hatches = {},
		wheel = { nextSpin = 0, lastPrize = 0 },
		discovered = {},
		trail = nil,
		economy = { high = 0, recent = 0, reward = 1, rewardDay = 0, raidDay = 0 },
		constellationRank = 0,
		tutorialEgg = false,
		boosts = { mining = 0, star = 0 },
		verifiedPasses = {},
		daily = { day = 1, lastClaim = 0 },
		receipts = {},
	}
end

local function isFinite(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

-- Non-negative whole number, or nil when the value is unusable.
local function count(value: any): number?
	if isFinite(value) and value >= 0 then
		return math.floor(value)
	end
	return nil
end

-- Non-negative number that may be fractional (e.g. uncollected income).
local function amount(value: any): number?
	if isFinite(value) and value >= 0 then
		return value
	end
	return nil
end

-- A saved tier, 1 (x1) when missing or out of range.
local function tierOf(value: any): number
	local tier = if type(value) == "number" and value == math.floor(value) then value else 1
	return math.clamp(tier, 1, #Config.Planets.TIERS)
end

-- The Neon Runway's price when it was removed (version 20).
local RUNWAY_REFUND = 5000

-- Version 19 and older: refunds and removes the Neon Runway, once.
local function migrateRunwayV19(data: { [string]: any })
	local hangar = data.hangar
	if type(hangar) == "table" and hangar.NeonRunway then
		hangar.NeonRunway = nil
		data.stardust = (count(data.stardust) or 0) + RUNWAY_REFUND
	end
	if type(data.hangarOff) == "table" then
		data.hangarOff.NeonRunway = nil
	end
end

-- Old max level by tier (before version 21): 4, 6, 8 ...
local function oldMaxLevel(tier: number): number
	return 4 + 2 * (tier - 1)
end

local function idNumber(id: string): number
	return tonumber(string.match(id, "%d+")) or 0
end

-- Version 20 and older: BuildIndex in stable id order, levels mapped to the
-- new max levels, legacy sale values on planets (eggs and hatches without
-- `paid` get theirs when they hatch), and no tutorial egg.
local function migrateEconomyV20(data: { [string]: any })
	local galaxyData = data.galaxy
	local stars = if type(galaxyData) == "table" and type(galaxyData.stars) == "table"
		then galaxyData.stars
		else nil
	if stars then
		local ids: { string } = {}
		for id, star in stars do
			if type(id) == "string" and type(star) == "table" then
				table.insert(ids, id)
			end
		end
		table.sort(ids, function(a, b)
			local na, nb = idNumber(a), idNumber(b)
			return if na ~= nb then na < nb else a < b
		end)
		for index, id in ids do
			local star = stars[id]
			star.build = index - 1
			local def = if type(star.typeId) == "string"
				then Config.Stars.BY_ID[star.typeId]
				else nil
			local level = count(star.level)
			if def and level then
				star.level =
					EconomyMath.remapLevel(level, oldMaxLevel(def.tier), StarMath.maxLevel(def.id))
			end
		end
		galaxyData.nextBuild = #ids
	end
	if type(data.planets) == "table" then
		for _, planet in data.planets do
			if type(planet) == "table" and type(planet.typeId) == "string" then
				local def = Config.Planets.BY_ID[planet.typeId]
				planet.legacy = if def then Config.Planets.LEGACY_SELL_VALUE[def.rarity] else 0
				planet.paid = 0
				planet.spent = 0
			end
		end
	end
	data.tutorialEgg = true
end

local function clamp(value: any, low: number, high: number, fallback: number): number
	if isFinite(value) then
		return math.clamp(value, low, high)
	end
	return fallback
end

local function counts(raw: any): { [string]: number }
	local out: { [string]: number } = {}
	if type(raw) == "table" then
		for key, value in raw do
			local n = count(value)
			if type(key) == "string" and n and n > 0 then
				out[key] = n
			end
		end
	end
	return out
end

local function numbers(raw: any): { [string]: number }
	local out: { [string]: number } = {}
	if type(raw) == "table" then
		for key, value in raw do
			local n = amount(value)
			if type(key) == "string" and n then
				out[key] = n
			end
		end
	end
	return out
end

local function flags(raw: any): { [string]: boolean }
	local out: { [string]: boolean } = {}
	if type(raw) == "table" then
		for key, value in raw do
			if type(key) == "string" and value == true then
				out[key] = true
			end
		end
	end
	return out
end

local function vec3(raw: any): Vec3?
	if type(raw) == "table" and isFinite(raw.x) and isFinite(raw.y) and isFinite(raw.z) then
		return { x = raw.x, y = raw.y, z = raw.z }
	end
	return nil
end

-- Highest numeric suffix among ids like "s12". Scans the raw saved table, so
-- nextId never reuses an id, even one that was dropped as corrupt.
local function highestId(ids: any): number
	local highest = 0
	if type(ids) ~= "table" then
		return 0
	end
	for id in ids do
		local digits = if type(id) == "string" then string.match(id, "^%a+(%d+)$") else nil
		local n = if digits then tonumber(digits) else nil
		if n and n > highest then
			highest = n
		end
	end
	return highest
end

local function galaxy(raw: any): Types.GalaxyRecord
	local source = if type(raw) == "table" then raw else {}
	local stars: { [string]: Types.StarRecord } = {}
	if type(source.stars) == "table" then
		for id, star in source.stars do
			if type(id) ~= "string" or type(star) ~= "table" then
				continue
			end
			local pos = vec3(star.pos)
			local level = count(star.level)
			local appearanceOk = star.appearance == nil or type(star.appearance) == "string"
			-- Unknown types are kept (a config mistake must not wipe a save);
			-- gameplay code checks config before using them.
			if pos and level and level >= 1 and type(star.typeId) == "string" and appearanceOk then
				-- A level above the type's max (e.g. from before version 5) is
				-- lowered to the max, so the star can evolve.
				if Config.Stars.BY_ID[star.typeId] then
					level = math.min(level, StarMath.maxLevel(star.typeId))
				end
				stars[id] = {
					typeId = star.typeId,
					level = level,
					pos = pos,
					appearance = star.appearance,
					build = count(star.build) or -1,
				}
			end
		end
	end
	-- BuildIndex: never reused. A star without one (damaged data) gets the
	-- next free one, in id order.
	local nextBuild = count(source.nextBuild) or 0
	local missing: { string } = {}
	for id, star in stars do
		if star.build < 0 then
			table.insert(missing, id)
		else
			nextBuild = math.max(nextBuild, star.build + 1)
		end
	end
	table.sort(missing)
	for _, id in missing do
		stars[id].build = nextBuild
		nextBuild += 1
	end
	local expansion = math.clamp(count(source.expansion) or 1, 1, #Config.Galaxy.EXPANSIONS)
	-- Stars outside the build box (the galaxy got smaller) move to the
	-- nearest free spot inside it, clear of the stars already inside; with
	-- no room left, they are pulled just inside the walls.
	local placed: { Types.Vec3 } = {}
	local outside: { string } = {}
	for id, star in stars do
		local inside = PlacementRules.clamp(star.pos, expansion)
		if inside.x ~= star.pos.x or inside.y ~= star.pos.y or inside.z ~= star.pos.z then
			table.insert(outside, id)
			continue
		end
		table.insert(placed, star.pos)
	end
	table.sort(outside)
	for _, id in outside do
		local star = stars[id]
		star.pos = PlacementRules.nearestValid(star.pos, expansion, placed)
			or PlacementRules.clamp(star.pos, expansion)
		table.insert(placed, star.pos)
	end
	return {
		expansion = expansion,
		nextId = math.max(count(source.nextId) or 1, highestId(source.stars) + 1),
		nextBuild = nextBuild,
		stars = stars,
	}
end

-- Version 2 saved solar systems and bodies (never used in a release). Each
-- system's star becomes a star at its position; planets and moons are now
-- part of a star's level, so they are dropped.
local function migrateGalaxyV2(raw: any)
	if type(raw) ~= "table" or raw.stars ~= nil then
		return
	end
	local stars = {}
	local systems = if type(raw.systems) == "table" then raw.systems else {}
	local bodies = if type(raw.bodies) == "table" then raw.bodies else {}
	for id, system in systems do
		local body = if type(system) == "table" then bodies[system.starId] else nil
		if type(body) == "table" then
			stars[id] = {
				typeId = Config.Stars.DEFAULT_TYPE,
				level = body.level,
				pos = system.pos,
			}
		end
	end
	raw.stars = stars
	raw.systems = nil
	raw.bodies = nil
end

-- Version 14 and older kept planets on the stars themselves: { slot ->
-- planet type } and { slot -> level }. Each becomes an owned planet record
-- of the mapped catalog type with the same level, in the same slot if the
-- star's new capacity still has it, otherwise in inventory. Nothing is lost.
-- It only acts on stars that still have those fields, so it is safe to run
-- on any profile; `fromOld` (a version 14 or older save) also carries the
-- old planet stats over, once.
local function migratePlanetsV14(data: { [string]: any }, fromOld: boolean)
	local raw = if type(data.galaxy) == "table" then data.galaxy.stars else nil
	local planets = if type(data.planets) == "table" then data.planets else {}
	local nextId = math.max(count(data.nextPlanetId) or 1, highestId(planets) + 1)
	if type(raw) == "table" then
		-- Stars in a fixed order, so ids come out the same every time.
		local starIds: { string } = {}
		for id in raw do
			if type(id) == "string" then
				table.insert(starIds, id)
			end
		end
		table.sort(starIds)
		for _, starId in starIds do
			local star = raw[starId]
			if type(star) ~= "table" or type(star.planets) ~= "table" then
				continue
			end
			local capacity = if type(star.typeId) == "string"
					and Config.Stars.BY_ID[star.typeId]
				then StarMath.slots(star.typeId)
				else 0
			local levels = if type(star.planetLevels) == "table" then star.planetLevels else {}
			for slot = 1, 64 do
				local oldType = star.planets[tostring(slot)]
				if type(oldType) ~= "string" then
					continue
				end
				local typeId = Config.Planets.LEGACY[oldType]
					or (
						if Config.Planets.BY_ID[oldType]
							then oldType
							else Config.Planets.LEGACY_FALLBACK
					)
				local level =
					math.clamp(count(levels[tostring(slot)]) or 1, 1, Config.Planets.MAX_LEVEL)
				local inOrbit = slot <= capacity
				planets[`p{nextId}`] = {
					typeId = typeId,
					level = level,
					star = if inOrbit then starId else nil,
					slot = if inOrbit then slot else nil,
				}
				nextId += 1
			end
			star.planets = nil
			star.planetLevels = nil
		end
	end
	data.planets = planets
	data.nextPlanetId = nextId
	-- Achievements and the tutorial now count equipped and hatched planets
	-- and planet level-ups; planets bought or upgraded before count too.
	local stats = data.stats
	if fromOld and type(stats) == "table" then
		local bought = count(stats.planetsBought) or 0
		local upgraded = count(stats.planetUpgrades) or 0
		stats.planetsEquipped = math.max(count(stats.planetsEquipped) or 0, bought)
		stats.planetsHatched = math.max(count(stats.planetsHatched) or 0, bought)
		stats.planetLevels = (count(stats.planetLevels) or 0) + upgraded
	end
end

-- Version 5 ship ids become their stage 14 replacements. A renamed ship
-- doesn't overwrite a loadout already saved under the new id.
local function migrateShipsV5(data: { [string]: any })
	local renamed = Config.Ships.RENAMED
	if type(data.ownedShips) == "table" then
		for old, new in renamed do
			if data.ownedShips[old] ~= nil then
				data.ownedShips[new] = data.ownedShips[new] or data.ownedShips[old]
				data.ownedShips[old] = nil
			end
		end
	end
	if type(data.activeShip) == "string" and renamed[data.activeShip] then
		data.activeShip = renamed[data.activeShip]
	end
	if type(data.loadouts) == "table" then
		for old, new in renamed do
			if data.loadouts[old] ~= nil then
				data.loadouts[new] = data.loadouts[new] or data.loadouts[old]
				data.loadouts[old] = nil
			end
		end
	end
end

-- Whether `color` is one of the offered colours (Config.Paint.SWATCHES).
function ProfileSchema.validColor(color: any): boolean
	return type(color) == "string" and table.find(Config.Paint.SWATCHES, color) ~= nil
end

-- Laser and boost colours of every owned ship, for the client.
function ProfileSchema.looks(profile: Profile): { [string]: Types.ShipLook }
	local looks: { [string]: Types.ShipLook } = {}
	for shipId, loadout in profile.loadouts do
		looks[shipId] = { laserColor = loadout.laserColor, boostColor = loadout.boostColor }
	end
	return looks
end

-- Each owned ship's equipment levels (ship -> item -> level), for the
-- owner's Shipyard.
function ProfileSchema.shipLevels(profile: Profile): { [string]: { [string]: number } }
	local result: { [string]: { [string]: number } } = {}
	for shipId, loadout in profile.loadouts do
		result[shipId] = table.clone(loadout.levels)
	end
	return result
end

-- The equipped trail's Stardust multiplier (1 with none).
function ProfileSchema.trailMultiplier(profile: Profile): number
	local def = if profile.trail then Config.Trails.BY_ID[profile.trail] else nil
	return if def then def.multiplier else 1
end

-- Repairs a loaded profile in place. Returns false (and changes nothing) when
-- the data must not be used, e.g. it was saved by a newer game version.
function ProfileSchema.normalize(data: { [string]: any }): (boolean, string?)
	local version = data.schemaVersion
	if version ~= nil and not isFinite(version) then
		return false, "corrupt schema version"
	end
	if version ~= nil and version > ProfileSchema.VERSION then
		return false, "saved by a newer version of the game"
	end
	-- Migrations from older schema versions, oldest first. A missing version
	-- is a brand-new profile (ProfileStore fills in the defaults' fields).
	if version ~= nil and version < 2 then
		-- Credits became Stardust: carry the balance over, never reset it.
		-- Version 1 had no stardust field, so a stardust value here could only
		-- be a template default (e.g. from Reconcile) and credits wins.
		if data.credits ~= nil then
			data.stardust = data.credits
		end
		data.credits = nil
	end
	if version ~= nil and version < 3 then
		migrateGalaxyV2(data.galaxy)
	end
	if version ~= nil and version < 6 then
		migrateShipsV5(data)
	end
	migratePlanetsV14(data, version ~= nil and version < 15)
	if version ~= nil and version < 20 then
		migrateRunwayV19(data)
	end
	if version ~= nil and version < 21 then
		migrateEconomyV20(data)
	end

	local defaults = ProfileSchema.default()
	local starter = Config.Ships.STARTER_SHIP

	data.schemaVersion = ProfileSchema.VERSION
	data.stardust = count(data.stardust) or defaults.stardust
	data.uncollected = amount(data.uncollected) or 0
	data.materials = counts(data.materials)
	data.cargo = counts(data.cargo)
	data.inventory = counts(data.inventory)

	local ownedShips = flags(data.ownedShips)
	ownedShips[starter] = true
	data.ownedShips = ownedShips
	if type(data.activeShip) ~= "string" or not ownedShips[data.activeShip] then
		data.activeShip = starter
	end

	data.ownedEquipment = flags(data.ownedEquipment)
	-- Every owned item has a level, 1 to MAX_LEVEL (1 for items bought before
	-- levels existed).
	local rawLevels = if type(data.equipmentLevels) == "table" then data.equipmentLevels else {}
	local levels: { [string]: number } = {}
	for itemId in data.ownedEquipment do
		levels[itemId] = math.clamp(count(rawLevels[itemId]) or 1, 1, Config.Equipment.MAX_LEVEL)
	end
	data.equipmentLevels = levels
	data.hangar = flags(data.hangar)
	-- Switched-off upgrades: only built ones that can be switched.
	local off: { [string]: boolean } = {}
	for id in flags(data.hangarOff) do
		local def = Config.Hangar.BY_ID[id]
		if def and def.toggle and data.hangar[id] then
			off[id] = true
		end
	end
	data.hangarOff = off
	data.verifiedPasses = flags(data.verifiedPasses)
	local daily = if type(data.daily) == "table" then data.daily else {}
	data.daily = {
		day = math.clamp(count(daily.day) or 1, 1, #Config.Daily.PRIZES),
		lastClaim = count(daily.lastClaim) or 0,
	}
	local boosts = if type(data.boosts) == "table" then data.boosts else {}
	data.boosts = { mining = amount(boosts.mining) or 0, star = amount(boosts.star) or 0 }
	data.ownedCosmetics = flags(data.ownedCosmetics)

	local loadouts: { [string]: Types.Loadout } = {}
	local rawLoadouts = if type(data.loadouts) == "table" then data.loadouts else {}
	-- Before version 22 equipment was the player's, fitted to every ship.
	local perShip = version == nil or version >= 22
	for shipId in ownedShips do
		local raw = rawLoadouts[shipId]
		local equipment: { [string]: string } = {}
		local itemLevels: { [string]: number } = {}
		local cosmetic: string? = nil
		if type(raw) == "table" and perShip and type(raw.levels) == "table" then
			for itemId, level in raw.levels do
				local item = if type(itemId) == "string"
					then Config.Equipment.BY_ID[itemId]
					else nil
				local whole = count(level)
				if item and whole then
					itemLevels[itemId] = math.clamp(whole, 1, Config.Equipment.MAX_LEVEL)
				end
			end
		elseif not perShip then
			for itemId in data.ownedEquipment do
				if Config.Equipment.BY_ID[itemId] then
					itemLevels[itemId] = data.equipmentLevels[itemId] or 1
				end
			end
		end
		if type(raw) == "table" then
			if type(raw.equipment) == "table" then
				for slot, itemId in raw.equipment do
					if
						type(slot) == "string"
						and type(itemId) == "string"
						and itemLevels[itemId]
					then
						equipment[slot] = itemId
					end
				end
			end
			if type(raw.cosmetic) == "string" and data.ownedCosmetics[raw.cosmetic] then
				cosmetic = raw.cosmetic
			end
		end
		local laser = if type(raw) == "table" then raw.laserColor else nil
		local boost = if type(raw) == "table" then raw.boostColor else nil
		-- Every item bought for this ship is fitted in its slot.
		for itemId in itemLevels do
			local item = Config.Equipment.BY_ID[itemId]
			if item and equipment[item.slot] == nil then
				equipment[item.slot] = itemId
			end
		end
		loadouts[shipId] = {
			equipment = equipment,
			levels = itemLevels,
			cosmetic = cosmetic,
			laserColor = if ProfileSchema.validColor(laser) then laser else nil,
			boostColor = if ProfileSchema.validColor(boost) then boost else nil,
		}
	end
	data.loadouts = loadouts

	-- Showcase: owned ships only, each once, at most SHOWCASE_SLOTS.
	local showcase: { string } = {}
	if type(data.showcase) == "table" then
		for _, shipId in ipairs(data.showcase) do
			if
				type(shipId) == "string"
				and ownedShips[shipId]
				and not table.find(showcase, shipId)
				and #showcase < Config.Paint.SHOWCASE_SLOTS
			then
				table.insert(showcase, shipId)
			end
		end
	end
	data.showcase = showcase

	-- Trails: known ids only for the one equipped, which must be owned.
	data.ownedTrails = flags(data.ownedTrails)
	data.redeemedCodes = flags(data.redeemedCodes)
	data.lastOnline = count(data.lastOnline) or 0
	if
		type(data.trail) ~= "string"
		or not data.ownedTrails[data.trail]
		or Config.Trails.BY_ID[data.trail] == nil
	then
		data.trail = nil
	end

	data.galaxy = galaxy(data.galaxy)
	data.constellationRank = count(data.constellationRank) or 0
	data.tutorialEgg = data.tutorialEgg == true

	-- Planets: known shape only; an equipped planet must name one of the
	-- player's stars and an open, unshared slot, or it goes to inventory.
	local planets: { [string]: Types.PlanetRecord } = {}
	local rawPlanets = if type(data.planets) == "table" then data.planets else {}
	local ids: { string } = {}
	for id in rawPlanets do
		if type(id) == "string" then
			table.insert(ids, id)
		end
	end
	table.sort(ids)
	local used: { [string]: boolean } = {}
	for _, id in ids do
		local raw = rawPlanets[id]
		if type(raw) ~= "table" or type(raw.typeId) ~= "string" then
			continue
		end
		local record: Types.PlanetRecord = {
			typeId = raw.typeId,
			level = math.clamp(count(raw.level) or 1, 1, Config.Planets.MAX_LEVEL),
			tier = tierOf(raw.tier),
			custom = if type(raw.custom) == "table" then raw.custom else nil,
			locked = if raw.locked == true then true else nil,
			paid = amount(raw.paid),
			spent = amount(raw.spent),
			legacy = amount(raw.legacy),
		}
		local star = if type(raw.star) == "string" then data.galaxy.stars[raw.star] else nil
		local slot = count(raw.slot)
		if star and slot and slot >= 1 and slot <= StarMath.slots(star.typeId) then
			local key = `{raw.star}#{slot}`
			if not used[key] then
				used[key] = true
				record.star = raw.star
				record.slot = slot
			end
		end
		planets[id] = record
	end
	data.planets = planets
	data.nextPlanetId = math.max(count(data.nextPlanetId) or 1, highestId(rawPlanets) + 1)

	-- The Planet Index: known types ever discovered, plus every type owned.
	local discovered: { [string]: boolean } = {}
	if type(data.discovered) == "table" then
		for typeId, seen in data.discovered do
			if type(typeId) == "string" and seen == true then
				discovered[typeId] = true
			end
		end
	end
	for _, planet in planets do
		discovered[planet.typeId] = true
	end
	data.discovered = discovered

	-- Hangar highlight colour: only a colour on offer.
	local pick = data.hangarColor
	data.hangarColor = nil
	for _, choice in Config.Hangar.HIGHLIGHT_COLORS do
		if choice.id == pick then
			data.hangarColor = pick
		end
	end

	-- Eggs and hatches: their planets were chosen when bought; never rerolled.
	local eggs: { [string]: Types.EggRecord } = {}
	if type(data.eggs) == "table" then
		for id, egg in data.eggs do
			if type(id) == "string" and type(egg) == "table" and type(egg.outcome) == "string" then
				eggs[id] = {
					outcome = egg.outcome,
					tier = tierOf(egg.tier),
					guaranteed = egg.guaranteed == true,
					boughtAt = count(egg.boughtAt) or 0,
					paid = amount(egg.paid),
				}
			end
		end
	end
	data.eggs = eggs
	local hatches: { [string]: Types.HatchRecord } = {}
	if type(data.hatches) == "table" then
		for slot = 1, Config.Eggs.HATCH_SLOTS do
			local hatch = data.hatches[tostring(slot)]
			if
				type(hatch) == "table"
				and type(hatch.outcome) == "string"
				and type(hatch.eggId) == "string"
				and count(hatch.startedAt)
				and count(hatch.endsAt)
			then
				hatches[tostring(slot)] = {
					eggId = hatch.eggId,
					outcome = hatch.outcome,
					tier = tierOf(hatch.tier),
					startedAt = count(hatch.startedAt) :: number,
					endsAt = count(hatch.endsAt) :: number,
					paid = amount(hatch.paid),
				}
			end
		end
	end
	data.hatches = hatches
	-- The next egg id passes every egg waiting or hatching.
	local eggIds: { [string]: boolean } = {}
	for id in eggs do
		eggIds[id] = true
	end
	for _, hatch in hatches do
		eggIds[hatch.eggId] = true
	end
	data.nextEggId = math.max(count(data.nextEggId) or 1, highestId(eggIds) + 1)
	data.eggsBought = count(data.eggsBought) or 0
	-- The Egg Lab: a level on offer, and the pedestal egg if it's a known type.
	local lab = if type(data.eggLab) == "table" then data.eggLab else {}
	local current = lab.current
	data.eggLab = {
		level = math.clamp(count(lab.level) or 1, 1, #Config.Eggs.LAB_LEVELS),
		current = if type(current) == "table"
				and type(current.outcome) == "string"
				and Config.Planets.BY_ID[current.outcome]
			then {
				outcome = current.outcome,
				tier = tierOf(current.tier),
				paid = amount(current.paid) or 0,
			}
			else nil,
		rolls = count(lab.rolls) or 0,
	}
	-- Economy bookkeeping; H never below the production the save has now.
	local economy = if type(data.economy) == "table" then data.economy else {}
	data.economy = {
		high = amount(economy.high) or 0,
		recent = amount(economy.recent) or 0,
		reward = math.max(amount(economy.reward) or 1, 1),
		rewardDay = count(economy.rewardDay) or 0,
		raidDay = count(economy.raidDay) or 0,
	}
	data.economy.high = EconomyMath.high(data :: any)

	local wheel = if type(data.wheel) == "table" then data.wheel else {}
	data.wheel = {
		nextSpin = count(wheel.nextSpin) or 0,
		lastPrize = math.clamp(count(wheel.lastPrize) or 0, 0, #Config.Wheel.PRIZES),
	}

	local zones = flags(data.unlockedZones)
	zones[Config.Zones.STARTER_ZONE] = true
	data.unlockedZones = zones

	data.research = numbers(data.research)
	data.stats = numbers(data.stats)

	local achievements: { [string]: Types.AchievementRecord } = {}
	if type(data.achievements) == "table" then
		for id, record in data.achievements do
			if type(id) == "string" and type(record) == "table" then
				achievements[id] = {
					progress = amount(record.progress) or 0,
					claimed = record.claimed == true,
				}
			end
		end
	end
	data.achievements = achievements

	local tutorial = if type(data.tutorial) == "table" then data.tutorial else {}
	data.tutorial = {
		step = math.max(count(tutorial.step) or 1, 1),
		done = tutorial.done == true,
	}

	local settings = if type(data.settings) == "table" then data.settings else {}
	local fallback = defaults.settings
	data.settings = {
		musicVolume = clamp(settings.musicVolume, 0, 1, fallback.musicVolume),
		sfxVolume = clamp(settings.sfxVolume, 0, 1, fallback.sfxVolume),
		cameraSensitivity = clamp(settings.cameraSensitivity, 0.1, 3, fallback.cameraSensitivity),
		stabilization = if type(settings.stabilization) == "boolean"
			then settings.stabilization
			else fallback.stabilization,
		reducedEffects = if type(settings.reducedEffects) == "boolean"
			then settings.reducedEffects
			else fallback.reducedEffects,
		pvp = if type(settings.pvp) == "boolean" then settings.pvp else fallback.pvp,
		showBounds = if type(settings.showBounds) == "boolean"
			then settings.showBounds
			else fallback.showBounds,
		showControls = if type(settings.showControls) == "boolean"
			then settings.showControls
			else fallback.showControls,
		floating = if type(settings.floating) == "boolean"
			then settings.floating
			else fallback.floating,
		autoIncubate = if type(settings.autoIncubate) == "boolean"
			then settings.autoIncubate
			else fallback.autoIncubate,
		keepNewTypes = if type(settings.keepNewTypes) == "boolean"
			then settings.keepNewTypes
			else fallback.keepNewTypes,
		autoSell = autoSellSettings(settings.autoSell),
	}

	local receipts: { string } = {}
	if type(data.receipts) == "table" then
		for _, receipt in ipairs(data.receipts) do
			if type(receipt) == "string" then
				table.insert(receipts, receipt)
			end
		end
	end
	while #receipts > MAX_RECEIPTS do
		table.remove(receipts, 1)
	end
	data.receipts = receipts

	return true, nil
end

-- Production B (EconomyMath.production): Stardust per second from stars and
-- planets in orbit, with the trail and the Refinery, before passes and
-- boosts. Not rounded.
function ProfileSchema.incomeRate(profile: Profile): number
	return EconomyMath.production(profile)
end

-- The slice of a profile its owner's client is allowed to see.
function ProfileSchema.view(profile: Profile): Types.ProfileView
	return {
		stardust = profile.stardust,
		uncollected = profile.uncollected,
		materials = table.clone(profile.materials),
		cargo = table.clone(profile.cargo),
		activeShip = profile.activeShip,
		expansion = profile.galaxy.expansion,
		incomeRate = ProfileSchema.incomeRate(profile),
		economy = ProfileSchema.economyView(profile),
		constellationRank = profile.constellationRank,
		ownedShips = table.clone(profile.ownedShips),
		ownedEquipment = table.clone(profile.ownedEquipment),
		equipmentLevels = table.clone(profile.equipmentLevels),
		tutorialStep = if profile.tutorial.done then 0 else Progression.tutorialStep(profile.stats),
		settings = table.clone(profile.settings),
		boosts = table.clone(profile.boosts),
		passes = table.clone(profile.verifiedPasses),
		daily = table.clone(profile.daily),
		looks = ProfileSchema.looks(profile),
		shipLevels = ProfileSchema.shipLevels(profile),
		showcase = table.clone(profile.showcase),
		ownedTrails = table.clone(profile.ownedTrails),
		trail = profile.trail,
		planets = ProfileSchema.planetsView(profile),
		eggs = ProfileSchema.eggsView(profile),
		eggsBought = profile.eggsBought,
		eggLab = ProfileSchema.eggLabView(profile),
		hatches = ProfileSchema.hatchesView(profile),
		wheel = table.clone(profile.wheel),
		discovered = table.clone(profile.discovered),
		hangarColor = profile.hangarColor,
		hangar = table.clone(profile.hangar),
		hangarOff = table.clone(profile.hangarOff),
		cloakUnlocked = ProfileSchema.cloakUnlocked(profile),
	}
end

-- What the owner's panels need to price things: H, today's R, the egg
-- price and the next star's BuildIndex.
function ProfileSchema.economyView(profile: Profile): Types.EconomyView
	return {
		high = EconomyMath.high(profile),
		reward = profile.economy.reward,
		eggPrice = EconomyMath.profileEggPrice(profile),
		nextBuild = profile.galaxy.nextBuild,
	}
end

-- Whether the player redeemed a code that unlocks the cloak (Config.Codes).
function ProfileSchema.cloakUnlocked(profile: Profile): boolean
	for code, def in Config.Codes.BY_CODE do
		if def.cloak and profile.redeemedCodes[code] then
			return true
		end
	end
	return false
end

-- Owned planets for the client (a copy).
function ProfileSchema.planetsView(profile: Profile): { [string]: Types.PlanetRecord }
	local result: { [string]: Types.PlanetRecord } = {}
	for id, planet in profile.planets do
		result[id] = table.clone(planet)
	end
	return result
end

-- Unhatched eggs for the client: a mystery egg's planet stays hidden.
function ProfileSchema.eggsView(profile: Profile): { [string]: Types.EggView }
	local result: { [string]: Types.EggView } = {}
	for id, egg in profile.eggs do
		local def = Config.Planets.BY_ID[egg.outcome]
		result[id] = {
			guaranteed = egg.guaranteed,
			outcome = if egg.guaranteed then egg.outcome else nil,
			rarity = if def then def.rarity else "Common",
			tier = egg.tier,
		}
	end
	return result
end

-- The Egg Lab for the client: the pedestal egg's rarity and tier, never
-- its planet.
function ProfileSchema.eggLabView(profile: Profile): Types.EggLabView
	local lab = profile.eggLab
	local current = lab.current
	local def = if current then Config.Planets.BY_ID[current.outcome] else nil
	return {
		level = lab.level,
		current = if current and def
			then { rarity = def.rarity :: string, tier = current.tier }
			else nil,
		rolls = lab.rolls,
	}
end

-- Hatches for the client: the rarity (it sets the hatch time) and times,
-- never the planet itself.
function ProfileSchema.hatchesView(profile: Profile): { [string]: Types.HatchView }
	local result: { [string]: Types.HatchView } = {}
	for slot, hatch in profile.hatches do
		local def = Config.Planets.BY_ID[hatch.outcome]
		local rarity: string = if def then def.rarity else "Common"
		result[slot] = {
			rarity = rarity,
			tier = hatch.tier,
			startedAt = hatch.startedAt,
			endsAt = hatch.endsAt,
		}
	end
	return result
end

return ProfileSchema
