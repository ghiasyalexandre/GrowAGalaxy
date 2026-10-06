--!strict
-- Types shared by client and server: the save schema and remote payloads.
-- Config types live next to their config tables in Shared/Config.
--
-- Everything in Profile is saved through ProfileStore, so it must stay plain
-- data: strings, numbers, booleans and tables with string keys or array
-- indices. No Instances, no Vector3/CFrame/Color3.

export type Vec3 = { x: number, y: number, z: number }

-- A placed star. Its orbits come from Config.Stars; the planets in them are
-- PlanetRecords that name it.
export type StarRecord = {
	typeId: string, -- Config.Stars id
	level: number,
	pos: Vec3, -- position relative to the region origin
	appearance: string?,
}

-- One owned planet (Config.Planets type). In inventory when `star` is nil,
-- otherwise in orbit `slot` (1..its star's orbits) of that star.
export type PlanetRecord = {
	typeId: string,
	level: number, -- 1..Config.Planets.MAX_LEVEL
	star: string?,
	slot: number?,
	custom: { [string]: any }?, -- per-planet customisation (none on sale yet)
	locked: boolean?, -- protected from selling (by hand, in bulk or automatically)
}

-- An unhatched egg (Config.Eggs). Its planet was chosen on the server when
-- it was bought and never changes. `guaranteed` eggs (bought as a chosen
-- planet) may show their outcome; mystery eggs never do before hatching.
export type EggRecord = {
	outcome: string, -- Config.Planets id
	guaranteed: boolean,
	boughtAt: number, -- unix seconds
}

-- An egg incubating in a hangar hatch slot.
export type HatchRecord = {
	eggId: string,
	outcome: string,
	startedAt: number, -- unix seconds
	endsAt: number,
}

export type GalaxyRecord = {
	expansion: number,
	nextId: number, -- next unique star id number ("s<n>") in this save
	stars: { [string]: StarRecord },
}

export type Loadout = {
	equipment: { [string]: string }, -- slot -> Config.Equipment id
	cosmetic: string?,
	laserColor: string?, -- Config.Paint.SWATCHES colour; nil = the standard laser
	boostColor: string?, -- Config.Paint.SWATCHES colour; nil = the standard engines
}

-- A ship's colours, as the client sees them.
export type ShipLook = { laserColor: string?, boostColor: string? }

export type AchievementRecord = { progress: number, claimed: boolean }

export type Settings = {
	musicVolume: number,
	sfxVolume: number,
	cameraSensitivity: number,
	stabilization: boolean,
	reducedEffects: boolean,
	pvp: boolean,
	showBounds: boolean, -- draw your galaxy region's boundary box
	showControls: boolean, -- the controls hint along the bottom of the screen
	floating: boolean, -- false: walk on floors (magnetic boots); float only in open space
	autoIncubate: boolean, -- start the next waiting egg when a chamber frees up
	keepNewTypes: boolean, -- auto-sell never sells a planet type not discovered before
	autoSell: { [string]: boolean }, -- rarity -> sell such planets as they hatch
}

export type Profile = {
	schemaVersion: number,
	stardust: number,
	uncollected: number,
	materials: { [string]: number }, -- deferred: no system uses materials yet
	cargo: { [string]: number }, -- deferred: mining pays Stardust directly
	ownedShips: { [string]: boolean },
	activeShip: string,
	loadouts: { [string]: Loadout }, -- per owned ship
	ownedEquipment: { [string]: boolean },
	equipmentLevels: { [string]: number }, -- owned item -> level 1..Config.Equipment.MAX_LEVEL
	ownedCosmetics: { [string]: boolean },
	inventory: { [string]: number }, -- crafted items not yet placed
	galaxy: GalaxyRecord,
	unlockedZones: { [string]: boolean },
	research: { [string]: number },
	achievements: { [string]: AchievementRecord },
	tutorial: { step: number, done: boolean },
	stats: { [string]: number },
	settings: Settings,
	hangar: { [string]: boolean }, -- hangar upgrades built (Config.Hangar)
	-- Owned ships on show in the hangar's Showcase Dock (up to
	-- Config.Paint.SHOWCASE_SLOTS), in slot order.
	showcase: { string },
	ownedTrails: { [string]: boolean }, -- Config.Trails ids bought
	redeemedCodes: { [string]: boolean }, -- Config.Codes codes already used
	lastOnline: number, -- unix seconds the player was last seen in a server; 0 = never
	trail: string?, -- the equipped trail, if any
	planets: { [string]: PlanetRecord }, -- every owned planet, by id ("p<n>")
	nextPlanetId: number,
	eggs: { [string]: EggRecord }, -- unhatched eggs, by id ("e<n>")
	nextEggId: number,
	eggsBought: number, -- mystery eggs ever bought (their price grows with it)
	hatches: { [string]: HatchRecord }, -- hangar hatch slot ("1".."5") -> incubation
	-- Daily wheel (Config.Wheel): unix seconds of the next free spin and the
	-- index of the last prize won (0 = never spun).
	wheel: { nextSpin: number, lastPrize: number },
	discovered: { [string]: boolean }, -- planet types ever owned (the Planet Index)
	-- Seconds of temporary 2x boost left per source; counts down only while
	-- the player is in a server.
	boosts: { mining: number, star: number },
	-- Passes Roblox last confirmed (key -> true): used only while a fresh
	-- ownership check fails.
	verifiedPasses: { [string]: boolean },
	-- Daily prizes (Config.Daily): the next day to claim (1..14) and the UTC
	-- day number of the last claim (0 = never).
	daily: { day: number, lastClaim: number },
	receipts: { string }, -- recent purchase ids for idempotent fulfilment (Stage 8)
}

-- The part of a profile its owner's client is told about.
export type ProfileView = {
	stardust: number,
	uncollected: number,
	materials: { [string]: number },
	cargo: { [string]: number },
	activeShip: string,
	expansion: number,
	incomeRate: number, -- Stardust per second from all stars
	ownedShips: { [string]: boolean },
	ownedEquipment: { [string]: boolean },
	equipmentLevels: { [string]: number },
	tutorialStep: number, -- Config.Tutorial step to show, 0 when done
	settings: Settings,
	boosts: { mining: number, star: number },
	passes: { [string]: boolean }, -- passes the server has verified
	daily: { day: number, lastClaim: number },
	looks: { [string]: ShipLook }, -- colours of owned ships
	showcase: { string },
	ownedTrails: { [string]: boolean },
	trail: string?,
	planets: { [string]: PlanetRecord },
	-- Eggs as the owner may see them: a mystery egg hides its planet.
	eggs: { [string]: { guaranteed: boolean, outcome: string? } },
	eggsBought: number,
	-- Hatches as the owner may see them: rarity and times, not the planet.
	hatches: { [string]: { rarity: string, startedAt: number, endsAt: number } },
	wheel: { nextSpin: number, lastPrize: number },
	discovered: { [string]: boolean },
}

export type RegionInfo = {
	slot: number,
	userId: number,
	name: string,
}

-- What the server tells a player about their spawned ship (ShipState):
-- effective stats with equipment applied.
export type ShipInfo = {
	shipId: string,
	displayName: string,
	maxSpeed: number,
	acceleration: number,
	braking: number,
	turnRate: number,
	beamPower: number,
	beamRange: number,
	heatCapacity: number,
	coolingRate: number,
	cargoCapacity: number,
	boostMultiplier: number,
	boostDuration: number,
	boostRecharge: number,
	hull: number,
}

export type InitialState = {
	profile: ProfileView,
	regions: { RegionInfo },
}

return nil
