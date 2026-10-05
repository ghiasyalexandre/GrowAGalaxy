--!strict
-- Ship colours, chosen per ship in the Shipyard's Colors tab and saved in
-- that ship's loadout. Purely cosmetic.
--
--   laserColor  the mining laser's (and rocket blast's) colour, from SWATCHES;
--               none = the standard laser (Config.Beam.COLOR)
--   boostColor  the engine glow, exhaust and wing trails, from SWATCHES;
--               none = the standard engine blue
--
-- Also how many ships the hangar's Showcase Dock holds.

return {
	-- Colours offered for lasers and boosts, in display order.
	SWATCHES = {
		"#FF6A3D",
		"#FF3B3B",
		"#FF4FA3",
		"#C04DFF",
		"#7A5CFF",
		"#3B7BFF",
		"#3FD2FF",
		"#3FFFD0",
		"#5CFF6B",
		"#C8FF3D",
		"#FFE13D",
		"#FFB020",
		"#FFFFFF",
		"#FFD6A0",
	} :: { string },
	DEFAULT_BOOST = "#3A7BFF", -- the standard exhaust's outer colour
	SHOWCASE_SLOTS = 3,
}
