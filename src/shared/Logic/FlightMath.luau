--!strict
-- Movement maths shared by the spacesuit and ship controllers (client) and
-- the flight guard (server). Pure functions on Vector3/CFrame values.

local FlightMath = {}

-- Moves `current` towards `target` by at most `rate * dt`. Uses `accel` when
-- the target is at least as fast as the current velocity, `decel` otherwise,
-- so slowing down can be quicker (or gentler) than speeding up.
function FlightMath.step(
	current: Vector3,
	target: Vector3,
	accel: number,
	decel: number,
	dt: number
): Vector3
	local rate = if target.Magnitude >= current.Magnitude then accel else decel
	local delta = target - current
	local maxStep = rate * dt
	if delta.Magnitude <= maxStep then
		return target
	end
	return current + delta.Unit * maxStep
end

-- Clamps each input axis to [-1, 1] and the whole vector to length 1, so
-- diagonal input is not faster.
function FlightMath.normalizeInput(input: Vector3): Vector3
	local clamped = Vector3.new(
		math.clamp(input.X, -1, 1),
		math.clamp(input.Y, -1, 1),
		math.clamp(input.Z, -1, 1)
	)
	if clamped.Magnitude > 1 then
		return clamped.Unit
	end
	return clamped
end

-- Spacesuit: input x = right, y = up, z = forward, relative to the camera.
function FlightMath.suitTarget(input: Vector3, camera: CFrame, maxSpeed: number): Vector3
	local move = FlightMath.normalizeInput(input)
	local direction = camera.RightVector * move.X
		+ camera.UpVector * move.Y
		+ camera.LookVector * move.Z
	return direction * maxSpeed
end

export type ShipHandling = {
	maxSpeed: number,
	reverseFactor: number,
	strafeFactor: number,
}

-- Ship: input z = throttle (forward positive), x = strafe, y = lift,
-- relative to the ship's own orientation.
function FlightMath.shipTarget(input: Vector3, ship: CFrame, handling: ShipHandling): Vector3
	local move = Vector3.new(
		math.clamp(input.X, -1, 1),
		math.clamp(input.Y, -1, 1),
		math.clamp(input.Z, -1, 1)
	)
	local forwardSpeed = if move.Z >= 0
		then move.Z * handling.maxSpeed
		else move.Z * handling.maxSpeed * handling.reverseFactor
	local sideSpeed = handling.maxSpeed * handling.strafeFactor
	return ship.LookVector * forwardSpeed
		+ ship.RightVector * (move.X * sideSpeed)
		+ ship.UpVector * (move.Y * sideSpeed)
end

-- Angle in radians between two orientations (positions are ignored).
function FlightMath.angleBetween(a: CFrame, b: CFrame): number
	local r = a.Rotation:Inverse() * b.Rotation
	local trace = r.XVector.X + r.YVector.Y + r.ZVector.Z
	return math.acos(math.clamp((trace - 1) / 2, -1, 1))
end

-- Rotates `from` towards `to` by at most `maxAngle` radians. Returns a
-- rotation-only CFrame.
function FlightMath.turnTowards(from: CFrame, to: CFrame, maxAngle: number): CFrame
	local angle = FlightMath.angleBetween(from, to)
	if angle <= maxAngle or angle < 1e-6 then
		return to.Rotation
	end
	return from.Rotation:Lerp(to.Rotation, maxAngle / angle)
end

-- Eases `from` towards `to`: each frame covers a share of the remaining
-- angle set by `response` (exponential smoothing, so turns start quickly and
-- settle gently), but never more than `maxRate * dt` radians. Returns a
-- rotation-only CFrame.
function FlightMath.easeTowards(
	from: CFrame,
	to: CFrame,
	maxRate: number,
	response: number,
	dt: number
): CFrame
	local angle = FlightMath.angleBetween(from, to)
	if angle < 1e-6 then
		return to.Rotation
	end
	local step = math.min(maxRate * dt, angle * (1 - math.exp(-response * dt)))
	return from.Rotation:Lerp(to.Rotation, step / angle)
end

