--!strict
-- Raid rules (Config.Raids) shared by the server (RaidSystem) and tests:
-- boss health, damage, when a queue starts, who earns the reward, where the
-- weak point goes, enrage, and hit tests for the boss's attacks. Pure module: no Roblox services; points are
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

-- How many times the weak point has moved at this much health: once per
-- WEAK_POINT_MOVE_SHARE of the boss's health lost.
function RaidMath.weakStage(health: number, maxHealth: number): number
	if maxHealth <= 0 then
		return 0
	end
	local lost = 1 - math.clamp(health / maxHealth, 0, 1)
	return math.floor(lost / R.WEAK_POINT_MOVE_SHARE + 1e-9)
end

-- Whether the boss is enraged (below ENRAGE_SHARE, still alive).
function RaidMath.enraged(health: number, maxHealth: number): boolean
	return health > 0 and maxHealth > 0 and health / maxHealth < R.ENRAGE_SHARE
end

-- Seconds until a move comes round again.
function RaidMath.moveInterval(interval: number, enraged: boolean): number
	return if enraged then interval / R.ENRAGE_SPEEDUP else interval
end

-- A unit vector from two numbers in [0, 1), evenly spread over the sphere.
function RaidMath.direction(u: number, v: number): Point
	local z = u * 2 - 1
	local ring = math.sqrt(math.max(1 - z * z, 0))
	local angle = v * 2 * math.pi
	return { x = math.cos(angle) * ring, y = math.sin(angle) * ring, z = z }
end

-- A new spot for the weak point (a unit direction from the boss's centre),
-- at least WEAK_POINT_MIN_ANGLE round from `previous`. `rng` returns numbers
-- in [0, 1).
function RaidMath.nextWeakDirection(previous: Point?, rng: () -> number): Point
	local minDot = math.cos(math.rad(R.WEAK_POINT_MIN_ANGLE))
	local candidate = RaidMath.direction(rng(), rng())
	for _ = 1, 24 do
		if previous == nil or dot(candidate, previous) <= minDot then
			return candidate
		end
		candidate = RaidMath.direction(rng(), rng())
	end
	-- Unlucky draws: the opposite side always qualifies.
	if previous then
		return { x = -previous.x, y = -previous.y, z = -previous.z }
	end
	return candidate
end

-- Whether a shockwave ring (centred on `center`, in the plane with unit
-- `normal`) that grew from radius `from` to `to` swept over `point`.
function RaidMath.ringHits(
	point: Point,
	center: Point,
	normal: Point,
	from: number,
	to: number
): boolean
	local d = sub(point, center)
	local off = dot(d, normal)
	if math.abs(off) > R.SHOCKWAVE_THICKNESS then
		return false
	end
	local radial = math.sqrt(math.max(dot(d, d) - off * off, 0))
	local half = R.SHOCKWAVE_BAND / 2
	return radial >= from - half and radial <= to + half
end

-- Whether a bombard blast at `spot` catches a ship at `ship`.
function RaidMath.inBlast(spot: Point, ship: Point): boolean
	local d = sub(ship, spot)
	return math.sqrt(dot(d, d)) <= R.BOMBARD_RADIUS
end

return RaidMath
