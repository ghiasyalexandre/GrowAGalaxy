--!strict
-- Hangar upgrades: buildings bought on your station's deck. Each one starts as
-- a red ground circle with a sign saying what it does and what it costs;
-- step on it (or use its prompt) to build it. An upgrade with `requires`
-- only appears once those are built.
--
-- Effects (all multiply, and stack across upgrades):
--   stats    ship stats (Config.Ships ShipStats names), from your next launch
--   income   Stardust per second from your stars and planets (part of B)
--   storage  the collector tank's and the offline earnings' caps
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
	cost: number, -- Stardust, a flat price
	-- Optional: price this many minutes of the player's reward rate R
	-- instead (never less than `cost`, HangarMath.price). None use it now.
	minutes: number?,
	requires: { string },
	pad: { x: number, z: number }, -- studs from the deck centre
	stats: { [string]: number }?,
	income: number?,
	storage: number?,
	vanity: boolean?, -- no gameplay effect
	toggle: boolean?, -- once built, the owner can switch it off and on (Settings)
	site: { x: number, y: number?, z: number }?,
}

local ORDER: { string } = {
	"StardustSilo",
	"FuelDepot",
	"Refinery",
	"CoolingTower",
	"MiningLab",
	"ArmorWorkshop",
	"HoloGalaxy",
	"ShowcaseDock",
	"VictorySpire",
}

local BY_ID: { [string]: HangarDef } = {
	StardustSilo = {
		id = "StardustSilo",
		displayName = "Stardust Silo",
		effect = "+50% collector tank and offline earnings caps",
		cost = 5000,
		requires = {},
		pad = { x = -20, z = -8 },
		storage = 1.5,
	},
	FuelDepot = {
		id = "FuelDepot",
		displayName = "Fuel Depot",
		effect = "+25% flight boost time on every ship",
		cost = 15000,
		requires = {},
		pad = { x = 20, z = -8 },
		stats = { boostDuration = 1.25 },
	},
	Refinery = {
		id = "Refinery",
		displayName = "Stardust Refinery",
		effect = "+10% Stardust from your stars and planets",
		cost = 30000,
		requires = { "StardustSilo" },
		pad = { x = -20, z = 8 },
		income = 1.1,
	},
	CoolingTower = {
		id = "CoolingTower",
		displayName = "Cooling Tower",
		effect = "+10% laser cooling on every ship",
		cost = 24000,
		requires = { "FuelDepot" },
		pad = { x = 20, z = 8 },
		stats = { coolingRate = 1.1 },
	},
	MiningLab = {
		id = "MiningLab",
		displayName = "Mining Lab",
		effect = "+10% laser power on every ship",
		cost = 50000,
		requires = { "Refinery" },
		pad = { x = -20, z = 24 },
		stats = { beamPower = 1.1 },
	},
	ArmorWorkshop = {
		id = "ArmorWorkshop",
		displayName = "Armor Workshop",
		effect = "+15% hull on every ship",
		cost = 70000,
		requires = { "CoolingTower" },
		pad = { x = 20, z = 24 },
		stats = { hull = 1.15 },
	},
	HoloGalaxy = {
		id = "HoloGalaxy",
		displayName = "Galaxy Hologram",
		effect = "Vanity: a turning galaxy hologram over your deck",
		cost = 1000,
		requires = {},
		pad = { x = -8, z = -30 },
		site = { x = 0, y = 16, z = -16 },
		vanity = true,
	},
	ShowcaseDock = {
		id = "ShowcaseDock",
		displayName = "Showcase Dock",
		effect = "Vanity: shows off 3 favourite ships (pick them in the Shipyard's Paint tab)",
		cost = 2500,
		requires = {},
		pad = { x = 20, z = -30 },
		site = { x = 52, z = 0 },
		vanity = true,
	},
	VictorySpire = {
		id = "VictorySpire",
		displayName = "Victory Spire",
		effect = "Vanity: a towering beacon spire seen across the galaxy",
		cost = 5000,
		requires = { "HoloGalaxy" },
		pad = { x = -20, z = -30 },
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
	-- Mesh buildings (tools/hangar_meshes): their glow is dimmed by this share
	-- (more than Config.World.EMISSIVE_DIM, so the bloom stays soft), and
	-- parts named Spin_<Group>_* turn at these speeds (radians per second).
	MESH_GLOW_DIM = 0.01,
	-- Mesh hangar upgrades: their lights (markers and dressing) shine at
	-- this share of their brightness and range, so they glow like the deck
	-- machines instead of blooming white.
	MESH_LIGHT_SCALE = 0.35,
	-- Upgrade pads' red lights shine at this share of the usual brightness
	-- and range (like the mesh buildings), so nine pads don't flood the deck.
	PAD_LIGHT_SCALE = 0.35,
	-- The arch ceiling panels (StationBuilder): one per arch. Their ranges
	-- overlap along the deck, so keep the brightness low; a tinted strip
	-- (not white) stays under the bloom threshold.
	CEILING_LIGHT = { brightness = 0.6, range = 24, color = "#9FB4CC" },
	SPIN_SPEEDS = {
		Star = 0.8,
		Fan = 2,
		Asteroid = 0.25,
		Holo = 0.35,
		Ring1 = 0.4,
		Ring2 = -0.5,
		Ring3 = 0.4,
		Crown = 1.5, -- the Planet Egg Lab's lamp ring
	} :: { [string]: number },
	SPIN_SPEED_DEFAULT = 0.5,
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
