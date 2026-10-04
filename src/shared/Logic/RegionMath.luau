--!strict
-- Where galaxy regions sit around the ISS and what counts as inside one.
--
-- Region space: the origin is the centre of the region's near face (the face
-- that points at the ISS). +Z points away from the ISS, +Y is up. A region of
-- size (w, h, d) covers x in [-w/2, w/2], y in [-h/2, h/2], z in [0, d].
-- Saved positions use region space, so a galaxy loads into any slot unchanged.
--
-- Pure math on plain {x, y, z} tables so it runs in the Lune unit tests; the
-- server turns the results into CFrames (see RegionSystem).

local Config = require(script.Parent.Parent.Config)
local Types = require(script.Parent.Parent.Types)

type Vec3 = Types.Vec3

local RegionMath = {}

-- World position of a slot's region origin, and the yaw (radians around +Y)
-- for CFrame.Angles(0, yaw, 0) that points the region's -Z axis at the ISS.
function RegionMath.slotOrigin(slot: number): (Vec3, number)
	local angle = (slot - 1) / Config.World.MAX_PLAYERS * 2 * math.pi
	local radius = Config.World.REGION_RING_RADIUS
	return {
		x = math.sin(angle) * radius,
		y = Config.World.REGION_RING_HEIGHT,
		z = math.cos(angle) * radius,
	},
		angle
end

-- Region space -> world space for a slot. Matches
-- CFrame.new(origin) * CFrame.Angles(0, yaw, 0) * localPos.
function RegionMath.toWorld(slot: number, localPos: Vec3): Vec3
	local origin, yaw = RegionMath.slotOrigin(slot)
	local c, s = math.cos(yaw), math.sin(yaw)
	return {
		x = origin.x + c * localPos.x + s * localPos.z,
		y = origin.y + localPos.y,
		z = origin.z - s * localPos.x + c * localPos.z,
	}
end

function RegionMath.regionSize(level: number): Vec3
	local expansions = Config.Galaxy.EXPANSIONS
	local def = expansions[math.clamp(level, 1, #expansions)]
	return def.size
end

function RegionMath.maxSystems(level: number): number
	local expansions = Config.Galaxy.EXPANSIONS
	return expansions[math.clamp(level, 1, #expansions)].maxSystems
end

-- True when localPos is inside a region of the given size, at least `margin`
-- studs away from every wall.
function RegionMath.isInside(localPos: Vec3, size: Vec3, margin: number): boolean
	local halfW, halfH = size.x / 2 - margin, size.y / 2 - margin
	return math.abs(localPos.x) <= halfW
		and math.abs(localPos.y) <= halfH
		and localPos.z >= margin
		and localPos.z <= size.z - margin
end

-- Lowest slot number not in `taken`, or nil when the server is full.
function RegionMath.firstFreeSlot(taken: { [number]: any }): number?
	for slot = 1, Config.World.MAX_PLAYERS do
		if taken[slot] == nil then
			return slot
		end
	end
	return nil
end

return RegionMath
