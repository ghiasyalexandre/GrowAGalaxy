--!strict
-- Where asteroids may spawn. Pure maths on plain {x, y, z} tables, so the
-- Lune unit tests run it directly; AsteroidSystem supplies the live lists of
-- asteroids and blockers (ships, players).
--
-- A spot is valid when the whole rock (centre plus radius):
--   * is at least ISS_CLEARANCE from the ISS (the origin),
--   * is within MAX_DISTANCE horizontally and HEIGHT vertically of it,
--   * is REGION_CLEARANCE outside every region slot at its largest expansion,
--     whether or not anyone owns it now (so a player joining later never
--     finds rocks inside their galaxy, and stations stay clear),
--   * keeps MIN_GAP from every other asteroid's surface,
--   * and keeps each blocker's clearance from every blocker.

local Config = require(script.Parent.Parent.Config)
local AsteroidsConfig = require(script.Parent.Parent.Config.Asteroids)
local RegionMath = require(script.Parent.RegionMath)
local Types = require(script.Parent.Parent.Types)

type Vec3 = Types.Vec3

export type Sphere = { position: Vec3, radius: number }
type SizeDef = AsteroidsConfig.SizeDef

local A = Config.Asteroids

local AsteroidField = {}

local function distance(a: Vec3, b: Vec3): number
	local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- Inside the spawn volume and clear of the ISS.
function AsteroidField.inVolume(position: Vec3, radius: number): boolean
	local horizontal = math.sqrt(position.x * position.x + position.z * position.z)
	local fromIss = math.sqrt(horizontal * horizontal + position.y * position.y)
	return fromIss >= A.ISS_CLEARANCE + radius
		and horizontal <= A.MAX_DISTANCE - radius
		and math.abs(position.y) <= A.HEIGHT - radius
end

-- Clear of every region slot (largest expansion) by REGION_CLEARANCE.
function AsteroidField.clearOfRegions(position: Vec3, radius: number): boolean
	local expansions = Config.Galaxy.EXPANSIONS
	local size = expansions[#expansions].size
	-- A negative margin grows the box outwards.
	local margin = -(A.REGION_CLEARANCE + radius)
	for slot = 1, Config.World.MAX_PLAYERS do
		if RegionMath.isInside(RegionMath.toLocal(slot, position), size, margin) then
			return false
		end
	end
	return true
end

-- Keeps `gap` studs between this sphere's surface and every other's.
function AsteroidField.clearOf(
	position: Vec3,
	radius: number,
	others: { Sphere },
	gap: number
): boolean
	for _, other in others do
		if distance(position, other.position) < radius + other.radius + gap then
			return false
		end
	end
	return true
end

-- Every rule above. `blockers` are ships and players, each a sphere whose
-- radius is its clearance.
function AsteroidField.isValid(
	position: Vec3,
	radius: number,
	asteroids: { Sphere },
	blockers: { Sphere }
): boolean
	return AsteroidField.inVolume(position, radius)
		and AsteroidField.clearOfRegions(position, radius)
		and AsteroidField.clearOf(position, radius, asteroids, A.MIN_GAP)
		and AsteroidField.clearOf(position, radius, blockers, 0)
end

-- A random point in the spawn volume, evenly spread over its area and
-- height. `rng` returns numbers in [0, 1). The point may still be invalid
-- (near the ISS or in a region): check it with isValid.
function AsteroidField.randomPoint(rng: () -> number): Vec3
	local angle = rng() * 2 * math.pi
	local r = math.sqrt(rng()) * A.MAX_DISTANCE
	return {
		x = math.sin(angle) * r,
		y = (rng() * 2 - 1) * A.HEIGHT,
		z = math.cos(angle) * r,
	}
end

-- A random point within `spread` studs of `centre`.
function AsteroidField.near(centre: Vec3, spread: number, rng: () -> number): Vec3
	-- Rejection-sample the unit ball; a few tries almost always suffice.
	for _ = 1, 8 do
		local x, y, z = rng() * 2 - 1, rng() * 2 - 1, rng() * 2 - 1
		if x * x + y * y + z * z <= 1 then
			return {
				x = centre.x + x * spread,
				y = centre.y + y * spread,
				z = centre.z + z * spread,
			}
		end
	end
	return { x = centre.x, y = centre.y, z = centre.z }
end

-- A size id chosen by Config.Asteroids weights.
function AsteroidField.pickSize(rng: () -> number): string
	local total = 0
	for _, id in A.SIZE_ORDER do
		total += A.SIZES[id].weight
	end
	local roll = rng() * total
	for _, id in A.SIZE_ORDER do
		roll -= A.SIZES[id].weight
		if roll < 0 then
			return id
		end
	end
	return A.SIZE_ORDER[#A.SIZE_ORDER]
end

export type GroupPlan = {
	members: number,
	spread: number, -- studs
	stream: Vec3?, -- unit direction for a stream; nil for a clump
}

-- How the next group of asteroids looks: how many, how spread out, and
-- whether it is a clump or a stream.
function AsteroidField.groupPlan(rng: () -> number): GroupPlan
	local range = A.CLUSTER_MAX - A.CLUSTER_MIN + 1
	local members =
		math.min(A.CLUSTER_MIN + math.floor(rng() ^ A.CLUSTER_SKEW * range), A.CLUSTER_MAX)
	local spread = A.CLUSTER_SPREAD_MIN + rng() * (A.CLUSTER_SPREAD_MAX - A.CLUSTER_SPREAD_MIN)
	local stream: Vec3? = nil
	if members >= 3 and rng() < A.STREAM_CHANCE then
		local z = rng() * 2 - 1
		local ring = math.sqrt(math.max(1 - z * z, 0))
		local angle = rng() * 2 * math.pi
		stream = { x = math.cos(angle) * ring, y = math.sin(angle) * ring * 0.4, z = z }
		local s = stream :: Vec3
		local length = math.sqrt(s.x * s.x + s.y * s.y + s.z * s.z)
		stream = { x = s.x / length, y = s.y / length, z = s.z / length }
	end
	return { members = members, spread = spread, stream = stream }
end

-- A random point in a group around `centre`: anywhere in the clump, or
-- along the stream's line (up to 2 x spread either way) with a little jitter.
function AsteroidField.inGroup(centre: Vec3, plan: GroupPlan, rng: () -> number): Vec3
	local stream = plan.stream
	if stream == nil then
		return AsteroidField.near(centre, plan.spread, rng)
	end
	local along = (rng() * 2 - 1) * plan.spread * 2
	local onLine = {
		x = centre.x + stream.x * along,
		y = centre.y + stream.y * along,
		z = centre.z + stream.z * along,
	}
	return AsteroidField.near(onLine, plan.spread * 0.3, rng)
end

-- A copy of a size with its radius scaled by (1 +- SIZE_JITTER), and its
-- durability and reward scaled with the rock's area (whole numbers, at
-- least 1). The weak point keeps its size.
function AsteroidField.varied(size: SizeDef, rng: () -> number): SizeDef
	local scale = 1 + (rng() * 2 - 1) * A.SIZE_JITTER
	local area = scale * scale
	local copy = table.clone(size)
	copy.radius = size.radius * scale
	copy.durability = math.max(1, math.floor(size.durability * area + 0.5))
	copy.reward = math.max(1, math.floor(size.reward * area + 0.5))
	return copy
end

return AsteroidField
