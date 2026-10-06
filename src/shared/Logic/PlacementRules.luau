--!strict
-- Rules for where a star (and so a whole solar system) may sit in a region.
-- Shared so the client's ghost preview and the server's validation agree; the
-- server always re-runs these checks and never trusts the client's verdict.
--
-- Footprint: every system reserves the room its largest possible layout
-- needs, a flat disc around the star (orbits are only slightly tilted):
-- radius Galaxy.SYSTEM_RADIUS, half-height Galaxy.SYSTEM_HALF_HEIGHT. Two
-- systems clash only if their discs overlap, so stars may also stack above
-- one another.
--
-- Build box: star centres stay WALL_MARGIN inside the side, front and back
-- walls and WALL_MARGIN_Y inside the floor and ceiling, so a footprint never
-- pokes out of the region.

local Config = require(script.Parent.Parent.Config)
local RegionMath = require(script.Parent.RegionMath)
local Types = require(script.Parent.Parent.Types)

type Vec3 = Types.Vec3

local G = Config.Galaxy

export type Rejection = "Invalid" | "OutOfBounds" | "TooHigh" | "TooClose" | "AtCapacity"

-- The allowed range for star centres, in region space.
export type Box = { min: Vec3, max: Vec3 }

local PlacementRules = {}

local function isFinite(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

function PlacementRules.isValidVec3(value: any): boolean
	return type(value) == "table" and isFinite(value.x) and isFinite(value.y) and isFinite(value.z)
end

function PlacementRules.snap(pos: Vec3, grid: number): Vec3
	local function round(n: number): number
		return math.floor(n / grid + 0.5) * grid
	end
	return { x = round(pos.x), y = round(pos.y), z = round(pos.z) }
end

-- Can the player add another solar system at this expansion level?
function PlacementRules.hasCapacity(systemCount: number, expansionLevel: number): boolean
	return systemCount < RegionMath.maxSystems(expansionLevel)
end

-- Where star centres may go at this expansion level.
function PlacementRules.buildBox(expansionLevel: number): Box
	local size = RegionMath.regionSize(expansionLevel)
	local side, up = G.WALL_MARGIN, G.WALL_MARGIN_Y
	return {
		min = { x = -size.x / 2 + side, y = -size.y / 2 + up, z = side },
		max = { x = size.x / 2 - side, y = size.y / 2 - up, z = size.z - side },
	}
end

-- `pos` moved to the nearest point inside the build box.
function PlacementRules.clamp(pos: Vec3, expansionLevel: number): Vec3
	local box = PlacementRules.buildBox(expansionLevel)
	return {
		x = math.clamp(pos.x, box.min.x, box.max.x),
		y = math.clamp(pos.y, box.min.y, box.max.y),
		z = math.clamp(pos.z, box.min.z, box.max.z),
	}
end

-- How far two footprints are from touching: > 0 means apart. Positive when
-- they're far enough apart either horizontally or vertically.
function PlacementRules.clearance(a: Vec3, b: Vec3): number
	local horizontal = math.sqrt((a.x - b.x) ^ 2 + (a.z - b.z) ^ 2) - 2 * G.SYSTEM_RADIUS
	local vertical = math.abs(a.y - b.y) - 2 * G.SYSTEM_HALF_HEIGHT
	return math.max(horizontal, vertical)
end

-- Checks bounds and spacing for a star at `pos` (region space). `others` are
-- the positions of the player's other stars; when moving a star, leave the
-- moving star out. On a clash, also returns how many studs short it is.
function PlacementRules.checkStar(
	pos: any,
	expansionLevel: number,
	others: { Vec3 }
): (boolean, Rejection?, number?)
	if not PlacementRules.isValidVec3(pos) then
		return false, "Invalid", nil
	end
	local box = PlacementRules.buildBox(expansionLevel)
	if pos.y < box.min.y or pos.y > box.max.y then
		return false, "TooHigh", nil
	end
	if pos.x < box.min.x or pos.x > box.max.x or pos.z < box.min.z or pos.z > box.max.z then
		return false, "OutOfBounds", nil
	end
	local worst: number? = nil
	for _, other in others do
		local gap = PlacementRules.clearance(pos, other)
		if gap < 0 and (worst == nil or gap < worst) then
			worst = gap
		end
	end
	if worst then
		return false, "TooClose", math.ceil(-worst)
	end
	return true, nil, nil
end

-- The valid spot nearest to `wanted` (clamped into the build box first),
-- searched outwards on a STEP grid; nil when the galaxy has no room at all.
function PlacementRules.nearestValid(wanted: Vec3, expansionLevel: number, others: { Vec3 }): Vec3?
	local start = PlacementRules.clamp(wanted, expansionLevel)
	if PlacementRules.checkStar(start, expansionLevel, others) then
		return start
	end
	local box = PlacementRules.buildBox(expansionLevel)
	local step = G.GRID_SNAP * 4
	local best: Vec3? = nil
	local bestDistance = math.huge
	local y = box.min.y
	while y <= box.max.y + 1e-6 do
		local x = box.min.x
		while x <= box.max.x + 1e-6 do
			local z = box.min.z
			while z <= box.max.z + 1e-6 do
				local spot = { x = x, y = y, z = z }
				local d = (x - start.x) ^ 2 + (y - start.y) ^ 2 + (z - start.z) ^ 2
				if d < bestDistance and PlacementRules.checkStar(spot, expansionLevel, others) then
					best, bestDistance = spot, d
				end
				z += step
			end
			x += step
		end
		y += step
	end
	return best
end

return PlacementRules
