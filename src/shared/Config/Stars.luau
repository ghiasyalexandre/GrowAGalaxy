--!strict
-- The star tycoon's stars. Seventeen types form a ladder from Brown Dwarf
-- through the dying giants and their remnants (Wolf-Rayet, Neutron Star,
-- Pulsar, Magnetar) to the Black Hole, and on to four fictional stars
-- (Nebula Heart, Prism Star, Cosmic Phoenix, Void Flame). A new star of a
-- type needs a star of the previous type already in your galaxy.
--
-- Levels: a star levels up from 1 to its tier's max level (MAX_LEVEL_BASE at
-- tier 1, one more every MAX_LEVEL_EVERY tiers: 4 ... 8). Each level
-- multiplies the type's base production. At max level it can evolve into the
-- next type in place: it keeps its planets and starts again at level 1.
-- Each type makes 3x the one before it, so evolving never lowers income.
--
-- Prices (economy v2): every star gets a BuildIndex k when it is built (0
-- for the first, never reused or lowered). A new star costs
-- cost x PRICE_GROWTH^k (1.1^k); levelling it costs cost x UPGRADE_FACTOR x
-- UPGRADE_GROWTH^(L - 1) x PRICE_GROWTH^k; evolving it costs the next type's
-- cost x PRICE_GROWTH^k (Logic/StarMath).
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
	radius: number, -- studs at level 1; at most Config.Galaxy.STAR_MAX_RADIUS / MAX_RADIUS_SCALE
	color: string,
	light: string,
	description: string,
}

-- Orbit slots shared by every star: radius from the star's centre in studs,
-- orbital period in (simulated) days, and the tilt of the orbit in degrees.
export type SlotDef = { orbit: number, periodDays: number, tilt: number }

local Galaxy = require(script.Parent.Galaxy)

local ORDER: { string } = {
	"BrownDwarf",
	"RedDwarf",
	"YellowDwarf",
	"BinaryStar",
	"WhiteDwarf",
	"RedGiant",
	"BlueGiant",
	"RedSupergiant",
	"WolfRayet",
	"NeutronStar",
	"Pulsar",
	"Magnetar",
	"BlackHole",
	"NebulaHeart",
	"PrismStar",
	"CosmicPhoenix",
	"VoidFlame",
}

-- Planet slots per tier: the old 4..11 scaled so the top is 9 (rounded),
-- whole and never decreasing.
local ORBITS_BY_TIER = { 3, 4, 5, 5, 6, 7, 7, 8, 8, 8, 9, 9, 9, 9, 9, 9, 9 }

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
		450,
		3,
		12,
		"#E2563B",
		"#FF7A5C",
		"Small, cool and long-lived."
	),
	YellowDwarf = star(
		"YellowDwarf",
		3,
		"Yellow Dwarf",
		1800,
		9,
		15,
		"#FFD36B",
		"#FFE6A3",
		"A sun like ours."
	),
	BinaryStar = star(
		"BinaryStar",
		4,
		"Binary Star",
		7000,
		27,
		13,
		"#FFC85A",
		"#9FC8FF",
		"Two suns dancing round each other, one stealing from the other."
	),
	WhiteDwarf = star(
		"WhiteDwarf",
		5,
		"White Dwarf",
		28000,
		81,
		11,
		"#F2F6FF",
		"#DDE8FF",
		"A dense, white-hot ember."
	),
	RedGiant = star(
		"RedGiant",
		6,
		"Red Giant",
		110000,
		243,
		20,
		"#FF6B3D",
		"#FFA07A",
		"Swollen and blazing red."
	),
	BlueGiant = star(
		"BlueGiant",
		7,
		"Blue Giant",
		450000,
		729,
		21,
		"#6FA8FF",
		"#A9CCFF",
		"Hot, bright and fierce."
	),
	RedSupergiant = star(
		"RedSupergiant",
		8,
		"Red Supergiant",
		2000000,
		2187,
		24,
		"#FF4A2E",
		"#FF8A66",
		"One of the largest stars there is."
	),
	-- The remnants, between the dying giants and the Black Hole.
	WolfRayet = star(
		"WolfRayet",
		9,
		"Wolf-Rayet Star",
		10000000,
		6561,
		16,
		"#6A5CFF",
		"#B8B0FF",
		"So hot and fierce it blows its own outer layers away."
	),
	NeutronStar = star(
		"NeutronStar",
		10,
		"Neutron Star",
		50000000,
		19683,
		8,
		"#DDEBFF",
		"#9FC8FF",
		"A city-sized cinder: a teaspoon weighs a billion tons."
	),
	Pulsar = star(
		"Pulsar",
		11,
		"Pulsar",
		250000000,
		59049,
		8,
		"#9FF0FF",
		"#3FD8FF",
		"A spinning lighthouse sweeping beams across space."
	),
	Magnetar = star(
		"Magnetar",
		12,
		"Magnetar",
		1300000000,
		177147,
		9,
		"#E060FF",
		"#FF5AC8",
		"The strongest magnet in the universe, cracking with starquakes."
	),
	BlackHole = star(
		"BlackHole",
		13,
		"Black Hole",
		7000000000,
		531441,
		14,
		"#05020A",
		"#B67CFF",
		"Light can't escape. Stardust can."
	),
	-- Beyond the Black Hole: fictional stars, each a step up the ladder.
	NebulaHeart = star(
		"NebulaHeart",
		14,
		"Nebula Heart",
		30000000000,
		1594323,
		20,
		"#B04ACF",
		"#5FE3FF",
		"A newborn star still wrapped in the nebula that made it."
	),
	PrismStar = star(
		"PrismStar",
		15,
		"Prism Star",
		120000000000,
		4782969,
		17,
		"#BFF6FF",
		"#FF9AE8",
		"Crystal-bright: it splits its light into every colour."
	),
	CosmicPhoenix = star(
		"CosmicPhoenix",
		16,
		"Cosmic Phoenix",
		480000000000,
		14348907,
		22,
		"#FF7A1A",
		"#FFD070",
		"It burns, dies and is reborn, brighter every time."
	),
	VoidFlame = star(
		"VoidFlame",
		17,
		"Void Flame",
		1900000000000,
		43046721,
		24,
		"#140A24",
		"#5CFF8A",
		"A star of dark matter, burning with green fire."
	),
}

