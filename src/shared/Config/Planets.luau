--!strict
-- The planet catalog: 42 planet types in six rarities. Every planet a player
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
-- (Common) to 5 (Interstellar), rounded up to the next HATCH_ROUND (10 s):
-- 10 s, 30 s, 80 s, 230 s, 640 s, 1,800 s.
--
-- Income (economy v2): a planet earns a share of the star it orbits. Its
-- `income` is what it makes on a star producing exactly 100/s, so its
-- coefficient is income / 100 (b), and in orbit it makes
--   host star's own rate x b x tier multiplier x (1 + LEVEL_INCOME_STEP x (L - 1))
-- (the host's rate before planets, trails, the Refinery or passes). Within
-- a rarity the types' incomes are evenly spaced, in catalog order.
--
-- Levels 1 to MAX_LEVEL: each level adds LEVEL_INCOME_STEP (x2 at level 5)
-- and grows the planet by LEVEL_SIZE_STEP; level L -> L + 1 costs the
-- current egg price x UPGRADE_COST[rarity] x UPGRADE_GROWTH^(L - 1), so
-- planet upgrades keep pace with the galaxy.
--
-- Tiers (TIERS): every planet also has a tier from 1 to 7, rolled with its
-- egg, that multiplies its income (x1 to x2.2) and adds effects.
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
	income: number, -- Stardust per second at level 1 on a star making 100/s (b x 100)
	radius: number, -- studs at level 1; at most Config.Galaxy.PLANET_MAX_RADIUS
	color: string,
	accent: string,
	material: string, -- Enum.Material name of the surface
	features: { string },
	description: string,
}

local WEIGHT_TOTAL = 3600000
local HATCH_ROUND = 10 -- hatch times are whole multiples of this

local RARITY_ORDER: { Rarity } =
	{ "Common", "Uncommon", "Rare", "Epic", "Legendary", "Interstellar" }

