--!strict
-- Incubator rules (Config.Eggs, Config.Planets), used by DataSystem's
-- startHatch / completeHatch and the tests. Each function changes the
-- tables it is given in one step, without yielding, so the egg, the hatch
-- and the planet can never be saved half-moved.
--
--   begin   a waiting egg -> a hatch in a free chamber ("1".."HATCH_SLOTS"),
--           ending after the planet's rarity's hatch time (unix seconds, so
--           it runs on while the player is offline)
--   due     the chambers whose time is up, in order
--   finish  removes a due hatch and returns its planet type, once: a second
--           call finds nothing. A type this server doesn't know is left to
--           hatch on a server that does.

local Config = require(script.Parent.Parent.Config)
local Types = require(script.Parent.Parent.Types)

local E = Config.Eggs
local P = Config.Planets

local HatchMath = {}

-- Seconds an egg of this planet type takes to hatch.
function HatchMath.seconds(typeId: string): number
	local def = P.BY_ID[typeId]
	local rarity = if def then P.RARITIES[def.rarity] else P.RARITIES.Common
	return rarity.hatchSeconds
end

function HatchMath.isChamber(chamber: number): boolean
	return chamber == math.floor(chamber) and chamber >= 1 and chamber <= E.HATCH_SLOTS
end

-- Moves egg `eggId` into chamber `chamber` at `now`. Returns the hatch, or
-- nil (and changes nothing) if the egg isn't there or the chamber is taken.
function HatchMath.begin(
	eggs: { [string]: Types.EggRecord },
	hatches: { [string]: Types.HatchRecord },
	eggId: string,
	chamber: number,
	now: number
): Types.HatchRecord?
	local egg = eggs[eggId]
	local key = tostring(chamber)
	if egg == nil or not HatchMath.isChamber(chamber) or hatches[key] ~= nil then
		return nil
	end
	local hatch: Types.HatchRecord = {
		eggId = eggId,
		outcome = egg.outcome,
		startedAt = now,
		endsAt = now + HatchMath.seconds(egg.outcome),
	}
	eggs[eggId] = nil
	hatches[key] = hatch
	return hatch
end

-- Chambers whose hatch is finished at `now`, in chamber order.
function HatchMath.due(hatches: { [string]: Types.HatchRecord }, now: number): { string }
	local result: { string } = {}
	for chamber, hatch in hatches do
		if hatch.endsAt <= now then
			table.insert(result, chamber)
		end
	end
	table.sort(result, function(a, b)
		return (tonumber(a) or 0) < (tonumber(b) or 0)
	end)
	return result
end

-- Takes a finished hatch out of its chamber and returns its planet type,
-- or nil if there's nothing finished there.
function HatchMath.finish(
	hatches: { [string]: Types.HatchRecord },
	chamber: string,
	now: number
): string?
	local hatch = hatches[chamber]
	if hatch == nil or hatch.endsAt > now or P.BY_ID[hatch.outcome] == nil then
		return nil
	end
	hatches[chamber] = nil
	return hatch.outcome
end

return HatchMath
