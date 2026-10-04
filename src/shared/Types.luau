--!strict
-- Types shared by client and server: the save schema and remote payloads.
-- Config types live next to their config tables in Shared/Config.
--
-- Everything in Profile is saved through ProfileStore, so it must stay plain
-- data: strings, numbers, booleans and tables with string keys or array
-- indices. No Instances, no Vector3/CFrame/Color3.

export type Vec3 = { x: number, y: number, z: number }

-- A placed star. Its planets, orbits and production come from its level and
-- Config.Stars, so only this is saved.
export type StarRecord = {
	typeId: string, -- Config.Stars id
	level: number,
	pos: Vec3, -- position relative to the region origin
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
}

export type AchievementRecord = { progress: number, claimed: boolean }

export type Settings = {
	musicVolume: number,
	sfxVolume: number,
	cameraSensitivity: number,
	stabilization: boolean,
	reducedEffects: boolean,
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
	ownedCosmetics: { [string]: boolean },
	inventory: { [string]: number }, -- crafted items not yet placed
	galaxy: GalaxyRecord,
	unlockedZones: { [string]: boolean },
	research: { [string]: number },
	achievements: { [string]: AchievementRecord },
	tutorial: { step: number, done: boolean },
	stats: { [string]: number },
	settings: Settings,
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
}

export type InitialState = {
	profile: ProfileView,
	regions: { RegionInfo },
}

return nil
