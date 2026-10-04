--!strict
-- Permanent achievements. Progress is read from the profile's stats table, so
-- an achievement is just "stat reaches goal".

export type Reward = {
	stardust: number,
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
		reward = { stardust = 100, cosmetic = "StargazerTitle" },
	},
	FirstMoon = {
		id = "FirstMoon",
		displayName = "Moonrise",
		description = "Add a moon to a planet.",
		enabled = false,
		stat = "moonsPlaced",
		goal = 1,
		reward = { stardust = 150 },
	},
	Miner100 = {
		id = "Miner100",
		displayName = "Rock Breaker",
		description = "Mine 100 asteroids.",
		enabled = true,
		stat = "asteroidsMined",
		goal = 100,
		reward = { stardust = 1000, cosmetic = "GoldenBeam" },
	},
	AdvancedWorld = {
		id = "AdvancedWorld",
		displayName = "Advanced World",
		description = "Upgrade a planet to an advanced level.",
		enabled = false,
		stat = "advancedPlanets",
		goal = 1,
		reward = { stardust = 2000 },
	},
	StarCluster = {
		id = "StarCluster",
		displayName = "Star Cluster",
		description = "Build three solar systems.",
		enabled = true,
		stat = "starsPlaced",
		goal = 3,
		reward = { stardust = 5000 },
	},
	Cartographer = {
		id = "Cartographer",
		displayName = "Cartographer",
		description = "Discover every mining field.",
		enabled = false,
		stat = "zonesDiscovered",
		goal = 4,
		reward = { stardust = 10000 },
	},
	CoolHead = {
		id = "CoolHead",
		displayName = "Cool Head",
		description = "Complete a multi-stage extraction without overheating.",
		enabled = true,
		stat = "coolExtractions",
		goal = 1,
		reward = { stardust = 3000 },
	},
	Planetfall = {
		id = "Planetfall",
		displayName = "Planetfall",
		description = "Put your first planet in orbit.",
		enabled = true,
		stat = "planetsBought",
		goal = 1,
		reward = { stardust = 300 },
	},
	StellarEvolution = {
		id = "StellarEvolution",
		displayName = "Stellar Evolution",
		description = "Evolve a star into the next type.",
		enabled = true,
		stat = "starEvolutions",
		goal = 1,
		reward = { stardust = 1500 },
	},
	Terraformer = {
		id = "Terraformer",
		displayName = "Terraformer",
		description = "Upgrade planets 5 times.",
		enabled = true,
		stat = "planetUpgrades",
		goal = 5,
		reward = { stardust = 8000 },
	},
	Worldbuilder = {
		id = "Worldbuilder",
		displayName = "Worldbuilder",
		description = "Buy 10 planets.",
		enabled = true,
		stat = "planetsBought",
		goal = 10,
		reward = { stardust = 20000 },
	},
	EventHorizon = {
		id = "EventHorizon",
		displayName = "Event Horizon",
		description = "Own a black hole.",
		enabled = true,
		stat = "blackHoles",
		goal = 1,
		reward = { stardust = 250000 },
	},
}

return {
	ORDER = ORDER,
	BY_ID = BY_ID,
}
