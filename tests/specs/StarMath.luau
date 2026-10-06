return function(T, Loader)
	local Config = Loader.require("src/shared/Config")
	local StarMath = Loader.require("src/shared/Logic/StarMath")

	local S, P = Config.Stars, Config.Planets
	local first = S.DEFAULT_TYPE

	local function star(typeId, level)
		return {
			typeId = typeId,
			level = level,
			pos = { x = 0, y = 0, z = 0 },
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

		T.test("orbits: whole, never fewer up the ladder, 9 at the top", function()
			local last = 0
			for _, id in S.ORDER do
				local n = StarMath.slots(id)
				T.truthy(n == math.floor(n) and n >= last, id)
				last = n
			end
			T.equal(StarMath.slots(first), 3)
			T.equal(StarMath.slots("BlackHole"), 9)
			T.equal(S.MAX_ORBITS, 9)
			T.truthy(#S.SLOTS >= S.MAX_ORBITS)
		end)

		T.test("evolving never takes orbits away", function()
			for _, id in S.ORDER do
				local target = StarMath.evolveTarget(id)
				if target then
					T.truthy(StarMath.slots(target) >= StarMath.slots(id), id)
				end
			end
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

		T.test("income adds the star (by level) and the planets in its orbits", function()
			local s = star("RedDwarf", 2)
			local equipped = {
				[1] = { typeId = "Basalt", level = 1 },
				[2] = { typeId = "Aurora", level = 3 },
			}
			local expected = math.floor(S.BY_ID.RedDwarf.income * StarMath.levelMultiplier(2) + 0.5)
				+ P.BY_ID.Basalt.income
				+ StarMath.planetIncome("Aurora", 3)
			T.near(StarMath.income(s, equipped), expected)
			T.near(StarMath.income(s), StarMath.starIncome("RedDwarf", 2))
		end)

		T.test("total income counts only planets on stars that exist, once each", function()
			local stars = { s1 = star("RedDwarf", 2), s2 = star(first, 1) }
			local planets = {
				p1 = { typeId = "Basalt", level = 1, star = "s1", slot = 1 },
				p2 = { typeId = "Aurora", level = 2, star = "s2", slot = 1 },
				p3 = { typeId = "Singularity", level = 5 }, -- inventory: makes nothing
				p4 = { typeId = "Geode", level = 1, star = "gone", slot = 1 },
			}
			local expected = StarMath.starIncome("RedDwarf", 2)
				+ StarMath.starIncome(first, 1)
				+ P.BY_ID.Basalt.income
				+ StarMath.planetIncome("Aurora", 2)
			T.near(StarMath.totalIncome(stars, planets), expected)
			T.near(
				StarMath.totalIncome(stars),
				StarMath.starIncome("RedDwarf", 2) + StarMath.starIncome(first, 1)
			)
		end)

		T.test("planets round-trip through the attribute strings", function()
			local equipped = {
				[1] = { typeId = "Basalt", level = 3 },
				[3] = { typeId = "DimensionalRift", level = 1 },
			}
			local back = StarMath.decodePlanets(StarMath.encodePlanets(equipped))
			T.equal(back[1], "Basalt")
			T.equal(back[2], nil)
			T.equal(back[3], "DimensionalRift")
			local levels = StarMath.decodePlanetLevels(StarMath.encodePlanetLevels(equipped))
			T.equal(levels[1], 3)
			T.equal(levels[3], 1)
			T.equal(StarMath.encodePlanetLevels(equipped), "3,,1,,,,,,")
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

		T.test("planets level up to MAX_LEVEL: more income, a bit bigger, pricier", function()
			for _, typeId in P.ORDER do
				local lastIncome, lastCost, lastRadius = 0, 0, 0
				for level = 1, P.MAX_LEVEL do
					local income = StarMath.planetIncome(typeId, level)
					T.truthy(
						income > lastIncome and income == math.floor(income),
						`{typeId} L{level} income`
					)
					local radius = StarMath.planetRadius(typeId, level)
					T.truthy(radius > lastRadius, `{typeId} L{level} radius`)
					local cost = StarMath.planetLevelCost(typeId, level)
					if level < P.MAX_LEVEL then
						T.truthy(
							cost ~= nil and (cost :: number) > lastCost,
							`{typeId} L{level} cost`
						)
						lastCost = cost :: number
					else
						T.equal(cost, nil)
					end
					lastIncome, lastRadius = income, radius
				end
				T.equal(StarMath.planetIncome(typeId, P.MAX_LEVEL), P.BY_ID[typeId].income * 3)
			end
			T.equal(StarMath.planetLevelCost("Basalt", 1), P.UPGRADE_COST.Common)
			T.equal(StarMath.planetLevelCost("Unknown", 1), nil)
		end)
	end)
end
