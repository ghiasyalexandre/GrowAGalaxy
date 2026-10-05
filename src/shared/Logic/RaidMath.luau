--!strict
-- Raid rules (Config.Raids) shared by the server (RaidSystem) and tests:
-- boss health, damage, when a queue starts, who earns the reward, and hit
-- tests for the boss's attacks. Pure module: no Roblox services; points are
-- plain { x, y, z } tables.

local Config = require(script.Parent.Parent.Config)

local R = Config.Raids

export type Point = { x: number, y: number, z: number }

local RaidMath = {}

-- The boss's health for this many raiders.
function RaidMath.bossHealth(difficulty: string, raiders: number): number
	local def = R.BY_ID[difficulty]
	local extra = math.max(raiders - 1, 0)
	return math.floor(def.bossHealth * (1 + def.healthPerExtraRaider * extra))
end

-- Damage one shot does to the boss.
function RaidMath.bossDamage(beamPower: number, weakPoint: boolean): number
	local damage = math.max(beamPower, 0) * R.DAMAGE_PER_POWER
	return if weakPoint then damage * R.WEAK_POINT_MULTIPLIER else damage
end

-- When a queue launches: QUEUE_COUNTDOWN after the first player joined, or
-- FULL_COUNTDOWN after it filled up, whichever is sooner.
function RaidMath.startTime(firstJoinedAt: number, filledAt: number?): number
	local normal = firstJoinedAt + R.QUEUE_COUNTDOWN
	if filledAt then
		return math.min(normal, filledAt + R.FULL_COUNTDOWN)
	end
	return normal
end

-- Whether a raider shares the reward: enough damage dealt, or still flying
-- when the boss fell.
function RaidMath.earnsReward(
	damageDealt: number,
	bossMaxHealth: number,
	stillFlying: boolean
): boolean
	return stillFlying or damageDealt >= bossMaxHealth * R.MIN_DAMAGE_SHARE
end

local function sub(a: Point, b: Point): Point
	return { x = a.x - b.x, y = a.y - b.y, z = a.z - b.z }
end

local function dot(a: Point, b: Point): number
	return a.x * b.x + a.y * b.y + a.z * b.z
end

-- Distance from `point` to the segment from `a` to `b`.
function RaidMath.distanceToSegment(point: Point, a: Point, b: Point): number
	local ab = sub(b, a)
	local ap = sub(point, a)
	local lengthSquared = dot(ab, ab)
	local t = if lengthSquared > 0 then math.clamp(dot(ap, ab) / lengthSquared, 0, 1) else 0
	local closest = { x = a.x + ab.x * t, y = a.y + ab.y * t, z = a.z + ab.z * t }
	local d = sub(point, closest)
	return math.sqrt(dot(d, d))
end

-- Whether a turbolaser aimed at `aim` hits a ship now at `ship`.
function RaidMath.boltHits(aim: Point, ship: Point): boolean
	local d = sub(ship, aim)
	return math.sqrt(dot(d, d)) <= R.BOLT_HIT_RADIUS
end

-- Seconds a bolt takes to fly `distance` studs.
function RaidMath.boltTime(distance: number): number
	return math.max(distance, 0) / R.BOLT_SPEED
end

return RaidMath
