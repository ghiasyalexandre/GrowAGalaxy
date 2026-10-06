--!strict
-- Daily prize wheel rules (Config.Wheel), shared by the server's WheelSystem,
-- the wheel panel and the tests.
--
-- One spin per COOLDOWN seconds, measured from the last spin (unix
-- seconds), for SPIN_COST Stardust. A spin's prize is pick(roll) for a
-- whole roll from 1 to total() drawn on the server, so prize i's chance is
-- exactly its weight / total(). Prizes are fixed Stardust amounts: no pass,
-- boost or trail multiplies them.

local Config = require(script.Parent.Parent.Config)

local W = Config.Wheel

local WheelMath = {}

-- The sum of the prize weights (100: the weights are percentages).
function WheelMath.total(): number
	local sum = 0
	for _, prize in W.PRIZES do
		sum += prize.weight
	end
	return sum
end

-- The prize index a whole roll in 1..total() lands on.
function WheelMath.pick(roll: number): number
	local at = 0
	for index, prize in W.PRIZES do
		at += prize.weight
		if roll <= at then
			return index
		end
	end
	return #W.PRIZES
end

-- Whether a spin is ready at `now`.
function WheelMath.ready(nextSpin: number, now: number): boolean
	return now >= nextSpin
end

-- Seconds until the next spin (0 when ready).
function WheelMath.wait(nextSpin: number, now: number): number
	return math.max(nextSpin - now, 0)
end

-- Spins at `now` if ready: returns the new nextSpin, or nil.
function WheelMath.spin(nextSpin: number, now: number): number?
	if not WheelMath.ready(nextSpin, now) then
		return nil
	end
	return now + W.COOLDOWN
end

-- The angle (degrees, clockwise from the top) at the middle of prize
-- `index`'s segment, with every segment the same size.
function WheelMath.segmentAngle(index: number): number
	return (index - 1) * 360 / #W.PRIZES
end

-- How far to turn a wheel showing `from` degrees so prize `index` stops
-- under the pointer at the top, after `turns` whole extra turns.
function WheelMath.landing(from: number, index: number, turns: number): number
	local target = -WheelMath.segmentAngle(index)
	local delta = (target - from) % 360
	return from + delta + 360 * turns
end

return WheelMath
