--!strict
-- Ship chassis. Equipment (Config.Equipment) and cosmetics (Config.Cosmetics)
-- are separate so skins never change stats.
--
-- Every ship can be earned. A ship with a productKey can also be unlocked with
-- Robux (Config.Products) and has exactly the same stats either way.
-- Working names from the design spec; tune freely.

export type ShipStats = {
	maxSpeed: number, -- studs per second
	acceleration: number, -- studs per second squared
	braking: number, -- studs per second squared
	turnRate: number, -- radians per second
	beamPower: number, -- extraction progress per second while on target
	beamRange: number, -- studs
	heatCapacity: number, -- heat units before overheating
	coolingRate: number, -- heat units shed per second while the beam is off
	cargoCapacity: number, -- material units
}

export type Cost = { credits: number, materials: { [string]: number } }

export type ShipDef = {
	id: string,
	displayName: string,
	role: string,
	description: string,
	enabled: boolean, -- false = defined for later stages, not offered yet
	stats: ShipStats,
	earn: Cost?, -- nil = free starter ship
	productKey: string?, -- optional Robux unlock with identical stats
}

local ORDER: { string } = {
	"StarterShuttle",
	"Prospector",
	"CrystalExplorer",
	"HeavyExcavator",
	"NebulaCruiser",
}

local BY_ID: { [string]: ShipDef } = {
	StarterShuttle = {
		id = "StarterShuttle",
		displayName = "Starter Shuttle",
		role = "Beginner mining",
		description = "Simple controls and a basic mining beam.",
		enabled = true,
		stats = {
			maxSpeed = 120,
			acceleration = 60,
			braking = 90,
			turnRate = 2.2,
			beamPower = 10,
			beamRange = 120,
			heatCapacity = 100,
			coolingRate = 25,
			cargoCapacity = 60,
		},
		earn = nil,
		productKey = nil,
	},
	Prospector = {
		id = "Prospector",
		displayName = "Prospector",
		role = "General progression",
		description = "Better extraction and a larger cargo hold.",
		enabled = true,
		stats = {
			maxSpeed = 140,
			acceleration = 70,
			braking = 100,
			turnRate = 2.2,
			beamPower = 16,
			beamRange = 140,
			heatCapacity = 120,
			coolingRate = 30,
			cargoCapacity = 150,
		},
		earn = { credits = 2500, materials = { Iron = 120, Silicate = 80 } },
		productKey = nil,
	},
	CrystalExplorer = {
		id = "CrystalExplorer",
		displayName = "Crystal Explorer",
		role = "Precision mining",
		description = "Better cooling, range and handling, with a modest hold.",
		enabled = false,
		stats = {
			maxSpeed = 170,
			acceleration = 90,
			braking = 130,
			turnRate = 2.8,
			beamPower = 18,
			beamRange = 200,
			heatCapacity = 160,
			coolingRate = 45,
			cargoCapacity = 140,
		},
		earn = { credits = 15000, materials = { Iron = 200, Ice = 150 } },
		productKey = "CrystalExplorerUnlock",
	},
	HeavyExcavator = {
		id = "HeavyExcavator",
		displayName = "Heavy Excavator",
		role = "Bulk mining",
		description = "Powerful extraction and a huge hold, but slow to turn.",
		enabled = false,
		stats = {
			maxSpeed = 110,
			acceleration = 40,
			braking = 60,
			turnRate = 1.4,
			beamPower = 30,
			beamRange = 130,
			heatCapacity = 200,
			coolingRate = 30,
			cargoCapacity = 400,
		},
		earn = { credits = 40000, materials = { Iron = 600, Crystal = 150 } },
		productKey = nil,
	},
	NebulaCruiser = {
		id = "NebulaCruiser",
		displayName = "Nebula Cruiser",
		role = "Advanced exploration",
		description = "Strong equipment and fast long-distance travel.",
		enabled = false,
		stats = {
			maxSpeed = 220,
			acceleration = 100,
			braking = 140,
			turnRate = 2.4,
			beamPower = 32,
			beamRange = 220,
			heatCapacity = 220,
			coolingRate = 50,
			cargoCapacity = 300,
		},
		earn = { credits = 120000, materials = { Crystal = 400, Ice = 300, StellarGas = 100 } },
		productKey = nil,
	},
}

return {
	ORDER = ORDER,
	BY_ID = BY_ID,
	STARTER_SHIP = "StarterShuttle",
}
