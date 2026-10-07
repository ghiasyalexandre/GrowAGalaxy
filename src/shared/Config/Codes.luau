--!strict
-- Redeemable codes, typed in the Settings panel (CodeSystem). Each can be
-- redeemed once per player; letter case and spaces around it don't matter.
-- Rewards are fixed amounts (no multipliers apply).

export type CodeDef = {
	stardust: number?,
	boost: { source: "mining" | "star", seconds: number }?,
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
		stardust = 5000000,
		message = "+5,000,000 Stardust!",
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
