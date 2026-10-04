--!strict
-- Planets, bought into a star's open orbit slots (Config.Stars.SLOTS). Eight
-- tiers from Barren Rock to Crystal World. A star holds planets up to its own
-- tier, so better stars unlock better planets. A planet can be upgraded in
-- its slot to the next tier for that tier's price minus half the current
-- one's. Every planet adds its income to its star's.
-- Logic/ConfigCheck validates this table.

export type PlanetTypeDef = {
	id: string,
	displayName: string,
	tier: number,
	enabled: boolean,
	cost: number, -- Stardust
	income: number, -- Stardust per second
	radius: number, -- studs; at most Config.Galaxy.PLANET_MAX_RADIUS
	color: string,
	material: string, -- Enum.Material name
	ring: string?, -- colour of a ring around the planet, if any
}

local ORDER: { string } = {
	"Barren",
	"Molten",
	"Desert",
	"Ocean",
	"Terran",
	"IceGiant",
	"GasGiant",
	"Crystal",
}

local function planet(
	id: string,
	tier: number,
	name: string,
	cost: number,
	income: number,
	radius: number,
	color: string,
	material: string,
	ring: string?
): PlanetTypeDef
	return {
		id = id,
		displayName = name,
		tier = tier,
		enabled = true,
		cost = cost,
		income = income,
		radius = radius,
		color = color,
		material = material,
		ring = ring,
	}
end

local BY_ID: { [string]: PlanetTypeDef } = {
	Barren = planet("Barren", 1, "Barren Rock", 150, 1.5, 3.5, "#8C8478", "Slate"),
	Molten = planet("Molten", 2, "Molten World", 800, 5, 4, "#D9542B", "CrackedLava"),
	Desert = planet("Desert", 3, "Desert World", 3000, 14, 4.5, "#D9B26A", "Sand"),
	Ocean = planet("Ocean", 4, "Ocean World", 9000, 35, 5, "#2F7FD6", "Glass"),
	Terran = planet("Terran", 5, "Terran World", 28000, 85, 5.5, "#4F9D5B", "Grass"),
	IceGiant = planet("IceGiant", 6, "Ice Giant", 80000, 200, 6, "#9FE3F0", "Glacier"),
	GasGiant = planet(
		"GasGiant",
		7,
		"Gas Giant",
		220000,
		480,
		6.8,
		"#E0A960",
		"SmoothPlastic",
		"#F3D9A8"
	),
	Crystal = planet(
		"Crystal",
		8,
		"Crystal World",
		650000,
		1100,
		6.2,
		"#C08CFF",
		"Neon",
		"#E9D6FF"
	),
}

return {
	ORDER = ORDER,
	BY_ID = BY_ID,
	-- Upgrading a planet credits this share of its current tier's price.
	UPGRADE_CREDIT = 0.5,
}
