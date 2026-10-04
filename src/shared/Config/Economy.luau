--!strict
-- Credits and income. Income formula (Logic/Income, Stage 5):
--
--   system income = tier multiplier x (star income + sum of planet incomes)
--   planet income = planet level income x (1 + sum of its moons' bonuses)
--   total rate    = sum of system incomes
--
-- The server adds rate x elapsed time to "uncollected" once per tick, for
-- online players only (no offline income in the MVP).

local Economy = {
	CURRENCY_NAME = "Credits",
	STARTING_CREDITS = 0,
	INCOME_TICK_SECONDS = 1,
	UNCOLLECTED_CAP_SECONDS = 7200, -- uncollected Credits stop growing after this much income
}

return Economy
