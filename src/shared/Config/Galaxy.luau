--!strict
-- Geometry and capacity of a player's galaxy region.
--
-- Orbit radii are fixed per slot, so bodies can never collide and a whole
-- solar system always fits inside SYSTEM_RADIUS. Placement then only has to
-- keep stars MIN_STAR_SPACING apart and WALL_MARGIN inside the region walls.
-- Logic/ConfigCheck verifies these numbers stay consistent.

export type Vec3 = { x: number, y: number, z: number }
export type Cost = { stardust: number, materials: { [string]: number } }

export type ExpansionDef = {
	size: Vec3, -- studs: x = width, y = height, z = depth (away from the ISS)
	maxSystems: number,
	cost: Cost?, -- nil for the starting size
}

local Galaxy = {
	STAR_MAX_RADIUS = 30,
	PLANET_MAX_RADIUS = 7,
	MOON_MAX_RADIUS = 2,

	PLANET_ORBIT_RADII = { 52, 96, 140, 184 } :: { number },
	MOON_ORBIT_RADII = { 11, 16 } :: { number },

	SYSTEM_RADIUS = 210, -- nothing in a system reaches further than this from its star
	MIN_STAR_SPACING = 420, -- 2 x SYSTEM_RADIUS, so systems never overlap
	WALL_MARGIN = 210, -- star centres stay this far inside the region walls

	GRID_SNAP = 10, -- optional placement snapping, studs

	EXPANSIONS = {
		{
			size = { x = 1024, y = 640, z = 1024 },
			maxSystems = 1,
			cost = nil,
		},
		{
			size = { x = 1536, y = 896, z = 1536 },
			maxSystems = 3,
			cost = { stardust = 6000, materials = { Iron = 300, Silicate = 300 } },
		},
		{
			size = { x = 2048, y = 1152, z = 2048 },
			maxSystems = 6,
			cost = { stardust = 40000, materials = { Iron = 800, Silicate = 800, Ice = 300 } },
		},
	} :: { ExpansionDef },
}

return Galaxy
