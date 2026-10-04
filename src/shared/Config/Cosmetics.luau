--!strict
-- Cosmetics never change gameplay stats. A cosmetic is earned (achievement
-- reward), bought (productKey into Config.Products), or both.

export type CosmeticDef = {
	id: string,
	displayName: string,
	kind: "ShipSkin" | "BeamColor" | "ThrusterTrail" | "StationTheme" | "Title",
	enabled: boolean,
	productKey: string?,
}

local BY_ID: { [string]: CosmeticDef } = {
	StargazerTitle = {
		id = "StargazerTitle",
		displayName = "Title: Stargazer",
		kind = "Title",
		enabled = true,
		productKey = nil,
	},
	GoldenBeam = {
		id = "GoldenBeam",
		displayName = "Golden Beam",
		kind = "BeamColor",
		enabled = false,
		productKey = nil,
	},
	AuroraTrail = {
		id = "AuroraTrail",
		displayName = "Aurora Thruster Trail",
		kind = "ThrusterTrail",
		enabled = false,
		productKey = "AuroraTrailPack",
	},
}

return {
	BY_ID = BY_ID,
}
