--!strict
-- Planet egg rules (Config.Eggs, Config.Planets), shared by the server's
-- EggSystem, the Egg Lab panel and the tests.
--
-- Rolling an egg at lab level L picks a planet type and a tier, each from
-- whole-number weights that depend on L (see Config.Eggs):
--
--   type weight  def.weight x rarityLuck ^ rarity index, rounded
--   tier weight  TIER_WEIGHTS[tier] x tierLuck ^ (tier - 1), rounded
--
-- pickType(L, roll) / pickTier(L, roll) take a whole roll from 1 to
-- typeTotal(L) / tierTotal(L), drawn on the server: each choice owns a run
-- of rolls as long as its weight, in catalog order, so its chance is
-- exactly weight / total. The panel shows these same numbers.
--
-- Random eggs are rolled only when Roblox says paid random items are
-- allowed for the player (PolicyService). "unknown" (not checked yet, or
-- the check failed) counts as not allowed.

local Config = require(script.Parent.Parent.Config)
local EconomyMath = require(script.Parent.EconomyMath)
local EggsConfig = require(script.Parent.Parent.Config.Eggs)

local E = Config.Eggs
local P = Config.Planets

export type Policy = "allowed" | "restricted" | "unknown"

local EggMath = {}

-- The next egg's price (each roll costs it) for best production `high`
-- (H) after `kept` eggs kept (EconomyMath.eggPrice).
function EggMath.price(high: number, kept: number): number
	return EconomyMath.eggPrice(high, kept)
end

-- A lab level's settings, clamped to the levels that exist.
function EggMath.lab(level: number): EggsConfig.LabLevel
	return E.LAB_LEVELS[math.clamp(level, 1, #E.LAB_LEVELS)]
end

-- Stardust to upgrade a lab from `level` to the next, or nil at the top.
function EggMath.upgradeCost(level: number): number?
	local nextLevel = E.LAB_LEVELS[level + 1]
	return if nextLevel then nextLevel.cost else nil
end

-- The best star tier needed for the lab's next level (nil at the top).
function EggMath.upgradeTier(level: number): number?
	local nextLevel = E.LAB_LEVELS[level + 1]
	return if nextLevel then nextLevel.minTier else nil
end

function EggMath.typeWeight(typeId: string, level: number): number
	local def = P.BY_ID[typeId]
	if def == nil then
		return 0
	end
	local luck = EggMath.lab(level).rarityLuck
	return math.floor(def.weight * luck ^ P.RARITIES[def.rarity].index + 0.5)
end

function EggMath.typeTotal(level: number): number
	local total = 0
	for _, id in P.ORDER do
		total += EggMath.typeWeight(id, level)
	end
	return total
end

function EggMath.tierWeight(tier: number, level: number): number
	local base = E.TIER_WEIGHTS[tier]
	if base == nil then
		return 0
	end
	return math.floor(base * EggMath.lab(level).tierLuck ^ (tier - 1) + 0.5)
end

function EggMath.tierTotal(level: number): number
	local total = 0
	for tier = 1, #E.TIER_WEIGHTS do
		total += EggMath.tierWeight(tier, level)
	end
	return total
end

-- The planet type a whole roll in 1..typeTotal(level) lands on.
function EggMath.pickType(level: number, roll: number): string
	local at = 0
	for _, id in P.ORDER do
		at += EggMath.typeWeight(id, level)
		if roll <= at then
			return id
		end
	end
	return P.ORDER[#P.ORDER]
end

-- The tier a whole roll in 1..tierTotal(level) lands on.
function EggMath.pickTier(level: number, roll: number): number
	local at = 0
	for tier = 1, #E.TIER_WEIGHTS do
		at += EggMath.tierWeight(tier, level)
		if roll <= at then
			return tier
		end
	end
	return #E.TIER_WEIGHTS
end

-- Chances as percentages (exact, before rounding for display).
function EggMath.typePercent(typeId: string, level: number): number
	return EggMath.typeWeight(typeId, level) / EggMath.typeTotal(level) * 100
end

function EggMath.rarityPercent(rarity: string, level: number): number
	local sum = 0
	for _, id in P.BY_RARITY[rarity] or ({} :: { string }) do
		sum += EggMath.typeWeight(id, level)
	end
	return sum / EggMath.typeTotal(level) * 100
end

function EggMath.tierPercent(tier: number, level: number): number
	return EggMath.tierWeight(tier, level) / EggMath.tierTotal(level) * 100
end

-- A rarity's base income range (Stardust per second at level 1, tier 1, on
-- a star making 100/s by itself).
function EggMath.rarityRange(rarity: string): (number, number)
	local low, high = math.huge, 0
	for _, id in P.BY_RARITY[rarity] or ({} :: { string }) do
		local income = P.BY_ID[id].income
		low, high = math.min(low, income), math.max(high, income)
	end
	return if low == math.huge then 0 else low, high
end

-- What an egg is worth on average at a lab level: Stardust per second at
-- level 1 on a star making 100/s (rarity odds x incomes x the expected tier
-- multiplier).
function EggMath.expectedIncome(level: number): number
	local total = EggMath.typeTotal(level)
	local base = 0
	for _, id in P.ORDER do
		base += EggMath.typeWeight(id, level) / total * P.BY_ID[id].income
	end
	local mult = 0
	for tier = 1, #E.TIER_WEIGHTS do
		mult += EggMath.tierPercent(tier, level) / 100 * P.TIERS[tier].multiplier
	end
	return base * mult
end

-- A percentage for display: up to 3 decimals, trailing zeros dropped
-- ("12.5%", "2.333%", "0.25%").
function EggMath.percentText(percent: number): string
	local text = string.format("%.3f", percent)
	text = string.gsub(text, "0+$", "")
	text = string.gsub(text, "%.$", "")
	return `{text}%`
end

-- The expected sale value of a fresh egg's planet as a share of what the
-- roll cost (Config.Planets.SELL_FRACTION by the lab's rarity odds).
function EggMath.expectedSaleShare(level: number): number
	local share = 0
	for _, rarity in P.RARITY_ORDER do
		share += EggMath.rarityPercent(rarity, level) / 100 * (P.SELL_FRACTION[rarity] or 0)
	end
	return share
end

-- Whether random eggs may be rolled under this policy.
function EggMath.canBuyRandom(policy: string): boolean
	return policy == "allowed"
end

-- How many eggs the player holds unhatched (waiting plus incubating).
function EggMath.held(eggs: { [string]: any }, hatches: { [string]: any }): number
	local n = 0
	for _ in eggs do
		n += 1
	end
	for _ in hatches do
		n += 1
	end
	return n
end

-- A hatch time as text ("10 s", "3 min 46 s", "30 min").
function EggMath.durationText(seconds: number): string
	local s = math.max(math.floor(seconds + 0.5), 0)
	if s < 60 then
		return `{s} s`
	end
	local minutes, rest = s // 60, s % 60
	if minutes < 60 then
		return if rest > 0 then `{minutes} min {rest} s` else `{minutes} min`
	end
	local hours, mins = minutes // 60, minutes % 60
	return if mins > 0 then `{hours} h {mins} min` else `{hours} h`
end

return EggMath
