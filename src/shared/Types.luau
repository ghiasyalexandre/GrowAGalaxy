--!strict
-- Types shared by client and server: the save schema and remote payloads.
-- Config types live next to their config tables in Shared/Config.
--
-- Everything in Profile is saved through ProfileStore, so it must stay plain
-- data: strings, numbers, booleans and tables with string keys or array
-- indices. No Instances, no Vector3/CFrame/Color3.

export type Vec3 = { x: number, y: number, z: number }

-- Orbit of a planet around its star, or of a moon around its planet. The radius
-- comes from the slot (Config.Galaxy); the angles are chosen by the player.
export type Orbit = {
	slot: number,
	tilt: number, -- radians, inclination of the orbital plane
	node: number, -- radians, rotation of the plane around the parent's up axis
	phase: number, -- radians, starting position along the orbit
}

export type BodyRecord = {
	kind: string, -- "star" | "planet" | "moon"
	typeId: string, -- Config.Celestials id
	systemId: string,
	parentId: string?, -- planets: their star; moons: their planet; stars: nil
	level: number,
	appearance: string?,
	orbit: Orbit?, -- nil for stars
}

export type SystemRecord = {
	starId: string,
	tier: number,
	pos: Vec3, -- star position relative to the region origin
}

export type GalaxyRecord = {
	expansion: number,
	nextId: number, -- next unique id for systems and bodies in this save
	systems: { [string]: SystemRecord },
	bodies: { [string]: BodyRecord },
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
	credits: number,
	uncollected: number,
	materials: { [string]: number }, -- station storage
	cargo: { [string]: number }, -- ship hold; capacity comes from the active ship
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
	credits: number,
	uncollected: number,
	materials: { [string]: number },
	cargo: { [string]: number },
	activeShip: string,
	expansion: number,
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
