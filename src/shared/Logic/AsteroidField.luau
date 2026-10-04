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
local RegionMath = require(script.Parent.RegionMath)
local Types = require(script.Parent.Parent.Types)

type Vec3 = Types.Vec3

export type Sphere = { position: Vec3, radius: number }

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

return AsteroidField
