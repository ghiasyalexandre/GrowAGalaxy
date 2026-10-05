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
	{ stardust = 250 },
	{ stardust = 400 },
	{ boost = { source = "mining", seconds = 10 * 60 } },
	{ stardust = 700 },
	{ stardust = 1000 },
	{ boost = { source = "star", seconds = 10 * 60 } },
	{ stardust = 2500, big = true },
	{ stardust = 1500 },
	{ stardust = 2000 },
	{ boost = { source = "mining", seconds = 20 * 60 } },
	{ stardust = 3000 },
	{ stardust = 4000 },
	{ boost = { source = "star", seconds = 20 * 60 } },
	{ stardust = 10000, big = true },
}

return {
	PRIZES = PRIZES,
	DAY_SECONDS = 86400, -- a "day" is a UTC calendar day
	OPEN_ON_JOIN = true, -- show the calendar on join when a prize is waiting
}
