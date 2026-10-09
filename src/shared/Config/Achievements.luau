--!strict
-- Permanent achievements. Progress is read from the profile's stats table, so
-- an achievement is just "stat reaches goal".

-- Rewards are once per achievement: Stardust worth SIZES[size].minutes of
-- the player's reward rate R (Logic/EconomyMath.reward), at least
-- SIZES[size].minimum, plus any cosmetic or ship.
export type Size = "minor" | "major" | "capstone"

export type Reward = {
	size: Size,
	cosmetic: string?,
	ship: string?,
}

export type AchievementDef = {
	id: string,
	displayName: string,
	description: string,
	enabled: boolean,
	stat: string,
	goal: number,
	reward: Reward,
}

local ORDER: { string } = {
	"FirstLight",
	"FirstMoon",
	"Miner100",
	"AdvancedWorld",
	"StarCluster",
	"Cartographer",
	"CoolHead",
	"Planetfall",
	"StellarEvolution",
	"Terraformer",
	"Worldbuilder",
	"EventHorizon",
}

local BY_ID: { [string]: AchievementDef } = {
	FirstLight = {
		id = "FirstLight",
		displayName = "First Light",
		description = "Build your first solar system.",
		enabled = true,
		stat = "starsPlaced",
		goal = 1,
		reward = { size = "minor", cosmetic = "StargazerTitle" },
	},
	FirstMoon = {
		id = "FirstMoon",
		displayName = "Moonrise",
		description = "Add a moon to a planet.",
		enabled = false,
		stat = "moonsPlaced",
		goal = 1,
		reward = { size = "minor" },
	},
	Miner100 = {
		id = "Miner100",
		displayName = "Rock Breaker",
		description = "Mine 100 asteroids.",
		enabled = true,
		stat = "asteroidsMined",
		goal = 100,
		reward = { size = "minor", cosmetic = "GoldenBeam" },
	},
	AdvancedWorld = {
		id = "AdvancedWorld",
		displayName = "Advanced World",
		description = "Upgrade a planet to an advanced level.",
		enabled = false,
		stat = "advancedPlanets",
		goal = 1,
		reward = { size = "major" },
	},
	StarCluster = {
		id = "StarCluster",
		displayName = "Star Cluster",
		description = "Build three solar systems.",
		enabled = true,
		stat = "starsPlaced",
		goal = 3,
		reward = { size = "major" },
	},
	Cartographer = {
		id = "Cartographer",
		displayName = "Cartographer",
		description = "Discover every mining field.",
		enabled = false,
		stat = "zonesDiscovered",
		goal = 4,
		reward = { size = "major" },
	},
	CoolHead = {
		id = "CoolHead",
		displayName = "Cool Head",
		description = "Complete a multi-stage extraction without overheating.",
		enabled = true,
		stat = "coolExtractions",
		goal = 1,
		reward = { size = "major" },
	},
	Planetfall = {
		id = "Planetfall",
		displayName = "Planetfall",
		description = "Put your first planet in orbit.",
		enabled = true,
		stat = "planetsEquipped",
		goal = 1,
		reward = { size = "minor" },
	},
	StellarEvolution = {
		id = "StellarEvolution",
		displayName = "Stellar Evolution",
		description = "Evolve a star into the next type.",
		enabled = true,
		stat = "starEvolutions",
		goal = 1,
		reward = { size = "minor" },
	},
	Terraformer = {
		id = "Terraformer",
		displayName = "Terraformer",
		description = "Level up planets 5 times.",
		enabled = true,
		stat = "planetLevels",
		goal = 5,
		reward = { size = "major" },
	},
	Worldbuilder = {
		id = "Worldbuilder",
		displayName = "Worldbuilder",
		description = "Hatch 10 planets.",
		enabled = true,
		stat = "planetsHatched",
		goal = 10,
		reward = { size = "major" },
	},
	EventHorizon = {
		id = "EventHorizon",
		displayName = "Event Horizon",
		description = "Own a black hole.",
		enabled = true,
		stat = "blackHoles",
		goal = 1,
		reward = { size = "capstone" },
	},
}

return {
	SIZES = {
		minor = { minutes = 1, minimum = 60 },
		major = { minutes = 3, minimum = 180 },
		capstone = { minutes = 10, minimum = 600 },
	} :: { [string]: { minutes: number, minimum: number } },
	ORDER = ORDER,
	BY_ID = BY_ID,
}