-- Orbits: evenly spaced from ORBIT_FIRST, ORBIT_GAP apart (wide enough for
-- the biggest planets side by side), enough for the top tier. The first
-- orbit sits ORBIT_CLEARANCE outside the biggest star at its top level
-- (Galaxy.STAR_MAX_RADIUS), so orbits move out when stars grow bigger. Periods follow
-- Kepler's third law from the innermost orbit's ORBIT_FIRST_DAYS (Mercury's
-- year), so outer planets really are slower.
local MAX_ORBITS = 9
local ORBIT_CLEARANCE = 10 -- studs: a top-level planet (about 7) plus a gap
local ORBIT_FIRST = math.ceil(Galaxy.STAR_MAX_RADIUS + ORBIT_CLEARANCE)
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
	MAX_LEVEL_BASE = 4, -- max level at tier 1
	MAX_LEVEL_EVERY = 4, -- one more max level every this many tiers (4 + floor((t - 1) / 4))
	-- Production at level L: income x (1 + LINEAR x n + CURVE x n^2), n = L - 1
	-- (x2.89 at level 8, the Phoenix's max).
	-- Every star's production (and so its planets', a share of it) times this.
	INCOME_BOOST = 1.1,
	LEVEL_INCOME_LINEAR = 0.2,
	LEVEL_INCOME_CURVE = 0.01,
	-- Level L -> L + 1 costs cost x UPGRADE_FACTOR x UPGRADE_GROWTH^(L - 1) x PRICE_GROWTH^k.
	UPGRADE_FACTOR = 0.18,
	UPGRADE_GROWTH = 1.2,
	-- A star at max level is this much bigger than at level 1.
	MAX_RADIUS_SCALE = 1.5,
	-- Orbit clock (drawn by each client): simulated seconds per real second.
	-- Normally the innermost planet takes about 16 s to go round; inspecting a
	-- system, a slider sets the rate from INSPECT_RATE_MIN to INSPECT_RATE_MAX.
	ORBIT_DEFAULT_RATE = 5.5 * 86400, -- 5.5 days per second
	INSPECT_RATE_MIN = 3600, -- 1 hour per second
	INSPECT_RATE_MAX = 30 * 365.25 * 86400, -- 3 decades per second
	DEFAULT_TYPE = "BrownDwarf", -- the first star; must be affordable at the start
	-- Per BuildIndex: the k-th star built (from 0) pays PRICE_GROWTH^k on
	-- its price, every level and every evolution.
	PRICE_GROWTH = 1.1,
	-- Placement ghost: how far ahead of the camera it starts, and its range.
	GHOST_DISTANCE = 300,
	GHOST_MIN_DISTANCE = 60,
	GHOST_MAX_DISTANCE = 900,
	GHOST_STEP = 40, -- studs per scroll step or elevation tap
	-- How often star income is added to "uncollected".
	INCOME_TICK = 1,
	MANAGE_DISTANCE = 135, -- studs: the star's Manage and Inspect prompts show this close (from inside the system)
}
