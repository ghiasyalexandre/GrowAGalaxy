--!strict
-- Ship equipment. Each item fits one slot and multiplies ship stats. Items
-- are bought and levelled for one ship at a time (its loadout's `levels`):
-- every ship has its own upgrades.
--
-- Price: level L of an item for a ship costs
--   max(cost, ship's Stardust price x costShare) x COST_GROWTH^(L - 1)
-- so better ships have pricier upgrades; `cost` is the floor (and the price
-- on the free starter ship).
--
-- Four groups (economy v2): beam, cooling, range and handling, one item
-- each. Buying an item gets level 1 (`modifiers` as listed: +15%); it can
-- then be upgraded up to MAX_LEVEL. At level L each modifier's bonus is
-- multiplied by LEVEL_BONUS[L] (+15%, +30%, +45%, +60%), and level L costs
-- cost x COST_GROWTH^(L - 1). Every item level also raises the mining
-- share of production a little (Logic/EconomyMath.miningFactor).

export type Cost = { stardust: number, materials: { [string]: number } }

export type EquipmentDef = {
	id: string,
	displayName: string,
	slot: string,
	enabled: boolean,
	modifiers: { [string]: number }, -- ShipStats field -> multiplier
	cost: Cost, -- the lowest price of level 1
	costShare: number, -- level 1's share of the ship's price
}

local SLOTS: { string } = { "Beam", "Thrusters", "Cooling", "Optics", "Cargo" }

local ORDER: { string } = {
	"BeamMk2",
	"BeamMk3",
	"ThrustersMk2",
	"CoolingMk2",
	"OpticsMk2",
	"CargoMk2",
}

local BY_ID: { [string]: EquipmentDef } = {
	BeamMk2 = {
		id = "BeamMk2",
		displayName = "Focused Beam Mk II",
		slot = "Beam",
		enabled = true,
		modifiers = { beamPower = 1.15 },
		cost = { stardust = 500, materials = {} },
		costShare = 0.1,
	},
	BeamMk3 = {
		id = "BeamMk3",
		displayName = "Focused Beam Mk III",
		slot = "Beam",
		enabled = false,
		modifiers = { beamPower = 1.5, beamRange = 1.1 },
		cost = { stardust = 6000, materials = {} },
		costShare = 0.1,
	},
	ThrustersMk2 = {
		id = "ThrustersMk2",
		displayName = "Ion Thrusters Mk II",
		slot = "Thrusters",
		enabled = true,
		modifiers = { maxSpeed = 1.15, acceleration = 1.15, boostDuration = 1.15 },
		cost = { stardust = 1500, materials = {} },
		costShare = 0.3,
	},
	CoolingMk2 = {
		id = "CoolingMk2",
		displayName = "Coolant Loop Mk II",
		slot = "Cooling",
		enabled = true,
		modifiers = { coolingRate = 1.15, heatCapacity = 1.15 },
		cost = { stardust = 750, materials = {} },
		costShare = 0.15,
	},
	OpticsMk2 = {
		id = "OpticsMk2",
		displayName = "Long-Range Optics Mk II",
		slot = "Optics",
		enabled = true,
		modifiers = { beamRange = 1.15 },
		cost = { stardust = 1000, materials = {} },
		costShare = 0.2,
	},
	CargoMk2 = {
		id = "CargoMk2",
		displayName = "Expanded Hold Mk II",
		slot = "Cargo",
		enabled = false, -- cargo is deferred
		modifiers = { cargoCapacity = 1.4 },
		cost = { stardust = 700, materials = {} },
		costShare = 0.1,
	},
}

return {
	SLOTS = SLOTS,
	ORDER = ORDER,
	BY_ID = BY_ID,
	MAX_LEVEL = 4,
	LEVEL_BONUS = { 1, 2, 3, 4 } :: { number },
	COST_GROWTH = 2,
}
