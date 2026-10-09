return function(T, Loader)
	local Config = Loader.require("src/shared/Config")
	local HatchMath = Loader.require("src/shared/Logic/HatchMath")

	local P, E = Config.Planets, Config.Eggs

	local function eggs()
		return {
			e1 = { outcome = "Basalt", guaranteed = false, boughtAt = 0 },
			e2 = { outcome = "Singularity", guaranteed = true, boughtAt = 0 },
		}
	end

	T.describe("HatchMath", function()
		T.test("starting moves the egg into the chamber in one step", function()
			local waiting, hatches = eggs(), {}
			local hatch = HatchMath.begin(waiting, hatches, "e1", 2, 1000)
			T.truthy(hatch)
			T.equal(waiting.e1, nil, "the egg left the inventory")
			T.equal(hatches["2"], hatch, "and is in chamber 2")
			T.equal(hatch.outcome, "Basalt", "same planet, never rerolled")
			T.equal(hatch.startedAt, 1000)
			T.equal(hatch.endsAt, 1000 + P.RARITIES.Common.hatchSeconds)
		end)

		T.test("the egg's tier carries into the hatch and out with the planet", function()
			local waiting, hatches = eggs(), {}
			waiting.e1.tier = 6
			local hatch = HatchMath.begin(waiting, hatches, "e1", 1, 0)
			T.equal(hatch.tier, 6)
			local done = HatchMath.advance(waiting, hatches, hatch.endsAt, false)
			T.equal(#done, 1)
			T.equal(done[1].tier, 6)
		end)

		T.test("hatch time comes from the planet's rarity", function()
			local waiting, hatches = eggs(), {}
			local hatch = HatchMath.begin(waiting, hatches, "e2", 1, 0)
			T.equal(hatch.endsAt, 1800, "Interstellar: 30 minutes")
		end)

		T.test("a busy chamber, a missing egg or a bad chamber changes nothing", function()
			local waiting, hatches = eggs(), {}
			HatchMath.begin(waiting, hatches, "e1", 1, 0)
			T.equal(HatchMath.begin(waiting, hatches, "e2", 1, 0), nil, "busy")
			T.truthy(waiting.e2, "egg kept")
			T.equal(HatchMath.begin(waiting, hatches, "e9", 2, 0), nil, "no such egg")
			T.equal(HatchMath.begin(waiting, hatches, "e2", E.HATCH_SLOTS + 1, 0), nil)
			T.equal(HatchMath.begin(waiting, hatches, "e2", 0, 0), nil)
			T.equal(HatchMath.begin(waiting, hatches, "e2", 1.5, 0), nil)
			T.equal(hatches["2"], nil)
		end)

		T.test("finishes only when due, exactly once, freeing the chamber", function()
			local waiting, hatches = eggs(), {}
			HatchMath.begin(waiting, hatches, "e1", 3, 100)
			local ends = hatches["3"].endsAt
			T.equal(HatchMath.finish(hatches, "3", ends - 1), nil, "not yet")
			T.truthy(hatches["3"])
			T.equal(HatchMath.finish(hatches, "3", ends), "Basalt")
			T.equal(hatches["3"], nil, "chamber free again")
			T.equal(HatchMath.finish(hatches, "3", ends + 10), nil, "never twice")
		end)

		T.test("offline: everything finished while away is due at once, in order", function()
			local waiting, hatches = eggs(), {}
			HatchMath.begin(waiting, hatches, "e2", 5, 0) -- ends 1800
			HatchMath.begin(waiting, hatches, "e1", 2, 0) -- ends 10
			T.equal(#HatchMath.due(hatches, 9), 0)
			local due = HatchMath.due(hatches, 10)
			T.equal(#due, 1)
			T.equal(due[1], "2")
			due = HatchMath.due(hatches, 86400)
			T.equal(#due, 2)
			T.equal(due[1], "2")
			T.equal(due[2], "5")
		end)

		T.test("advance finishes in end order; auto-start chains eggs offline", function()
			local waiting = {
				e1 = { outcome = "Basalt", guaranteed = false, boughtAt = 0 }, -- 10 s
				e2 = { outcome = "Desert", guaranteed = false, boughtAt = 0 }, -- 10 s
				e3 = { outcome = "Aurora", guaranteed = false, boughtAt = 0 }, -- 80 s
			}
			local hatches = {}
			HatchMath.begin(waiting, hatches, "e1", 1, 0)
			-- Away for 25 s: e1 ends at 10, e2 starts then and ends at 20,
			-- e3 starts at 20 and is still hatching.
			local done = HatchMath.advance(waiting, hatches, 25, true)
			T.equal(#done, 2)
			T.equal(done[1].typeId, "Basalt")
			T.equal(done[1].at, 10)
			T.equal(done[2].typeId, "Desert")
			T.equal(done[2].at, 20)
			T.equal(hatches["1"].outcome, "Aurora")
			T.equal(hatches["1"].startedAt, 20)
			T.equal(next(waiting), nil)
			-- Nothing again until it's due, and never twice.
			T.equal(#HatchMath.advance(waiting, hatches, 99, true), 0)
			T.equal(#HatchMath.advance(waiting, hatches, 100, true), 1)
			T.equal(#HatchMath.advance(waiting, hatches, 1000, true), 0)
		end)

		T.test("without auto-start a freed chamber stays empty", function()
			local waiting = eggs()
			local hatches = {}
			HatchMath.begin(waiting, hatches, "e1", 1, 0)
			T.equal(#HatchMath.advance(waiting, hatches, 50, false), 1)
			T.equal(hatches["1"], nil)
			T.truthy(waiting.e2)
		end)

		T.test("fill puts the oldest eggs into every free chamber", function()
			local waiting = {}
			for index = 1, E.HATCH_SLOTS + 2 do
				waiting[`e{index}`] = { outcome = "Basalt", guaranteed = false, boughtAt = 0 }
			end
			local hatches = {}
			HatchMath.begin(waiting, hatches, "e7", 2, 0)
			T.equal(HatchMath.fill(waiting, hatches, 5), E.HATCH_SLOTS - 1)
			T.equal(hatches["1"].eggId, "e1")
			T.equal(hatches["2"].eggId, "e7", "a busy chamber is left alone")
			T.equal(hatches["3"].eggId, "e2")
			T.truthy(waiting[`e{E.HATCH_SLOTS}`], "the newest waits")
		end)

		T.test("a planet type this server doesn't know keeps waiting", function()
			local hatches =
				{ ["1"] = { eggId = "e1", outcome = "FutureType", startedAt = 0, endsAt = 1 } }
			T.equal(HatchMath.finish(hatches, "1", 100), nil)
			T.truthy(hatches["1"])
		end)
	end)
end
