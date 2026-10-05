--!strict
-- Daily prize rules (Config.Daily), shared by the server (claims) and the
-- client (the calendar). A profile keeps `day` (the next day to claim,
-- 1..14) and `lastClaim` (the UTC day number of the last claim, 0 = never).
-- Pure module: no Roblox services.

local Config = require(script.Parent.Parent.Config)
local DailyConfig = require(script.Parent.Parent.Config.Daily)

local D = Config.Daily

type Prize = DailyConfig.Prize

export type DailyRecord = { day: number, lastClaim: number }

local DailyMath = {}

-- The UTC day number for a Unix time.
function DailyMath.today(unixTime: number): number
	return math.floor(unixTime / D.DAY_SECONDS)
end

-- Whether a prize can be claimed today.
function DailyMath.canClaim(record: DailyRecord, today: number): boolean
	return record.lastClaim < today
end

-- Claims today's prize: returns the day claimed and the record afterwards,
-- or nil if today's prize was already claimed. After day 14 comes day 1.
function DailyMath.claim(record: DailyRecord, today: number): (number?, DailyRecord)
	if not DailyMath.canClaim(record, today) then
		return nil, record
	end
	local day = math.clamp(record.day, 1, #D.PRIZES)
	local nextDay = if day >= #D.PRIZES then 1 else day + 1
	return day, { day = nextDay, lastClaim = today }
end

-- Seconds until the next claim opens (the next UTC midnight).
function DailyMath.secondsToNext(unixTime: number): number
	return (DailyMath.today(unixTime) + 1) * D.DAY_SECONDS - unixTime
end

-- A short label for a prize: "2,500 Stardust" or "2x Mining 10 min".
function DailyMath.describe(prize: Prize): string
	if prize.stardust then
		local digits = tostring(math.floor(prize.stardust))
		local formatted = digits
		local length = #digits
		if length > 3 then
			formatted = ""
			for i = 1, length do
				formatted ..= string.sub(digits, i, i)
				local left = length - i
				if left > 0 and left % 3 == 0 then
					formatted ..= ","
				end
			end
		end
		return `{formatted} Stardust`
	elseif prize.boost then
		local name = if prize.boost.source == "mining" then "Mining" else "Stars"
		return `2x {name} {prize.boost.seconds // 60} min`
	end
	return "Prize"
end

return DailyMath
