--!strict
-- Robux products (Stage 8). Purchases stay switched off until real ids from the
-- Creator Dashboard are filled in and PURCHASES_ENABLED is set to true.
-- Everything sold here is either cosmetic or also earnable through gameplay.

export type ProductDef = {
	key: string,
	kind: "GamePass" | "DeveloperProduct",
	id: number, -- 0 = not configured yet
	displayName: string,
	grants: { ship: string?, cosmetic: string? },
}

local BY_KEY: { [string]: ProductDef } = {
	GalactixRacerUnlock = {
		key = "GalactixRacerUnlock",
		kind = "GamePass",
		id = 0,
		displayName = "Galactix Racer (instant unlock)",
		grants = { ship = "GalactixRacer" },
	},
	AuroraTrailPack = {
		key = "AuroraTrailPack",
		kind = "GamePass",
		id = 0,
		displayName = "Aurora Thruster Trail",
		grants = { cosmetic = "AuroraTrail" },
	},
}

return {
	PURCHASES_ENABLED = false,
	BY_KEY = BY_KEY,
}
