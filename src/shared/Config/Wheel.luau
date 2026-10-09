--!strict
-- The daily prize wheel (HUD button on the right): one free spin every
-- COOLDOWN seconds. Prizes are minutes of the player's reward rate R
-- (Logic/EconomyMath.reward: today's snapshot of their production), with no
-- other multiplier; `weight` out of the prizes' total is the exact chance,
-- shown on the wheel. The server picks the prize and grants it before the
-- client's spin animation starts.

export type Prize = { minutes: number, weight: number, color: string }

return {
	COOLDOWN = 24 * 60 * 60,
	SPIN_COST = 0, -- free
	PRIZES = {
		{ minutes = 1, weight = 40, color = "#5FE3FF" },
		{ minutes = 2, weight = 25, color = "#5CFF8A" },
		{ minutes = 3, weight = 15, color = "#FFE13D" },
		{ minutes = 5, weight = 12, color = "#FFB020" },
		{ minutes = 8, weight = 6, color = "#FF6EC8" },
		{ minutes = 12, weight = 2, color = "#B06BFF" },
	} :: { Prize },
	SPIN_SECONDS = 4, -- the wheel animation (1 s with reduced motion)
}
