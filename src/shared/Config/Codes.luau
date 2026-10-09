--!strict
-- Redeemable codes, typed in the Settings panel (CodeSystem). Each can be
-- redeemed once per player; letter case and spaces around it don't matter.
-- Stardust rewards are `minutes` of the player's reward rate R
-- (Logic/EconomyMath.reward), so a code is worth the same share of
-- progress at any stage.

export type CodeDef = {
	minutes: number?,
	allPlanets: boolean?, -- one level 1 planet of every type, into the inventory
	allShips: boolean?, -- every ship in Config.Ships
	cloak: boolean?, -- unlocks the Cloak switch in Settings (CloakSystem)
	-- Erases the player's progress (a fresh save, all codes usable again;
	-- purchase receipts kept). Must be typed twice within RESET_CONFIRM_SECONDS.
	reset: boolean?,
	message: string, -- shown when redeemed
}

local BY_CODE: { [string]: CodeDef } = {
	ILUVGHIASY = {
		minutes = 120000,
		message = "Two minutes of your production in Stardust!",
	},
	BETATESTER = {
		minutes = 120,
		message = "Two minutes of your production in Stardust!",
	},
	-- Codes are matched upper-cased: "PlanetzPlz" and "StarzShipz" work.
	PLANETZPLZ = {
		allPlanets = true,
		message = "One of every planet is in your Planets panel (P)!",
	},
	RESETMYGALAXY = {
		reset = true,
		message = "Your galaxy has been reset. Rejoin to start fresh!",
	},
	SNEAKYSPACE = {
		cloak = true,
		message = "Cloak unlocked! Turn it on in Settings to sneak around unseen.",
	},
	STARZSHIPZ = {
		allShips = true,
		message = "Every spaceship is yours! Pick one in the Shipyard.",
	},
}

return {
	BY_CODE = BY_CODE,
	MAX_LENGTH = 32,
	RESET_CONFIRM_SECONDS = 30,
}
