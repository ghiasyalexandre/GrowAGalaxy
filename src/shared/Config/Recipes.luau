--!strict
-- Crafting recipes (immediate in the MVP). Outputs are either a component
-- (listed in COMPONENTS) or a celestial type id from Config.Celestials, which
-- the player can then place in their galaxy.

export type RecipeDef = {
	id: string,
	displayName: string,
	enabled: boolean,
	materials: { [string]: number },
	items: { [string]: number }, -- crafted items consumed (e.g. a Stellar Core)
	output: string,
	outputCount: number,
}

export type ComponentDef = { id: string, displayName: string, description: string }

local COMPONENTS: { [string]: ComponentDef } = {
	StellarCore = {
		id = "StellarCore",
		displayName = "Stellar Core",
		description = "A manufactured core that ignites into your first star.",
	},
}

local ORDER: { string } = {
	"StellarCore",
	"StarterStar",
	"RockyPlanet",
	"SmallMoon",
	"IcePlanet",
	"CrystalPlanet",
}

local BY_ID: { [string]: RecipeDef } = {
	StellarCore = {
		id = "StellarCore",
		displayName = "Stellar Core",
		enabled = true,
		materials = { Iron = 30, Silicate = 20 },
		items = {},
		output = "StellarCore",
		outputCount = 1,
	},
	StarterStar = {
		id = "StarterStar",
		displayName = "Starter Star",
		enabled = true,
		materials = {},
		items = { StellarCore = 1 },
		output = "StarterStar",
		outputCount = 1,
	},
	RockyPlanet = {
		id = "RockyPlanet",
		displayName = "Rocky Planet",
		enabled = true,
		materials = { Iron = 20, Silicate = 30 },
		items = {},
		output = "RockyPlanet",
		outputCount = 1,
	},
	SmallMoon = {
		id = "SmallMoon",
		displayName = "Small Moon",
		enabled = true,
		materials = { Iron = 10, Silicate = 15 },
		items = {},
		output = "SmallMoon",
		outputCount = 1,
	},
	IcePlanet = {
		id = "IcePlanet",
		displayName = "Ice Planet",
		enabled = false,
		materials = { Silicate = 15, Ice = 35 },
		items = {},
		output = "IcePlanet",
		outputCount = 1,
	},
	CrystalPlanet = {
		id = "CrystalPlanet",
		displayName = "Crystal Planet",
		enabled = false,
		materials = { Silicate = 25, Crystal = 20 },
		items = {},
		output = "CrystalPlanet",
		outputCount = 1,
	},
}

return {
	COMPONENTS = COMPONENTS,
	ORDER = ORDER,
	BY_ID = BY_ID,
}
