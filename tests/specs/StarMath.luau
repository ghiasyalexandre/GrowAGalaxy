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
			T.falsy(StarMath.typeUnlocked("BlackHole", { a = star("RedSupergiant", 1) }))
			T.truthy(StarMath.typeUnlocked("BlackHole", { a = star("Magnetar", 1) }))
			T.truthy(StarMath.typeUnlocked("WolfRayet", { a = star("RedSupergiant", 1) }))
		end)

		T.test("the next goal is the tier above your best star", function()
			T.equal(StarMath.nextTier({}), first)
			T.equal(
				StarMath.nextTier({ a = star(first, 1), b = star("YellowDwarf", 2) }),
				"BinaryStar"
			)
			T.equal(StarMath.nextTier({ a = star("BlackHole", 1) }), "NebulaHeart")
			T.equal(StarMath.nextTier({ a = star("VoidFlame", 1) }), nil)
		end)

		T.test("stars evolve up the ladder and stop at the black hole", function()
			T.equal(StarMath.evolveTarget("BrownDwarf"), "RedDwarf")
			T.equal(StarMath.evolveTarget("RedSupergiant"), "WolfRayet")
			T.equal(StarMath.evolveTarget("WolfRayet"), "NeutronStar")
			T.equal(StarMath.evolveTarget("NeutronStar"), "Pulsar")
			T.equal(StarMath.evolveTarget("Pulsar"), "Magnetar")
			T.equal(StarMath.evolveTarget("Magnetar"), "BlackHole")
			T.equal(StarMath.evolveTarget("BlackHole"), "NebulaHeart")
			T.equal(StarMath.evolveTarget("VoidFlame"), nil)
		end)

		T.test("max level is 4 + floor((tier - 1) / 4): 4 at tier 1, 8 at the top", function()
			for _, id in S.ORDER do
				local tier = S.BY_ID[id].tier
				T.equal(StarMath.maxLevel(id), 4 + (tier - 1) // 4, id)
			end
			T.equal(StarMath.maxLevel(first), 4)
			T.equal(StarMath.maxLevel("VoidFlame"), 8)
			T.near(StarMath.levelMultiplier(8), 2.89)
		end)

		T.test("prices follow the BuildIndex: cost x 1.1^k, levels and evolutions too", function()
			T.equal(StarMath.placeCost(first, 0), 100)
			T.equal(StarMath.placeCost(first, 2), math.ceil(100 * 1.1 ^ 2 - 1e-9))
			T.equal(StarMath.upgradeCost(first, 1, 0), math.ceil(100 * 0.18 - 1e-9))
			T.equal(
				StarMath.upgradeCost("RedDwarf", 3, 4),
				math.ceil(450 * 0.18 * 1.2 ^ 2 * 1.1 ^ 4 - 1e-9)
			)
			T.equal(StarMath.evolveCost(first, 1), math.ceil(450 * 1.1 - 1e-9))
			T.equal(StarMath.evolveCost("VoidFlame", 0), nil)
			-- A first-slot Void Flame's seven level-ups: 1.9T x 0.18 x (1.2^7 - 1) / 0.2.
			local total = 0
			for level = 1, 7 do
				total += StarMath.upgradeCost("VoidFlame", level, 0) :: number
			end
			T.truthy(math.abs(total - 1.9e12 * 0.18 * (1.2 ^ 7 - 1) / 0.2) < 10, `{total}`)
		end)

		T.test("levelling stops at max level, prices rise level by level", function()
			local top = StarMath.maxLevel(first)
			T.truthy(StarMath.upgradeCost(first, 1))
			T.truthy(StarMath.upgradeCost(first, top - 1) > StarMath.upgradeCost(first, 1))
			T.equal(StarMath.upgradeCost(first, top), nil)
		end)

		T.test("a star evolves only at max level, and never past the top star", function()
			local top = StarMath.maxLevel(first)
			T.falsy(StarMath.canEvolve(star(first, top - 1)))
			T.truthy(StarMath.canEvolve(star(first, top)))
			T.truthy(StarMath.canEvolve(star("BlackHole", StarMath.maxLevel("BlackHole"))))
			local last = S.ORDER[#S.ORDER]
			T.falsy(StarMath.canEvolve(star(last, StarMath.maxLevel(last))))
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
			local own = S.BY_ID.RedDwarf.income * S.INCOME_BOOST * StarMath.levelMultiplier(2)
			local expected = own
				+ own * P.BY_ID.Basalt.income / 100
				+ StarMath.planetIncome("Aurora", 3, 1, own)
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
			local red, brown = StarMath.starIncome("RedDwarf", 2), StarMath.starIncome(first, 1)
			local expected = red
				+ brown
				+ StarMath.planetIncome("Basalt", 1, 1, red)
				+ StarMath.planetIncome("Aurora", 2, 1, brown)
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

		T.test("a planet's tier multiplies its share, up to x2.2 at the top tier", function()
			local base = StarMath.planetFactor("Singularity", 1)
			T.equal(StarMath.planetFactor("Singularity", 1, 1), base)
			T.near(StarMath.planetFactor("Singularity", 1, #P.TIERS), base * 2.2)
			local last = 0
			for tier = 1, #P.TIERS do
				local income = StarMath.planetIncome("Basalt", 5, tier, 100)
				T.truthy(income > last, `tier {tier}`)
				last = income
			end
		end)

		T.test("planets level up to MAX_LEVEL: more income, a bit bigger, pricier", function()
			for _, typeId in P.ORDER do
				local lastIncome, lastCost, lastRadius = 0, 0, 0
				for level = 1, P.MAX_LEVEL do
					local income = StarMath.planetIncome(typeId, level, 1, 100)
					T.truthy(income > lastIncome, `{typeId} L{level} income`)
					local radius = StarMath.planetRadius(typeId, level)
					T.truthy(radius > lastRadius, `{typeId} L{level} radius`)
					local cost = StarMath.planetLevelCost(typeId, level, 1000)
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
				T.near(
					StarMath.planetIncome(typeId, P.MAX_LEVEL, 1, 100),
					P.BY_ID[typeId].income * 2
				)
			end
			-- Level prices are a share of the egg price, rounded up.
			T.equal(StarMath.planetLevelCost("Basalt", 1, 1000), 100)
			T.equal(StarMath.planetLevelCost("Basalt", 2, 1000), 160)
			T.equal(StarMath.planetLevelCost("Unknown", 1, 1000), nil)
		end)
	end)
end
