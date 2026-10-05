--!strict
-- Redeemable codes, typed in the Settings panel (CodeSystem). Each can be
-- redeemed once per player; letter case and spaces around it don't matter.
-- Rewards are fixed amounts (no multipliers apply).

export type CodeDef = {
	stardust: number?,
	boost: { source: "mining" | "star", seconds: number }?,
	message: string, -- shown when redeemed
}

local BY_CODE: { [string]: CodeDef } = {
	ILUVGHIASY = {
		stardust = 5000000,
		message = "+5,000,000 Stardust!",
	},
}

return {
	BY_CODE = BY_CODE,
	MAX_LENGTH = 32,
}
