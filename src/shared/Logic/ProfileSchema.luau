--!strict
-- Default save data and load-time cleanup for player profiles.
--
-- normalize() repairs types and fills in missing fields, but keeps unknown ids
-- (a ship or material removed from config by mistake must not wipe someone's
-- save). Gameplay code always checks config before using a saved id.
-- Pure module: no Roblox services, so the Lune unit tests run it directly.

local Config = require(script.Parent.Parent.Config)
local Types = require(script.Parent.Parent.Types)

type Profile = Types.Profile
type Vec3 = Types.Vec3
type Orbit = Types.Orbit

local MAX_RECEIPTS = 50
local BODY_KINDS = { star = true, planet = true, moon = true }

local ProfileSchema = {}

ProfileSchema.VERSION = 1

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
		credits = Config.Economy.STARTING_CREDITS,
		uncollected = 0,
		materials = {},
		cargo = {},
		ownedShips = { [starter] = true },
		activeShip = starter,
		loadouts = { [starter] = { equipment = {} } },
		ownedEquipment = {},
		ownedCosmetics = {},
		inventory = {},
		galaxy = { expansion = 1, nextId = 1, systems = {}, bodies = {} },
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

local function orbit(raw: any): Orbit?
	if type(raw) ~= "table" then
		return nil
	end
	local slot = count(raw.slot)
	if
		not slot
		or slot < 1
		or not isFinite(raw.tilt)
		or not isFinite(raw.node)
		or not isFinite(raw.phase)
	then
		return nil
	end
	return { slot = slot, tilt = raw.tilt, node = raw.node, phase = raw.phase }
end

-- Highest numeric suffix among ids like "s12" / "b40". Scans the raw saved
-- tables, so nextId never reuses an id, even one that was dropped as corrupt.
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
	local systems: { [string]: Types.SystemRecord } = {}
	local bodies: { [string]: Types.BodyRecord } = {}

	if type(source.systems) == "table" then
		for id, system in source.systems do
			local pos = if type(system) == "table" then vec3(system.pos) else nil
			local tier = if type(system) == "table" then count(system.tier) else nil
			if type(id) == "string" and pos and tier and type(system.starId) == "string" then
				systems[id] = {
					starId = system.starId,
					tier = math.clamp(tier, 1, #Config.SolarSystems.TIERS),
					pos = pos,
				}
			end
		end
	end

	if type(source.bodies) == "table" then
		for id, body in source.bodies do
			if type(id) ~= "string" or type(body) ~= "table" then
				continue
			end
			local level = count(body.level)
			local parentOk = body.parentId == nil or type(body.parentId) == "string"
			local appearanceOk = body.appearance == nil or type(body.appearance) == "string"
			local bodyOrbit = orbit(body.orbit)
			local orbitOk = (body.kind == "star") == (bodyOrbit == nil)
			if
				BODY_KINDS[body.kind]
				and type(body.typeId) == "string"
				and type(body.systemId) == "string"
				and level
				and level >= 1
				and parentOk
				and appearanceOk
				and orbitOk
			then
				bodies[id] = {
					kind = body.kind,
					typeId = body.typeId,
					systemId = body.systemId,
					parentId = body.parentId,
					level = level,
					appearance = body.appearance,
					orbit = bodyOrbit,
				}
			end
		end
	end

	local floorId = math.max(highestId(source.systems), highestId(source.bodies)) + 1
	return {
		expansion = math.clamp(count(source.expansion) or 1, 1, #Config.Galaxy.EXPANSIONS),
		nextId = math.max(count(source.nextId) or 1, floorId),
		systems = systems,
		bodies = bodies,
	}
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
	-- Migrations from older schema versions go here, oldest first, e.g.
	-- if (version or 0) < 2 then ... end

	local defaults = ProfileSchema.default()
	local starter = Config.Ships.STARTER_SHIP

	data.schemaVersion = ProfileSchema.VERSION
	data.credits = count(data.credits) or defaults.credits
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
		credits = profile.credits,
		uncollected = profile.uncollected,
		materials = table.clone(profile.materials),
		cargo = table.clone(profile.cargo),
		activeShip = profile.activeShip,
		expansion = profile.galaxy.expansion,
	}
end

return ProfileSchema
