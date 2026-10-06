--!strict
-- The daily prize wheel (HUD button on the right): one spin every COOLDOWN
-- seconds, costing SPIN_COST Stardust (never Robux). Because Stardust can
-- be bought, a spin is a paid random item: it's only offered where
-- PolicyService allows those (as mystery eggs). Prizes are fixed Stardust amounts that no
-- multiplier touches; `weight` out of the prizes' total is the exact chance,
-- shown on the wheel. The server picks the prize and grants it before the
-- client's spin animation starts.

export type Prize = { stardust: number, weight: number, color: string }

return {
	COOLDOWN = 24 * 60 * 60,
	SPIN_COST = 1000, -- Stardust per spin
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
