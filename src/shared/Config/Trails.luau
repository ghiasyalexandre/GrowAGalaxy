--!strict
-- Trail effects, bought with Stardust in the Shipyard's Trails tab. The one
-- you equip streams behind you, both floating in your suit and flying your
-- ship, and multiplies your production rate B (stars and planets, and so
-- mining, which pays a share of B: Logic/EconomyMath) by its multiplier.
-- It never touches rewards, sales or purchases. Only one applies.
-- Multipliers rise in steps of 0.1; prices rise steeply.

export type TrailDef = {
	id: string,
	displayName: string,
	multiplier: number,
	cost: number, -- Stardust
	colors: { string }, -- start to end of the trail
	width: number, -- studs, at the start
	lifetime: number, -- seconds the trail lingers
}

local ORDER: { string } =
	{ "CometDust", "NebulaRibbon", "SolarFlare", "AuroraVeil", "QuasarStream" }

local BY_ID: { [string]: TrailDef } = {
	CometDust = {
		id = "CometDust",
		displayName = "Comet Dust",
		multiplier = 1.1,
		cost = 2500,
		colors = { "#E8F6FF", "#7FC8FF" },
		width = 1.2,
		lifetime = 0.6,
	},
	NebulaRibbon = {
		id = "NebulaRibbon",
		displayName = "Nebula Ribbon",
		multiplier = 1.25,
		cost = 100000,
		colors = { "#FF6EC8", "#7A5CFF" },
		width = 1.6,
		lifetime = 0.8,
	},
	SolarFlare = {
		id = "SolarFlare",
		displayName = "Solar Flare",
		multiplier = 1.5,
		cost = 10000000,
		colors = { "#FFF4C2", "#FFB020", "#FF4A1F" },
		width = 2,
		lifetime = 0.9,
	},
	AuroraVeil = {
		id = "AuroraVeil",
		displayName = "Aurora Veil",
		multiplier = 1.75,
		cost = 1000000000,
		colors = { "#5CFF6B", "#3FD2FF", "#C04DFF" },
		width = 2.4,
		lifetime = 1.1,
	},
	QuasarStream = {
		id = "QuasarStream",
		displayName = "Quasar Stream",
		multiplier = 2.0,
		cost = 80000000000,
		colors = { "#FFFFFF", "#3FFFD0", "#7A5CFF", "#FF3B3B" },
		width = 2.8,
		lifetime = 1.3,
	},
}

return {
	ORDER = ORDER,
	BY_ID = BY_ID,
}
