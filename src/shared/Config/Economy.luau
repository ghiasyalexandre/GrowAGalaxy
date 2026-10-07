--!strict
-- Stardust, the one currency. Players earn it by mining asteroids (paid at
-- once, see Config.Asteroids) and from the stars in their galaxy (accrues as
-- "uncollected" until collected at their station, Stage 4). They spend it on
-- stars, star upgrades, ships, equipment and galaxy expansion.
--
-- The server adds star income x elapsed time to "uncollected" once per tick
-- while a player is online. Offline: when they come back, their stars pay
-- what they made while away (at the rate they had when they left, with
-- permanent passes and trail; boosts don't run offline), up to
-- OFFLINE_CAP_SECONDS of it, straight into the wallet (Logic/OfflineMath).

local Economy = {
	CURRENCY_NAME = "Stardust",
	STARTING_STARDUST = 100, -- enough for the first star (Logic/ConfigCheck makes sure)
	INCOME_TICK_SECONDS = 1,
	UNCOLLECTED_CAP_SECONDS = 10000000, -- uncollected Stardust stops growing after this much income
	OFFLINE_CAP_SECONDS = 1 * 86400, -- offline earnings count at most 3 days
	OFFLINE_MIN_SECONDS = 60, -- shorter breaks (rejoins) earn nothing extra
}

return Economy
