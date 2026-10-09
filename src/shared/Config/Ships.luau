--!strict
-- Ship chassis. Equipment (Config.Equipment) and cosmetics (Config.Cosmetics)
-- are separate so skins never change stats.
--
-- The ladder: ships unlock in ORDER. A ship can be bought once you own the
-- one before it and your best star has reached its minTier
-- (Logic/Progression.shipUnlocked), so a lucky windfall can't skip the
-- whole ladder. A ship with a productKey can
-- also be unlocked with Robux (Config.Products) and has the same stats. Beam
-- power and hull climb on a curve (each step up adds more than the last),
-- like the prices.
--
-- Models: ShipBuilder dresses a ship with ReplicatedStorage/Assets/Ships/<model>
-- (imported in Studio, see assets/roblox/Ships/README.md), scaled so its
-- longest horizontal side is modelSize studs and turned modelYaw degrees so
-- its nose faces -Z. Without the asset the greybox shuttle stands in.
--
-- A rider ship (the hoverboard) carries its pilot in plain sight, standing
-- on the deck: the seat sits just above it, the pilot isn't hidden and
-- RiderController plays a standing pose over the sit pose.

export type ShipStats = {
	maxSpeed: number, -- studs per second
	acceleration: number, -- studs per second squared
	braking: number, -- studs per second squared
	turnRate: number, -- radians per second
	beamPower: number, -- extraction progress per second while on target
	beamRange: number, -- studs
	heatCapacity: number, -- heat units before overheating
	coolingRate: number, -- heat units shed per second while the beam is off
	cargoCapacity: number, -- material units
	hull: number, -- hull points: PvP damage it takes before exploding (Config.Combat)
	-- Boost (hold Shift / L3): top speed x boostMultiplier for up to
	-- boostDuration seconds; an empty tank refills in boostRecharge seconds.
	boostMultiplier: number,
	boostDuration: number,
	boostRecharge: number,
}

export type Cost = { stardust: number, materials: { [string]: number } }

export type ShipDef = {
	id: string,
	displayName: string,
	role: string,
	description: string,
	enabled: boolean, -- false = defined for later stages, not offered yet
	paint: string, -- hull colour (greybox, untextured models, UI accents)
	model: string, -- asset name under ReplicatedStorage/Assets/Ships
	modelSize: number, -- studs: the model's longest horizontal side
	modelYaw: number, -- degrees turned about Y so the nose faces -Z
	stats: ShipStats,
	earn: Cost?, -- nil = free starter ship
	minTier: number, -- the player's best star tier needed to buy it with Stardust
	productKey: string?, -- optional Robux unlock with identical stats
	rider: boolean, -- the pilot stands on it in view (hoverboards)
}

local ORDER: { string } = {
	"MicroRecon",
	"RedFighter",
	"GalactixRacer",
	"Warship",
	"CamoStellar",
	"InfraredFurtive",
	"InterstellarRunner",
	"Transtellar",
	"DualStriker",
	"UltravioletIntruder",
	"MeteorSlicer",
	"QuasarBoard",
}

type Spec = {
	name: string,
	role: string,
	description: string,
	paint: string,
	model: string?,
	size: number,
	yaw: number?,
	cost: number?,
	minTier: number?,
	productKey: string?,
	rider: boolean?,
	-- maxSpeed, acceleration, braking, turnRate, beamPower, beamRange,
	-- heatCapacity, coolingRate, boostMultiplier, boostDuration, boostRecharge
	stats: { number },
}

