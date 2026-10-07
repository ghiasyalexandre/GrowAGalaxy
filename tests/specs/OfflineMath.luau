return function(T, Loader)
	local Config = Loader.require("src/shared/Config")
	local OfflineMath = Loader.require("src/shared/Logic/OfflineMath")

	local E = Config.Economy

	T.describe("OfflineMath", function()
		T.test("stars earn while you're away, at your current rate", function()
			local amount, seconds = OfflineMath.earned(10, 1000, 1000 + 3600)
			T.equal(amount, 36000)
			T.equal(seconds, 3600)
		end)

		T.test("capped at 1 day of production", function()
			T.equal(E.OFFLINE_CAP_SECONDS, 86400)
			local amount = OfflineMath.earned(5, 1000, 1000 + 30 * 86400)
			T.equal(amount, 5 * 86400)
		end)

		T.test("nothing on a first visit, a short break or a clock going backwards", function()
			T.equal((OfflineMath.earned(10, 0, 5000)), 0)
			T.equal((OfflineMath.earned(10, 1000, 1000 + E.OFFLINE_MIN_SECONDS - 1)), 0)
			T.equal((OfflineMath.earned(10, 5000, 1000)), 0)
			T.equal((OfflineMath.earned(0, 1000, 99999)), 0)
		end)
	end)
end
