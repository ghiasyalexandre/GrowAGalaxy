return function(T, Loader)
	local Config = Loader.require("src/shared/Config")
	local OfflineMath = Loader.require("src/shared/Logic/OfflineMath")

	local E = Config.Economy

	T.describe("OfflineMath", function()
		T.test("stars earn a quarter of their rate while you're away", function()
			local amount, seconds = OfflineMath.earned(10, 1000, 1000 + 3600)
			T.equal(amount, 9000)
			T.equal(seconds, 3600)
		end)

		T.test("capped at 8 hours of production, 12 with the Silo", function()
			T.equal(E.OFFLINE_CAP_SECONDS, 8 * 3600)
			T.equal(OfflineMath.earned(4, 1000, 1000 + 30 * 86400), 4 * 0.25 * 8 * 3600)
			T.equal(OfflineMath.earned(4, 1000, 1000 + 30 * 86400, 1.5), 4 * 0.25 * 12 * 3600)
		end)

		T.test("nothing on a first visit, a short break or a clock going backwards", function()
			T.equal((OfflineMath.earned(10, 0, 5000)), 0)
			T.equal((OfflineMath.earned(10, 1000, 1000 + E.OFFLINE_MIN_SECONDS - 1)), 0)
			T.equal((OfflineMath.earned(10, 5000, 1000)), 0)
			T.equal((OfflineMath.earned(0, 1000, 99999)), 0)
		end)
	end)
end
