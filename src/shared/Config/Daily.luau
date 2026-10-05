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
	{ stardust = 250 },
	{ stardust = 400 },
	{ boost = { source = "mining", seconds = 10 * 60 } },
	{ stardust = 700 },
	{ stardust = 1000 },
	{ boost = { source = "star", seconds = 15 * 60 } },
	{ stardust = 3500, big = true },
	{ stardust = 1900 },
	{ stardust = 2500 },
	{ boost = { source = "mining", seconds = 20 * 60 } },
	{ stardust = 3600 },
	{ stardust = 4500 },
	{ boost = { source = "star", seconds = 30 * 60 } },
	{ stardust = 15000, big = true },
}

return {
	PRIZES = PRIZES,
	DAY_SECONDS = 86400, -- a "day" is a UTC calendar day
	OPEN_ON_JOIN = true, -- show the calendar on join when a prize is waiting
}
