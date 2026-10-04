return function(T, Loader)
	local roblox = require("@lune/roblox")
	local Vector3 = roblox.Vector3

	local Config = Loader.require("src/shared/Config")
	local BeamMath = Loader.require("src/shared/Logic/BeamMath")

	local B = Config.Beam
	local CONE = math.rad(B.AIM_CONE_DEGREES)

	local function angleOf(v): number
		return math.acos(math.clamp(BeamMath.FORWARD:Dot(v.Unit), -1, 1))
	end

	T.describe("BeamMath", function()
		T.test("each shot adds heat and the last one overheats at capacity", function()
			local heat, overheated = 0, false
			for _ = 1, 11 do
				heat, overheated = BeamMath.shotHeat(heat, 100, 9)
			end
			T.near(heat, 99)
			T.falsy(overheated)
			heat, overheated = BeamMath.shotHeat(heat, 100, 9)
			T.equal(heat, 100)
			T.truthy(overheated)
		end)

		T.test("firing heats the beam until it overheats at capacity", function()
			local heat, overheated = 0, false
			for _ = 1, 40 do
				heat, overheated = BeamMath.heatStep(heat, overheated, true, 0.1, 100, 20, 25, 0.3)
			end
			T.near(heat, 80, 1e-6, "4 seconds at 20 per second")
			T.falsy(overheated)
			for _ = 1, 10 do
				heat, overheated = BeamMath.heatStep(heat, overheated, true, 0.1, 100, 20, 25, 0.3)
			end
			T.near(heat, 100, 1e-6, "capped at capacity")
			T.truthy(overheated)
		end)

		T.test("an overheated beam stays locked until it cools to the resume share", function()
			local heat, overheated = 100, true
			-- Still holding the trigger: no more heat, it cools instead.
			heat, overheated = BeamMath.heatStep(heat, overheated, true, 1, 100, 20, 25, 0.3)
			T.near(heat, 75)
			T.truthy(overheated, "still locked at 75")
			heat, overheated = BeamMath.heatStep(heat, overheated, true, 2, 100, 20, 25, 0.3)
			T.near(heat, 25)
			T.falsy(overheated, "unlocked below 30")
			heat = BeamMath.heatStep(heat, overheated, false, 5, 100, 20, 25, 0.3)
			T.near(heat, 0, 1e-9, "never below zero")
		end)

		T.test("clampToCone keeps aims inside the cone and fixes those outside", function()
			local inside = Vector3.new(0.2, 0, -1).Unit
			T.near((BeamMath.clampToCone(BeamMath.FORWARD, inside, CONE) - inside).Magnitude, 0)
			local wide = Vector3.new(1, 0, -0.2).Unit
			local clamped = BeamMath.clampToCone(BeamMath.FORWARD, wide, CONE)
			T.near(angleOf(clamped), CONE, 1e-6, "on the cone's edge")
			T.near(clamped.Magnitude, 1, 1e-6, "unit length")
			T.truthy(clamped.X > 0, "same side as the aim")
			local back = BeamMath.clampToCone(BeamMath.FORWARD, Vector3.new(0, 0, 1), CONE)
			T.near(angleOf(back), CONE, 1e-6, "straight back still lands on the cone")
		end)

		T.test("sanitizeAim rejects junk from clients", function()
			T.equal(BeamMath.sanitizeAim("left", CONE), nil, "not a Vector3")
			T.equal(BeamMath.sanitizeAim(Vector3.zero, CONE), nil, "zero")
			T.equal(BeamMath.sanitizeAim(Vector3.new(0, 0, -1e9), CONE), nil, "huge")
			T.equal(BeamMath.sanitizeAim(Vector3.new(0 / 0, 0, -1), CONE), nil, "NaN")
			T.equal(BeamMath.sanitizeAim(Vector3.new(math.huge, 0, 0), CONE), nil, "infinite")
			local aim = BeamMath.sanitizeAim(Vector3.new(0, 1.2, 0), CONE)
			T.truthy(aim ~= nil, "a sideways aim is clamped, not rejected")
			T.near(angleOf(aim), CONE, 1e-6)
			T.near(aim.Magnitude, 1, 1e-6)
		end)
	end)
end
