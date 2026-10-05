--!strict
-- Simulated time for orbiting planets: where a planet is on its orbit after
-- some simulated seconds, the inspect slider's logarithmic scale between
-- Config.Stars.INSPECT_RATE_MIN and INSPECT_RATE_MAX, and readable labels
-- ("5.5 days / s", "2.6 years"). Pure, so the specs check what clients draw.

local Config = require(script.Parent.Parent.Config)

local S = Config.Stars

local DAY = 86400
local YEAR = 365.25 * DAY

local OrbitTime = {}

OrbitTime.DAY = DAY
OrbitTime.YEAR = YEAR

-- Angle in radians of a planet in orbit `slot` after `seconds` of simulated
-- time, starting from `phase`.
function OrbitTime.angle(slot: number, seconds: number, phase: number): number
	local def = S.SLOTS[slot]
	local period = (if def then def.periodDays else 365.25) * DAY
	return phase + 2 * math.pi * ((seconds / period) % 1)
end

-- Slider position (0 to 1) -> simulated seconds per real second, on a log
-- scale so every step of the slider feels the same.
function OrbitTime.rateAt(position: number): number
	local low, high = math.log(S.INSPECT_RATE_MIN), math.log(S.INSPECT_RATE_MAX)
	return math.exp(low + (high - low) * math.clamp(position, 0, 1))
end

-- The inverse: where a rate sits on the slider.
function OrbitTime.positionOf(rate: number): number
	local low, high = math.log(S.INSPECT_RATE_MIN), math.log(S.INSPECT_RATE_MAX)
	return math.clamp((math.log(math.max(rate, 1e-6)) - low) / (high - low), 0, 1)
end

local function amount(value: number, unit: string): string
	local rounded = if value >= 10
		then math.floor(value + 0.5)
		else math.floor(value * 10 + 0.5) / 10
	local text = if rounded == math.floor(rounded)
		then tostring(math.floor(rounded))
		else tostring(rounded)
	return `{text} {unit}{if rounded == 1 then "" else "s"}`
end

-- A span of simulated time in the friendliest unit: "45 minutes",
-- "6 hours", "88 days", "2.6 years", "3 decades".
function OrbitTime.describe(seconds: number): string
	if seconds < 3600 then
		return amount(seconds / 60, "minute")
	elseif seconds < DAY then
		return amount(seconds / 3600, "hour")
	elseif seconds < YEAR then
		return amount(seconds / DAY, "day")
	elseif seconds < 10 * YEAR then
		return amount(seconds / YEAR, "year")
	end
	return amount(seconds / (10 * YEAR), "decade")
end

-- A rate as "<span> / s".
function OrbitTime.describeRate(rate: number): string
	return `{OrbitTime.describe(rate)} / s`
end

return OrbitTime
