--!strict
-- Mining laser maths shared by the pilot's client and the server: heat and
-- overheating, and keeping the aim inside the cone in front of the ship.
-- Directions are in ship space, where -Z is the nose.

local BeamMath = {}

BeamMath.FORWARD = Vector3.new(0, 0, -1)

-- Advances beam heat by `dt` seconds. Firing adds `heatRate` per second until
-- `capacity`, which overheats the beam; otherwise it cools at `coolingRate`.
-- An overheated beam can't fire until heat falls to `resumeShare` of the
-- capacity. Returns the new heat and overheated flag.
function BeamMath.heatStep(
	heat: number,
	overheated: boolean,
	firing: boolean,
	dt: number,
	capacity: number,
	heatRate: number,
	coolingRate: number,
	resumeShare: number
): (number, boolean)
	if firing and not overheated then
		heat = math.min(capacity, heat + heatRate * dt)
		return heat, heat >= capacity
	end
	heat = math.max(0, heat - coolingRate * dt)
	if overheated and heat <= capacity * resumeShare then
		overheated = false
	end
	return heat, overheated
end

-- `direction` (a unit vector) turned towards `forward` (a unit vector) until
-- it is at most `maxAngle` radians away from it.
function BeamMath.clampToCone(forward: Vector3, direction: Vector3, maxAngle: number): Vector3
	local cos = math.clamp(forward:Dot(direction), -1, 1)
	if math.acos(cos) <= maxAngle then
		return direction
	end
	local side = direction - forward * cos
	if side.Magnitude < 1e-6 then
		-- Pointing straight back: any edge of the cone will do.
		side = if math.abs(forward.Y) < 0.9 then Vector3.new(0, 1, 0) else Vector3.new(1, 0, 0)
		side -= forward * forward:Dot(side)
	end
	return forward * math.cos(maxAngle) + side.Unit * math.sin(maxAngle)
end

-- Checks an aim a client sent: a finite, roughly unit Vector3. Returns it
-- normalised and inside the cone in front of the nose, or nil if invalid.
function BeamMath.sanitizeAim(value: unknown, maxAngle: number): Vector3?
	if typeof(value) ~= "Vector3" then
		return nil
	end
	local aim = value :: Vector3
	local length = aim.Magnitude
	-- NaN fails both comparisons; infinity fails the upper bound.
	if not (length >= 0.5 and length <= 2) then
		return nil
	end
	return BeamMath.clampToCone(BeamMath.FORWARD, aim / length, maxAngle)
end

return BeamMath
