return function(T, Loader)
	local Config = Loader.require("src/shared/Config")
	local StarMath = Loader.require("src/shared/Logic/StarMath")

	local id = Config.Stars.DEFAULT_TYPE
	local def = Config.Stars.BY_ID[id]

	T.describe("StarMath", function()
		T.test("each star you own makes the next one pricier", function()
			T.equal(StarMath.placeCost(id, 0), def.cost)
			T.truthy(StarMath.placeCost(id, 1) > def.cost)
			T.equal(StarMath.placeCost("Nope", 0), nil)
		end)

		T.test("upgrades cost the next level's price and stop at the top", function()
			T.equal(StarMath.upgradeCost(id, 1), def.levels[2].upgradeCost)
			T.equal(StarMath.upgradeCost(id, #def.levels), nil)
		end)

		T.test("a new star has no planets; upgrades add them", function()
			T.equal(#StarMath.planetsAt(id, 1), 0)
			T.equal(#StarMath.planetsAt(id, 2), 1)
			T.truthy(#StarMath.planetsAt(id, #def.levels) >= 2)
		end)

		T.test("total income sums every star, unknown types make nothing", function()
			local stars = {
				a = { typeId = id, level = 1, pos = { x = 0, y = 0, z = 0 } },
				b = { typeId = id, level = 2, pos = { x = 0, y = 0, z = 0 } },
				c = { typeId = "Nope", level = 3, pos = { x = 0, y = 0, z = 0 } },
			}
			T.near(StarMath.totalIncome(stars), def.levels[1].income + def.levels[2].income)
		end)

		T.test("income accrues up to the cap and never lowers an amount above it", function()
			T.near(StarMath.accrue(0, 2, 3, 100), 6)
			T.near(StarMath.accrue(99, 2, 3, 100), 100)
			T.near(StarMath.accrue(150, 2, 3, 100), 150)
		end)
	end)
end
