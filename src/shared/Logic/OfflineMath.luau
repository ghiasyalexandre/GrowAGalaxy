--!strict
-- Offline earnings (Config.Economy): what a player's stars made while they
-- were away. Pure, so the server (DataSystem) and tests share it.

local Config = require(script.Parent.Parent.Config)

local E = Config.Economy

local OfflineMath = {}

-- Whole Stardust earned at OFFLINE_RATE of `rate` per second between
-- `lastOnline` and `now` (unix seconds), counting at most
-- OFFLINE_CAP_SECONDS x `capMultiplier` (the Stardust Silo), and the
-- seconds counted. Nothing for a first visit (lastOnline 0), a clock that
-- went backwards, or less than OFFLINE_MIN_SECONDS away.
function OfflineMath.earned(
	rate: number,
	lastOnline: number,
	now: number,
	capMultiplier: number?
): (number, number)
	if lastOnline <= 0 or rate <= 0 then
		return 0, 0
	end
	local away = now - lastOnline
	if away < E.OFFLINE_MIN_SECONDS then
		return 0, 0
	end
	local counted = math.min(away, E.OFFLINE_CAP_SECONDS * (capMultiplier or 1))
	return math.floor(rate * E.OFFLINE_RATE * counted), counted
end

return OfflineMath
