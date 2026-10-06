--!strict
-- The planet catalog: 28 planet types in six rarities. Every planet a player
-- has is an individually owned instance (profile.planets) hatched from an
-- egg (Config.Eggs) at their hangar, or migrated from before planets were
-- owned. A planet sits in the player's inventory or in one orbit of one of
-- their stars; only planets in orbit produce Stardust.
--
-- Odds: every planet type has an exact integer weight out of WEIGHT_TOTAL
-- (its rarity's share split evenly among the rarity's types). Display values
-- are rounded only when shown.
--
-- Hatch time by rarity: round(10 x 180^(rarityIndex / 5)) seconds, index 0
-- (Common) to 5 (Interstellar), rounded up to the next HATCH_ROUND (30 s):
-- 30 s, 30 s, 90 s, 240 s, 660 s, 1,800 s.
--
-- Levels 1 to MAX_LEVEL: each level adds LEVEL_INCOME_STEP of the base
-- income (x3 at level 5) and grows the planet by LEVEL_SIZE_STEP; level
-- L -> L + 1 costs UPGRADE_COST[rarity] x UPGRADE_GROWTH^(L - 1).
--
-- Looks: `features` pick the shapes that make each type recognisable (see
-- the client's Fx/PlanetLook); rarer types combine more of them.
-- Logic/ConfigCheck validates this table.

export type Rarity = "Common" | "Uncommon" | "Rare" | "Epic" | "Legendary" | "Interstellar"

export type RarityDef = {
	id: Rarity,
	displayName: string,
	index: number, -- 0 (Common) to 5 (Interstellar)
	weight: number, -- out of WEIGHT_TOTAL, for the whole rarity
	color: string, -- labels, glows and hatch effects
	hatchSeconds: number,
}

export type PlanetTypeDef = {
	id: string,
	displayName: string,
	rarity: Rarity,
	weight: number, -- out of WEIGHT_TOTAL
	income: number, -- Stardust per second at level 1
	radius: number, -- studs at level 1; at most Config.Galaxy.PLANET_MAX_RADIUS
	color: string,
	accent: string,
	material: string, -- Enum.Material name of the surface
	features: { string },
	description: string,
}

local WEIGHT_TOTAL = 1200000
local HATCH_ROUND = 30 -- hatch times are whole multiples of this

local RARITY_ORDER: { Rarity } =
	{ "Common", "Uncommon", "Rare", "Epic", "Legendary", "Interstellar" }

local RARITY_SPECS: { [Rarity]: { name: string, weight: number, color: string } } = {
	Common = { name = "Common", weight = 600000, color = "#B8C2CC" }, -- 50%
	Uncommon = { name = "Uncommon", weight = 336000, color = "#5CFF8A" }, -- 28%
	Rare = { name = "Rare", weight = 168000, color = "#3FA9F5" }, -- 14%
	Epic = { name = "Epic", weight = 60000, color = "#B06BFF" }, -- 5%
	Legendary = { name = "Legendary", weight = 24000, color = "#FFB020" }, -- 2%
	Interstellar = { name = "Interstellar", weight = 12000, color = "#FF4FD8" }, -- 1%
}

local RARITIES: { [string]: RarityDef } = {}
for index: number, id: Rarity in RARITY_ORDER do
	local spec = RARITY_SPECS[id]
	RARITIES[id] = {
		id = id,
		displayName = spec.name,
		index = index - 1,
		weight = spec.weight,
		color = spec.color,
		hatchSeconds = math.ceil(math.floor(10 * 180 ^ ((index - 1) / 5) + 0.5) / HATCH_ROUND)
			* HATCH_ROUND,
	}
end

type Spec = {
	name: string,
	income: number,
	radius: number,
	color: string,
	accent: string,
	material: string,
	features: { string },
	description: string,
}

-- By rarity, in display order.
local SPECS: { [Rarity]: { { id: string, spec: Spec } } } = {
	Common = {
		{
			id = "Basalt",
			spec = {
				name = "Basalt World",
				income = 2,
				radius = 3.6,
				color = "#5A5A62",
				accent = "#2E2E34",
				material = "Basalt",
				features = { "patches" },
				description = "Dark volcanic rock, pocked with old craters.",
			},
		},
		{
			id = "Desert",
			spec = {
				name = "Dune World",
				income = 4,
				radius = 3.8,
				color = "#D9B26A",
				accent = "#B8894A",
				material = "Sand",
				features = { "bands" },
				description = "Endless dunes in sweeping stripes.",
			},
		},
		{
			id = "Moss",
			spec = {
				name = "Moss World",
				income = 5,
				radius = 3.8,
				color = "#5E8C3A",
				accent = "#3F6B2A",
				material = "Grass",
				features = { "patches", "atmosphere" },
				description = "Soft green moss under a misty sky.",
			},
		},
		{
			id = "Rust",
			spec = {
				name = "Rust World",
				income = 6,
				radius = 3.9,
				color = "#A4502C",
				accent = "#5E2A16",
				material = "CorrodedMetal",
				features = { "patches", "bands" },
				description = "Iron plains rusted deep red.",
			},
		},
	},
	Uncommon = {
		{
			id = "StormClouds",
			spec = {
				name = "Storm World",
				income = 12,
				radius = 4.2,
				color = "#5C6E8A",
				accent = "#E3EAF5",
				material = "SmoothPlastic",
				features = { "clouds", "bands" },
				description = "Wrapped in churning grey storm bands.",
			},
		},
		{
			id = "Coral",
			spec = {
				name = "Coral Reef World",
				income = 14,
				radius = 4.2,
				color = "#2F9FB5",
				accent = "#FF7A8A",
				material = "SmoothPlastic",
				features = { "patches", "atmosphere" },
				description = "Warm shallow seas full of coral reefs.",
			},
		},
		{
			id = "CopperCanyon",
			spec = {
				name = "Copper Canyons",
				income = 16,
				radius = 4.3,
				color = "#B8693A",
				accent = "#E8A36A",
				material = "Slate",
				features = { "bands", "cracks" },
				description = "Deep copper canyons carved by ancient rivers.",
			},
		},
		{
			id = "GlowFungi",
			spec = {
				name = "Fungal Glow World",
				income = 18,
				radius = 4.3,
				color = "#3A2F4F",
				accent = "#9CFF6B",
				material = "Grass",
				features = { "glowpatches", "atmosphere" },
				description = "Forests of glowing mushrooms light the dark.",
			},
		},
	},
	Rare = {
		{
			id = "ObsidianLava",
			spec = {
				name = "Obsidian Lava World",
				income = 35,
				radius = 4.6,
				color = "#1C1A22",
				accent = "#FF5A1F",
				material = "Basalt",
				features = { "glowcracks", "embers" },
				description = "Black glass crust split by rivers of lava.",
			},
		},
		{
			id = "Aurora",
			spec = {
				name = "Aurora World",
				income = 40,
				radius = 4.6,
				color = "#2A3F6E",
				accent = "#6BFFB8",
				material = "Glacier",
				features = { "aurora", "atmosphere" },
				description = "Icy plains under dancing aurora curtains.",
			},
		},
		{
			id = "Geode",
			spec = {
				name = "Giant Geode World",
				income = 45,
				radius = 4.6,
				color = "#6B5A7A",
				accent = "#C88CFF",
				material = "Slate",
				features = { "spikes" },
				description = "Huge amethyst crystals burst from its crust.",
			},
		},
		{
			id = "MagneticRings",
			spec = {
				name = "Magnetic Ring World",
				income = 50,
				radius = 4.7,
				color = "#4A5560",
				accent = "#5FE3FF",
				material = "Metal",
				features = { "ring", "ring2" },
				description = "Crossed rings held up by a giant magnetic field.",
			},
		},
		{
			id = "Bioluminescent",
			spec = {
				name = "Bioluminescent Ocean",
				income = 55,
				radius = 4.7,
				color = "#123A5A",
				accent = "#3FFFD0",
				material = "SmoothPlastic",
				features = { "glowpatches", "clouds" },
				description = "A deep ocean alive with glowing creatures.",
			},
		},
		{
			id = "FracturedQuartz",
			spec = {
				name = "Fractured Quartz World",
				income = 60,
				radius = 4.8,
				color = "#D8D4E8",
				accent = "#FFFFFF",
				material = "Glass",
				features = { "shards", "spikes" },
				description = "A cracked quartz globe catching every light.",
			},
		},
	},
	Epic = {
		{
			id = "FloatingIslands",
			spec = {
				name = "Floating Islands",
				income = 120,
				radius = 5.0,
				color = "#4F9D5B",
				accent = "#8C6A44",
				material = "Grass",
				features = { "islands", "atmosphere" },
				description = "Green islands drift free around its core.",
			},
		},
		{
			id = "Mechanical",
			spec = {
				name = "Mechanical World",
				income = 140,
				radius = 5.0,
				color = "#7A8090",
				accent = "#FFB020",
				material = "DiamondPlate",
				features = { "gears", "glowcracks" },
				description = "A machine the size of a planet, still running.",
			},
		},
		{
			id = "PlasmaStorm",
			spec = {
				name = "Plasma Storm World",
				income = 160,
				radius = 5.1,
				color = "#3B1A5A",
				accent = "#FF4FD8",
				material = "SmoothPlastic",
				features = { "clouds", "glowcracks", "embers" },
				description = "Pink plasma lightning races through its storms.",
			},
		},
		{
			id = "PrismaticOcean",
			spec = {
				name = "Prismatic Ocean",
				income = 180,
				radius = 5.1,
				color = "#3A7BFF",
				accent = "#FFFFFF",
				material = "Glass",
				features = { "prism", "atmosphere" },
				description = "Seas that split starlight into rainbows.",
			},
		},
		{
			id = "Shattered",
			spec = {
				name = "Shattered World",
				income = 200,
				radius = 5.2,
				color = "#8A6E5A",
				accent = "#FF7A3D",
				material = "Slate",
				features = { "shards", "core" },
				description = "Broken plates drift around its burning heart.",
			},
		},
		{
			id = "Eclipse",
			spec = {
				name = "Eclipse World",
				income = 220,
				radius = 5.2,
				color = "#101018",
				accent = "#FFE6A3",
				material = "SmoothPlastic",
				features = { "eclipse" },
				description = "Forever eclipsed, crowned by a blazing halo.",
			},
		},
	},
	Legendary = {
		{
			id = "PhoenixCore",
			spec = {
				name = "Phoenix Core",
				income = 480,
				radius = 5.5,
				color = "#FF7A1F",
				accent = "#FFE16B",
				material = "CrackedLava",
				features = { "core", "glowcracks", "embers" },
				description = "A reborn world with a fire that never dies.",
			},
		},
		{
			id = "CelestialGarden",
			spec = {
				name = "Celestial Garden",
				income = 520,
				radius = 5.5,
				color = "#6BCF7F",
				accent = "#FF9EC4",
				material = "Grass",
				features = { "islands", "glowpatches", "atmosphere" },
				description = "Blossoming garden islands among the stars.",
			},
		},
		{
			id = "CosmicClockwork",
			spec = {
				name = "Cosmic Clockwork",
				income = 560,
				radius = 5.6,
				color = "#C9A44A",
				accent = "#FFE6A3",
				material = "Metal",
				features = { "gears", "ring" },
				description = "Golden gears that keep the cosmos on time.",
			},
		},
		{
			id = "NebulaShell",
			spec = {
				name = "Nebula Shell",
				income = 600,
				radius = 5.6,
				color = "#7A5CFF",
				accent = "#FF6EC8",
				material = "Glass",
				features = { "core", "clouds" },
				description = "A glass shell holding a swirling nebula.",
			},
		},
	},
	Interstellar = {
		{
			id = "DiamondCrystal",
			spec = {
				name = "Jagged Diamond",
				income = 1100,
				radius = 5.8,
				color = "#E8F6FF",
				accent = "#FFFFFF",
				material = "Glass",
				features = { "spikes", "shards" },
				description = "A colossal diamond, jagged and flawless.",
			},
		},
		{
			id = "Singularity",
			spec = {
				name = "Contained Singularity",
				income = 1250,
				radius = 5.8,
				color = "#050208",
				accent = "#B06BFF",
				material = "SmoothPlastic",
				features = { "singularity" },
				description = "A black hole held in a cage of light.",
			},
		},
		{
			id = "PulsarLattice",
			spec = {
				name = "Pulsar Lattice",
				income = 1400,
				radius = 5.8,
				color = "#1A2A4A",
				accent = "#5FE3FF",
				material = "Metal",
				features = { "lattice", "core" },
				description = "Beams of a captured pulsar crossing its core.",
			},
		},
		{
			id = "DimensionalRift",
			spec = {
				name = "Dimensional Rift",
				income = 1600,
				radius = 5.8,
				color = "#120A1A",
				accent = "#FF3BD8",
				material = "Slate",
				features = { "rift", "shards" },
				description = "A tear in space, glowing from the other side.",
			},
		},
	},
}

local ORDER: { string } = {}
local BY_ID: { [string]: PlanetTypeDef } = {}
local BY_RARITY: { [string]: { string } } = {}
for _, rarity: Rarity in RARITY_ORDER do
	local list = SPECS[rarity]
	BY_RARITY[rarity] = {}
	for _, entry in list do
		local spec = entry.spec
		table.insert(ORDER, entry.id)
		table.insert(BY_RARITY[rarity], entry.id)
		BY_ID[entry.id] = {
			id = entry.id,
			displayName = spec.name,
			rarity = rarity,
			weight = RARITIES[rarity].weight // #list,
			income = spec.income,
			radius = spec.radius,
			color = spec.color,
			accent = spec.accent,
			material = spec.material,
			features = spec.features,
			description = spec.description,
		}
	end
end

return {
	WEIGHT_TOTAL = WEIGHT_TOTAL,
	RARITY_ORDER = RARITY_ORDER,
	RARITIES = RARITIES,
	ORDER = ORDER,
	BY_ID = BY_ID,
	BY_RARITY = BY_RARITY,
	MAX_LEVEL = 5,
	LEVEL_INCOME_STEP = 0.5, -- share of base income added per level
	LEVEL_SIZE_STEP = 0.035, -- share of radius added per level (+14% at level 5)
	-- Level 1 -> 2 price by rarity; each level after costs UPGRADE_GROWTH x more.
	UPGRADE_COST = {
		Common = 300,
		Uncommon = 1000,
		Rare = 4000,
		Epic = 15000,
		Legendary = 60000,
		Interstellar = 250000,
	} :: { [string]: number },
	UPGRADE_GROWTH = 1.8,
	-- Planets from before the egg system (one per orbit, bought by tier),
	-- turned into these catalog types by the save migration (version 15).
	-- Each keeps its level, and makes at least as much as it did.
	LEGACY = {
		Barren = "Basalt",
		Molten = "Rust",
		Desert = "CopperCanyon",
		Ocean = "Bioluminescent",
		Terran = "FloatingIslands",
		IceGiant = "Shattered",
		GasGiant = "NebulaShell",
		Crystal = "DiamondCrystal",
	} :: { [string]: string },
	LEGACY_FALLBACK = "Basalt", -- for an old planet id that's no longer known

	-- Selling a planet (from the inventory, never one in orbit or locked)
	-- pays SELL_VALUE[rarity] plus SELL_LEVEL_REFUND of the Stardust spent
	-- levelling it. Values are kept low enough that a mystery egg's expected
	-- sale value stays under its price (ConfigCheck), so buying eggs to sell
	-- them never pays.
	SELL_VALUE = {
		Common = 40,
		Uncommon = 100,
		Rare = 300,
		Epic = 1000,
		Legendary = 3000,
		Interstellar = 10000,
	} :: { [string]: number },
	SELL_LEVEL_REFUND = 0.5,
	-- Rarities a player may set to sell automatically when they hatch.
	AUTO_SELL_RARITIES = { "Common", "Uncommon", "Rare", "Epic" } :: { string },
	-- Planets a player may own at once; a planet hatching past it is sold.
	MAX_PLANETS = 200,
}
