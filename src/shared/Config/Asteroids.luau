--!strict
-- Asteroids scattered across the flight area, mined with ship beams for
-- Stardust. The server keeps the population near TARGET_COUNT (never above
-- MAX_COUNT), spawning small clusters at random valid spots: outside the
-- ISS's clearance, outside every region slot (at its largest expansion, plus
-- its station), clear of ships and players, and apart from other asteroids.
--
-- Mining: hold the beam on an asteroid to build extraction progress. The
-- glowing weak point extracts at the ship's full beamPower; plain rock at
-- ROCK_EFFICIENCY of it. When progress reaches the asteroid's durability it
-- breaks and pays its reward once, plus up to PRECISION_BONUS for the share
-- of progress made on the weak point. Logic/ConfigCheck validates this table.

export type SizeDef = {
	id: string,
	displayName: string,
	weight: number, -- relative spawn chance
	radius: number, -- studs, the main rock
	weakPointRadius: number, -- studs, the glowing weak point on its surface
	durability: number, -- extraction progress needed (a beamPower of 10 = 10 per second)
	reward: number, -- Stardust for breaking it, before the precision bonus
}

local SIZE_ORDER: { string } = { "Small", "Medium", "Large" }

local SIZES: { [string]: SizeDef } = {
	Small = {
		id = "Small",
		displayName = "Small asteroid",
		weight = 50,
		radius = 7,
		weakPointRadius = 1.8,
		durability = 25,
		reward = 12,
	},
	Medium = {
		id = "Medium",
		displayName = "Medium asteroid",
		weight = 35,
		radius = 12,
		weakPointRadius = 2.4,
		durability = 50,
		reward = 30,
	},
	Large = {
		id = "Large",
		displayName = "Large asteroid",
		weight = 15,
		radius = 18,
		weakPointRadius = 3,
		durability = 100,
		reward = 70,
	},
}

local Asteroids = {
	SIZE_ORDER = SIZE_ORDER,
	SIZES = SIZES,

	-- Population
	TARGET_COUNT = 110,
	MAX_COUNT = 140,
	SPAWN_INTERVAL = 3, -- seconds between spawn passes
	CLUSTERS_PER_PASS = 2, -- clusters started per pass while below TARGET_COUNT
	CLUSTER_MIN = 2,
	CLUSTER_MAX = 5,
	CLUSTER_SPREAD = 80, -- studs: how far cluster members sit from its centre
	PLACEMENT_ATTEMPTS = 12, -- tries per asteroid before giving up this pass

	-- Where they may spawn (studs, around the ISS at the origin)
	ISS_CLEARANCE = 700, -- nothing closer than this to the ISS
	MAX_DISTANCE = 5600, -- horizontal distance limit; inside the flight area
	HEIGHT = 450, -- studs above and below the ISS
	REGION_CLEARANCE = 280, -- around every region slot's largest box; covers its station
	MIN_GAP = 30, -- studs between asteroid surfaces
	SHIP_CLEARANCE = 60, -- from any ship
	PLAYER_CLEARANCE = 40, -- from any player

	-- Mining
	ROCK_EFFICIENCY = 0.3, -- share of beamPower when the beam hits rock, not the weak point
	PRECISION_BONUS = 0.25, -- extra reward share when all progress was made on the weak point
	RESERVATION_TIMEOUT = 6, -- seconds without a hit before it is freed (and its progress lost)
	BUSY_NOTICE_COOLDOWN = 4, -- seconds between "someone else is mining this" toasts
	BREAK_LINGER = 0.4, -- seconds a broken asteroid stays (hidden) so clients see it break

	-- Scanner: while flying, markers show the nearest asteroids.
	SCAN_RANGE = 2500, -- studs from your ship
	SCAN_MARKERS = 5, -- at most this many at once
	SCAN_INTERVAL = 0.5, -- seconds between scans

	-- Looks and sound
	-- Ships with every Roblox client (Studio's content/sounds folder), so it
	-- needs no uploaded asset. Empty string = silent.
	BREAK_SOUND = "rbxasset://sounds/impact_explosion_03.mp3",
	BREAK_SOUND_VOLUME = 0.6,
	ROCK_COLORS = { "#7A6E63", "#6B625A", "#857A70", "#5E5852" } :: { string },
	WEAK_POINT_COLOR = "#7FF7FF",
	CRACK_COLOR = "#FF8A3D", -- rock glows towards this as extraction progresses
}

return Asteroids
