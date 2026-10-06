--!strict
-- Hangar upgrades: buildings bought on your station's deck. Each one starts as
-- a red ground circle with a sign saying what it does and what it costs;
-- step on it (or use its prompt) to build it. An upgrade with `requires`
-- only appears once those are built.
--
-- Effects (all multiply, and stack across upgrades):
--   stats    ship stats (Config.Ships ShipStats names), from your next launch
--   income   Stardust per second from your stars
--   storage  how much uncollected Stardust your stars can hold
--   vanity   none: it's there to show off (a runway, a hologram, a spire,
--            the Showcase Dock that displays your three favourite ships)
--
-- `pad` is where the circle sits on the deck, in station space (x right, z
-- towards the back; the berth is off the -z edge). The building stands on
-- the pad, or at `site` when given: off the deck's edge, or `site.y` studs
-- above it.

export type HangarDef = {
	id: string,
	displayName: string,
	effect: string, -- shown on the pad's sign and the building
	cost: number, -- Stardust
	requires: { string },
	pad: { x: number, z: number }, -- studs from the deck centre
	stats: { [string]: number }?,
	income: number?,
	storage: number?,
	vanity: boolean?, -- no gameplay effect
	site: { x: number, y: number?, z: number }?,
}

local ORDER: { string } = {
	"StardustSilo",
	"FuelDepot",
	"Refinery",
	"CoolingTower",
	"MiningLab",
	"ArmorWorkshop",
	"NeonRunway",
	"HoloGalaxy",
	"ShowcaseDock",
	"VictorySpire",
}

local BY_ID: { [string]: HangarDef } = {
	StardustSilo = {
		id = "StardustSilo",
		displayName = "Stardust Silo",
		effect = "Stars hold 50% more uncollected Stardust",
		cost = 1500,
		requires = {},
		pad = { x = -20, z = -20 },
		storage = 1.5,
	},
	FuelDepot = {
		id = "FuelDepot",
		displayName = "Fuel Depot",
		effect = "+25% boost time on every ship",
		cost = 3000,
		requires = {},
		pad = { x = 20, z = -20 },
		stats = { boostDuration = 1.25 },
	},
	Refinery = {
		id = "Refinery",
		displayName = "Stardust Refinery",
		effect = "+15% Stardust from your stars",
		cost = 7000,
		requires = { "StardustSilo" },
		pad = { x = -20, z = -4 },
		income = 1.15,
	},
	CoolingTower = {
		id = "CoolingTower",
		displayName = "Cooling Tower",
		effect = "+25% laser cooling on every ship",
		cost = 14000,
		requires = { "FuelDepot" },
		pad = { x = 20, z = -4 },
		stats = { coolingRate = 1.25 },
	},
	MiningLab = {
		id = "MiningLab",
		displayName = "Mining Lab",
		effect = "+15% laser power on every ship",
		cost = 40000,
		requires = { "Refinery" },
		pad = { x = -20, z = 12 },
		stats = { beamPower = 1.15 },
	},
	ArmorWorkshop = {
		id = "ArmorWorkshop",
		displayName = "Armor Workshop",
		effect = "+30% hull on every ship",
		cost = 30000,
		requires = { "CoolingTower" },
		pad = { x = 20, z = 12 },
		stats = { hull = 1.3 },
	},
	NeonRunway = {
		id = "NeonRunway",
		displayName = "Neon Runway",
		effect = "Vanity: chevron lights guide you in to your dock",
		cost = 5000,
		requires = {},
		pad = { x = 8, z = -30 },
		site = { x = 0, z = -60 },
		vanity = true,
	},
	HoloGalaxy = {
		id = "HoloGalaxy",
		displayName = "Galaxy Hologram",
		effect = "Vanity: a turning galaxy hologram over your deck",
		cost = 12000,
		requires = {},
		pad = { x = -8, z = -30 },
		site = { x = 0, y = 16, z = -16 },
		vanity = true,
	},
	ShowcaseDock = {
		id = "ShowcaseDock",
		displayName = "Showcase Dock",
		effect = "Vanity: shows off 3 favourite ships (pick them in the Shipyard's Paint tab)",
		cost = 15000,
		requires = {},
		pad = { x = 20, z = 28 },
		site = { x = 52, z = 0 },
		vanity = true,
	},
	VictorySpire = {
		id = "VictorySpire",
		displayName = "Victory Spire",
		effect = "Vanity: a towering beacon spire seen across the galaxy",
		cost = 30000,
		requires = { "HoloGalaxy" },
		pad = { x = -20, z = 28 },
		site = { x = -46, z = 24 },
		vanity = true,
	},
}

return {
	ORDER = ORDER,
	BY_ID = BY_ID,
	PAD_RADIUS = 4, -- studs
	PAD_COLOR = "#FF3B3B",
	-- A player standing on a pad tries to buy it at most this often.
	TOUCH_COOLDOWN = 2,
	SIGN_DISTANCE = 120, -- studs: pad signs show within this range
	-- Hangar highlight colours a player can pick (Settings): the station's
	-- glowing strips, rail, beacon and name signs. None picked: the region's
	-- own colour.
	HIGHLIGHT_COLORS = {
		{ id = "Cyan", name = "Cyan", hex = "#4FC3F7" },
		{ id = "Blue", name = "Blue", hex = "#3F7BFF" },
		{ id = "Purple", name = "Purple", hex = "#B06BFF" },
		{ id = "Pink", name = "Pink", hex = "#FF6EC8" },
		{ id = "Red", name = "Red", hex = "#FF4A4A" },
		{ id = "Orange", name = "Orange", hex = "#FF9A3D" },
		{ id = "Gold", name = "Gold", hex = "#FFD36B" },
		{ id = "Green", name = "Green", hex = "#5CFF8A" },
		{ id = "Mint", name = "Mint", hex = "#3FFFD0" },
		{ id = "White", name = "White", hex = "#E8F0FF" },
	} :: { { id: string, name: string, hex: string } },
}
