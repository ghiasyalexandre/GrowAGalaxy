--!strict
-- The first-session tutorial: one hint at a time on the HUD. A step is done
-- once its stat (profile.stats) is at least 1, so steps can be completed in
-- any order; the HUD shows the first step not done yet. Logic/Progression
-- works out the current step.

export type StepDef = {
	stat: string,
	text: string,
}

local STEPS: { StepDef } = {
	{ stat = "shipsLaunched", text = "Use the Hangar console to launch your ship, then board it." },
	{
		stat = "asteroidsMined",
		text = "Follow the scanner markers to an asteroid. Click to shoot its glowing weak point.",
	},
	{ stat = "starsPlaced", text = "Back at your station, buy your first star at the Star Shop." },
	{ stat = "collections", text = "Your star makes Stardust. Pick it up at the Collect console." },
	{
		stat = "planetsBought",
		text = "Fly to your star, choose Manage star and buy a planet to orbit it.",
	},
}

return {
	STEPS = STEPS,
}
