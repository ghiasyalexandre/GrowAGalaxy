--!strict
-- Stardust, the one currency. Players earn it by mining asteroids (paid at
-- once, see Config.Asteroids) and from the stars in their galaxy (accrues as
-- "uncollected" until collected at their station, Stage 4). They spend it on
-- stars, star upgrades, ships, equipment and galaxy expansion.
--
-- The server adds star income x elapsed time to "uncollected" once per tick,
-- for online players only (no offline income in the MVP).

local Economy = {
	CURRENCY_NAME = "Stardust",
	STARTING_STARDUST = 0,
	INCOME_TICK_SECONDS = 1,
	UNCOLLECTED_CAP_SECONDS = 7200, -- uncollected Stardust stops growing after this much income
}

return Economy
