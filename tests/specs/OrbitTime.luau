return function(T, Loader)
	local Config = Loader.require("src/shared/Config")
	local OrbitTime = Loader.require("src/shared/Logic/OrbitTime")

	local S = Config.Stars

	T.describe("OrbitTime", function()
		T.test("the slider runs from an hour to three decades per second", function()
			T.near(OrbitTime.rateAt(0), 3600)
			T.near(OrbitTime.rateAt(1), S.INSPECT_RATE_MAX, 1)
			T.near(OrbitTime.rateAt(-1), 3600)
		end)

		T.test("slider positions and rates round-trip", function()
			for _, position in { 0, 0.25, 0.5, 0.9, 1 } do
				T.near(OrbitTime.positionOf(OrbitTime.rateAt(position)), position, 1e-6)
			end
		end)

		T.test("the default speed sits inside the slider's range", function()
			local at = OrbitTime.positionOf(S.ORBIT_DEFAULT_RATE)
			T.truthy(at > 0 and at < 1)
		end)

		T.test("a planet goes once round its orbit in one of its years", function()
			local year = S.SLOTS[1].periodDays * OrbitTime.DAY
			T.near(OrbitTime.angle(1, 0, 0.5), 0.5)
			T.near(OrbitTime.angle(1, year / 4, 0), math.pi / 2, 1e-6)
			T.near(OrbitTime.angle(1, year, 0), 0, 1e-6)
		end)

		T.test("time spans read naturally", function()
			T.equal(OrbitTime.describe(3600), "1 hour")
			T.equal(OrbitTime.describe(88 * OrbitTime.DAY), "88 days")
			T.equal(OrbitTime.describe(2.6 * OrbitTime.YEAR), "2.6 years")
			T.equal(OrbitTime.describe(30 * OrbitTime.YEAR), "3 decades")
			T.equal(OrbitTime.describeRate(5.5 * OrbitTime.DAY), "5.5 days / s")
		end)
	end)
end
