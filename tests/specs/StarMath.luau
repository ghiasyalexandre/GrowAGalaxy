return function(T, Loader)
	local Config = Loader.require("src/shared/Config")
	local StarMath = Loader.require("src/shared/Logic/StarMath")

	local S, P = Config.Stars, Config.Planets
	local first = S.DEFAULT_TYPE

	local function star(typeId, level, planets)
		return {
			typeId = typeId,
			level = level,
			pos = { x = 0, y = 0, z = 0 },
			planets = planets or {},
		}
	end

	T.describe("StarMath", function()
		T.test("each star you own makes the next one pricier", function()
			T.equal(StarMath.placeCost(first, 0), S.BY_ID[first].cost)
			T.truthy(StarMath.placeCost(first, 1) > S.BY_ID[first].cost)
			T.equal(StarMath.placeCost("Nope", 0), nil)
		end)

		T.test("a tier unlocks once you own a star of the tier before it", function()
			T.truthy(StarMath.typeUnlocked(first, {}))
			T.falsy(StarMath.typeUnlocked("RedDwarf", {}))
			T.truthy(StarMath.typeUnlocked("RedDwarf", { a = star(first, 1) }))
			T.falsy(StarMath.typeUnlocked("BlackHole", { a = star("RedGiant", 1) }))
			T.truthy(StarMath.typeUnlocked("BlackHole", { a = star("RedSupergiant", 1) }))
		end)

		T.test("the next goal is the tier above your best star", function()
			T.equal(StarMath.nextTier({}), first)
			T.equal(
				StarMath.nextTier({ a = star(first, 1), b = star("YellowDwarf", 2) }),
				"WhiteDwarf"
			)
			T.equal(StarMath.nextTier({ a = star("BlackHole", 1) }), nil)
		end)

		T.test("stars evolve up the ladder and stop at the black hole", function()
			T.equal(StarMath.evolveTarget("BrownDwarf"), "RedDwarf")
			T.equal(StarMath.evolveTarget("RedSupergiant"), "BlackHole")
			T.equal(StarMath.evolveTarget("BlackHole"), nil)
		end)

		T.test("levels open orbit slots and stop at the top", function()
			T.equal(StarMath.slots(1), 1)
			T.equal(StarMath.slots(#S.LEVELS), #S.SLOTS)
			T.truthy(StarMath.upgradeCost(first, 1))
			T.equal(StarMath.upgradeCost(first, #S.LEVELS), nil)
		end)

		T.test("a star holds planets up to its own tier", function()
			T.truthy(StarMath.planetAllowed("BrownDwarf", "Barren"))
			T.falsy(StarMath.planetAllowed("BrownDwarf", "Molten"))
			T.truthy(StarMath.planetAllowed("BlackHole", "Crystal"))
		end)

		T.test("free slots respect the level and skip taken orbits", function()
			T.equal(StarMath.freeSlot(star(first, 1)), "1")
			T.equal(StarMath.freeSlot(star(first, 1, { ["1"] = "Barren" })), nil)
			T.equal(StarMath.freeSlot(star(first, 3, { ["1"] = "Barren" })), "2")
		end)

		T.test(
			"planet upgrades go one tier up, credit half the old price, stop at the top",
			function()
				local nextId, cost = StarMath.planetUpgrade("Barren")
				T.equal(nextId, "Molten")
				T.equal(cost, P.BY_ID.Molten.cost - P.BY_ID.Barren.cost * P.UPGRADE_CREDIT)
				T.equal((StarMath.planetUpgrade("Crystal")), nil)
			end
		)

		T.test("income adds the star (by level) and its planets", function()
			local s = star("RedDwarf", 2, { ["1"] = "Barren", ["2"] = "Molten" })
			local expected = S.BY_ID.RedDwarf.income * S.LEVELS[2].incomeMultiplier
				+ P.BY_ID.Barren.income
				+ P.BY_ID.Molten.income
			T.near(StarMath.income(s), expected)
			T.near(StarMath.totalIncome({ a = s, b = star("Nope", 1) }), expected)
		end)

		T.test("planets round-trip through the attribute string", function()
			local text = StarMath.encodePlanets({ ["1"] = "Barren", ["3"] = "Ocean" })
			local back = StarMath.decodePlanets(text)
			T.equal(back[1], "Barren")
			T.equal(back[2], nil)
			T.equal(back[3], "Ocean")
		end)

		T.test("income accrues up to the cap and never lowers an amount above it", function()
			T.near(StarMath.accrue(0, 2, 3, 100), 6)
			T.near(StarMath.accrue(99, 2, 3, 100), 100)
			T.near(StarMath.accrue(150, 2, 3, 100), 150)
		end)
	end)
end
