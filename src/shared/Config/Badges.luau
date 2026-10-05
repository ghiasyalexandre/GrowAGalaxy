--!strict
-- Roblox badges (Creator Hub ids), awarded by the server (BadgeSystem).
-- Each is earned when a saved stat reaches its goal; players who already
-- reached it before the badge existed get it the next time they join.

export type BadgeDef = {
	id: number, -- Creator Hub badge id
	displayName: string,
	stat: string, -- profile.stats key
	goal: number,
}

local BY_KEY: { [string]: BadgeDef } = {
	BlackHole = {
		id = 748713779889083,
		displayName = "Black Hole",
		stat = "blackHoles", -- a star evolved into a Black Hole
		goal = 1,
	},
}

return {
	BY_KEY = BY_KEY,
}
