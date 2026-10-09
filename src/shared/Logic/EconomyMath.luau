--!strict
-- Economy v2 accounting (docs/stage-48-economy-v2.md), shared by the server,
-- the client's panels and the tests. Pure: no Roblox services.
--
--   B  production per second: every star's own rate plus every equipped
--      planet's share of its host star, times the equipped trail and the
--      Refinery. No passes, boosts, mining or rewards. It prices nothing by
--      itself; mining pays a share of it.
--   H  the profile's best B so far (economy.high, never falls): eggs and
--      planet upgrades are priced from it, so unequipping can't make them
--      cheaper.
--   R  the reward rate: the average B over the last REWARD_WINDOW_SECONDS of
--      online play, snapshotted once per reward (UTC) day (at least 1).
--      Daily prizes, the wheel, raids, achievements, codes and vanity
--      prices are minutes of it. Never derived from the wallet, passes or
--      boosts.

local Config = require(script.Parent.Parent.Config)
local HangarMath = require(script.Parent.HangarMath)
local StarMath = require(script.Parent.StarMath)
local Types = require(script.Parent.Parent.Types)

local E = Config.Economy

local EconomyMath = {}

-- The equipped trail's multiplier (1 with none).
function EconomyMath.trail(profile: Types.Profile): number
	local def = if profile.trail then Config.Trails.BY_ID[profile.trail] else nil
	return if def then def.multiplier else 1
end

-- B: Stardust per second from stars and planets in orbit, with the trail
-- and the Refinery, before passes and boosts. Not rounded.
function EconomyMath.production(profile: Types.Profile): number
	return StarMath.totalIncome(profile.galaxy.stars, profile.planets)
		* EconomyMath.trail(profile)
		* HangarMath.incomeMultiplier(profile.hangar)
end

-- H: the saved best production, or B now if that's higher.
function EconomyMath.high(profile: Types.Profile): number
	return math.max(profile.economy.high, EconomyMath.production(profile))
end

-- The next egg roll's price from H and the eggs kept: one to two minutes of
-- the best production, never under the floor, rounded up.
function EconomyMath.eggPrice(high: number, kept: number): number
	local eggs = Config.Eggs
	local base = math.max(eggs.PRICE_BASE, eggs.PRICE_INCOME_SECONDS * math.max(high, 0))
	local growth = math.min(eggs.PRICE_GROWTH_CAP, eggs.PRICE_GROWTH ^ math.max(kept, 0))
	return math.ceil(base * growth - 1e-9)
end

-- The egg price for a profile now.
function EconomyMath.profileEggPrice(profile: Types.Profile): number
	return EconomyMath.eggPrice(EconomyMath.high(profile), profile.eggsBought)
end

-- Stardust worth `minutes` of reward rate R (at least 1/s), whole, and at
-- least `minimum`.
function EconomyMath.reward(minutes: number, rate: number, minimum: number?): number
	local amount = math.floor(60 * minutes * math.max(1, rate))
	return math.max(amount, minimum or 0)
end

-- The mining factor a for a ship on the ladder (1 = the starter) and the
-- equipment levels the player owns in total.
function EconomyMath.miningFactor(shipStep: number, itemLevels: number): number
	local s = math.clamp(shipStep - 1, 0, E.MINING_SHIP_STEPS)
	local e = math.clamp(itemLevels, 0, E.MINING_ITEM_LEVELS)
	return E.MINING_BASE + E.MINING_PER_SHIP * s + E.MINING_PER_ITEM_LEVEL * e
end

-- The mining factor for a profile: its active ship's place on the ladder
-- and the levels of the equipment bought for that ship.
function EconomyMath.profileMiningFactor(profile: Types.Profile): number
	local step = table.find(Config.Ships.ORDER, profile.activeShip) or 1
	local loadout = profile.loadouts[profile.activeShip]
	local levels = 0
	if loadout then
		for _, level in loadout.levels do
			levels += level
		end
	end
	return EconomyMath.miningFactor(step, levels)
end

-- Stardust for breaking an asteroid: B x a x reference work seconds, the
-- precision bonus for the share of work on the weak point, times
-- `multiplier` (mining pass, boost, swarm bonus). Whole.
function EconomyMath.miningPayout(
	production: number,
	factor: number,
	work: number,
	weakShare: number,
	multiplier: number
): number
	local precision = 1 + Config.Asteroids.PRECISION_BONUS * math.clamp(weakShare, 0, 1)
	return math.max(
		1,
		math.floor(math.max(production, 1) * factor * work * precision * multiplier + 0.5)
	)
end

-- The collector tank's capacity: UNCOLLECTED_CAP_SECONDS of online income
-- (rate with the star pass), raised by the Silo.
function EconomyMath.tankCap(rate: number, storage: number): number
	return math.max(rate, 1) * E.UNCOLLECTED_CAP_SECONDS * storage
end

-- Rolling average of B for R. `window` is the player's online history:
-- one bucket per minute (minute number -> { weighted B, seconds }).
export type Window = { [number]: { sum: number, seconds: number } }

-- Adds `dt` seconds at production `rate` ending at `clock` seconds, drops
-- buckets older than REWARD_WINDOW_SECONDS, and returns the average B over
-- what is left (0 with no history).
function EconomyMath.track(window: Window, rate: number, dt: number, clock: number): number
	local minute = math.floor(clock / 60)
	local bucket = window[minute]
	if bucket == nil then
		bucket = { sum = 0, seconds = 0 }
		window[minute] = bucket
	end
	bucket.sum += math.max(rate, 0) * math.max(dt, 0)
	bucket.seconds += math.max(dt, 0)
	local oldest = minute - math.ceil(E.REWARD_WINDOW_SECONDS / 60) + 1
	local sum, seconds = 0, 0
	for key, item in window do
		if key < oldest then
			window[key] = nil
		else
			sum += item.sum
			seconds += item.seconds
		end
	end
	return if seconds > 0 then sum / seconds else 0
end

-- R for a reward day: the last session's average B, at least 1.
function EconomyMath.snapshot(recent: number): number
	return math.max(1, recent)
end

-- The price of the next Constellation Project at `rank` (0 for the first).
function EconomyMath.constellationPrice(rank: number): number
	local steps = math.min(math.max(rank, 0), E.CONSTELLATION_STEPS)
	return math.min(
		E.CONSTELLATION_CAP,
		math.ceil(E.CONSTELLATION_SECONDS * E.CONSTELLATION_RATE * E.CONSTELLATION_GROWTH ^ steps)
	)
end

-- Whether a profile may start Constellation Projects: CONSTELLATION_STARS
-- top-type stars at their max level, and the best Egg Lab.
function EconomyMath.constellationReady(profile: Types.Profile): boolean
	local S = Config.Stars
	local top = S.ORDER[#S.ORDER]
	local maxed = 0
	for _, star in profile.galaxy.stars do
		if star.typeId == top and star.level >= StarMath.maxLevel(top) then
			maxed += 1
		end
	end
	return maxed >= E.CONSTELLATION_STARS and profile.eggLab.level >= #Config.Eggs.LAB_LEVELS
end

-- A level from before economy v2 mapped onto a new max, keeping the share
-- of the way to max: 1 + floor((old - 1) / (oldMax - 1) x (newMax - 1)).
function EconomyMath.remapLevel(old: number, oldMax: number, newMax: number): number
	if oldMax <= 1 then
		return 1
	end
	local share = math.clamp((old - 1) / (oldMax - 1), 0, 1)
	return math.clamp(1 + math.floor(share * (newMax - 1) + 1e-9), 1, newMax)
end

return EconomyMath
