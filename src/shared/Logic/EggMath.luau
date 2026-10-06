--!strict
-- Planet egg rules (Config.Eggs, Config.Planets), shared by the server's
-- EggSystem, the Planet Egg Lab panel and the tests.
--
-- A mystery egg's planet is pick(roll) for a whole roll from 1 to
-- WEIGHT_TOTAL drawn on the server: each type owns a run of rolls as long as
-- its weight, in catalog order, so its chance is exactly weight /
-- WEIGHT_TOTAL. Planets can't be bought any other way.
--
-- Random eggs are sold only when Roblox says paid random items are allowed
-- for the player (PolicyService). "unknown" (not checked yet, or the check
-- failed) counts as not allowed.

local Config = require(script.Parent.Parent.Config)

local E = Config.Eggs
local P = Config.Planets

export type Policy = "allowed" | "restricted" | "unknown"

local EggMath = {}

-- The next mystery egg's price after `bought` eggs.
function EggMath.price(bought: number): number
	return math.floor(E.PRICE_BASE * E.PRICE_GROWTH ^ math.max(bought, 0) + 0.5)
end

-- Buying `count` mystery eggs at once after `bought`: each at its own
-- price, as if bought one by one. Returns the prices and their total.
function EggMath.batch(bought: number, count: number): ({ number }, number)
	local prices: { number } = {}
	local total = 0
	for index = 0, count - 1 do
		local price = EggMath.price(bought + index)
		table.insert(prices, price)
		total += price
	end
	return prices, total
end

-- Whether `count` is one of the offered multi-buy sizes.
function EggMath.isBatchSize(count: unknown): boolean
	return type(count) == "number" and table.find(Config.Eggs.MULTI_BUY, count) ~= nil
end

-- The planet type a whole roll in 1..WEIGHT_TOTAL lands on.
function EggMath.pick(roll: number): string
	local at = 0
	for _, id in P.ORDER do
		at += P.BY_ID[id].weight
		if roll <= at then
			return id
		end
	end
	return P.ORDER[#P.ORDER]
end

-- A type's chance as a percentage (exact, before rounding for display).
function EggMath.percent(typeId: string): number
	local def = P.BY_ID[typeId]
	return if def then def.weight / P.WEIGHT_TOTAL * 100 else 0
end

-- A percentage for display: up to 3 decimals, trailing zeros dropped
-- ("12.5%", "2.333%", "0.25%").
function EggMath.percentText(percent: number): string
	local text = string.format("%.3f", percent)
	text = string.gsub(text, "0+$", "")
	text = string.gsub(text, "%.$", "")
	return `{text}%`
end

-- Whether random eggs may be sold under this policy.
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
