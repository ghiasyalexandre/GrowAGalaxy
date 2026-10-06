--!strict
-- Geometry and capacity of a player's galaxy region.
--
-- Orbit radii are fixed per slot, so bodies can never collide and a whole
-- solar system always fits inside SYSTEM_RADIUS. Placement then only has to
-- keep systems' footprints apart (Logic/PlacementRules) and inside the walls.
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

	-- A system's reserved footprint: a flat disc around its star that its
	-- largest layout never leaves. Nothing reaches further than SYSTEM_RADIUS
	-- sideways or SYSTEM_HALF_HEIGHT up or down (orbits tilt only a little).
	-- Two systems may not overlap footprints; they may stack vertically.
	SYSTEM_RADIUS = 222,
	SYSTEM_HALF_HEIGHT = 48,
	-- Star centres stay this far inside the side/front/back walls, and the
	-- floor and ceiling, so footprints stay inside the region.
	WALL_MARGIN = 222,
	WALL_MARGIN_Y = 48,

	GRID_SNAP = 10, -- optional placement snapping, studs

	EXPANSIONS = {
		{
			size = { x = 1024, y = 640, z = 1024 },
			maxSystems = 3,
			cost = nil,
		},
		{
			size = { x = 1536, y = 896, z = 1536 },
			maxSystems = 6,
			cost = { stardust = 12000, materials = {} },
		},
		{
			size = { x = 2048, y = 1152, z = 2048 },
			maxSystems = 10,
			cost = { stardust = 90000, materials = {} },
		},
	} :: { ExpansionDef },
}

return Galaxy
