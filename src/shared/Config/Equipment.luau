--!strict
-- Ship equipment. Each item fits one slot and multiplies ship stats. Equipment
-- is owned by the player and can be fitted to any owned ship.

export type Cost = { stardust: number, materials: { [string]: number } }

export type EquipmentDef = {
	id: string,
	displayName: string,
	slot: string,
	enabled: boolean,
	modifiers: { [string]: number }, -- ShipStats field -> multiplier
	cost: Cost,
}

local SLOTS: { string } = { "Beam", "Thrusters", "Cooling", "Cargo" }

local ORDER: { string } = {
	"BeamMk2",
	"BeamMk3",
	"ThrustersMk2",
	"CoolingMk2",
	"CargoMk2",
}

local BY_ID: { [string]: EquipmentDef } = {
	BeamMk2 = {
		id = "BeamMk2",
		displayName = "Focused Beam Mk II",
		slot = "Beam",
		enabled = true,
		modifiers = { beamPower = 1.25 },
		cost = { stardust = 600, materials = {} },
	},
	BeamMk3 = {
		id = "BeamMk3",
		displayName = "Focused Beam Mk III",
		slot = "Beam",
		enabled = false,
		modifiers = { beamPower = 1.5, beamRange = 1.1 },
		cost = { stardust = 6000, materials = {} },
	},
	ThrustersMk2 = {
		id = "ThrustersMk2",
		displayName = "Ion Thrusters Mk II",
		slot = "Thrusters",
		enabled = true,
		modifiers = { maxSpeed = 1.15, acceleration = 1.2 },
		cost = { stardust = 500, materials = {} },
	},
	CoolingMk2 = {
		id = "CoolingMk2",
		displayName = "Coolant Loop Mk II",
		slot = "Cooling",
		enabled = true,
		modifiers = { coolingRate = 1.3, heatCapacity = 1.2 },
		cost = { stardust = 500, materials = {} },
	},
	CargoMk2 = {
		id = "CargoMk2",
		displayName = "Expanded Hold Mk II",
		slot = "Cargo",
		enabled = false, -- cargo is deferred
		modifiers = { cargoCapacity = 1.4 },
		cost = { stardust = 700, materials = {} },
	},
}

return {
	SLOTS = SLOTS,
	ORDER = ORDER,
	BY_ID = BY_ID,
}
