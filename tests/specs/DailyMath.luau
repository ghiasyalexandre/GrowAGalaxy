return function(T, Loader)
	local Config = Loader.require("src/shared/Config")
	local DailyMath = Loader.require("src/shared/Logic/DailyMath")

	local DAYS = #Config.Daily.PRIZES

	T.describe("DailyMath", function()
		T.test("there are 14 days of prizes", function()
			T.equal(DAYS, 14)
		end)

		T.test("one claim per UTC day", function()
			local record = { day = 1, lastClaim = 0 }
			local day, after = DailyMath.claim(record, 100)
			T.equal(day, 1)
			T.equal(after.day, 2)
			local again = DailyMath.claim(after, 100)
			T.equal(again, nil, "second claim the same day")
			T.truthy(DailyMath.canClaim(after, 101))
		end)

		T.test("after day 14 the calendar starts again at day 1", function()
			local record = { day = DAYS, lastClaim = 5 }
			local day, after = DailyMath.claim(record, 6)
			T.equal(day, DAYS)
			T.equal(after.day, 1)
		end)

		T.test("missing days keeps your place", function()
			local day = DailyMath.claim({ day = 5, lastClaim = 10 }, 30)
			T.equal(day, 5)
		end)

		T.test("days and countdowns follow UTC midnight", function()
			T.equal(DailyMath.today(86400 * 3 + 5), 3)
			T.equal(DailyMath.secondsToNext(86400 * 3 + 100), 86300)
		end)

		T.test("prizes read clearly", function()
			T.equal(DailyMath.describe(10000), "10,000 Stardust")
			T.equal(DailyMath.describe(250), "250 Stardust")
		end)

		T.test("prizes are minutes of the reward rate; a new player's first is 120", function()
			T.equal(DailyMath.amount(1, 1), 120)
			T.equal(DailyMath.amount(14, 1000), 15 * 60 * 1000)
			T.equal(DailyMath.amount(1, 0.5), 120, "R is at least 1")
		end)
	end)
end