local SPECS: { [string]: Spec } = {
	MicroRecon = {
		name = "Micro Recon",
		role = "Starter scout",
		description = "Small, simple and easy to fly.",
		paint = "#9FB4C7",
		size = 14,
		stats = { 120, 60, 90, 2.2, 10, 120, 100, 25, 1.6, 3, 6 },
	},
	RedFighter = {
		name = "Red Fighter",
		role = "Agile miner",
		description = "Quicker turns and a stronger beam.",
		paint = "#D9433B",
		size = 16,
		cost = 5000,
		minTier = 3,
		stats = { 135, 70, 100, 2.4, 14, 130, 115, 28, 1.7, 3.5, 5.5 },
	},
	GalactixRacer = {
		name = "Galactix Racer",
		role = "Speed",
		description = "Built to go fast, with a long boost.",
		paint = "#3FA9F5",
		size = 16,
		cost = 50000,
		minTier = 5,
		productKey = "GalactixRacerShip",
		stats = { 165, 95, 120, 2.6, 15, 130, 115, 30, 2.0, 4, 5 },
	},
	Warship = {
		name = "Warship",
		role = "Heavy mining",
		description = "A slow, armoured hull with a heavy beam.",
		paint = "#5B6470",
		size = 20,
		cost = 500000,
		minTier = 7,
		stats = { 125, 55, 85, 1.8, 24, 150, 170, 32, 1.5, 3, 6.5 },
	},
	CamoStellar = {
		name = "Camo Stellar",
		role = "All-rounder",
		description = "Balanced speed, power and cooling.",
		paint = "#5E7D4A",
		model = "CamoStellarJet",
		productKey = "CamoStellarShip",
		size = 17,
		cost = 5000000,
		minTier = 9,
		stats = { 150, 80, 110, 2.5, 23, 155, 160, 38, 1.8, 4, 5 },
	},
	InfraredFurtive = {
		name = "Infrared Furtive",
		role = "Stealth hunter",
		description = "Fast and sharp, runs cool under fire.",
		paint = "#B8322C",
		size = 18,
		cost = 50000000,
		minTier = 10,
		stats = { 170, 95, 125, 2.7, 28, 165, 170, 42, 2.0, 4.5, 4.5 },
	},
	InterstellarRunner = {
		name = "Interstellar Runner",
		role = "Long-range speed",
		description = "The fastest cruiser for crossing the galaxy.",
		productKey = "InterstellarRunnerShip",
		paint = "#E8B04A",
		size = 18,
		cost = 500000000,
		minTier = 11,
		stats = { 195, 110, 135, 2.6, 32, 170, 180, 45, 2.2, 5, 4.5 },
	},
	Transtellar = {
		name = "Transtellar",
		role = "Deep-space miner",
		description = "Long reach and a deep heat sink.",
		paint = "#7E8CE0",
		size = 20,
		cost = 5000000000,
		minTier = 12,
		stats = { 185, 100, 135, 2.4, 44, 185, 200, 48, 2.0, 5, 4.5 },
	},
	DualStriker = {
		name = "Dual Striker",
		role = "Heavy striker",
		description = "Twin hulls carry a punishing beam.",
		paint = "#F28C28",
		size = 22,
		cost = 25000000000,
		minTier = 13,
		stats = { 180, 100, 130, 2.3, 54, 190, 230, 50, 1.9, 5, 4.5 },
	},
	UltravioletIntruder = {
		name = "Ultraviolet Intruder",
		role = "Elite interceptor",
		description = "Blistering speed and a strong beam.",
		paint = "#8C4DE0",
		size = 20,
		cost = 100000000000,
		minTier = 15,
		stats = { 210, 120, 145, 2.8, 57, 205, 240, 55, 2.3, 5.5, 4 },
	},
	MeteorSlicer = {
		name = "Meteor Slicer",
		role = "Flagship",
		description = "The best ship in the galaxy at everything.",
		paint = "#C9C2B8",
		size = 20,
		cost = 400000000000,
		minTier = 17,
		productKey = "MeteorSlicerShip",
		stats = { 240, 135, 160, 3.0, 70, 220, 260, 60, 2.5, 6, 4 },
	},
	QuasarBoard = {
		name = "Quasar Hoverboard",
		role = "Legend",
		description = "Surf the galaxy standing up, riding four grav pods and twin quasar engines.",
		paint = "#3FE8FF",
		size = 12,
		cost = 1600000000000,
		minTier = 17,
		productKey = "QuasarBoardShip",
		rider = true,
		stats = { 270, 160, 185, 3.3, 82, 230, 290, 66, 2.7, 6.5, 3.5 },
	},
}

local BY_ID: { [string]: ShipDef } = {}
for index, id in ORDER do
	local spec = SPECS[id]
	local s = spec.stats
	BY_ID[id] = {
		id = id,
		displayName = spec.name,
		role = spec.role,
		description = spec.description,
		enabled = true,
		paint = spec.paint,
		model = spec.model or id,
		modelSize = spec.size,
		modelYaw = spec.yaw or 0,
		stats = {
			maxSpeed = s[1],
			acceleration = s[2],
			braking = s[3],
			turnRate = s[4],
			beamPower = s[5],
			beamRange = s[6],
			heatCapacity = s[7],
			coolingRate = s[8],
			cargoCapacity = 60 + 30 * (index - 1),
			-- Rises on a curve: 100, 124, 156 ... 700 for the flagship.
			hull = 100 + 20 * (index - 1) + 4 * (index - 1) ^ 2,
			boostMultiplier = s[9],
			boostDuration = s[10],
			boostRecharge = s[11],
		},
		earn = if spec.cost then { stardust = spec.cost, materials = {} } else nil,
		minTier = spec.minTier or 1,
		productKey = spec.productKey,
		rider = spec.rider == true,
	}
end

return {
	ORDER = ORDER,
	BY_ID = BY_ID,
	STARTER_SHIP = "MicroRecon",
	-- Ship ids from before the stage 14 ladder, mapped on load (ProfileSchema v6).
	RENAMED = {
		StarterShuttle = "MicroRecon",
		Prospector = "RedFighter",
		CrystalExplorer = "GalactixRacer",
		HeavyExcavator = "Warship",
		NebulaCruiser = "CamoStellar",
	} :: { [string]: string },
	-- Seconds each ship stays on the ISS showroom podiums before they all
	-- move on one place (ShowroomSystem).
	SHOWROOM_SECONDS = 8,
	-- Shipyard preview turntable speed, radians per second.
	PREVIEW_SPIN = 0.8,
}
