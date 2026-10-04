--!strict
-- Default save data and load-time cleanup for player profiles.
--
-- normalize() repairs types and fills in missing fields, but keeps unknown ids
-- (a ship or material removed from config by mistake must not wipe someone's
-- save). Gameplay code always checks config before using a saved id.
-- Pure module: no Roblox services, so the Lune unit tests run it directly.

local Config = require(script.Parent.Parent.Config)
local Progression = require(script.Parent.Progression)
local StarMath = require(script.Parent.StarMath)
local Types = require(script.Parent.Parent.Types)

type Profile = Types.Profile
type Vec3 = Types.Vec3

local MAX_RECEIPTS = 50

local ProfileSchema = {}

-- 1: first release. 2: "credits" renamed to "stardust" (the one currency).
-- 3: galaxy saves stars (level-based upgrades) instead of systems and bodies.
ProfileSchema.VERSION = 3

local function defaultSettings(): Types.Settings
	return {
		musicVolume = 0.5,
		sfxVolume = 0.8,
		cameraSensitivity = 1,
		stabilization = true,
		reducedEffects = false,
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
		loadouts = { [starter] = { equipment = {} } },
		ownedEquipment = {},
		ownedCosmetics = {},
		inventory = {},
		galaxy = { expansion = 1, nextId = 1, stars = {} },
		unlockedZones = { [Config.Zones.STARTER_ZONE] = true },
		research = {},
		achievements = {},
		tutorial = { step = 1, done = false },
		stats = {},
		settings = defaultSettings(),
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
				stars[id] = {
					typeId = star.typeId,
					level = level,
					pos = pos,
					appearance = star.appearance,
				}
			end
		end
	end
	return {
		expansion = math.clamp(count(source.expansion) or 1, 1, #Config.Galaxy.EXPANSIONS),
		nextId = math.max(count(source.nextId) or 1, highestId(source.stars) + 1),
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
	data.ownedCosmetics = flags(data.ownedCosmetics)

	local loadouts: { [string]: Types.Loadout } = {}
	local rawLoadouts = if type(data.loadouts) == "table" then data.loadouts else {}
	for shipId in ownedShips do
		local raw = rawLoadouts[shipId]
		local equipment: { [string]: string } = {}
		local cosmetic: string? = nil
		if type(raw) == "table" then
			if type(raw.equipment) == "table" then
				for slot, itemId in raw.equipment do
					if
						type(slot) == "string"
						and type(itemId) == "string"
						and data.ownedEquipment[itemId]
					then
						equipment[slot] = itemId
					end
				end
			end
			if type(raw.cosmetic) == "string" and data.ownedCosmetics[raw.cosmetic] then
				cosmetic = raw.cosmetic
			end
		end
		loadouts[shipId] = { equipment = equipment, cosmetic = cosmetic }
	end
	data.loadouts = loadouts

	data.galaxy = galaxy(data.galaxy)

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

-- The slice of a profile its owner's client is allowed to see.
function ProfileSchema.view(profile: Profile): Types.ProfileView
	return {
		stardust = profile.stardust,
		uncollected = profile.uncollected,
		materials = table.clone(profile.materials),
		cargo = table.clone(profile.cargo),
		activeShip = profile.activeShip,
		expansion = profile.galaxy.expansion,
		incomeRate = StarMath.totalIncome(profile.galaxy.stars),
		ownedShips = table.clone(profile.ownedShips),
		ownedEquipment = table.clone(profile.ownedEquipment),
		tutorialStep = if profile.tutorial.done then 0 else Progression.tutorialStep(profile.stats),
		settings = table.clone(profile.settings),
	}
end

return ProfileSchema