-- Moves a number towards `target` by a share of the gap set by `rate`, the
-- same amount whatever the frame rate.
function FlightMath.smooth(current: number, target: number, rate: number, dt: number): number
	return current + (target - current) * (1 - math.exp(-rate * dt))
end

-- An angle in radians wrapped into [-pi, pi).
function FlightMath.wrapAngle(angle: number): number
	return (angle + math.pi) % (2 * math.pi) - math.pi
end

-- How far a ship rolls (radians) while turning at `yawRate` radians per
-- second (positive = turning left) and strafing with `strafe` in [-1, 1]
-- (positive = right). Positive roll lowers the left wing, so the ship leans
-- into turns and towards the side it strafes to.
function FlightMath.bankAngle(
	yawRate: number,
	strafe: number,
	perTurn: number,
	strafeBank: number,
	maxBank: number
): number
	return math.clamp(yawRate * perTurn - strafe * strafeBank, -maxBank, maxBank)
end

-- Chase-camera / steering orientation from yaw and pitch (radians).
function FlightMath.aim(yaw: number, pitch: number): CFrame
	return CFrame.fromOrientation(pitch, yaw, 0)
end

-- Yaw and pitch that point along a CFrame's look direction.
function FlightMath.yawPitchOf(cf: CFrame): (number, number)
	local look = cf.LookVector
	local yaw = math.atan2(-look.X, -look.Z)
	local pitch = math.asin(math.clamp(look.Y, -1, 1))
	return yaw, pitch
end

-- Could something with this top speed have covered `distance` in `dt` seconds?
function FlightMath.plausibleTravel(
	distance: number,
	dt: number,
	maxSpeed: number,
	tolerance: number,
	slack: number
): boolean
	return distance <= maxSpeed * dt * tolerance + slack
end

-- Removes the parts of `velocity` that would carry `position` further past
-- the flight area: a vertical cylinder of `radius` around the origin, from
-- -height to +height. Velocity back inside, or along the edge, is kept.
function FlightMath.clampToBounds(
	position: Vector3,
	velocity: Vector3,
	radius: number,
	height: number
): Vector3
	local result = velocity
	local flat = Vector3.new(position.X, 0, position.Z)
	if flat.Magnitude > radius then
		local outward = flat.Unit
		local along = result:Dot(outward)
		if along > 0 then
			result -= outward * along
		end
	end
	if (position.Y > height and result.Y > 0) or (position.Y < -height and result.Y < 0) then
		result = Vector3.new(result.X, 0, result.Z)
	end
	return result
end

-- Is a point inside the flight area, allowing `margin` extra studs?
function FlightMath.inBounds(
	position: Vector3,
	radius: number,
	height: number,
	margin: number
): boolean
	local flat = Vector3.new(position.X, 0, position.Z)
	return flat.Magnitude <= radius + margin and math.abs(position.Y) <= height + margin
end

export type BoostState = {
	energy: number, -- seconds of boost left
	locked: boolean, -- emptied; waiting to refill to the restart share
}

-- One frame of a ship's boost tank. Boosting drains a second per second; not
-- boosting refills the whole tank in `recharge` seconds. Running dry locks
-- boost until the tank is back to `restartShare` of `duration`. Returns the
-- new state and whether the ship boosts this frame.
function FlightMath.boostStep(
	state: BoostState,
	wanted: boolean,
	duration: number,
	recharge: number,
	restartShare: number,
	dt: number
): (BoostState, boolean)
	if wanted and not state.locked and state.energy > 0 then
		local energy = math.max(0, state.energy - dt)
		return { energy = energy, locked = energy <= 0 }, true
	end
	local energy = math.min(duration, state.energy + duration / math.max(recharge, 0.01) * dt)
	local locked = state.locked and energy < duration * restartShare
	return { energy = energy, locked = locked }, false
end

-- Is a point inside a box part (any rotation)?
function FlightMath.insideBox(boxCFrame: CFrame, boxSize: Vector3, point: Vector3): boolean
	local p = boxCFrame:PointToObjectSpace(point)
	return math.abs(p.X) <= boxSize.X / 2
		and math.abs(p.Y) <= boxSize.Y / 2
		and math.abs(p.Z) <= boxSize.Z / 2
end

return FlightMath
