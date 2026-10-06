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

		T.test("a planet type this server doesn't know keeps waiting", function()
			local hatches =
				{ ["1"] = { eggId = "e1", outcome = "FutureType", startedAt = 0, endsAt = 1 } }
			T.equal(HatchMath.finish(hatches, "1", 100), nil)
			T.truthy(hatches["1"])
		end)
	end)
end
