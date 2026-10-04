return function(T, Loader)
	local roblox = require("@lune/roblox")
	local Vector3 = roblox.Vector3
	local CFrame = roblox.CFrame

	local Config = Loader.require("src/shared/Config")
	local FlightMath = Loader.require("src/shared/Logic/FlightMath")

	T.describe("FlightMath", function()
		T.test("step accelerates no faster than the acceleration rate", function()
			local v = FlightMath.step(Vector3.zero, Vector3.new(0, 0, -100), 30, 70, 0.5)
			T.near(v.Magnitude, 15)
		end)

		T.test("step reaches the target without overshooting", function()
			local v = FlightMath.step(Vector3.new(0, 0, -10), Vector3.new(0, 0, -12), 30, 70, 1)
			T.near(v.Z, -12)
		end)

		T.test("step uses the deceleration rate when slowing down", function()
			local v = FlightMath.step(Vector3.new(0, 0, -100), Vector3.zero, 30, 70, 0.5)
			T.near(v.Magnitude, 65)
		end)

		T.test("diagonal suit input is no faster than straight input", function()
			local camera = CFrame.new()
			local straight = FlightMath.suitTarget(Vector3.new(0, 0, 1), camera, 24)
			local diagonal = FlightMath.suitTarget(Vector3.new(1, 1, 1), camera, 24)
			T.near(straight.Magnitude, 24)
			T.near(diagonal.Magnitude, 24)
		end)

		T.test("suit moves along the camera's look direction", function()
			local camera = CFrame.lookAt(Vector3.zero, Vector3.new(1, 0, 0))
			local v = FlightMath.suitTarget(Vector3.new(0, 0, 1), camera, 10)
			T.near(v.X, 10)
			T.near(v.Z, 0)
		end)

		T.test("ship reverse and strafe are capped by their factors", function()
			local handling = { maxSpeed = 100, reverseFactor = 0.3, strafeFactor = 0.45 }
			local ship = CFrame.new()
			T.near(FlightMath.shipTarget(Vector3.new(0, 0, 1), ship, handling).Magnitude, 100)
			T.near(FlightMath.shipTarget(Vector3.new(0, 0, -1), ship, handling).Magnitude, 30)
			T.near(FlightMath.shipTarget(Vector3.new(1, 0, 0), ship, handling).Magnitude, 45)
			-- Forward is the ship's look direction.
			T.near(FlightMath.shipTarget(Vector3.new(0, 0, 1), ship, handling).Z, -100)
		end)

		T.test("aim and yawPitchOf round-trip", function()
			for _, pair in { { 0.3, 0.2 }, { -2.5, -0.9 }, { 1.2, 0 } } do
				local yaw, pitch = FlightMath.yawPitchOf(FlightMath.aim(pair[1], pair[2]))
				T.near(yaw, pair[1], 1e-4, "yaw")
				T.near(pitch, pair[2], 1e-4, "pitch")
			end
		end)

		T.test("turnTowards turns no further than the limit", function()
			local from = FlightMath.aim(0, 0)
			local to = FlightMath.aim(math.rad(90), 0)
			T.near(FlightMath.angleBetween(from, to), math.rad(90), 1e-4, "angle")
			local step = FlightMath.turnTowards(from, to, math.rad(30))
			T.near(FlightMath.angleBetween(from, step), math.rad(30), 1e-3, "turned 30 degrees")
			T.near(FlightMath.angleBetween(step, to), math.rad(60), 1e-3, "60 degrees left")
			local done = FlightMath.turnTowards(from, to, math.rad(120))
			T.near(FlightMath.angleBetween(done, to), 0, 1e-3, "reaches the target")
		end)

		T.test("easeTowards slows as it arrives and respects the turn rate", function()
			local from = FlightMath.aim(0, 0)
			local to = FlightMath.aim(math.rad(90), 0)
			-- Far away the turn rate is the limit.
			local capped = FlightMath.easeTowards(from, to, math.rad(30), 50, 0.1)
			T.near(FlightMath.angleBetween(from, capped), math.rad(3), 1e-3, "capped")
			-- Close in, it covers a share of what's left.
			local near = FlightMath.aim(math.rad(88), 0)
			local eased = FlightMath.easeTowards(near, to, math.rad(360), 5, 0.1)
			local share = 1 - math.exp(-0.5)
			T.near(FlightMath.angleBetween(near, eased), math.rad(2) * share, 1e-4, "eased")
			T.near(FlightMath.angleBetween(FlightMath.easeTowards(to, to, 1, 5, 0.1), to), 0)
		end)

		T.test("smooth is frame-rate independent", function()
			local once = FlightMath.smooth(0, 10, 4, 0.2)
			local twice = FlightMath.smooth(FlightMath.smooth(0, 10, 4, 0.1), 10, 4, 0.1)
			T.near(once, twice, 1e-9)
			T.truthy(once > 0 and once < 10)
		end)

		T.test("wrapAngle keeps angles within half a turn", function()
			T.near(FlightMath.wrapAngle(math.rad(350)), math.rad(-10), 1e-9)
			T.near(FlightMath.wrapAngle(math.rad(-190)), math.rad(170), 1e-9)
			T.near(FlightMath.wrapAngle(0.5), 0.5, 1e-9)
		end)

		T.test("ships bank into turns and strafes, within the limit", function()
			local maxBank = math.rad(35)
			-- Turning left (positive yaw rate) lowers the left wing (positive roll).
			T.truthy(FlightMath.bankAngle(1, 0, 0.45, 0.26, maxBank) > 0, "left turn")
			T.truthy(FlightMath.bankAngle(-1, 0, 0.45, 0.26, maxBank) < 0, "right turn")
			T.truthy(FlightMath.bankAngle(0, 1, 0.45, 0.26, maxBank) < 0, "strafe right")
			T.near(FlightMath.bankAngle(10, -1, 0.45, 0.26, maxBank), maxBank, 1e-9, "clamped")
			-- Positive roll really is left wing down in Roblox's axes.
			local rolled = CFrame.Angles(0, 0, 0.3)
			T.truthy(rolled.RightVector.Y > 0, "right wing up")
			-- And a left turn really increases yaw.
			local yaw = FlightMath.yawPitchOf(CFrame.lookAt(Vector3.zero, Vector3.new(-1, 0, -1)))
			T.truthy(yaw > 0, "facing left of -Z is positive yaw")
		end)

		T.test("plausibleTravel allows top speed with tolerance and rejects teleports", function()
			local m = Config.Movement
			local function ok(distance)
				return FlightMath.plausibleTravel(
					distance,
					0.5,
					120,
					m.FLIGHT_GUARD_TOLERANCE,
					m.FLIGHT_GUARD_SLACK
				)
			end
			T.truthy(ok(60), "exactly top speed")
			T.truthy(ok(95), "within tolerance")
			T.falsy(ok(500), "a teleport")
		end)

		T.test("clampToBounds stops outward thrust at the edge only", function()
			local inside =
				FlightMath.clampToBounds(Vector3.new(100, 0, 0), Vector3.new(50, 10, 0), 1000, 500)
			T.near(inside.X, 50, 1e-9, "inside the area nothing changes")
			local edge =
				FlightMath.clampToBounds(Vector3.new(1100, 0, 0), Vector3.new(50, 0, 20), 1000, 500)
			T.near(edge.X, 0, 1e-9, "outward part removed")
			T.near(edge.Z, 20, 1e-9, "sideways part kept")
			local back =
				FlightMath.clampToBounds(Vector3.new(1100, 0, 0), Vector3.new(-50, 0, 0), 1000, 500)
			T.near(back.X, -50, 1e-9, "heading back in is allowed")
			local high =
				FlightMath.clampToBounds(Vector3.new(0, 600, 0), Vector3.new(0, 30, 5), 1000, 500)
			T.near(high.Y, 0, 1e-9, "no climbing above the ceiling")
			local low =
				FlightMath.clampToBounds(Vector3.new(0, -600, 0), Vector3.new(0, 30, 0), 1000, 500)
			T.near(low.Y, 30, 1e-9, "climbing back up from below is allowed")
		end)

		T.test("inBounds uses the cylinder and the margin", function()
			T.truthy(FlightMath.inBounds(Vector3.new(0, 0, 999), 1000, 500, 0))
			T.falsy(FlightMath.inBounds(Vector3.new(0, 0, 1001), 1000, 500, 0))
			T.truthy(FlightMath.inBounds(Vector3.new(0, 0, 1001), 1000, 500, 50))
			T.falsy(FlightMath.inBounds(Vector3.new(0, -501, 0), 1000, 500, 0))
		end)

		T.test("insideBox handles rotated boxes", function()
			local box = CFrame.new(10, 0, 0) * CFrame.Angles(0, math.rad(45), 0)
			local size = Vector3.new(10, 10, 2)
			T.truthy(FlightMath.insideBox(box, size, Vector3.new(10, 0, 0)))
			T.truthy(FlightMath.insideBox(box, size, box * Vector3.new(4.9, 0, 0)))
			T.falsy(FlightMath.insideBox(box, size, box * Vector3.new(0, 0, 1.5)))
		end)
	end)
end
