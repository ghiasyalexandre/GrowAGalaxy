--!strict
-- Physical layout of one server: the ISS hub, the Earth backdrop, galaxy regions
-- and personal stations. Distances are in studs. Keep everything within ~6000 studs
-- of the origin so physics and rendering stay precise.

export type Vec3 = { x: number, y: number, z: number }

-- One image layer of the nebula backdrop (NEBULA.LAYERS).
export type NebulaLayer = {
	name: string,
	image: string, -- rbxassetid
	height: number, -- studs above NEBULA.CENTER
	spin: number, -- radians per second (negative turns the other way)
	brightness: number, -- SurfaceGui brightness
	transparency: number, -- extra image transparency
}

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
	-- Share by which every glow (Neon colours, lights, beams) of player
	-- stations, hangar upgrades and the Zero G Dodgeball arena is dimmed.
	EMISSIVE_DIM = 0.2,
	-- Bloom (Lighting SpaceBloom): in open space, and inside player stations
	-- and the Zero G Dodgeball arena (BloomController eases between them).
	BLOOM_INTENSITY = 0.6,
	BLOOM_INDOOR = 0.2,
	-- Lighting.Ambient and OutdoorAmbient (WorldSystem): the light everything
	-- gets before any lamp.
	AMBIENT = "#5F6273",
	OUTDOOR_AMBIENT = "#5A5D73",
	STATION_DISTANCE = 140,

	-- The Helix Nebula backdrop far below (World/NebulaBuilder): image
	-- layers painted by tools/nebula/helix.py (uploaded as Roblox images),
	-- stacked from the bottom up, `height` studs above CENTER, each turning
	-- slowly at `spin` radians per second. TOP is the highest point of the
	-- backdrop (the flight area stays above it, ConfigCheck).
	NEBULA = {
		CENTER = { x = 0, y = -2300, z = 0 } :: Vec3,
		-- Studs across. A Part can be at most 2048, so each layer is built as
		-- 2 x 2 tiles (NebulaBuilder): up to 4096.
		SIZE = 2724,
		STAR_HEIGHT = 110, -- the white dwarf, above CENTER
		TOP = -2150,
		LAYERS = {
			{
				name = "Halo",
				image = "rbxassetid://89347641877952",
				height = 0,
				spin = 0.004,
				brightness = 1.2,
				transparency = 0,
			},
			{
				name = "Ring",
				image = "rbxassetid://71338801270797",
				height = 40,
				spin = -0.006,
				brightness = 1.4,
				transparency = 0,
			},
			{
				name = "Core",
				image = "rbxassetid://93167090080763",
				height = 70,
				spin = 0.009,
				brightness = 1.3,
				transparency = 0.05,
			},
			{
				name = "Glow",
				image = "rbxassetid://105028283456003",
				height = 100,
				spin = 0,
				brightness = 2,
				transparency = 0,
			},
		} :: { NebulaLayer },
	},

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
