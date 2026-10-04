--!strict
-- The star tycoon's stars. Eight types form a ladder from Brown Dwarf to
-- Black Hole. A new star of a type needs a star of the previous type already
-- in your galaxy; any star can also evolve into the next type in place,
-- keeping its level and planets.
--
-- Every type shares the LEVELS table: levels multiply the type's base
-- production and open orbit slots for planets (Config.Planets). A star's
-- tier is also the highest planet tier it can hold.
--
-- Saved per star: id, position, type, level, planets by slot. Everything
-- else is derived from this table. Logic/ConfigCheck validates it.

export type StarTypeDef = {
	id: string,
	displayName: string,
	tier: number, -- position on the ladder, 1 = Brown Dwarf
	enabled: boolean,
	cost: number, -- Stardust for a new star of this type (before PRICE_GROWTH); also the evolve price
	income: number, -- Stardust per second at level 1
	radius: number, -- studs at level 1; at most Config.Galaxy.STAR_MAX_RADIUS / 1.2
	color: string,
	light: string,
	description: string,
}

export type LevelDef = {
	incomeMultiplier: number,
	slots: number, -- open planet orbit slots
	upgradeShare: number?, -- upgrade price as a share of the type's cost; nil for level 1
	radiusScale: number,
}

-- Orbit slots shared by every star: radius from the star's centre, period
-- in seconds, and the tilt of the orbit in degrees.
export type SlotDef = { orbit: number, period: number, tilt: number }

local ORDER: { string } = {
	"BrownDwarf",
	"RedDwarf",
	"YellowDwarf",
	"WhiteDwarf",
	"RedGiant",
	"BlueGiant",
	"RedSupergiant",
	"BlackHole",
}

local function star(
	id: string,
	tier: number,
	name: string,
	cost: number,
	income: number,
	radius: number,
	color: string,
	light: string,
	description: string
): StarTypeDef
	return {
		id = id,
		displayName = name,
		tier = tier,
		enabled = true,
		cost = cost,
		income = income,
		radius = radius,
		color = color,
		light = light,
		description = description,
	}
end

local BY_ID: { [string]: StarTypeDef } = {
	BrownDwarf = star(
		"BrownDwarf",
		1,
		"Brown Dwarf",
		100,
		1,
		10,
		"#8A5A3C",
		"#C98A5E",
		"A failed star, glowing faintly."
	),
	RedDwarf = star(
		"RedDwarf",
		2,
		"Red Dwarf",
		600,
		4,
		12,
		"#E2563B",
		"#FF7A5C",
		"Small, cool and long-lived."
	),
	YellowDwarf = star(
		"YellowDwarf",
		3,
		"Yellow Dwarf",
		2500,
		12,
		15,
		"#FFD36B",
		"#FFE6A3",
		"A sun like ours."
	),
	WhiteDwarf = star(
		"WhiteDwarf",
		4,
		"White Dwarf",
		8000,
		30,
		11,
		"#F2F6FF",
		"#DDE8FF",
		"A dense, white-hot ember."
	),
	RedGiant = star(
		"RedGiant",
		5,
		"Red Giant",
		25000,
		75,
		20,
		"#FF6B3D",
		"#FFA07A",
		"Swollen and blazing red."
	),
	BlueGiant = star(
		"BlueGiant",
		6,
		"Blue Giant",
		75000,
		180,
		21,
		"#6FA8FF",
		"#A9CCFF",
		"Hot, bright and fierce."
	),
	RedSupergiant = star(
		"RedSupergiant",
		7,
		"Red Supergiant",
		200000,
		420,
		24,
		"#FF4A2E",
		"#FF8A66",
		"One of the largest stars there is."
	),
	BlackHole = star(
		"BlackHole",
		8,
		"Black Hole",
		600000,
		1000,
		14,
		"#05020A",
		"#B67CFF",
		"Light can't escape. Stardust can."
	),
}

local LEVELS: { LevelDef } = {
	{ incomeMultiplier = 1, slots = 1, upgradeShare = nil, radiusScale = 1 },
	{ incomeMultiplier = 2, slots = 2, upgradeShare = 1, radiusScale = 1.05 },
	{ incomeMultiplier = 3.5, slots = 3, upgradeShare = 2, radiusScale = 1.1 },
	{ incomeMultiplier = 5.5, slots = 4, upgradeShare = 4, radiusScale = 1.15 },
	{ incomeMultiplier = 8, slots = 4, upgradeShare = 8, radiusScale = 1.2 },
}

local SLOTS: { SlotDef } = {
	{ orbit = 52, period = 18, tilt = 4 },
	{ orbit = 96, period = 30, tilt = -7 },
	{ orbit = 140, period = 44, tilt = 10 },
	{ orbit = 184, period = 62, tilt = -5 },
}

return {
	ORDER = ORDER,
	BY_ID = BY_ID,
	LEVELS = LEVELS,
	SLOTS = SLOTS,
	DEFAULT_TYPE = "BrownDwarf", -- the first star; must be affordable at the start
	-- Each star you already own multiplies the price of the next one.
	PRICE_GROWTH = 1.25,
	-- Placement ghost: how far ahead of the camera it starts, and its range.
	GHOST_DISTANCE = 300,
	GHOST_MIN_DISTANCE = 60,
	GHOST_MAX_DISTANCE = 900,
	GHOST_STEP = 40, -- studs per scroll step or elevation tap
	-- How often star income is added to "uncollected".
	INCOME_TICK = 1,
	MANAGE_DISTANCE = 400, -- studs: the star's Manage prompt reach
}
