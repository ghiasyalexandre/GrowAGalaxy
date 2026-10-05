--!strict
-- Types shared by client and server: the save schema and remote payloads.
-- Config types live next to their config tables in Shared/Config.
--
-- Everything in Profile is saved through ProfileStore, so it must stay plain
-- data: strings, numbers, booleans and tables with string keys or array
-- indices. No Instances, no Vector3/CFrame/Color3.

export type Vec3 = { x: number, y: number, z: number }

-- A placed star and the planets bought for it. Orbits and production come
-- from Config.Stars and Config.Planets, so only this is saved.
export type StarRecord = {
	typeId: string, -- Config.Stars id
	level: number,
	pos: Vec3, -- position relative to the region origin
	planets: { [string]: string }, -- orbit slot ("1".."4") -> Config.Planets id
	appearance: string?,
}

export type GalaxyRecord = {
	expansion: number,
	nextId: number, -- next unique star id number ("s<n>") in this save
	stars: { [string]: StarRecord },
}

export type Loadout = {
	equipment: { [string]: string }, -- slot -> Config.Equipment id
	cosmetic: string?,
	paint: string?, -- Config.Paint.SWATCHES colour; nil = factory colours
	finish: string?, -- Config.Paint.FINISHES id; nil = factory finish
}

-- A ship's paint job, as the client sees it.
export type ShipLook = { paint: string?, finish: string? }

export type AchievementRecord = { progress: number, claimed: boolean }

export type Settings = {
	musicVolume: number,
	sfxVolume: number,
	cameraSensitivity: number,
	stabilization: boolean,
	reducedEffects: boolean,
	pvp: boolean,
	showBounds: boolean, -- draw your galaxy region's boundary box
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
	looks: { [string]: ShipLook }, -- paint jobs of owned ships
	showcase: { string },
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
