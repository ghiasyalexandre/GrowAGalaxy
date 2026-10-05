--!strict
-- Ship paint jobs, chosen per ship in the Shipyard's Paint tab and saved in
-- that ship's loadout. Purely cosmetic.
--
--   paint   a colour from SWATCHES, or none for the ship's factory colours.
--           Imported models are textured: each client turns the texture to
--           greyscale and multiplies it by the colour (ShipPaintController),
--           so panel lines and shading survive the new coat.
--   finish  a FINISHES id, or none for the factory finish.

export type FinishDef = {
	id: string,
	displayName: string,
	material: string, -- Enum.Material name
	reflectance: number,
}

local FINISH_ORDER: { string } = { "Standard", "Metallic", "Glossy" }

local FINISHES: { [string]: FinishDef } = {
	Standard = {
		id = "Standard",
		displayName = "Standard",
		material = "SmoothPlastic",
		reflectance = 0,
	},
	Metallic = {
		id = "Metallic",
		displayName = "Metallic",
		material = "Metal",
		reflectance = 0.15,
	},
	Glossy = {
		id = "Glossy",
		displayName = "Glossy",
		material = "SmoothPlastic",
		reflectance = 0.35,
	},
}

return {
	FINISH_ORDER = FINISH_ORDER,
	FINISHES = FINISHES,
	-- Colours offered in the Paint tab, in display order.
	SWATCHES = {
		"#F2F4F7",
		"#9AA3B0",
		"#3A3F4B",
		"#151820",
		"#E23B3B",
		"#FF7A2F",
		"#FFC83D",
		"#B8E04A",
		"#3FD27A",
		"#2FC7C9",
		"#3FA9F5",
		"#3B5BDB",
		"#8C4DE0",
		"#E04FB0",
		"#FF9EC4",
		"#8A5A3C",
	} :: { string },
	-- How bright the greyscale texture is kept before the colour multiplies
	-- it: 0 = pure greyscale x colour; higher keeps more contrast in dark coats.
	TINT_FLOOR = 0.12,
	-- Ships a player can put on show in their hangar's Showcase Dock.
	SHOWCASE_SLOTS = 3,
}
