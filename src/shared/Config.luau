--!strict
-- Tunable gameplay values. NOTE: replicated to clients — nothing secret here,
-- and the server never trusts a client-reported value from this file.

local Types = require(script.Parent.Types)

type DropperDef = Types.DropperDef

-- Droppers unlock in order: each buy pad appears once the previous one is owned.
local DROPPERS: { DropperDef } = {
	{
		id = "AsteroidMiner",
		displayName = "Asteroid Miner",
		cost = 25,
		oreValue = 2,
		dropInterval = 2,
		color = Color3.fromRGB(170, 160, 150),
	},
	{
		id = "CometHarvester",
		displayName = "Comet Harvester",
		cost = 150,
		oreValue = 8,
		dropInterval = 2,
		color = Color3.fromRGB(120, 220, 255),
	},
	{
		id = "NebulaSiphon",
		displayName = "Nebula Siphon",
		cost = 900,
		oreValue = 30,
		dropInterval = 2,
		color = Color3.fromRGB(220, 110, 255),
	},
	{
		id = "StarForge",
		displayName = "Star Forge",
		cost = 5000,
		oreValue = 120,
		dropInterval = 2.5,
		color = Color3.fromRGB(255, 200, 80),
	},
	{
		id = "BlackHoleReactor",
		displayName = "Black Hole Reactor",
		cost = 30000,
		oreValue = 500,
		dropInterval = 3,
		color = Color3.fromRGB(140, 60, 255),
	},
}

local DROPPERS_BY_ID: { [string]: DropperDef } = {}
for _, def in DROPPERS do
	DROPPERS_BY_ID[def.id] = def
end

return table.freeze({
	CURRENCY_NAME = "Stardust",
	STARTING_STARDUST = 25,

	DATASTORE_NAME = "GrowAGalaxy2_Profiles_v1",
	AUTOSAVE_INTERVAL = 60,

	GRAVITY = 120,
	PLOT_COUNT = 6,
	PLOT_SIZE = 80,
	PLOT_RING_RADIUS = 110,
	HUB_SIZE = 60,

	CONVEYOR_SPEED = 12,
	ORE_LIFETIME = 20,
	MAX_ORE_PER_PLOT = 60,
	PAD_REACH = 12,

	DROPPERS = table.freeze(DROPPERS),
	DROPPERS_BY_ID = table.freeze(DROPPERS_BY_ID),
})
