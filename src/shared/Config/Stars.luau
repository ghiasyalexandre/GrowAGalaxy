--!strict
-- The star tycoon. Players buy stars with Stardust, place them in their
-- region, and upgrade them. Every upgrade level that lists a planet adds that
-- planet to the star's orbit; production rises with every level.
--
-- Only id, position, type, level and appearance are saved per star: planets,
-- orbits and production are derived from the level and this table. Orbits
-- stay inside Config.Galaxy.SYSTEM_RADIUS, so placement spacing
-- (MIN_STAR_SPACING) already leaves room for a fully upgraded system.
-- Logic/ConfigCheck validates this table.

export type PlanetDef = {
	name: string,
	radius: number, -- studs
	orbit: number, -- orbit radius, studs from the star's centre
	period: number, -- seconds per orbit
	tilt: number, -- degrees, inclination of the orbit
	color: string,
	material: string, -- Enum.Material name
}

export type LevelDef = {
	income: number, -- Stardust per second at this level
	upgradeCost: number?, -- Stardust to reach this level; nil for level 1
	planet: number?, -- index into PLANETS added at this level
	starRadius: number, -- studs; at most Config.Galaxy.STAR_MAX_RADIUS
}

export type StarTypeDef = {
	id: string,
	displayName: string,
	enabled: boolean,
	cost: number, -- Stardust for the first star of this type
	color: string,
	levels: { LevelDef },
}

local PLANETS: { PlanetDef } = {
	{
		name = "Ember",
		radius = 4,
		orbit = 52,
		period = 18,
		tilt = 4,
		color = "#C8693A",
		material = "Basalt",
	},
	{
		name = "Verdant",
		radius = 5.5,
		orbit = 96,
		period = 30,
		tilt = -7,
		color = "#4F9D5B",
		material = "Grass",
	},
	{
		name = "Azure",
		radius = 6,
		orbit = 140,
		period = 44,
		tilt = 10,
		color = "#3F7FD6",
		material = "Glacier",
	},
	{
		name = "Gas Giant",
		radius = 7,
		orbit = 184,
		period = 62,
		tilt = -5,
		color = "#D9B26A",
		material = "Sand",
	},
}

local ORDER: { string } = { "YellowDwarf" }

local BY_ID: { [string]: StarTypeDef } = {
	YellowDwarf = {
		id = "YellowDwarf",
		displayName = "Yellow Star",
		enabled = true,
		cost = 100,
		color = "#FFD36B",
		levels = {
			{ income = 1, starRadius = 18 },
			{ income = 2.5, upgradeCost = 250, planet = 1, starRadius = 20 },
			{ income = 5, upgradeCost = 700, planet = 2, starRadius = 22 },
			{ income = 9, upgradeCost = 1800, planet = 3, starRadius = 25 },
			{ income = 15, upgradeCost = 4500, planet = 4, starRadius = 28 },
		},
	},
}

return {
	ORDER = ORDER,
	BY_ID = BY_ID,
	PLANETS = PLANETS,
	DEFAULT_TYPE = "YellowDwarf",
	-- Each star you already own multiplies the price of the next one.
	PRICE_GROWTH = 2.5,
	-- Placement ghost: how far ahead of the camera it starts, and its range.
	GHOST_DISTANCE = 300,
	GHOST_MIN_DISTANCE = 60,
	GHOST_MAX_DISTANCE = 900,
	GHOST_STEP = 40, -- studs per scroll step or elevation tap
	-- How often star income is added to "uncollected".
	INCOME_TICK = 1,
	MANAGE_DISTANCE = 400, -- studs: the star's Manage prompt reach
}
