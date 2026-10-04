--!strict
-- Rules for where a star (and so a whole solar system) may sit in a region.
-- Shared so the client's ghost preview and the server's validation agree; the
-- server always re-runs these checks and never trusts the client's verdict.

local Config = require(script.Parent.Parent.Config)
local RegionMath = require(script.Parent.RegionMath)
local Types = require(script.Parent.Parent.Types)

type Vec3 = Types.Vec3

export type Rejection = "Invalid" | "OutOfBounds" | "TooClose" | "AtCapacity"

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

local function distance(a: Vec3, b: Vec3): number
	local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- Can the player add another solar system at this expansion level?
function PlacementRules.hasCapacity(systemCount: number, expansionLevel: number): boolean
	return systemCount < RegionMath.maxSystems(expansionLevel)
end

-- Checks bounds and spacing for a star at `pos` (region space). `others` are
-- the positions of the player's other stars; when moving a star, leave the
-- moving star out.
function PlacementRules.checkStar(
	pos: any,
	expansionLevel: number,
	others: { Vec3 }
): (boolean, Rejection?)
	if not PlacementRules.isValidVec3(pos) then
		return false, "Invalid"
	end
	local size = RegionMath.regionSize(expansionLevel)
	if not RegionMath.isInside(pos, size, Config.Galaxy.WALL_MARGIN) then
		return false, "OutOfBounds"
	end
	for _, other in others do
		if distance(pos, other) < Config.Galaxy.MIN_STAR_SPACING then
			return false, "TooClose"
		end
	end
	return true, nil
end

return PlacementRules
