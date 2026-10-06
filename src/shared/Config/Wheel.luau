--!strict
-- The daily prize wheel (HUD button on the right): one free spin every
-- COOLDOWN seconds, no paid spins. Prizes are fixed Stardust amounts that no
-- multiplier touches; `weight` out of the prizes' total is the exact chance,
-- shown on the wheel. The server picks the prize and grants it before the
-- client's spin animation starts.

export type Prize = { stardust: number, weight: number, color: string }

return {
	COOLDOWN = 24 * 60 * 60,
	PRIZES = {
		{ stardust = 1000, weight = 40, color = "#5FE3FF" },
		{ stardust = 2500, weight = 25, color = "#5CFF8A" },
		{ stardust = 5000, weight = 15, color = "#FFE13D" },
		{ stardust = 10000, weight = 12, color = "#FFB020" },
		{ stardust = 15000, weight = 6, color = "#FF6EC8" },
		{ stardust = 25000, weight = 2, color = "#B06BFF" },
	} :: { Prize },
	SPIN_SECONDS = 4, -- the wheel animation (1 s with reduced motion)
}
