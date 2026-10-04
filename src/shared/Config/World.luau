--!strict
-- Physical layout of one server: the ISS hub, the Earth backdrop, galaxy regions
-- and personal stations. Distances are in studs. Keep everything within ~6000 studs
-- of the origin so physics and rendering stay precise.

export type Vec3 = { x: number, y: number, z: number }

local World = {
	-- One galaxy region per player. Set Game Settings > Places > Max Players to match.
	MAX_PLAYERS = 8,

	-- Regions sit on a ring around the ISS. A region's origin is the centre of its
	-- near face (the face pointing at the ISS) and the region extends away from the
	-- ISS, so expanding a region never moves its station or its saved bodies.
	REGION_RING_RADIUS = 3000,
	REGION_RING_HEIGHT = 0,
	REGION_EDGE_THICKNESS = 4,

	-- Personal station distance in front of the region's near face (towards the ISS).
	STATION_DISTANCE = 140,

	EARTH_CENTER = { x = 0, y = -3000, z = 0 } :: Vec3,
	EARTH_DIAMETER = 2000, -- a single Part can be at most 2048 studs

	-- Asteroids are scattered across the whole flight area: see Config.Asteroids.

	WARP_COOLDOWN = 2, -- seconds between navigation warps per player

	-- Hex colours used by the world builders.
	COLORS = {
		hull = "#E8EAED",
		hullAlt = "#C7CCD4",
		truss = "#8D9099",
		solar = "#1C2E6E",
		solarFrame = "#C9A447",
		radiator = "#F4F4F4",
		accent = "#FFB23F",
		glass = "#A9DCFF",
		deck = "#4E5463",
		console = "#2B3040",
		earthOcean = "#1F5FBF",
		earthLand = "#3F8F45",
		atmosphere = "#7EC8FF",
	},

	-- Boundary colour for each region slot.
	REGION_COLORS = {
		"#4FC3F7",
		"#FF8A65",
		"#AED581",
		"#BA68C8",
		"#FFD54F",
		"#4DB6AC",
		"#F06292",
		"#7986CB",
	},
}

return World
