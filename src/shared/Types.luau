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
	-- BuildIndex: 0 for the player's first star built, then 1, 2 ...; never
	-- changes (moving or evolving keeps it). Prices scale with it.
	build: number,
}

-- One owned planet (Config.Planets type). In inventory when `star` is nil,
-- otherwise in orbit `slot` (1..its star's orbits) of that star.
export type PlanetRecord = {
	typeId: string,
	level: number, -- 1..Config.Planets.MAX_LEVEL
	tier: number, -- 1..#Config.Planets.TIERS (income multiplier and effects)
	star: string?,
	slot: number?,
	custom: { [string]: any }?, -- per-planet customisation (none on sale yet)
	locked: boolean?, -- protected from selling (by hand, in bulk or automatically)
	paid: number?, -- Stardust its accepted egg roll actually cost (0 = free)
	spent: number?, -- Stardust actually spent levelling it
	-- From before economy v2: a fixed sale value used instead (once).
	legacy: number?,
}

-- An unhatched egg (Config.Eggs). Its planet was chosen on the server when
-- it was bought and never changes. `guaranteed` eggs (bought as a chosen
-- planet) may show their outcome; mystery eggs never do before hatching.
export type EggRecord = {
	outcome: string, -- Config.Planets id
	tier: number, -- rolled with the egg, shown before it hatches
	guaranteed: boolean,
	boughtAt: number, -- unix seconds
	paid: number?, -- Stardust the accepted roll cost; nil = from before economy v2
}

-- An egg incubating in a hangar hatch slot.
export type HatchRecord = {
	eggId: string,
	outcome: string,
	tier: number,
	startedAt: number, -- unix seconds
	endsAt: number,
	paid: number?, -- as EggRecord.paid
}

-- The player's Egg Lab (Config.Eggs): its level and the rolled egg on its
-- pedestal waiting to be kept or rerolled (its planet is never shown).
export type EggLabRecord = {
	level: number, -- 1..#Config.Eggs.LAB_LEVELS
	current: { outcome: string, tier: number, paid: number }?,
	rolls: number, -- rolls ever made
}

-- The Egg Lab as its owner may see it: the pedestal egg's rarity and tier.
export type EggLabView = {
	level: number,
	current: { rarity: string, tier: number }?,
	rolls: number, -- rolls made (each one changes the pedestal egg)
}

export type GalaxyRecord = {
	expansion: number,
	nextId: number, -- next unique star id number ("s<n>") in this save
	nextBuild: number, -- the BuildIndex the next star built gets
	stars: { [string]: StarRecord },
}

-- The owner's view of their economy: H, today's R, the next egg price and
-- the next star's BuildIndex.
export type EconomyView = { high: number, reward: number, eggPrice: number, nextBuild: number }

-- Economy v2 bookkeeping (Logic/EconomyMath).
export type EconomyRecord = {
	high: number, -- H: best production B so far (never falls)
	recent: number, -- average B over the last online REWARD_WINDOW_SECONDS
	reward: number, -- R: the reward rate for rewardDay
	rewardDay: number, -- UTC day number R was snapshotted (0 = never)
	raidDay: number, -- UTC day number of the last raid win that paid
}

export type Loadout = {
	equipment: { [string]: string }, -- slot -> Config.Equipment id
	-- Items bought for this ship -> level 1..Config.Equipment.MAX_LEVEL
	-- (every ship has its own upgrades).
	levels: { [string]: number },
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
	economy: EconomyRecord,
	constellationRank: number, -- Constellation Projects completed (cosmetic)
	tutorialEgg: boolean, -- the free tutorial egg was given
	planets: { [string]: PlanetRecord }, -- every owned planet, by id ("p<n>")
	nextPlanetId: number,
	eggs: { [string]: EggRecord }, -- unhatched eggs, by id ("e<n>")
	nextEggId: number,
	eggsBought: number, -- mystery eggs ever kept (their price grows with it)
	eggLab: EggLabRecord,
	hatches: { [string]: HatchRecord }, -- hangar hatch slot ("1".."5") -> incubation
	-- Daily wheel (Config.Wheel): unix seconds of the next spin and the
	-- index of the last prize won (0 = never spun).
	wheel: { nextSpin: number, lastPrize: number },
	discovered: { [string]: boolean }, -- planet types ever owned (the Planet Index)
	hangarColor: string?, -- Config.Hangar.HIGHLIGHT_COLORS id, nil = the region's colour
	hangarOff: { [string]: boolean }, -- built toggleable hangar upgrades switched off
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

-- An unhatched egg as its owner sees it: rarity and tier; the planet only
-- for a guaranteed egg.
export type EggView = { guaranteed: boolean, outcome: string?, rarity: string, tier: number }
export type HatchView = { rarity: string, tier: number, startedAt: number, endsAt: number }

-- The part of a profile its owner's client is told about.
export type ProfileView = {
	stardust: number,
	uncollected: number,
	materials: { [string]: number },
	cargo: { [string]: number },
	activeShip: string,
	expansion: number,
	incomeRate: number, -- production B: Stardust per second from stars and planets (trail, Refinery)
	economy: EconomyView,
	constellationRank: number,
	ownedShips: { [string]: boolean },
	ownedEquipment: { [string]: boolean },
	equipmentLevels: { [string]: number },
	tutorialStep: number, -- Config.Tutorial step to show, 0 when done
	settings: Settings,
	boosts: { mining: number, star: number },
	passes: { [string]: boolean }, -- passes the server has verified
	daily: { day: number, lastClaim: number },
	looks: { [string]: ShipLook }, -- colours of owned ships
	shipLevels: { [string]: { [string]: number } }, -- each ship's equipment levels
	showcase: { string },
	ownedTrails: { [string]: boolean },
	trail: string?,
	planets: { [string]: PlanetRecord },
	-- Eggs as the owner may see them: a mystery egg hides its planet.
	eggs: { [string]: EggView },
	eggsBought: number,
	eggLab: EggLabView,
	-- Hatches as the owner may see them: rarity, tier and times, not the planet.
	hatches: { [string]: HatchView },
	wheel: { nextSpin: number, lastPrize: number },
	discovered: { [string]: boolean },
	hangarColor: string?,
	hangar: { [string]: boolean }, -- hangar upgrades built
	hangarOff: { [string]: boolean },
	cloakUnlocked: boolean, -- a cloak code was redeemed (Settings shows the Cloak switch)
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
