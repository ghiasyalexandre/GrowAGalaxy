--!strict
-- Celestial body types and their upgrade levels.
--
-- Stars and planets produce Credits per second. Moons add a percentage bonus
-- to their parent planet's income. Visual radii are capped by Config.Galaxy so
-- upgrades can never make bodies collide.

export type Cost = { credits: number, materials: { [string]: number } }

export type LevelDef = {
	name: string,
	income: number, -- Credits per second (stars and planets)
	moonBonus: number, -- moons only: fraction added to the parent planet's income
	planetSlots: number, -- stars only: orbital slots this level supports
	moonSlots: number, -- planets only: moon slots this level supports
	radius: number, -- visual radius in studs
	upgradeCost: Cost?, -- cost to reach this level; nil for level 1
}

export type CelestialDef = {
	id: string,
	displayName: string,
	kind: "star" | "planet" | "moon",
	enabled: boolean,
	levels: { LevelDef },
	appearances: { string }, -- appearance variant ids; the first is the default
}

local function level(name: string, fields: { [string]: any }): LevelDef
	return {
		name = name,
		income = fields.income or 0,
		moonBonus = fields.moonBonus or 0,
		planetSlots = fields.planetSlots or 0,
		moonSlots = fields.moonSlots or 0,
		radius = fields.radius,
		upgradeCost = fields.upgradeCost,
	}
end

local ORDER: { string } =
	{ "StarterStar", "RockyPlanet", "IcePlanet", "CrystalPlanet", "SmallMoon" }

local BY_ID: { [string]: CelestialDef } = {
	StarterStar = {
		id = "StarterStar",
		displayName = "Starter Star",
		kind = "star",
		enabled = true,
		appearances = { "Golden" },
		levels = {
			level("Young Star", { income = 1, planetSlots = 2, radius = 18 }),
			level("Bright Star", {
				income = 2.5,
				planetSlots = 3,
				radius = 23,
				upgradeCost = { credits = 400, materials = { Iron = 40, Silicate = 40 } },
			}),
			level("Radiant Star", {
				income = 5,
				planetSlots = 4,
				radius = 28,
				upgradeCost = { credits = 2500, materials = { Iron = 150, Silicate = 150 } },
			}),
		},
	},
	RockyPlanet = {
		id = "RockyPlanet",
		displayName = "Rocky Planet",
		kind = "planet",
		enabled = true,
		appearances = { "Basalt" },
		levels = {
			level("Barren", { income = 0.5, moonSlots = 1, radius = 4 }),
			level("Developing", {
				income = 1.2,
				moonSlots = 1,
				radius = 5,
				upgradeCost = { credits = 150, materials = { Iron = 20, Silicate = 30 } },
			}),
			level("Established", {
				income = 2.5,
				moonSlots = 2,
				radius = 6,
				upgradeCost = { credits = 900, materials = { Iron = 60, Silicate = 80 } },
			}),
			level("Advanced", {
				income = 5,
				moonSlots = 2,
				radius = 7,
				upgradeCost = { credits = 4000, materials = { Iron = 200, Silicate = 250 } },
			}),
		},
	},
	IcePlanet = {
		id = "IcePlanet",
		displayName = "Ice Planet",
		kind = "planet",
		enabled = false,
		appearances = { "Glacier" },
		levels = {
			level("Frozen", { income = 0.8, moonSlots = 1, radius = 4.5 }),
			level("Thawing", {
				income = 1.8,
				moonSlots = 1,
				radius = 5.5,
				upgradeCost = { credits = 300, materials = { Ice = 40, Silicate = 20 } },
			}),
			level("Glacial", {
				income = 3.5,
				moonSlots = 2,
				radius = 6.5,
				upgradeCost = { credits = 1500, materials = { Ice = 120, Iron = 40 } },
			}),
		},
	},
	CrystalPlanet = {
		id = "CrystalPlanet",
		displayName = "Crystal Planet",
		kind = "planet",
		enabled = false,
		appearances = { "Amethyst" },
		levels = {
			level("Seeded", { income = 1.5, moonSlots = 1, radius = 5 }),
			level("Faceted", {
				income = 3.5,
				moonSlots = 2,
				radius = 6,
				upgradeCost = { credits = 2500, materials = { Crystal = 60, Silicate = 60 } },
			}),
			level("Prismatic", {
				income = 7,
				moonSlots = 2,
				radius = 7,
				upgradeCost = { credits = 9000, materials = { Crystal = 180, Iron = 100 } },
			}),
		},
	},
	SmallMoon = {
		id = "SmallMoon",
		displayName = "Small Moon",
		kind = "moon",
		enabled = true,
		appearances = { "Dusty" },
		levels = {
			level("Pebble", { moonBonus = 0.10, radius = 1.5 }),
			level("Cratered", {
				moonBonus = 0.15,
				radius = 1.8,
				upgradeCost = { credits = 200, materials = { Iron = 15, Silicate = 20 } },
			}),
			level("Luminous", {
				moonBonus = 0.25,
				radius = 2,
				upgradeCost = { credits = 1200, materials = { Iron = 60, Silicate = 60 } },
			}),
		},
	},
}

return {
	ORDER = ORDER,
	BY_ID = BY_ID,
}
