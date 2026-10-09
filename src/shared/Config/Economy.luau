--!strict
-- Stardust, the one currency. Players earn it by mining asteroids (paid at
-- once, see Config.Asteroids) and from the stars in their galaxy (accrues as
-- "uncollected" until collected at their station, Stage 4). They spend it on
-- stars, star upgrades, ships, equipment and galaxy expansion.
--
-- The server adds star income x elapsed time to "uncollected" once per tick
-- while a player is online. Offline: when they come back, their stars pay
-- OFFLINE_RATE of what they made while away (at the rate they had when they
-- left, with the star pass and trail; boosts don't run offline), counting
-- up to OFFLINE_CAP_SECONDS, straight into the wallet (Logic/OfflineMath).

local Economy = {
	CURRENCY_NAME = "Stardust",
	STARTING_STARDUST = 100, -- enough for the first star (Logic/ConfigCheck makes sure)
	INCOME_TICK_SECONDS = 1,
	-- The collector's tank holds this many seconds of permanent online income
	-- (stars and planets with the star pass, no boosts); new income pauses
	-- when it's full until collected. The Stardust Silo raises it.
	UNCOLLECTED_CAP_SECONDS = 2 * 3600,
	-- Offline: at most this many seconds count (the Silo raises it too), paid
	-- at OFFLINE_RATE of the production rate at logout.
	OFFLINE_CAP_SECONDS = 8 * 3600,
	OFFLINE_RATE = 0.25,
	OFFLINE_MIN_SECONDS = 60, -- shorter breaks (rejoins) earn nothing extra

	-- Reward rate R (Logic/EconomyMath): the average production B over the
	-- last REWARD_WINDOW_SECONDS of online play, snapshotted once per reward
	-- (UTC) day. Daily prizes, the wheel, raids, achievements, codes and
	-- vanity prices are minutes of it.
	REWARD_WINDOW_SECONDS = 600,

	-- Mining pays production B x a per reference work second, where
	-- a = MINING_BASE + MINING_PER_SHIP x (ship ladder step - 1)
	--   + MINING_PER_ITEM_LEVEL x (equipment levels owned), so active play
	-- earns about 1.65 to 1.85 x idle production.
	MINING_BASE = 0.65,
	MINING_PER_SHIP = 0.015,
	MINING_SHIP_STEPS = 10, -- ship steps counted (the 11-ship ladder)
	MINING_PER_ITEM_LEVEL = 0.003125,
	MINING_ITEM_LEVELS = 16, -- item levels counted (4 groups x 4 levels)

	-- Constellation Projects (the day-30+ sink): once a player owns
	-- CONSTELLATION_STARS max-level stars of the top type and the best Egg
	-- Lab, each project costs CONSTELLATION_SECONDS of the reference max-fleet
	-- production x CONSTELLATION_GROWTH^min(rank, CONSTELLATION_STEPS), at
	-- most CONSTELLATION_CAP, and raises their constellation rank (cosmetic
	-- only: no income or power).
	CONSTELLATION_STARS = 20,
	CONSTELLATION_RATE = 4105365781.77, -- reference max-fleet production, per second
	CONSTELLATION_SECONDS = 21600,
	CONSTELLATION_GROWTH = 1.2,
	CONSTELLATION_STEPS = 18,
	CONSTELLATION_CAP = 2e15,
}

return Economy
