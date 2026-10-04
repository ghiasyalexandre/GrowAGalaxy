--!strict
-- Solar-system tiers. Each system starts at tier 1. A tier raises the level
-- caps of the bodies inside it and multiplies the system's income.
--
-- Rule (checked by Logic/ConfigCheck): tier N's requirements must be reachable
-- under tier N-1's caps, so an upgrade never requires something only it unlocks.

export type Cost = { stardust: number, materials: { [string]: number } }

export type TierRequirements = {
	starLevel: number,
	planets: number,
	planetMinLevel: number, -- every counted planet must be at least this level
	moons: number,
	cost: Cost,
}

export type TierDef = {
	name: string,
	enabled: boolean,
	incomeMultiplier: number,
	bonusPlanetSlots: number, -- added to the star's own slot count (capped by Galaxy orbits)
	levelCaps: { star: number, planet: number, moon: number },
	requirements: TierRequirements?, -- nil for tier 1
}

local TIERS: { TierDef } = {
	{
		name = "Fledgling",
		enabled = true,
		incomeMultiplier = 1,
		bonusPlanetSlots = 0,
		levelCaps = { star = 2, planet = 2, moon = 2 },
		requirements = nil,
	},
	{
		name = "Settled",
		enabled = true,
		incomeMultiplier = 1.25,
		bonusPlanetSlots = 1,
		levelCaps = { star = 3, planet = 4, moon = 3 },
		requirements = {
			starLevel = 2,
			planets = 2,
			planetMinLevel = 2,
			moons = 1,
			cost = { stardust = 1500, materials = { Iron = 120, Silicate = 120 } },
		},
	},
	{
		name = "Thriving",
		enabled = false,
		incomeMultiplier = 1.6,
		bonusPlanetSlots = 1,
		levelCaps = { star = 3, planet = 4, moon = 3 },
		requirements = {
			starLevel = 3,
			planets = 3,
			planetMinLevel = 3,
			moons = 3,
			cost = { stardust = 8000, materials = { Iron = 400, Silicate = 400 } },
		},
	},
}

return {
	TIERS = TIERS,
}
