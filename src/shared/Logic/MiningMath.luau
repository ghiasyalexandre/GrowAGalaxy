--!strict
-- Extraction maths for asteroid mining, shared by server and tests.

local MiningMath = {}

-- Extraction progress per second: full beamPower on the weak point, a share
-- of it on plain rock.
function MiningMath.rate(beamPower: number, onWeakPoint: boolean, rockEfficiency: number): number
	return if onWeakPoint then beamPower else beamPower * rockEfficiency
end

-- Stardust for a broken asteroid: its base reward plus up to `bonus` (a
-- share, e.g. 0.25) scaled by how much of the progress came from the weak
-- point. Always a whole number, never less than the base.
function MiningMath.reward(
	base: number,
	weakProgress: number,
	progress: number,
	bonus: number
): number
	local share = if progress > 0 then math.clamp(weakProgress / progress, 0, 1) else 0
	return math.floor(base * (1 + bonus * share) + 0.5)
end

-- May `requester` mine an asteroid reserved by `owner` (nil = nobody) that
-- was last hit at `lastHit`? The owner always may; anyone else once the
-- reservation has gone `timeout` seconds without a hit.
function MiningMath.mayMine(
	owner: any,
	requester: any,
	lastHit: number,
	now: number,
	timeout: number
): boolean
	return owner == nil or owner == requester or now - lastHit >= timeout
end

return MiningMath
