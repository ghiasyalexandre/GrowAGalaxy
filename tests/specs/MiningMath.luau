return function(T, Loader)
	local MiningMath = Loader.require("src/shared/Logic/MiningMath")

	T.describe("MiningMath", function()
		T.test("the weak point extracts at full power, rock at a share of it", function()
			T.equal(MiningMath.rate(10, true, 0.3), 10)
			T.near(MiningMath.rate(10, false, 0.3), 3)
		end)

		T.test("reward is the base with no weak-point work", function()
			T.equal(MiningMath.reward(30, 0, 50, 0.25), 30)
		end)

		T.test("all work on the weak point earns the full precision bonus", function()
			T.equal(MiningMath.reward(40, 100, 100, 0.25), 50)
		end)

		T.test("a partial share earns part of the bonus, rounded to a whole number", function()
			T.equal(MiningMath.reward(12, 50, 100, 0.25), 14) -- 12 x 1.125 = 13.5
		end)

		T.test("reward never drops below the base, even with bad inputs", function()
			T.equal(MiningMath.reward(12, -5, 10, 0.25), 12)
			T.equal(MiningMath.reward(12, 5, 0, 0.25), 12)
			T.equal(MiningMath.reward(12, 50, 10, 0.25), 15, "share is capped at 1")
		end)

		T.test("reservations: owner always, others only after the timeout", function()
			local alice, bob = {}, {}
			T.truthy(MiningMath.mayMine(nil, bob, 0, 100, 4), "free asteroid")
			T.truthy(MiningMath.mayMine(alice, alice, 99, 100, 4), "owner")
			T.falsy(MiningMath.mayMine(alice, bob, 99, 100, 4), "held by someone active")
			T.truthy(MiningMath.mayMine(alice, bob, 95, 100, 4), "lapsed reservation")
		end)
	end)
end