local RARITY_SPECS: { [Rarity]: { name: string, weight: number, color: string } } = {
	Common = { name = "Common", weight = 1641600, color = "#B8C2CC" }, -- 45.6%
	Uncommon = { name = "Uncommon", weight = 921600, color = "#5CFF8A" }, -- 25.6%
	Rare = { name = "Rare", weight = 460800, color = "#3FA9F5" }, -- 12.8%
	Epic = { name = "Epic", weight = 360000, color = "#B06BFF" }, -- 10%
	Legendary = { name = "Legendary", weight = 144000, color = "#FFB020" }, -- 4%
	Interstellar = { name = "Interstellar", weight = 72000, color = "#FF4FD8" }, -- 2%
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
				income = 0.5,
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
				income = 0.56,
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
				income = 0.62,
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
				income = 0.68,
				radius = 3.9,
				color = "#A4502C",
				accent = "#5E2A16",
				material = "CorrodedMetal",
				features = { "patches", "bands" },
				description = "Iron plains rusted deep red.",
			},
		},
		{
			id = "IceRock",
			spec = {
				name = "Frozen Rock",
				income = 0.74,
				radius = 3.9,
				color = "#CFE6F2",
				accent = "#8FB4C8",
				material = "Ice",
				features = { "cracks" },
				description = "A small world locked under cracked ice.",
			},
		},
		{
			id = "SaltFlats",
			spec = {
				name = "Salt Flat World",
				income = 0.8,
				radius = 4.0,
				color = "#EDE6D6",
				accent = "#BFB49A",
				material = "Salt",
				features = { "bands", "patches" },
				description = "Blinding white salt plains, crusted in rings.",
			},
		},
	},
	Uncommon = {
		{
			id = "StormClouds",
			spec = {
				name = "Storm World",
				income = 1.2,
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
				income = 1.28,
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
				income = 1.36,
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
				income = 1.44,
				radius = 4.3,
				color = "#3A2F4F",
				accent = "#9CFF6B",
				material = "Grass",
				features = { "glowpatches", "atmosphere" },
				description = "Forests of glowing mushrooms light the dark.",
			},
		},
		{
			id = "Jungle",
			spec = {
				name = "Jungle World",
				income = 1.52,
				radius = 4.4,
				color = "#2E7A3A",
				accent = "#1E5228",
				material = "Grass",
				features = { "patches", "clouds" },
				description = "Steaming rainforest under rolling clouds.",
			},
		},
		{
			id = "AshVolcano",
			spec = {
				name = "Ash Volcano World",
				income = 1.6,
				radius = 4.4,
				color = "#5A4A44",
				accent = "#FF6A2E",
				material = "Basalt",
				features = { "glowcracks", "clouds" },
				description = "Volcanoes glowing through a sky of ash.",
			},
		},
	},
	Rare = {
		{
			id = "ObsidianLava",
			spec = {
				name = "Obsidian Lava World",
				income = 2.4,
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
				income = 2.525,
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
				income = 2.65,
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
				income = 2.775,
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
				income = 2.9,
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
				income = 3.025,
				radius = 4.8,
				color = "#D8D4E8",
				accent = "#FFFFFF",
				material = "Glass",
				features = { "shards", "spikes" },
				description = "A cracked quartz globe catching every light.",
			},
		},
		{
			id = "ToxicSwamp",
			spec = {
				name = "Toxic Swamp World",
				income = 3.15,
				radius = 4.8,
				color = "#6A8A2A",
				accent = "#B8FF3A",
				material = "Mud",
				features = { "glowpatches", "atmosphere" },
				description = "Bubbling green bogs under a sickly haze.",
			},
		},
		{
			id = "RingedGiant",
			spec = {
				name = "Ringed Gas Giant",
				income = 3.275,
				radius = 4.9,
				color = "#D8B07A",
				accent = "#A8784A",
				material = "SmoothPlastic",
				features = { "bands", "ring" },
				description = "Banded storms circled by a wide dusty ring.",
			},
		},
		{
			id = "Frostfire",
			spec = {
				name = "Frostfire World",
				income = 3.4,
				radius = 4.9,
				color = "#9FD8FF",
				accent = "#FF7A3D",
				material = "Glacier",
				features = { "glowcracks", "aurora" },
				description = "Ice that burns: fire glowing up through glaciers.",
			},
		},
	},
	Epic = {
		{
			id = "FloatingIslands",
			spec = {
				name = "Floating Islands",
				income = 5,
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
				income = 5.25,
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
				income = 5.5,
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
				income = 5.75,
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
				income = 6,
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
				income = 6.25,
				radius = 5.2,
				color = "#101018",
				accent = "#FFE6A3",
				material = "SmoothPlastic",
				features = { "eclipse" },
				description = "Forever eclipsed, crowned by a blazing halo.",
			},
		},
		{
			id = "StarfieldOcean",
			spec = {
				name = "Starfield Ocean",
				income = 6.5,
				radius = 5.2,
				color = "#1A2A6A",
				accent = "#FFE6A3",
				material = "Glass",
				features = { "glowpatches", "clouds", "atmosphere" },
				description = "A night-black sea that sparkles like the sky.",
			},
		},
		{
			id = "CrystalHive",
			spec = {
				name = "Crystal Hive",
				income = 6.75,
				radius = 5.3,
				color = "#B06BFF",
				accent = "#FFD36B",
				material = "Glass",
				features = { "spikes", "glowpatches" },
				description = "Honeycombed with glowing amethyst chambers.",
			},
		},
		{
			id = "StormForge",
			spec = {
				name = "Storm Forge",
				income = 7,
				radius = 5.3,
				color = "#3A3F4E",
				accent = "#5FE3FF",
				material = "DiamondPlate",
				features = { "gears", "clouds", "glowcracks" },
				description = "A machine world powered by its own lightning.",
			},
		},
	},
	Legendary = {
		{
			id = "PhoenixCore",
			spec = {
				name = "Phoenix Core",
				income = 10,
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
				income = 10.6,
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
				income = 11.2,
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
				income = 11.8,
				radius = 5.6,
				color = "#7A5CFF",
				accent = "#FF6EC8",
				material = "Glass",
				features = { "core", "clouds" },
				description = "A glass shell holding a swirling nebula.",
			},
		},
		{
			id = "SolarCrown",
			spec = {
				name = "Solar Crown",
				income = 12.4,
				radius = 5.7,
				color = "#FFB020",
				accent = "#FFF4C2",
				material = "SmoothPlastic",
				features = { "core", "ring", "embers" },
				description = "A tiny sun of its own, wearing a ring of fire.",
			},
		},
		{
			id = "VoidBloom",
			spec = {
				name = "Void Bloom",
				income = 13,
				radius = 5.7,
				color = "#2A0F4A",
				accent = "#FF4FD8",
				material = "Slate",
				features = { "islands", "glowpatches" },
				description = "Islands of pink light floating over the void.",
			},
		},
	},
	Interstellar = {
		{
			id = "DiamondCrystal",
			spec = {
				name = "Jagged Diamond",
				income = 16,
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
				income = 16.8,
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
				income = 17.6,
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
				income = 18.4,
				radius = 5.8,
				color = "#120A1A",
				accent = "#FF3BD8",
				material = "Slate",
				features = { "rift", "shards" },
				description = "A tear in space, glowing from the other side.",
			},
		},
		{
			id = "PocketGalaxy",
			spec = {
				name = "Pocket Galaxy",
				income = 19.2,
				radius = 5.9,
				color = "#140A24",
				accent = "#B06BFF",
				material = "Glass",
				features = { "singularity", "ring2" },
				description = "A whole galaxy turning inside a glass sphere.",
			},
		},
		{
			id = "ChronoSphere",
			spec = {
				name = "Chrono Sphere",
				income = 20,
				radius = 5.9,
				color = "#E8E0FF",
				accent = "#5FE3FF",
				material = "Metal",
				features = { "gears", "lattice", "core" },
				description = "The clockwork that keeps time for the universe.",
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
	HATCH_ROUND = HATCH_ROUND,
	-- Tiers 1 to 7, rolled with the egg (Config.Eggs odds): each multiplies
	-- the planet's income (and nothing else; selling pays the rarity's value).
	-- The rarity sets the base range (every planet of a rarity makes more
	-- than every planet of the rarity below, ConfigCheck), the tier scales
	-- it up to x10. `effects` name the looks Fx/TierFx adds, cooler each tier.
	TIERS = {
		{ name = "Plain", multiplier = 1, color = "#B8C2CC", effects = {} },
		{ name = "Glowing", multiplier = 1.12, color = "#9FD8FF", effects = { "glow" } },
		{
			name = "Sparkling",
			multiplier = 1.25,
			color = "#5CFF8A",
			effects = { "glow", "sparkles" },
		},
		{
			name = "Ringed",
			multiplier = 1.4,
			color = "#3FA9F5",
			effects = { "glow", "sparkles", "halo" },
		},
		{
			name = "Radiant",
			multiplier = 1.6,
			color = "#B06BFF",
			effects = { "glow", "sparkles", "halo", "aura" },
		},
		{
			name = "Cosmic",
			multiplier = 1.85,
			color = "#FFB020",
			effects = { "glow", "sparkles", "halo", "aura", "motes" },
		},
		{
			name = "Celestial",
			multiplier = 2.2,
			color = "#FF4FD8",
			effects = { "glow", "sparkles", "halo", "aura", "motes", "rainbow" },
		},
	} :: { { name: string, multiplier: number, color: string, effects: { string } } },
	MAX_LEVEL = 5,
	LEVEL_INCOME_STEP = 0.25, -- share of base income added per level
	LEVEL_SIZE_STEP = 0.035, -- share of radius added per level (+14% at level 5)
	-- Level 1 -> 2 price as a share of the current egg price, by rarity; each
	-- level after costs UPGRADE_GROWTH x more.
	UPGRADE_COST = {
		Common = 0.1,
		Uncommon = 0.15,
		Rare = 0.22,
		Epic = 0.32,
		Legendary = 0.45,
		Interstellar = 0.6,
	} :: { [string]: number },
	UPGRADE_GROWTH = 1.6,
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
	-- pays SELL_FRACTION[rarity] of what its egg roll actually cost plus
	-- SELL_LEVEL_REFUND of the Stardust actually spent levelling it. Tier
	-- never adds salvage. A mystery egg's expected sale value stays far under
	-- its price (ConfigCheck), so buying eggs to sell them never pays.
	-- Planets from before economy v2 keep their old fixed value (`legacy`).
	SELL_FRACTION = {
		Common = 0.02,
		Uncommon = 0.03,
		Rare = 0.05,
		Epic = 0.08,
		Legendary = 0.12,
		Interstellar = 0.2,
	} :: { [string]: number },
	SELL_LEVEL_REFUND = 0.25,
	-- Fixed sale values from before economy v2: a planet (or an egg still
	-- unhatched) from then sells for this once instead (ProfileSchema v21).
	LEGACY_SELL_VALUE = {
		Common = 40,
		Uncommon = 100,
		Rare = 300,
		Epic = 1000,
		Legendary = 3000,
		Interstellar = 10000,
	} :: { [string]: number },
	-- Rarities a player may set to sell automatically when they hatch.
	AUTO_SELL_RARITIES = { "Common", "Uncommon", "Rare", "Epic" } :: { string },
	-- Planets a player may own at once. Eggs kept, incubating or on the lab's
	-- pedestal reserve a place, so rolls pause when it's full: a hatch is
	-- never sold or lost for lack of room.
	MAX_PLANETS = 200,
}
