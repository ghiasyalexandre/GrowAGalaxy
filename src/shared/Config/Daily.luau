--!strict
-- Daily prizes: one claim per day (UTC), working through days 1 to 14, then
-- starting again at day 1. Missing a day never loses progress: the next
-- claim is simply the next day on the calendar.
--
-- Each day gives Stardust worth `minutes` of the player's reward rate R
-- (Logic/EconomyMath.reward: today's snapshot of their production, at least
-- 1/s), so prizes stay meaningful all game. No other multiplier applies.

export type Prize = {
	minutes: number,
	big: boolean?, -- shown larger, with extra sparkle (days 7 and 14)
}

local PRIZES: { Prize } = {
	{ minutes = 2 },
	{ minutes = 3 },
	{ minutes = 4 },
	{ minutes = 4 },
	{ minutes = 5 },
	{ minutes = 6 },
	{ minutes = 8, big = true },
	{ minutes = 4 },
	{ minutes = 5 },
	{ minutes = 6 },
	{ minutes = 8 },
	{ minutes = 10 },
	{ minutes = 12 },
	{ minutes = 15, big = true },
}

return {
	PRIZES = PRIZES,
	DAY_SECONDS = 86400, -- a "day" is a UTC calendar day
	OPEN_ON_JOIN = true, -- show the calendar on join when a prize is waiting
}
