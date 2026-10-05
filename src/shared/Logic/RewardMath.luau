--!strict
-- Every reward multiplier in one place. The server applies these when a
-- reward is earned or production accrues, exactly once:
--
--   effective multiplier = permanent (pass) x temporary (boost)
--
-- Mining and star production are separate sources; neither's multiplier
-- touches the other, and neither touches purchased Stardust, balances,
-- income already accrued, or moving income from "uncollected" to the wallet.
-- Beam power (extraction speed) is separate from rewards too.
--
-- Entitlements: `passes` are pass keys the server has verified with Roblox;
-- `boosts` are seconds of boost time left per source.
-- Pure module: no Roblox services.

local Config = require(script.Parent.Parent.Config)

local P = Config.Products

export type Source = "mining" | "star"

export type Entitlements = {
	passes: { [string]: boolean },
	boosts: { mining: number, star: number },
	trail: number?, -- the equipped trail's multiplier (Config.Trails); 1 when nil
}

local RewardMath = {}

-- No passes, no boosts: everything at 1x.
function RewardMath.none(): Entitlements
	return { passes = {}, boosts = { mining = 0, star = 0 } }
end

local function grantsOf(key: string): any
	local def = P.BY_KEY[key]
	return if def and def.enabled then def.grants else nil
end

-- The permanent multiplier from passes for one source.
function RewardMath.permanent(source: Source, passes: { [string]: boolean }): number
	local multiplier = 1
	for key, owned in passes do
		local grants = owned and grantsOf(key)
		if grants and grants.multiplier and grants.multiplier.source == source then
			multiplier *= grants.multiplier.value
		end
	end
	return multiplier
end

-- The temporary multiplier: BOOST_MULTIPLIER while boost time is left.
function RewardMath.temporary(source: Source, boosts: { mining: number, star: number }): number
	return if (boosts[source] or 0) > 0 then P.BOOST_MULTIPLIER else 1
end

-- The multiplier for a reward earned right now: passes x boost x trail.
function RewardMath.multiplier(source: Source, e: Entitlements): number
	return RewardMath.permanent(source, e.passes)
		* RewardMath.temporary(source, e.boosts)
		* (e.trail or 1)
end

-- Stardust for breaking an asteroid worth `base`.
function RewardMath.miningReward(base: number, e: Entitlements): number
	return math.floor(base * RewardMath.multiplier("mining", e) + 0.5)
end

-- Star income made over `dt` seconds at `rate` (already including hangar
-- upgrades) with `boostLeft` seconds of star boost at the interval's start.
-- Only the part of the interval the boost covers is boosted.
function RewardMath.starIncome(
	rate: number,
	dt: number,
	boostLeft: number,
	passes: { [string]: boolean },
	trail: number?
): number
	if rate <= 0 or dt <= 0 then
		return 0
	end
	local boosted = math.clamp(boostLeft, 0, dt)
	local base = rate * RewardMath.permanent("star", passes) * (trail or 1)
	return base * (boosted * P.BOOST_MULTIPLIER + (dt - boosted))
end

-- Boost time left after `dt` seconds of play.
function RewardMath.tick(boostLeft: number, dt: number): number
	return math.max(boostLeft - math.max(dt, 0), 0)
end

-- Buying a boost adds its time; the strength never changes.
function RewardMath.extend(boostLeft: number, seconds: number): number
	return math.max(boostLeft, 0) + math.max(seconds, 0)
end

-- Extraction power multiplier from passes (not a reward multiplier).
function RewardMath.beamPower(passes: { [string]: boolean }): number
	local multiplier = 1
	for key, owned in passes do
		local grants = owned and grantsOf(key)
		if grants and grants.beamPower then
			multiplier *= grants.beamPower
		end
	end
	return multiplier
end

-- Whether star income goes straight to the wallet.
function RewardMath.autoCollect(passes: { [string]: boolean }): boolean
	for key, owned in passes do
		local grants = owned and grantsOf(key)
		if grants and grants.autoCollect then
			return true
		end
	end
	return false
end

-- "12:05" or "1:02:03" for a HUD timer.
function RewardMath.clock(seconds: number): string
	local s = math.max(math.floor(seconds), 0)
	local h, m = s // 3600, (s // 60) % 60
	if h > 0 then
		return string.format("%d:%02d:%02d", h, m, s % 60)
	end
	return string.format("%d:%02d", m, s % 60)
end

return RewardMath
