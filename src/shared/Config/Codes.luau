--!strict
-- Redeemable codes, typed in the Settings panel (CodeSystem). Each can be
-- redeemed once per player; letter case and spaces around it don't matter.
-- Rewards are fixed amounts (no multipliers apply).

export type CodeDef = {
	stardust: number?,
	boost: { source: "mining" | "star", seconds: number }?,
	allPlanets: boolean?, -- one level 1 planet of every type, into the inventory
	allShips: boolean?, -- every ship in Config.Ships
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
	STARZSHIPZ = {
		allShips = true,
		message = "Every spaceship is yours! Pick one in the Shipyard.",
	},
}

return {
	BY_CODE = BY_CODE,
	MAX_LENGTH = 32,
}
