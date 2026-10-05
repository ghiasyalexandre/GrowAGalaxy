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
--
-- `pad` is where the circle and the building sit on the deck, in station
-- space (x right, z towards the back; the berth is off the -z edge).

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
}

local ORDER: { string } = {
	"StardustSilo",
	"FuelDepot",
	"Refinery",
	"CoolingTower",
	"MiningLab",
	"ArmorWorkshop",
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
		cost = 6000,
		requires = { "StardustSilo" },
		pad = { x = -20, z = -4 },
		income = 1.15,
	},
	CoolingTower = {
		id = "CoolingTower",
		displayName = "Cooling Tower",
		effect = "+25% laser cooling on every ship",
		cost = 10000,
		requires = { "FuelDepot" },
		pad = { x = 20, z = -4 },
		stats = { coolingRate = 1.25 },
	},
	MiningLab = {
		id = "MiningLab",
		displayName = "Mining Lab",
		effect = "+15% laser power on every ship",
		cost = 25000,
		requires = { "Refinery" },
		pad = { x = -20, z = 12 },
		stats = { beamPower = 1.15 },
	},
	ArmorWorkshop = {
		id = "ArmorWorkshop",
		displayName = "Armor Workshop",
		effect = "+30% hull on every ship",
		cost = 20000,
		requires = { "CoolingTower" },
		pad = { x = 20, z = 12 },
		stats = { hull = 1.3 },
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
}
