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

		T.test("max level is 4 at tier 1 and 2 more (even) each tier", function()
			local previous = 0
			for _, id in S.ORDER do
				local top = StarMath.maxLevel(id)
				T.equal(top % 2, 0, `{id} max level is even`)
				if previous > 0 then
					T.equal(top - previous, S.MAX_LEVEL_STEP)
				end
				previous = top
			end
			T.equal(StarMath.maxLevel(first), 4)
		end)

		T.test("levelling stops at max level, prices rise level by level", function()
			local top = StarMath.maxLevel(first)
			T.truthy(StarMath.upgradeCost(first, 1))
			T.truthy(StarMath.upgradeCost(first, top - 1) > StarMath.upgradeCost(first, 1))
			T.equal(StarMath.upgradeCost(first, top), nil)
		end)

		T.test("a star evolves only at max level, and never past the black hole", function()
			local top = StarMath.maxLevel(first)
			T.falsy(StarMath.canEvolve(star(first, top - 1)))
			T.truthy(StarMath.canEvolve(star(first, top)))
			T.falsy(StarMath.canEvolve(star("BlackHole", StarMath.maxLevel("BlackHole"))))
		end)

		T.test("orbits: 4 at tier 1, one more per evolution", function()
			T.equal(StarMath.slots(first), 4)
			T.equal(StarMath.slots("RedDwarf"), 5)
			T.equal(StarMath.slots("BlackHole"), 4 + #S.ORDER - 1)
			T.truthy(#S.SLOTS >= StarMath.slots("BlackHole"))
		end)

		T.test("outer orbits are slower (Kepler)", function()
			for index = 2, #S.SLOTS do
				T.truthy(S.SLOTS[index].periodDays > S.SLOTS[index - 1].periodDays)
			end
		end)

		T.test("a star grows with level up to MAX_RADIUS_SCALE", function()
			local base = S.BY_ID[first].radius
			T.near(StarMath.radius(first, 1), base)
			T.near(StarMath.radius(first, StarMath.maxLevel(first)), base * S.MAX_RADIUS_SCALE)
		end)

		T.test("a star holds planets up to its own tier", function()
			T.truthy(StarMath.planetAllowed("BrownDwarf", "Barren"))
			T.falsy(StarMath.planetAllowed("BrownDwarf", "Molten"))
			T.truthy(StarMath.planetAllowed("BlackHole", "Crystal"))
		end)

		T.test("free slots skip taken orbits and stop at the type's orbits", function()
			T.equal(StarMath.freeSlot(star(first, 1)), "1")
			T.equal(StarMath.freeSlot(star(first, 1, { ["1"] = "Barren" })), "2")
			local full = { ["1"] = "Barren", ["2"] = "Barren", ["3"] = "Barren", ["4"] = "Barren" }
			T.equal(StarMath.freeSlot(star(first, 4, full)), nil)
			T.equal(StarMath.freeSlot(star("RedDwarf", 1, full)), "5")
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
			local expected = math.floor(S.BY_ID.RedDwarf.income * StarMath.levelMultiplier(2) + 0.5)
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

		T.test("each star level adds more production than the last", function()
			local lastGain = 0
			for level = 2, 18 do
				local gain = StarMath.levelMultiplier(level) - StarMath.levelMultiplier(level - 1)
				T.truthy(gain > lastGain - 1e-9, `level {level}`)
				lastGain = gain
			end
			T.equal(StarMath.levelMultiplier(1), 1)
		end)
	end)
end
