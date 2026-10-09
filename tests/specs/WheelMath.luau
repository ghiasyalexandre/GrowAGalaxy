return function(T, Loader)
	local Config = Loader.require("src/shared/Config")
	local WheelMath = Loader.require("src/shared/Logic/WheelMath")

	local W = Config.Wheel

	T.describe("WheelMath", function()
		T.test("the designed prizes and odds", function()
			local expected = {
				{ 1, 40 },
				{ 2, 25 },
				{ 3, 15 },
				{ 5, 12 },
				{ 8, 6 },
				{ 12, 2 },
			}
			T.equal(#W.PRIZES, #expected)
			for index, pair in expected do
				T.equal(W.PRIZES[index].minutes, pair[1])
				T.equal(W.PRIZES[index].weight, pair[2])
			end
			T.equal(WheelMath.total(), 100)
			T.equal(W.SPIN_COST, 0, "the spin is free")
			local expectedMinutes = 0
			for _, prize in W.PRIZES do
				expectedMinutes += prize.minutes * prize.weight / 100
			end
			T.near(expectedMinutes, 2.67, 1e-9, "2.67 minutes of R on average")
		end)

		T.test("every roll lands on a prize, each prize on exactly its weight", function()
			local counts = {}
			for roll = 1, WheelMath.total() do
				local index = WheelMath.pick(roll)
				counts[index] = (counts[index] or 0) + 1
			end
			for index, prize in W.PRIZES do
				T.equal(counts[index], prize.weight, `prize {index}`)
			end
		end)

		T.test("one free spin per day", function()
			T.truthy(WheelMath.ready(0, 1000), "never spun")
			local nextSpin = WheelMath.spin(0, 1000)
			T.equal(nextSpin, 1000 + W.COOLDOWN)
			T.equal(WheelMath.spin(nextSpin :: number, 1000 + W.COOLDOWN - 1), nil, "too early")
			T.equal(WheelMath.wait(nextSpin :: number, 1000 + 3600), W.COOLDOWN - 3600)
			T.truthy(WheelMath.spin(nextSpin :: number, 1000 + W.COOLDOWN), "a day later")
			T.equal(W.COOLDOWN, 86400)
		end)

		T.test("the wheel stops with the prize under the pointer", function()
			for index = 1, #W.PRIZES do
				for _, from in { 0, 37, -500, 1234.5 } do
					local stop = WheelMath.landing(from, index, 5)
					T.truthy(stop >= from + 360 * 5, "turns forward at least 5 times")
					local shown = (stop + WheelMath.segmentAngle(index)) % 360
					T.near(shown, 0, 1e-6)
				end
			end
		end)
	end)
end
