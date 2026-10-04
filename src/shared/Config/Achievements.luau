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
}

return {
	ORDER = ORDER,
	BY_ID = BY_ID,
}
