--!strict
-- Daily prizes: one claim per day (UTC), working through days 1 to 14, then
-- starting again at day 1. Missing a day never loses progress: the next
-- claim is simply the next day on the calendar.
--
-- Each day gives Stardust, or free boost time (the same 2x boosts sold in the
-- Store, Config.Products.BOOST_MULTIPLIER). Rewards are fixed amounts:
-- multipliers never apply to them.

export type Prize = {
	stardust: number?,
	boost: { source: "mining" | "star", seconds: number }?,
	big: boolean?, -- shown larger, with extra sparkle (days 7 and 14)
}

local PRIZES: { Prize } = {
	-- Each day's Stardust grows faster than the last (a curve, not a line).
	{ stardust = 5000 },
	{ stardust = 25000 },
	{ boost = { source = "mining", seconds = 15 * 60 } },
	{ stardust = 50000 },
	{ stardust = 100000 },
	{ boost = { source = "star", seconds = 20 * 60 } },
	{ stardust = 250000, big = true },
	{ stardust = 100000 },
	{ stardust = 100000 },
	{ boost = { source = "mining", seconds = 30 * 60 } },
	{ stardust = 250000 },
	{ stardust = 1000000 },
	{ boost = { source = "star", seconds = 30 * 60 } },
	{ stardust = 5000000, big = true },
}

return {
	PRIZES = PRIZES,
	DAY_SECONDS = 86400, -- a "day" is a UTC calendar day
	OPEN_ON_JOIN = true, -- show the calendar on join when a prize is waiting
}
