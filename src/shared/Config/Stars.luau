--!strict
-- The star tycoon's stars. Eight types form a ladder from Brown Dwarf to
-- Black Hole. A new star of a type needs a star of the previous type already
-- in your galaxy.
--
-- Levels: a star levels up from 1 to its tier's max level (MAX_LEVEL_BASE at
-- tier 1, MAX_LEVEL_STEP more per tier: 4, 6, 8 ... always even). Each level
-- multiplies the type's base production. At max level it can evolve into the
-- next type in place: it keeps its planets and starts again at level 1.
--
-- Orbits: each type has its own number of orbital slots (`orbits`, never
-- more than 9, never fewer than the type before); evolving a star opens its
-- next type's slots. Planets are owned separately (profile.planets) and
-- equipped into those slots; evolving never grants planets.
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
	orbits: number, -- planet slots (1..9, nondecreasing up the ladder)
	radius: number, -- studs at level 1; at most Config.Galaxy.STAR_MAX_RADIUS / 1.2
	color: string,
	light: string,
	description: string,
}

-- Orbit slots shared by every star: radius from the star's centre in studs,
-- orbital period in (simulated) days, and the tilt of the orbit in degrees.
export type SlotDef = { orbit: number, periodDays: number, tilt: number }

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

-- Planet slots per tier: the old 4..11 scaled so the top is 9 (rounded),
-- whole and never decreasing.
local ORBITS_BY_TIER = { 3, 4, 5, 6, 7, 7, 8, 9 }

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
		orbits = ORBITS_BY_TIER[tier],
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
		700,
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
		3500,
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
		14000,
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
		50000,
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
		170000,
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
		550000,
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
		1800000,
		1000,
		14,
		"#05020A",
		"#B67CFF",
		"Light can't escape. Stardust can."
	),
}

-- Orbits: evenly spaced from ORBIT_FIRST, ORBIT_GAP apart (wide enough for
-- the biggest planets side by side), enough for the top tier. Periods follow
-- Kepler's third law from the innermost orbit's ORBIT_FIRST_DAYS (Mercury's
-- year), so outer planets really are slower.
local MAX_ORBITS = 9
local ORBIT_FIRST = 44
local ORBIT_GAP = 14
local ORBIT_FIRST_DAYS = 88
local TILTS = { 4, -7, 10, -5, 7, -9, 3, -4, 8 }

local SLOTS: { SlotDef } = {}
for index = 1, MAX_ORBITS do
	local orbit = ORBIT_FIRST + ORBIT_GAP * (index - 1)
	SLOTS[index] = {
		orbit = orbit,
		periodDays = ORBIT_FIRST_DAYS * (orbit / ORBIT_FIRST) ^ 1.5,
		tilt = TILTS[(index - 1) % #TILTS + 1],
	}
end

return {
	ORDER = ORDER,
	BY_ID = BY_ID,
	SLOTS = SLOTS,
	MAX_ORBITS = MAX_ORBITS, -- no star holds more planets than this
	MAX_LEVEL_BASE = 4, -- max level at tier 1 (even)
	MAX_LEVEL_STEP = 2, -- added per tier (even, so max levels stay even)
	-- Production at level L: income x (1 + LINEAR x n + CURVE x n^2), n = L - 1.
	-- The same as a flat 0.75 per level up to level 4, then it pulls ahead:
	-- x10.5 at level 10 and x25.7 at level 18 (a flat step gave x7.75, x13.75).
	LEVEL_INCOME_LINEAR = 0.6,
	LEVEL_INCOME_CURVE = 0.05,
	-- Level L -> L + 1 costs the type's price x UPGRADE_SHARE x UPGRADE_GROWTH^(L - 1).
	UPGRADE_SHARE = 0.4,
	UPGRADE_GROWTH = 1.35,
	-- A star at max level is this much bigger than at level 1.
	MAX_RADIUS_SCALE = 1.2,
	-- Orbit clock (drawn by each client): simulated seconds per real second.
	-- Normally the innermost planet takes about 16 s to go round; inspecting a
	-- system, a slider sets the rate from INSPECT_RATE_MIN to INSPECT_RATE_MAX.
	ORBIT_DEFAULT_RATE = 5.5 * 86400, -- 5.5 days per second
	INSPECT_RATE_MIN = 3600, -- 1 hour per second
	INSPECT_RATE_MAX = 30 * 365.25 * 86400, -- 3 decades per second
	DEFAULT_TYPE = "BrownDwarf", -- the first star; must be affordable at the start
	-- Each star you already own multiplies the price of the next one.
	PRICE_GROWTH = 1.35,
	-- Placement ghost: how far ahead of the camera it starts, and its range.
	GHOST_DISTANCE = 300,
	GHOST_MIN_DISTANCE = 60,
	GHOST_MAX_DISTANCE = 900,
	GHOST_STEP = 40, -- studs per scroll step or elevation tap
	-- How often star income is added to "uncollected".
	INCOME_TICK = 1,
	MANAGE_DISTANCE = 90, -- studs: the star's Manage and Inspect prompts show this close (from inside the system)
}
